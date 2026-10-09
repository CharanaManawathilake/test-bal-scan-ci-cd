[![Test](https://github.com/CharanaManawathilake/test-bal-scan-ci-cd/actions/workflows/test.yml/badge.svg?branch=master)](https://github.com/CharanaManawathilake/test-bal-scan-ci-cd/actions/workflows/test.yml)
[![GitHub license](https://img.shields.io/github/license/CharanaManawathilake/test-bal-scan-ci-cd)](https://github.com/CharanaManawathilake/test-bal-scan-ci-cd/blob/master/LICENSE)

# Scan Ballerina

A GitHub Action that installs Ballerina with
[`setup-ballerina`](https://github.com/ballerina-platform/setup-ballerina),
runs `bal scan` on your Ballerina packages, uploads the findings to
**Security → Code scanning** and fails the job on a severity threshold.

It is a standalone version of
[`ballerina-library/.github/actions/scan-ballerina`](https://github.com/ballerina-platform/ballerina-library/tree/main/.github/actions/scan-ballerina).
It adds the inputs and outputs that static analysis actions for other
languages commonly provide: excluded paths, a findings budget, new-issues-only
on pull requests, annotations and a job summary.

## Usage

```yaml
permissions:
  contents: read
  security-events: write   # SARIF upload
  pull-requests: read      # only-new-issues on private repositories

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: <owner>/<repo>@v1
        with:
          ballerina-version: 2201.13.3
          paths: ballerina
          fail-on-severity: high
```

The action uploads the SARIF before it applies the gate, so findings reach
code scanning even when the job fails. Private repositories need GitHub Code
Security for the upload. Without it the upload fails, but the action carries
on.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `setup-ballerina` | `true` | Install Ballerina with `setup-ballerina@v1.1.4`. Set to `false` when an earlier step installed it. |
| `ballerina-version` | `latest` | Ballerina version to install. |
| `tool-version` | empty | `bal scan` tool version; empty picks the latest one compatible with the distribution. |
| `paths` | `ballerina` | Newline or comma separated packages, or directories searched for packages. Missing paths are ignored. |
| `exclude-paths` | empty | Newline or comma separated globs, relative to the repository root, for packages and files to leave out. A directory excludes everything below it. `*` stays within one directory and `**` crosses directories. |
| `exclude-tests` | `true` | Drop findings in `tests/` and `modules/*/tests/`. |
| `scan-args` | empty | Extra `bal scan` arguments, such as `--exclude-rules=ballerina:1,ballerina:10` (no spaces inside a value). `--format` and `--target-dir` are not allowed. |
| `fail-on-severity` | `none` | Fail when findings are at or above `low`, `medium` or `high`. |
| `max-findings` | `0` | Findings at or above `fail-on-severity` allowed before the job fails. |
| `fail-on-missing-report` | `true` | Fail when `bal scan` writes no report for a package, for example because it does not compile. |
| `only-new-issues` | `false` | On pull requests, count only findings in files the pull request changes. The uploaded SARIF keeps every finding, so code scanning does not close alerts in other files. |
| `upload` | `true` | Upload the SARIF to code scanning. |
| `category` | `bal-scan` | Code scanning category. Use a different one for each scan in a workflow. |
| `annotations` | `false` | Show each counted finding as a file and line annotation. |
| `job-summary` | `true` | Write the result, counts and findings to the job summary. |
| `github-token` | `github.token` | Token for installing Ballerina, listing pull request files and uploading the SARIF. |

Severities map from SARIF levels: `error` is high, `warning` is medium and
`note` is low.

## Outputs

| Output | Description |
| --- | --- |
| `result` | `passed`, `failed`, or `skipped` when no package was found. |
| `sarif-file` | The merged SARIF file; empty when no report was produced. |
| `sarif-id` | ID of the uploaded SARIF. |
| `high-count`, `medium-count`, `low-count`, `total-count` | Counted findings, after the test, path and new-issues filters. |
| `packages-scanned` | Number of packages scanned. |
| `missing-report` | `true` when a package produced no report. |

## Tests

`.github/workflows/test.yml` runs the action from this repository against
the packages under `test-cases/`, one job per case, on every push, pull
request and nightly, and on demand with a chosen `balVersion`. The
scan step runs with `continue-on-error`. A check step then compares its outputs,
and whether it failed, with the case's expected values. So the workflow is
green only when the action behaves as expected.

| Case | Inputs | Findings (high / medium / low) | Result |
| --- | --- | --- | --- |
| `clean` | fail on low | 0 / 0 / 0 | passed |
| `multiple-issues` | fail on high, annotations | 2 / 1 / 2 | failed |
| `multiple-issues` | fail on high, max 2 | 2 / 1 / 2 | passed |
| `multiple-issues` | fail on high, high rules excluded via `scan-args` | 0 / 1 / 2 | passed |
| `test-only-issues` | fail on low, exclude tests | 0 / 0 / 0 | passed |
| `test-only-issues` | fail on low, keep tests | 0 / 0 / 2 | failed |
| `custom-severity` | fail on medium | 0 / 1 / 1 | failed |
| `custom-severity` | fail on high | 0 / 1 / 1 | passed |
| all of `test-cases/` | `multiple-issues` and `broken` excluded by glob, keep tests | 0 / 1 / 3 in 3 packages | passed |
| `broken` + `clean` | `broken` does not compile | missing report | failed |
| `broken` | missing report allowed | missing report | passed |
| `does-not-exist` | fail on low | no packages | skipped |
| `clean` | Ballerina installed by an earlier step | 0 / 0 / 0 | passed |

`only-new-issues` is not in the matrix, because its result depends on the
event and on the files a pull request changes. It was checked by hand against
a real pull request, an unknown pull request and a push.

Each case uploads its SARIF under its own category (`bal-scan-<case>`) and
keeps it as a run artifact (`sarif-bal-scan-<case>`).

## Layout

The layout follows
[`setup-ballerina`](https://github.com/ballerina-platform/setup-ballerina): the
action and its helper scripts sit at the root, next to the repository files.

```
.github/
  CODEOWNERS
  ISSUE_TEMPLATE/          bug, improvement, new feature and task forms
  workflows/test.yml       tests the action against test-cases/
action.yml                 the action
scan.sh                    scans, filters, counts and works out the gate
merge-sarif.jq             merges package reports into one run (from scan-ballerina)
test-cases/
  clean/                   no findings
  multiple-issues/         ballerina:13, os:1, crypto:1, ballerina:1, :3
  test-only-issues/        ballerina:1, :10, all under tests/
  custom-severity/         crypto:1, ballerina:1
  broken/                  does not compile, so no report
issue_template.md
pull_request_template.md
LICENSE                    Apache 2.0
README.md
```

## Run locally

```bash
cd test-cases/multiple-issues
bal tool pull scan
bal scan --format=sarif     # report: target/report/scan_results.sarif
```
