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

> For Maven projects, consider `analysis_mode: 'maven'` instead — the
> plugin derives the properties below from the reactor, so there
> is nothing to hand-maintain. See
> [Note: Maven analysis mode](#note-maven-analysis-mode).

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

## Workspace Variables in Arguments

The `args`, `maven_args` and `coverage_report_paths` inputs expand a
fixed list of names before
the analysis backend runs:

`GITHUB_WORKSPACE`, `GITHUB_REPOSITORY`, `GITHUB_REF_NAME`, `GITHUB_SHA`,
`GITHUB_RUN_ID`, `RUNNER_TEMP`, `RUNNER_OS`

Both the `${NAME}` and `$NAME` forms work:

```yaml
coverage_report_paths: >-
  ${GITHUB_WORKSPACE}/target/site/jacoco/jacoco.xml
```

The `coverage_report_paths` input sets
`sonar.coverage.jacoco.xmlReportPaths` in both analysis modes; it
accepts a comma-separated list, and callers running the build with
[maven-build-action][mba] can wire its `coverage_report_paths` output
straight through. CLI mode benefits most: unlike Maven mode, it never
reads the Maven project model, so it cannot derive report paths itself.

[mba]: https://github.com/lfreleng-actions/maven-build-action

Every other `${...}` reaches the backend as written, which leaves Maven's
own `${project.*}` and `${settings.*}` for Maven to resolve. A name
outside the list stays literal even where the environment holds a value
for it, `${SONAR_TOKEN}` among them: this step holds credentials, and an
open substitution would put one on a command line and in the process
table.

Nothing in the expansion executes, so `$(...)`, backticks and `$((...))`
reach the backend as written too.

The inputs split on whitespace, so a value carrying a space needs a path
without one.

## SonarQube Cloud Documentation

Refer to the links below:

- <https://github.com/SonarSource/sonarqube-scan-action>
- <https://docs.sonarsource.com/sonarqube-server/latest/analyzing-source-code/scanners/sonarscanner/>

For information on the build wrapper for C language based projects:

<https://docs.sonarsource.com/sonarqube-cloud/advanced-setup/languages/c-family/prerequisites/#using-build-wrapper>

## Inputs

<!-- markdownlint-disable MD013 -->

| Variable Name                | Required | Default                                                           | Description                                                                                                                            |
| ---------------------------- | -------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| sonar_token                  | True     | N/A                                                               | Mandatory authentication token to upload results                                                                                       |
| sonar_root_cert              | False    | N/A                                                               | PEM encoded server root certificate (for HTTPS upload)                                                                                 |
| build_wrapper_url            | False    | N/A                                                               | HTTPS download location of build wrapper/shell script                                                                                  |
| build_wrapper_out_dir        | False    | N/A                                                               | Local filesystem location of build artefacts                                                                                           |
| prescan_script_url           | False    | N/A                                                               | HTTPS URL of a script run with bash after checkout, before scan, WITHOUT the build wrapper (mutually exclusive with build_wrapper_url) |
| sonar_host_url               | False    | <https://sonarcloud.io>                                           | Uploads scans to the given host URL                                                                                                    |
| lc_all                       | False    | en_US.UTF-8                                                       | Locale for code base (if not covered by en_US.UTF-8)                                                                                   |
| debug                        | False    | false                                                             | Enable debugging output                                                                                                                |
| project_base_dir             | False    | .                                                                 | Set the sonar.projectBaseDir analysis property                                                                                         |
| scanner_version              | False    | 8.1.0.6389                                                        | Version of the Sonar Scanner CLI to use                                                                                                |
| scanner_binaries_url         | False    | <https://binaries.sonarsource.com/Distribution/sonar-scanner-cli> | URL to download the Sonar Scanner CLI binaries from (air-gapped/self-hosted mirrors)                                                   |
| scanner_binaries_auth_header | False    | ''                                                                | Authorization header for the scanner binaries download; pass via a secret (e.g. `${{ secrets.MIRROR_AUTH_HEADER }}`)                   |
| skip_signature_verification  | False    | false                                                             | Skip GPG signature verification of the scanner binaries (requires a trusted mirror)                                                    |
| scanner_java_opts            | False    | ''                                                                | Extra JVM options for the Sonar Scanner CLI (e.g. '-Xmx4g' for large codebases)                                                        |
| skip_jre_provisioning        | False    | false                                                             | Skip JRE auto-provisioning by the Sonar Scanner CLI (see note below)                                                                   |
| args                         | False    | -Dsonar.scanner.cache.enabled=false                               | Arguments passed to the analysis backend; both CLI and Maven modes receive these                                                       |
| sonar_organization           | False    | ''                                                                | Override the SonarQube organization (sonar.organization)                                                                               |
| sonar_project_key            | False    | ''                                                                | Override the SonarQube project key (sonar.projectKey)                                                                                  |
| sonar_branch_name            | False    | ''                                                                | Analysis branch name (sonar.branch.name); useful for Gerrit decoration                                                                 |
| sonar_branch_target          | False    | ''                                                                | Analysis target branch (sonar.branch.target); useful for Gerrit decoration                                                             |
| sonar_gerrit_project         | False    | ''                                                                | Gerrit project name recorded on the analysis (sonar.analysis.gerritProjectName)                                                        |
| coverage_report_paths        | False    | ''                                                                | JaCoCo XML report paths recorded on the analysis (sonar.coverage.jacoco.xmlReportPaths)                                                |
| wait_for_quality_gate        | False    | false                                                             | Poll the SonarQube quality gate after the analysis task completes                                                                      |
| quality_gate_timeout         | False    | 150                                                               | Wall-clock limit in seconds for quality gate polling (an in-flight API request may extend the step by up to 60 seconds)                |
| fail_on_quality_gate         | False    | false                                                             | Fail the action when the quality gate status is not OK (requires wait_for_quality_gate: true)                                          |
| analysis_mode                | False    | cli                                                               | Analysis backend: 'cli' (Sonar Scanner CLI) or 'maven' (sonar-maven-plugin); see note below                                            |
| maven_sonar_plugin_version   | False    | 5.7.0.6970                                                        | Version of org.sonarsource.scanner.maven:sonar-maven-plugin (maven mode; requires Java 11+)                                            |
| maven_args                   | False    | ''                                                                | Extra arguments appended to the Maven sonar invocation (maven mode), e.g. '--settings /path/settings.xml'                              |

<!-- markdownlint-enable MD013 -->

## Outputs

<!-- markdownlint-disable MD013 -->

| Output Name         | Description                                      |
| ------------------- | ------------------------------------------------ |
| sonar_org           | SonarQube organization                           |
| project_key         | SonarQube project key                            |
| config_file         | Path to the SonarQube configuration file         |
| dashboard_url       | SonarQube dashboard URL for the analysed project |
| quality_gate_status | Quality gate status (see values below)           |
| scanner_args        | Assembled `-Dsonar.*` arguments (see note below) |

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

The `sonar_gerrit_project` input maps to
`sonar.analysis.gerritProjectName`, recording the originating Gerrit
project as analysis metadata so you can trace a scan back to its source.

### Note: Maven analysis mode

By default the action runs the Sonar Scanner CLI, which suits any
language. Setting `analysis_mode: 'maven'` instead runs
`sonar-maven-plugin` against an **already-built** Maven reactor.

Prefer Maven mode for multi-module Java projects. The plugin reads the
Maven project model, so it derives module structure, compiled binaries,
test binaries, source encoding and JaCoCo report paths automatically --
replacing the hand-maintained `sonar.java.binaries`,
`sonar.coverage.jacoco.xmlReportPaths` and per-module properties shown
in [Example: Java Maven Multi-Module
Project](#example-java-maven-multi-module-project), which drift out of
step with the reactor as modules come and go.

Maven mode analyses an existing build; it does not create one. The
caller must provision Maven and run the build (including tests and
coverage, since the quality gate measures coverage on new code)
beforehand, in the same workspace. Pair it with
`no_checkout: true` when an earlier step already checked out and built
the project:

```yaml
- name: 'Build'
  uses: lfreleng-actions/maven-build-action@<sha>  # vX.Y.Z
  with:
    java-version: '21'
    mvn-phases: 'clean install'

- name: 'SonarQube scan'
  uses: lfreleng-actions/sonarqube-cloud-scan-action@<sha>  # vX.Y.Z
  with:
    sonar_token: ${{ secrets.SONAR_TOKEN }}
    analysis_mode: 'maven'
    no_checkout: true
    wait_for_quality_gate: true
    fail_on_quality_gate: true
```

Both modes accept the same `-Dsonar.*` properties, so
`sonar_organization`, `sonar_project_key`, the branch-decoration inputs
and `args` behave identically. The `scanner_*`, `scanner_java_opts`,
`skip_jre_provisioning` and `sonar_root_cert` inputs configure the
Scanner CLI and have no effect in Maven mode; use `maven_args` (for
example `--settings /path/settings.xml`) and the standard `MAVEN_OPTS`
environment variable instead. A self-hosted instance behind a private
CA needs that certificate in the JVM truststore for Maven mode, for
example:

<!-- markdownlint-disable MD046 -->

```yaml
  env:
    MAVEN_OPTS: >-
      -Djavax.net.ssl.trustStore=/path/truststore.jks
      -Djavax.net.ssl.trustStorePassword=${{ secrets.TRUSTSTORE_PASSWORD }}
```

<!-- markdownlint-enable MD046 -->

Project identity carries across too. The Scanner CLI reads
`sonar-project.properties` directly, whereas `sonar-maven-plugin` reads
the Maven project model alone and would otherwise derive a project key
from the POM coordinates. Maven mode thus forwards the
`sonar.organization` and `sonar.projectKey` values the action resolved
from that file (or from the config it generates when none exists), so
both backends analyse the same project without extra configuration.

This action pins the plugin version to a current release rather than
tracking `LATEST`, so an upstream publish cannot change analysis
behaviour unnoticed. Override `maven_sonar_plugin_version` to pin a
different release -- for example `3.9.1.2184` for parity with an older
pipeline. The default requires Java 11 or newer.

The action passes the credential through the `SONAR_TOKEN` environment
variable, which the plugin reads natively, so it never appears on the
Maven command line.

### Note: argument inputs are whitespace-separated

The `args` and `maven_args` inputs split on whitespace when the action
hands them to the backend, so a single argument cannot itself contain
spaces: quoting inside the input value does not survive. A value such as
`-Dsonar.projectName="My Project"` or
`--settings "/path with spaces/settings.xml"` reaches the tool as two
separate arguments.

Prefer forms without embedded spaces, and pass identity fields through
the dedicated inputs (`sonar_project_key`, `sonar_organization`,
`sonar_branch_name`, `sonar_branch_target`, `sonar_gerrit_project`,
`coverage_report_paths`),
which the action validates and assembles for you.

### Note: Asserting on scanner arguments

The `scanner_args` output carries the `-Dsonar.*` properties this
action derives from its own typed inputs, after workspace-variable
expansion. It exists so a caller can prove a property it supplied
reached the scan.

That matters because the failure is silent. Drop an input from a
caller's `with:` block and the scan still succeeds, because the
backend falls back to its own discovery. Coverage is the sharpest
case: `sonar.coverage.jacoco.xmlReportPaths` going missing does not
produce an error, it produces a *different* coverage figure, which is
indistinguishable from a correct one.

```yaml
      - name: 'Scan'
        id: scan
        uses: lfreleng-actions/sonarqube-cloud-scan-action@<sha>
        with:
          sonar_token: ${{ secrets.SONAR_TOKEN }}
          coverage_report_paths: ${{ steps.build.outputs.coverage_report_paths }}

      - name: 'Confirm coverage reached the analysis'
        shell: bash
        env:
          ARGS: ${{ steps.scan.outputs.scanner_args }}
          EXPECTED: ${{ steps.build.outputs.coverage_report_paths }}
        run: |
          # Compare the value, not the property name alone: matching
          # the name still passes when the scan lost or replaced the
          # paths, which is the failure this check exists for.
          if [ -z "${EXPECTED}" ]; then
            echo '::error::The build produced no coverage report paths'
            exit 1
          fi
          # Pad both sides so the pattern matches a WHOLE argument.
          # Without the trailing space, EXPECTED=report.xml would also
          # match an argument ending report.xml.bak.
          case " ${ARGS} " in
            *" -Dsonar.coverage.jacoco.xmlReportPaths=${EXPECTED} "*) ;;
            *)
              echo '::error::Coverage paths did not reach the scan'
              echo "  expected: ${EXPECTED}"
              echo "  actual:   ${ARGS}"
              exit 1
              ;;
          esac
```

The output carries values after workspace-variable expansion, so a
path written as `${GITHUB_WORKSPACE}/target/...` appears resolved.
Compare against the expanded form, or keep those variables out of the
value you assert on.

#### What it covers

Properties this action builds from its own inputs:

<!-- markdownlint-disable MD013 -->

| Input                   | Property                               |
| ----------------------- | -------------------------------------- |
| `sonar_organization`    | `sonar.organization`                   |
| `sonar_project_key`     | `sonar.projectKey`                     |
| `sonar_branch_name`     | `sonar.branch.name`                    |
| `sonar_branch_target`   | `sonar.branch.target`                  |
| `sonar_gerrit_project`  | `sonar.analysis.gerritProjectName`     |
| `coverage_report_paths` | `sonar.coverage.jacoco.xmlReportPaths` |

<!-- markdownlint-enable MD013 -->

#### What it does not cover

- **The free-form `args` input**, by design. See below.
- **`maven_args`**, which `maven` mode expands separately into the
  same `mvn` invocation.
- **Arguments each backend adds later.** Maven mode appends
  `-Dsonar.host.url`, and `-Dsonar.verbose` when `debug` is on, after
  the action builds this value. So a property from `sonar_host_url`
  will not appear here even though the analysis received it.
- **Changes the backend makes to the string.** Maven mode expands the
  argument string unquoted, which also performs pathname expansion, so
  a value containing glob syntax can reach `mvn` in a different form
  from the one reported here.

Assert on the typed inputs in the table; anything reaching the backend
another way produces a false failure.

#### What the output can contain

The action places no credential here itself. The six values above are
the caller's own, though, and GitHub resolves a secret expression in a
typed input before the action runs, so
`sonar_project_key: ${{ secrets.INTERNAL_KEY }}` does appear in this
output.

The output is **bounded** rather than unconditionally safe to log: six
named fields holding identifiers, branch names and report paths, none
of them a credential field, each visible at the call site. Treat the
output as sensitive if you put something sensitive in those six
inputs.

#### Why the action excludes `args`

This action puts no credential on the command line — `sonar_token`
reaches the backends through the environment, and the quality gate
through a curl config file on stdin. A caller can, though, because a
GitHub expression in `args` resolves before the action runs:

```yaml
          # Do NOT do this. The token is visible in the runner's
          # process list, and the legacy sonar.login property is
          # deprecated. Use the sonar_token input instead.
          args: -Dsonar.login=${{ secrets.SONAR_TOKEN }}
```

An earlier revision of this output published the whole assembled
string and tried to detect that case. Nothing made it reliable:
the string is free-form text read by `parseArgsStringToArgv` in CLI
mode, by shell word-splitting *and* pathname expansion in Maven mode,
and the two disagree about quoting. Review found seven distinct ways
past successive versions of the check.

Publishing what the action itself derived removes the question. No
`args` content reaches this output, so nothing a caller writes *there*
can, whatever they put in it and whichever way the backend reads it.
The six typed values remain, which is why the section above bounds the
claim rather than dropping it.

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
