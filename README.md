# bal scan CI/CD demo

A small Ballerina package with deliberate static-analysis issues, plus CI
pipelines that run `bal scan` on it:

- **GitHub Actions** (`.github/workflows/ballerina-scan.yml`) uses
  [`setup-ballerina`](https://github.com/ballerina-platform/setup-ballerina) and
  the shared
  [`scan-ballerina`](https://github.com/ballerina-platform/ballerina-library/tree/main/.github/actions/scan-ballerina)
  action.
- **GitLab CI/CD** (`.gitlab-ci.yml`) follows
  [the Ballerina GitLab guide](https://ballerina.io/learn/cicd/#gitlab-cicd-for-ballerina)
  and adds a scan stage.

## Layout

```
ballerina/                  the package (scan-ballerina's default `paths` value)
  main.bal                  ballerina:1, :2, :3, :10, :12   (code smells)
  service.bal               ballerina/http:1, :2, :4
  security.bal              ballerina:13, ballerina/crypto:1, :2, os:1, log:1
.github/workflows/ballerina-scan.yml
.gitlab-ci.yml
```

## Expected findings

Checked locally with Ballerina 2201.13.5 and scan tool 0.12.0: **17 findings**.

| Severity | SARIF level | Count | Rules |
| --- | --- | --- | --- |
| High | `error` | 2 | `ballerina:13` (hardcoded secret), `ballerina/os:1` |
| Medium | `warning` | 6 | `crypto:1`, `crypto:2`, `log:1`, `http:1`, `http:2`, `http:4` |
| Low | `note` | 9 | `ballerina:1`, `:2`, `:3` (×5), `:10`, `:12` |

Both pipelines gate on **high** by default. The package has 2 high findings,
so **the scan job is expected to fail**. That shows the gate is working.

## GitHub Actions

1. `setup-ballerina@v1.1.4` installs Ballerina 2201.13.3 on the runner.
2. `bal build` runs in `ballerina/`.
3. `scan-ballerina@main` pulls the scan tool and runs `bal scan --format=sarif`.
   It uploads the SARIF to **Security → Code scanning** (category `bal-scan`)
   and fails the job based on `fail-on-severity`.
4. The job writes a severity table to the job summary and keeps the SARIF as an
   artifact.

To use a different threshold, run the workflow manually (**Actions → Run
workflow**) and choose `none`, `low`, `medium` or `high`.

The SARIF upload needs `security-events: write`. On private repos it also needs
GitHub Code Security. If that's missing, the upload step fails but the gate
still runs.

## GitLab CI/CD

GitLab can't use GitHub actions, so the `bal-scan` job repeats the action's
steps in shell:

- installs Ballerina from the `.deb` (as in the Ballerina guide), then runs
  `bal tool pull scan` and `bal scan --format=sarif`
- counts findings by level with `jq` and gates on the `FAIL_ON_SEVERITY` CI
  variable
- turns the SARIF into a GitLab **Code Quality** report, so findings show in the
  merge request widget, and keeps the raw SARIF as an artifact

The Ballerina guide caches `~/.ballerina/`. GitLab only caches paths inside the
project directory, so this pipeline leaves caching out.

## Run locally

```bash
cd ballerina
bal tool pull scan
bal build
bal scan --format=sarif     # report: target/report/scan_results.sarif
```
