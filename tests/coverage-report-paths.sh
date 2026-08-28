#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation
#
# Checks the coverage_report_paths input end to end through the
# argument-assembly step: the value must be validated, appended as
# sonar.coverage.jacoco.xmlReportPaths, and take part in workspace
# variable expansion, for both analysis modes. The step body comes out
# of action.yaml rather than living here twice, so this checks what the
# action runs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${SCRIPT_DIR}/../action.yaml"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Pull the 'Build scanner arguments' step's run block out of the
# action: from the "run: |" that follows "id: scan-args" until the
# indentation drops back below the block's eight spaces.
awk '
  /^      id: scan-args$/ { in_step = 1 }
  in_step && /^      run: \|$/ { in_run = 1; next }
  in_run {
    if ($0 ~ /^        / || $0 == "") { print; next }
    exit
  }
' "$ACTION" | sed 's/^        //' > "$WORK/scan-args.sh"

if ! grep -q 'COVERAGE_REPORT_PATHS' "$WORK/scan-args.sh"; then
  echo 'Extraction failed: scan-args body lacks COVERAGE_REPORT_PATHS' >&2
  exit 1
fi

export GITHUB_WORKSPACE=/home/runner/work/p/p

# Environment contract of the scan-args step. Each case overrides what
# it exercises.
base_env() {
  export BASE_ARGS=''
  export MAVEN_ARGS_INPUT=''
  export SONAR_ORG_OVERRIDE=''
  export PROJECT_KEY_OVERRIDE=''
  export BRANCH_NAME=''
  export BRANCH_TARGET=''
  export GERRIT_PROJECT=''
  export COVERAGE_REPORT_PATHS=''
  export SKIP_JRE=false
  export ANALYSIS_MODE=cli
  export RESOLVED_ORG=org
  export RESOLVED_KEY=key
}

# Runs the extracted step body and captures the 'args' output it writes.
run_step() {
  local out="$WORK/gh-output" rc=0
  : > "$out"
  GITHUB_OUTPUT="$out" bash "$WORK/scan-args.sh" > "$WORK/stdout" \
    2> "$WORK/stderr" || rc=$?
  sed -n '/^args<</,/^ARGS_EOF/{/^args<</d;/^ARGS_EOF/d;p;}' "$out"
  return "$rc"
}

passed=0
failed=0

report() {
  local ok="$1" label="$2" detail="${3-}"
  if [ "$ok" = yes ]; then
    passed=$((passed + 1))
    echo "ok   ${label}"
  else
    failed=$((failed + 1))
    echo "FAIL ${label}"
    [ -n "$detail" ] && echo "       ${detail}"
  fi
}

echo '--- a workspace-anchored path expands into the property'
base_env
# shellcheck disable=SC2016
COVERAGE_REPORT_PATHS='${GITHUB_WORKSPACE}/target/site/jacoco/jacoco.xml'
args="$(run_step)"
want='-Dsonar.coverage.jacoco.xmlReportPaths=/home/runner/work/p/p/target/site/jacoco/jacoco.xml'
case " $args " in
  *" $want "*) report yes 'cli mode carries the expanded property' ;;
  *) report no 'cli mode carries the expanded property' "got: $args" ;;
esac

echo '--- maven mode assembles the same property'
base_env
COVERAGE_REPORT_PATHS='module-a/target/site/jacoco/jacoco.xml,module-b/target/site/jacoco/jacoco.xml'
ANALYSIS_MODE=maven
args="$(run_step)"
want='-Dsonar.coverage.jacoco.xmlReportPaths=module-a/target/site/jacoco/jacoco.xml,module-b/target/site/jacoco/jacoco.xml'
case " $args " in
  *" $want "*) report yes 'maven mode carries the comma-separated list' ;;
  *) report no 'maven mode carries the comma-separated list' "got: $args" ;;
esac

echo '--- an empty value adds nothing'
base_env
args="$(run_step)"
case "$args" in
  *xmlReportPaths*) report no 'empty input leaves the property unset' "got: $args" ;;
  *) report yes 'empty input leaves the property unset' ;;
esac

echo '--- whitespace is rejected with the path-specific message'
base_env
COVERAGE_REPORT_PATHS='a.xml b.xml'
if run_step > /dev/null 2>&1; then
  report no 'a value carrying whitespace fails the step'
else
  report yes 'a value carrying whitespace fails the step'
fi
if grep -q 'report paths containing whitespace are unsupported' \
  "$WORK/stderr"; then
  report yes 'the rejection names the real limitation'
else
  report no 'the rejection names the real limitation' \
    "stderr: $(cat "$WORK/stderr")"
fi

echo '--- a variable resolving to whitespace is rejected too'
# Validation applies to the expanded value: a self-hosted runner whose
# workspace path carries a space must fail the step rather than hand
# the backend a corrupted, word-split property.
base_env
# shellcheck disable=SC2016
COVERAGE_REPORT_PATHS='${GITHUB_WORKSPACE}/report.xml'
export GITHUB_WORKSPACE='/home/run ner/work/p'
if run_step > /dev/null 2>&1; then
  report no 'a workspace path carrying whitespace fails the step'
else
  report yes 'a workspace path carrying whitespace fails the step'
fi
if grep -q 'after workspace variable expansion' "$WORK/stderr"; then
  report yes 'the rejection names the expansion'
else
  report no 'the rejection names the expansion' \
    "stderr: $(cat "$WORK/stderr")"
fi
export GITHUB_WORKSPACE=/home/runner/work/p/p

echo
echo "passed: ${passed}  failed: ${failed}"
[ "$failed" -eq 0 ]
