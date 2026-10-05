# bal scan CI/CD tests

Small Ballerina packages with known `bal scan` findings, plus CI pipelines that
scan each one with different flags and check the result:

- **GitHub Actions** (`.github/workflows/scan-action-tests.yml`) uses
  [`setup-ballerina`](https://github.com/ballerina-platform/setup-ballerina) and
  tests the shared
  [`scan-ballerina`](https://github.com/ballerina-platform/ballerina-library/tree/main/.github/actions/scan-ballerina)
  action.
- **GitLab CI/CD** (`.gitlab-ci.yml`) follows
  [the Ballerina GitLab guide](https://ballerina.io/learn/cicd/#gitlab-cicd-for-ballerina)
  and repeats the action's steps in shell.

## Layout

```
test-cases/
  clean/                    no findings
  multiple-issues/          ballerina:13, os:1, crypto:1, ballerina:1, :3
  test-only-issues/         ballerina:1, :10, all under tests/
  custom-severity/          crypto:1, ballerina:1
.github/workflows/scan-action-tests.yml
.gitlab-ci.yml
```

## Test cases

Checked locally with Ballerina 2201.13.5 and scan tool 0.12.0. Both pipelines
run one parallel job per row.

| Case | Flags | Findings (high / medium / low) | Job |
| --- | --- | --- | --- |
| `clean` | fail on `low` | 0 / 0 / 0 | passes |
| `multiple-issues` | fail on `high` | 2 / 1 / 2 | fails |
| `test-only-issues` | fail on `low`, exclude tests | 0 / 0 / 0 | passes |
| `test-only-issues` | fail on `low`, keep tests | 0 / 0 / 2 | fails |
| `custom-severity` | fail on `medium` | 0 / 1 / 1 | fails |

The jobs aren't wrapped in assertions: a case with findings at or above its
gate fails its job, the same way it would in a real pipeline.

## GitHub Actions

1. `setup-ballerina@v1.1.4` installs Ballerina 2201.13.3 on the runner.
2. `scan-ballerina@main` scans the case's package with its flags, uploads the
   SARIF to **Security → Code scanning** and then fails the job if the gate is
   hit. Each case uploads under its own category (`bal-scan-<case>`), because
   code scanning keeps one run per category.

The upload needs `security-events: write`; private repositories also need
GitHub Code Security.

## GitLab CI/CD

GitLab can't use GitHub actions, so the `bal-scan` job uses `parallel:matrix`
and repeats the action's steps in shell:

- installs Ballerina from the `.deb` (as in the Ballerina guide), then pulls
  scan tool 0.12.0 from dev Central, the version the GitHub action picks
- runs `bal scan --format=sarif` and, when `EXCLUDE_TESTS` is `true`, drops
  findings under `tests/` and `modules/*/tests/` with `jq`
- counts findings by level and fails the job when any are at or above
  `FAIL_ON_SEVERITY`
- keeps the SARIF files as artifacts

The Ballerina guide caches `~/.ballerina/`. GitLab only caches paths inside the
project directory, so this pipeline leaves caching out.

## Run locally

```bash
cd test-cases/multiple-issues
bal tool pull scan
bal scan --format=sarif     # report: target/report/scan_results.sarif
```
