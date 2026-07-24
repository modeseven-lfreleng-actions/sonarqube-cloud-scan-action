<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: 2025 The Linux Foundation
-->

# 🔐 SonarQube Cloud Scan

Performs a SonarQube Cloud security scan of a given repository's code base.

Uploads the results to either the cloud service or an on-premise/hosted server.

## sonarqube-cloud-scan-action

## Required Credentials

The scanning action requires access to an API key for it to produce results.
Most projects configure this at the GitHub organisation level as:

`SONAR_TOKEN`

Optionally, set it at the repository level, but it MUST be available in the
Github environment for scans to produce results. For projects using Jenkins,
the same credential must be available to Jenkins jobs.

## Usage Example: Action

<!-- markdownlint-disable MD013 -->

```yaml
jobs:
  sonarqube-cloud:
    name: 'SonarQube Cloud Scan'
    runs-on: ubuntu-latest
    permissions:
        # Needed to upload the results to code-scanning dashboard
        security-events: write
        # Needed to publish results and get a badge (see publish_results below)
        id-token: write
        # Uncomment these below if installing in a private repository
        # contents: read
        # actions: read
    steps:
      - name: 'SonarQube Cloud Scan'
        uses: lfit-releng-reusable-workflows/.github/actions/sonarqube-cloud-scan-action@main
        with:
            SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

<!-- markdownlint-enable MD013 -->

## Usage Example: Reusable Workflow

See: <https://github.com/lfit/releng-reusable-workflows/blob/main/.github/workflows/reuse-sonarqube-cloud.yaml>

## Repository Contents and Scan Configuration

Provide information to the scanning action so that it understands how the
project/repository is setup. The accuracy of scans improves when provided with
the source code location (local directory) and for specific project types,
how to build it. For example, projects written in C (and related family of
languages) may need a wrapper script to invoke a build step/process. Provide
the path to the build wrapper either as arguments to the action, or add it
to the local repository configuration file.

Configure the scan parameters by creating either of these two files:

- sonar-project.properties
- sonarcloud.properties

As a temporary measure, in the absence of a configuration file, the scan action
will populate the file with these two parameters, enumerated at runtime:

```console
sonar.organization=[GITHUB REPOSITORY OWNER]
sonar.projectKey=[GITHUB REPOSITORY NAME]
```

This ensures that an initial scan for the repository will produce results in
portal. For further details on populating the scan configuration file with
the required information, refer to the documentation links in the section
below.

### Important: SCM Exclusions and Compiled Binaries

**Note:** The action automatically sets `sonar.scm.exclusions.disabled=true` in
ephemeral configuration files.

By default, SonarQube respects `.gitignore` patterns when scanning repositories.
This can cause issues for projects that build compiled artifacts (like Java `.class`
files) into directories that are intentionally excluded from version control
(e.g., `target/` for Maven projects).

**The Problem:**

- Maven/Gradle compile `.java` source files into `.class` files in `target/classes/`
- The `target/` directory is typically listed in `.gitignore`
- SonarQube sees that `target/` is in `.gitignore` and skips those
  directories entirely
- This results in the error: "Your project contains .java files, please provide
  compiled classes with sonar.java.binaries property, or enable the Java
  bytecode scanner"

**The Solution:**
Set `sonar.scm.exclusions.disabled=true` to tell SonarQube to ignore
`.gitignore` patterns, allowing it to access compiled binaries needed for
comprehensive analysis.

**For Java/Maven Projects:**
If you create your own `sonar-project.properties` file, include:

```ini
# Disable SCM exclusions so .gitignore doesn't hide target directories
sonar.scm.exclusions.disabled=true

# Binary directories (compiled .class files)
sonar.java.binaries=target/classes
# Or for multi-module projects:
# sonar.java.binaries=module1/target/classes,module2/target/classes
```

Without this setting, you'll need to either:

1. Remove `target/` from `.gitignore` (not recommended)
2. Manually copy compiled classes to a non-ignored directory (inefficient)
3. Set `sonar.scm.exclusions.disabled=true` (recommended)

### Example: Java Maven Multi-Module Project

For a typical Maven multi-module Java project with this structure:

```text
my-project/
├── pom.xml
├── module1/
│   └── src/
│       ├── main/java/
│       └── test/java/
├── module2/
│   └── src/
│       ├── main/java/
│       └── test/java/
└── sonar-project.properties
```

Create a `sonar-project.properties` file like this:

```ini
# Organization and project identification
sonar.organization=my-org
sonar.projectKey=my-project

# Disable SCM exclusions so .gitignore doesn't hide target directories
sonar.scm.exclusions.disabled=true

# Source directories
sonar.sources=module1/src/main/java,module2/src/main/java

# Test directories
sonar.tests=module1/src/test/java,module2/src/test/java

# Binary directories (compiled .class files)
sonar.java.binaries=module1/target/classes,module2/target/classes

# Test binary directories
sonar.java.test.binaries=module1/target/test-classes,module2/target/test-classes

# Java version
sonar.java.source=17
sonar.java.target=17

# Encoding
sonar.sourceEncoding=UTF-8

# JaCoCo coverage report paths (if using JaCoCo)
sonar.coverage.jacoco.xmlReportPaths=**/target/site/jacoco/jacoco.xml
```

**Important:** Run your Maven build (e.g., `mvn clean install`) **before**
running the SonarQube scan so that the compiled `.class` files exist in the
`target/` directories.

## SonarQube Cloud Documentation

Refer to the links below:

- <https://github.com/SonarSource/sonarqube-scan-action>
- <https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/>

For information on the build wrapper for C language based projects:

<https://docs.sonarsource.com/sonarqube-cloud/advanced-setup/languages/c-family/prerequisites/#using-build-wrapper>

## Inputs

<!-- markdownlint-disable MD013 -->

| Variable Name         | Required | Default                             | Description                                                                                                                            |
| --------------------- | -------- | ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| sonar_token           | True     | N/A                                 | Mandatory authentication token to upload results                                                                                       |
| sonar_root_cert       | False    | N/A                                 | PEM encoded server root certificate (for HTTPS upload)                                                                                 |
| build_wrapper_url     | False    | N/A                                 | HTTPS download location of build wrapper/shell script                                                                                  |
| build_wrapper_out_dir | False    | N/A                                 | Local filesystem location of build artefacts                                                                                           |
| prescan_script_url    | False    | N/A                                 | HTTPS URL of a script run with bash after checkout, before scan, WITHOUT the build wrapper (mutually exclusive with build_wrapper_url) |
| sonar_host_url        | False    | <https://sonarcloud.io>             | Uploads scans to the given host URL                                                                                                    |
| lc_all                | False    | en_US.UTF-8                         | Locale for code base (if not covered by en_US.UTF-8)                                                                                   |
| debug                 | False    | false                               | Enable debugging output                                                                                                                |
| project_base_dir      | False    | .                                   | Set the sonar.projectBaseDir analysis property                                                                                         |
| scanner_version       | False    | (uses SonarSource action's default) | Version of the Sonar Scanner CLI to use                                                                                                |
| skip_jre_provisioning | False    | false                               | Skip JRE auto-provisioning by the Sonar Scanner CLI (see note below)                                                                   |
| args                  | False    | -Dsonar.scanner.cache.enabled=false | Arguments to pass to the Sonar Scanner CLI                                                                                             |
| sonar_organization    | False    | ''                                  | Override the SonarQube organization (sonar.organization)                                                                               |
| sonar_project_key     | False    | ''                                  | Override the SonarQube project key (sonar.projectKey)                                                                                  |
| sonar_branch_name     | False    | ''                                  | Analysis branch name (sonar.branch.name); useful for Gerrit decoration                                                                 |
| sonar_branch_target   | False    | ''                                  | Analysis target branch (sonar.branch.target); useful for Gerrit decoration                                                             |
| wait_for_quality_gate | False    | false                               | Poll the SonarQube quality gate after the analysis task completes                                                                      |
| fail_on_quality_gate  | False    | false                               | Fail the action when the quality gate status is not OK (requires wait_for_quality_gate: true)                                          |

<!-- markdownlint-enable MD013 -->

## Outputs

<!-- markdownlint-disable MD013 -->

| Output Name         | Description                                             |
| ------------------- | ------------------------------------------------------- |
| sonar_org           | SonarQube organization                                  |
| project_key         | SonarQube project key                                   |
| config_file         | Path to the SonarQube configuration file                |
| dashboard_url       | SonarQube dashboard URL for the analysed project        |
| quality_gate_status | Quality gate status (see values below)                  |

<!-- markdownlint-enable MD013 -->

### Note: Quality gate evaluation

Set `wait_for_quality_gate: 'true'` to poll the background analysis
task after the scan and read the resulting quality gate status. The
`quality_gate_status` output carries the result and defaults to
`UNKNOWN`. The job summary adds a quality-gate line when polling runs
(`wait_for_quality_gate: 'true'`). Set `fail_on_quality_gate: 'true'` to
fail the action when the
quality gate status is not `OK`. `fail_on_quality_gate` takes effect
when `wait_for_quality_gate` is also `true`, because the action must
poll the gate before it can act on the result. Evaluation relies on
`jq`; runners that lack `jq` skip the gate and report `UNKNOWN`. When the
action cannot resolve the gate before polling (missing `jq`, report task
file, `ceTaskUrl`, `serverUrl`, or a missing/malformed `sonar_token`), it
reports `UNKNOWN` and continues without failing, even with
`fail_on_quality_gate: 'true'`.

The `quality_gate_status` output takes one of the following values:

- `OK` — the quality gate passed.
- `ERROR` — the quality gate failed.
- `NONE` — SonarQube reports no quality gate assigned to the project.
- `UNKNOWN` — the gate could not resolve (evaluation skipped, the
  analysis task did not complete, or the API request failed). The
  output also defaults to `UNKNOWN` when `wait_for_quality_gate` is
  `false`.

### Note: Gerrit branch decoration

The `sonar_branch_name` and `sonar_branch_target` inputs map to the
`sonar.branch.name` and `sonar.branch.target` analysis properties. Plain
GitHub pull-request analysis derives branch context automatically, so
reserve these inputs for Gerrit or other non-GitHub source platforms
that need to name the branch under analysis. Set `sonar_branch_name`
whenever you set `sonar_branch_target`: SonarQube honours the target
branch when the analysis names its branch, and otherwise treats the run
as the main branch and ignores the target.

### Note: JRE auto-provisioning

SonarSource is deprecating the bundled Java 17 runtime in the Sonar
Scanner CLI; support ends July 2026. By default this action sets
`skip_jre_provisioning=false`, allowing the scanner to download and
run the JRE that SonarCloud / SonarQube requires. This keeps the
runtime current automatically and silences the related analysis
warning.

Set `skip_jre_provisioning: 'true'` when network egress to the
SonarSource binary host fails or air-gapped builds need to use the
bundled JRE. See:

<https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/scanners/scanner-environment/managing-jre-auto-provisioning/>

## Troubleshooting

### Error: "Your project contains .java files, please provide compiled classes"

**Symptoms:**

```text
WARN  Binary paths (sonar.java.binaries) are empty
ERROR Your project contains .java files, please provide compiled
      classes with sonar.java.binaries property
```

**Cause:** SonarQube cannot find the compiled `.class` files, which can
happen when:

1. The build has not completed yet (no `.class` files exist)
2. The `target/` directory is in `.gitignore` and
   `sonar.scm.exclusions.disabled=true` is not set
3. The `sonar.java.binaries` path is incorrect

**Solution:**

1. Ensure you run your build **before** the SonarQube scan (e.g.,
   `mvn clean install`)
2. Add `sonar.scm.exclusions.disabled=true` to your `sonar-project.properties`
3. Verify your `sonar.java.binaries` paths match where Maven/Gradle outputs
   `.class` files

### Large Number of Files Ignored

**Symptoms:**

```text
INFO  1806 files ignored because of scm ignore settings
```

**Cause:** SonarQube is respecting `.gitignore` patterns and excluding files,
potentially including compiled binaries needed for analysis.

**Solution:** Add `sonar.scm.exclusions.disabled=true` to your configuration file.

### Missing JaCoCo Coverage Reports

**Symptoms:**

```text
WARNING: Report file target/site/jacoco/jacoco.csv does not exist
```

**Cause:** Maven build did not generate JaCoCo reports, or they are in a
different location.

**Solution:**

1. Ensure your Maven `pom.xml` includes the JaCoCo plugin
2. Run tests before scanning: use `mvn clean verify` instead of `mvn compile`
3. For multi-module projects, use wildcards:
   `sonar.coverage.jacoco.xmlReportPaths=**/target/site/jacoco/jacoco.xml`

<!-- markdownlint-enable MD013 -->
