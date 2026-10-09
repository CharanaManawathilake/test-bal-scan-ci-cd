#!/usr/bin/env bash
# Runs bal scan on every Ballerina package under SCAN_PATHS, merges the reports
# into one SARIF file, applies the filters and works out the gate result. The
# action uploads the SARIF and fails the job afterwards, so findings reach code
# scanning even when the gate fails.
#
# Inputs come from the environment (see action.yml); outputs go to GITHUB_OUTPUT.

set -o pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

out() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }
fail_input() { echo "::error::$1"; exit 1; }
check_bool() {
  case "$2" in true|false) ;; *) fail_input "$1 must be true or false, got '$2'" ;; esac
}

case "$FAIL_ON" in none|low|medium|high) ;; *) fail_input "fail-on-severity must be none, low, medium or high, got '$FAIL_ON'" ;; esac
[[ "$MAX_FINDINGS" =~ ^[0-9]+$ ]] || fail_input "max-findings must be a whole number, got '$MAX_FINDINGS'"
check_bool exclude-tests "$EXCLUDE_TESTS"
check_bool only-new-issues "$ONLY_NEW"
check_bool fail-on-missing-report "$FAIL_ON_MISSING"
check_bool annotations "$ANNOTATIONS"
check_bool job-summary "$JOB_SUMMARY"
command -v bal > /dev/null || fail_input "bal was not found. Set setup-ballerina to true or install Ballerina before this step"

# Writes the outputs of a run that scanned nothing.
empty_outputs() {
  out sarif-file ""
  for o in high-count medium-count low-count total-count; do out "$o" 0; done
  out packages-scanned 0
  out missing-report false
}

# --- Scan tool -----------------------------------------------------------------

active_tool() {
  bal tool list | awk -F'|' '$2 ~ /^ *scan *$/ { if (match($3, /[0-9]+\.[0-9]+\.[0-9]+[^ ]*/)) print substr($3, RSTART, RLENGTH) }'
}

DIST="$(bal version | sed -n 's/^Ballerina \([0-9][0-9.]*\).*/\1/p')"
WANTED="$TOOL_VERSION"
PULL_ENV=()
# Temporary: 0.12.0 is only on dev Central and needs 2201.13.2+. Scoped to the pull so dependencies resolve from production.
if [ -z "$WANTED" ] && [ "$(printf '%s\n%s\n' 2201.13.2 "$DIST" | sort -V | head -n1)" = "2201.13.2" ]; then
  WANTED=0.12.0
  PULL_ENV=(BALLERINA_DEV_CENTRAL=true)
fi
ACTIVE="$(active_tool)"
# bal tool pull fails when the tool is already active, as it is on the second call in a job.
if [ -z "$ACTIVE" ] || { [ -n "$WANTED" ] && [ "$ACTIVE" != "$WANTED" ]; }; then
  if [ -n "$WANTED" ]; then
    env "${PULL_ENV[@]}" bal tool pull "scan:$WANTED"
    bal tool use "scan:$WANTED"
  else
    bal tool pull scan
  fi
fi
echo "Using bal scan $(active_tool) on Ballerina $DIST"

# --- Packages ------------------------------------------------------------------

# exclude-paths globs as anchored regexes. A pattern also matches everything
# below it, so a directory name excludes the whole directory.
EXCLUDE_RE="$(printf '%s' "${EXCLUDE_PATHS//$'\n'/,}" | jq -R -s -c '
  split(",")
  | map(gsub("^\\s+|\\s+$"; "") | sub("^\\./"; "") | sub("/+$"; "") | select(length > 0)
      | gsub("(?<c>[.+^${}()|\\[\\]\\\\])"; "\\\(.c)")
      | gsub("\\*\\*/"; "\u0001") | gsub("\\*\\*"; "\u0002")
      | gsub("\\*"; "[^/]*") | gsub("\\?"; "[^/]")
      | gsub("\u0001"; "(.*/)?") | gsub("\u0002"; ".*")
      | "^" + . + "(/.*)?$")')"

is_excluded() {
  jq -n -e --arg p "$1" --argjson res "$EXCLUDE_RE" 'any($res[]; . as $r | $p | test($r))' > /dev/null
}

PACKAGES=()
IFS=',' read -ra ENTRIES <<< "${SCAN_PATHS//$'\n'/,}"
for p in "${ENTRIES[@]}"; do
  p="$(printf '%s' "$p" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's:/*$::')"
  [ -n "$p" ] && [ -d "$p" ] || continue
  while IFS= read -r toml; do
    pkg="$(dirname "$toml")"
    pkg="${pkg#./}"
    if is_excluded "$pkg"; then
      echo "Skipping excluded package $pkg"
      continue
    fi
    PACKAGES+=("$pkg")
  done < <(find "$p" \( -name target -o -name build -o -name .git \) -prune -o -name Ballerina.toml -print | sort)
done
# Overlapping paths would otherwise scan a package twice.
mapfile -t PACKAGES < <(printf '%s\n' "${PACKAGES[@]}" | sed '/^$/d' | sort -u)

WORK="$RUNNER_TEMP/bal-scan-$CATEGORY"
rm -rf "$WORK" "$WORK.sarif" && mkdir -p "$WORK"
if [ "${#PACKAGES[@]}" -eq 0 ]; then
  echo "::notice::No Ballerina packages found for category '$CATEGORY'"
  empty_outputs
  out result skipped
  exit 0
fi

# --- Scan ----------------------------------------------------------------------

read -ra EXTRA_ARGS <<< "$SCAN_ARGS"
for a in "${EXTRA_ARGS[@]}"; do
  case "$a" in
    --format*|--target-dir*) fail_input "scan-args cannot set $a: the action needs the SARIF report in the default location" ;;
  esac
done
MISSING=()
for pkg in "${PACKAGES[@]}"; do
  echo "::group::bal scan $pkg"
  f="$pkg/target/report/scan_results.sarif"
  # A report left over from an earlier run would hide a failed scan.
  rm -f "$f"
  (cd "$pkg" && bal scan --format=sarif "${EXTRA_ARGS[@]}") || true
  # bal scan can exit 0 without writing a report, for example when the package does not compile.
  if [ -f "$f" ] && jq -e '.runs[0]' "$f" > /dev/null 2>&1; then
    prefix="$pkg/"
    [ "$pkg" = "." ] && prefix=""
    jq --arg prefix "$prefix" --argjson exclude_tests "$EXCLUDE_TESTS" --argjson exclude "$EXCLUDE_RE" '
      (if $exclude_tests then .runs[].results |= map(select(
        (.locations[0].physicalLocation.artifactLocation.uri // "") | test("^(modules/[^/]+/)?tests/") | not))
      else . end)
      | (.runs[].results[]?.locations[]?.physicalLocation.artifactLocation.uri) |=
          (if test("^(/|[a-zA-Z][a-zA-Z0-9+.-]*:)") or startswith($prefix) then . else $prefix + . end)
      | .runs[].results |= map(select(
          (.locations[0].physicalLocation.artifactLocation.uri // "") as $u | any($exclude[]; . as $r | $u | test($r)) | not))
    ' "$f" > "$WORK/$(echo "$pkg" | tr '/' '_').sarif"
  else
    echo "::warning::bal scan did not produce a report for package '$pkg'"
    MISSING+=("$pkg")
  fi
  echo "::endgroup::"
done

out packages-scanned "${#PACKAGES[@]}"
out missing-report "$([ "${#MISSING[@]}" -gt 0 ] && echo true || echo false)"

if [ -z "$(ls -A "$WORK")" ]; then
  out sarif-file ""
  for o in high-count medium-count low-count total-count; do out "$o" 0; done
  if [ "$FAIL_ON_MISSING" = "true" ]; then
    out result failed
    out failure-reason "bal scan did not produce a report for any package in '$CATEGORY'"
  else
    echo "::warning::bal scan did not produce a report for any package in category '$CATEGORY'"
    out result passed
  fi
  exit 0
fi

# Code scanning accepts one run per category, so packages are merged.
SARIF="$WORK.sarif"
jq -s -f "$SCRIPTS/merge-sarif.jq" "$WORK"/*.sarif > "$SARIF"
out sarif-file "$SARIF"

# --- Findings that count -------------------------------------------------------

# only-new-issues narrows the gate, counts, annotations and summary to the files
# the pull request changes. The uploaded SARIF keeps every finding: dropping
# some would make code scanning close their alerts on the pull request.
CHANGED=null
if [ "$ONLY_NEW" = "true" ]; then
  case "$EVENT_NAME" in
    pull_request|pull_request_target)
      if FILES="$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/files" --paginate --jq '.[].filename')"; then
        CHANGED="$(printf '%s\n' "$FILES" | jq -R -s -c 'split("\n") | map(select(length > 0))')"
        echo "only-new-issues: counting findings in the $(jq 'length' <<< "$CHANGED") file(s) changed by pull request #$PR_NUMBER"
      else
        echo "::warning::Could not list the files changed by pull request #$PR_NUMBER, so every finding counts. The token needs pull-requests: read"
      fi
      ;;
    *) echo "::notice::only-new-issues applies to pull requests; every finding counts on '$EVENT_NAME'" ;;
  esac
fi

FINDINGS="$WORK.findings.json"
jq --argjson changed "$CHANGED" '
  [.runs[0].results[]
    | {
        severity: ({"error": "high", "warning": "medium", "note": "low"}[.level // "warning"] // "low"),
        rule: .ruleId,
        file: (.locations[0].physicalLocation.artifactLocation.uri // ""),
        line: (.locations[0].physicalLocation.region.startLine // 1),
        message: (.message.text // .ruleId)
      }
    | select($changed == null or (.file as $f | any($changed[]; . == $f)))]
  | sort_by({"high": 0, "medium": 1, "low": 2}[.severity], .file, .line)
' "$SARIF" > "$FINDINGS"

count() { jq --arg s "$1" '[.[] | select(.severity == $s)] | length' "$FINDINGS"; }
HIGH="$(count high)"; MEDIUM="$(count medium)"; LOW="$(count low)"
TOTAL=$((HIGH + MEDIUM + LOW))
UNCOUNTED=$(( $(jq '.runs[0].results | length' "$SARIF") - TOTAL ))
echo "bal scan '$CATEGORY': $HIGH high, $MEDIUM medium, $LOW low severity finding(s) in ${#PACKAGES[@]} package(s)"
[ "$UNCOUNTED" -gt 0 ] && echo "$UNCOUNTED finding(s) in files the pull request does not change are not counted"
out high-count "$HIGH"
out medium-count "$MEDIUM"
out low-count "$LOW"
out total-count "$TOTAL"

# --- Gate ----------------------------------------------------------------------

REASONS=()
if [ "$FAIL_ON" != "none" ]; then
  case "$FAIL_ON" in
    high) FAILING=$HIGH ;;
    medium) FAILING=$((HIGH + MEDIUM)) ;;
    low) FAILING=$TOTAL ;;
  esac
  if [ "$FAILING" -gt "$MAX_FINDINGS" ]; then
    REASONS+=("bal scan found $FAILING finding(s) at or above $FAIL_ON severity in '$CATEGORY', more than the $MAX_FINDINGS allowed")
  fi
fi
if [ "${#MISSING[@]}" -gt 0 ] && [ "$FAIL_ON_MISSING" = "true" ]; then
  REASONS+=("bal scan did not produce a report for $(printf "'%s' " "${MISSING[@]}")in '$CATEGORY'")
fi
if [ "${#REASONS[@]}" -gt 0 ]; then
  RESULT=failed
  REASON="$(printf '%s; ' "${REASONS[@]}")"
  out failure-reason "${REASON%; }"
else
  RESULT=passed
fi
out result "$RESULT"

# --- Annotations and summary ---------------------------------------------------

if [ "$ANNOTATIONS" = "true" ]; then
  jq -r '
    def esc: gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A");
    def prop: esc | gsub(":"; "%3A") | gsub(","; "%2C");
    .[] | "::\({"high": "error", "medium": "warning", "low": "notice"}[.severity]) file=\(.file | prop),line=\(.line),title=\("bal scan " + .rule | prop)::\(.message | esc)"
  ' "$FINDINGS"
fi

if [ "$JOB_SUMMARY" = "true" ] && [ -n "$GITHUB_STEP_SUMMARY" ]; then
  {
    echo "### bal scan: $CATEGORY"
    echo
    if [ "$RESULT" = "failed" ]; then
      echo "**Failed:** $(printf '%s. ' "${REASONS[@]}")"
    else
      echo "**Passed** (fail on: $FAIL_ON)"
    fi
    echo
    echo "| High | Medium | Low | Packages scanned | Without a report |"
    echo "| ---: | ---: | ---: | ---: | ---: |"
    echo "| $HIGH | $MEDIUM | $LOW | ${#PACKAGES[@]} | ${#MISSING[@]} |"
    if [ "$UNCOUNTED" -gt 0 ]; then
      echo
      echo "$UNCOUNTED finding(s) in files the pull request does not change are not counted."
    fi
    if [ "$TOTAL" -gt 0 ]; then
      echo
      echo "<details><summary>Findings</summary>"
      echo
      echo "| Severity | Rule | Location | Message |"
      echo "| --- | --- | --- | --- |"
      jq -r --arg base "${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/blob/$GITHUB_SHA" '
        def cell: gsub("\\|"; "\\|") | gsub("\n"; " ");
        .[:100][] | "| \(.severity) | `\(.rule)` | [\(.file):\(.line)](\($base)/\(.file)#L\(.line)) | \(.message | cell) |"
      ' "$FINDINGS"
      [ "$TOTAL" -gt 100 ] && echo && echo "Showing the first 100 of $TOTAL findings. The full list is in the SARIF file."
      echo
      echo "</details>"
    fi
    echo
  } >> "$GITHUB_STEP_SUMMARY"
fi
