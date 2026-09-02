#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation
#
# Checks that the scanner_args output carries what this action derived
# from its own typed inputs, and never the caller's free-form 'args'.
#
# The exclusion is the property under test. It bounds the output
# rather than emptying it: the six typed values are still the
# caller's, and a secret placed in one of those inputs does appear.
# What cannot appear is free-form 'args' content.
#
# A caller can interpolate
# a secret into 'args' -- a GitHub expression there resolves before the
# action runs -- and no bash inspection of that string can reliably
# tell a credential from ordinary text, because CLI mode parses it with
# parseArgsStringToArgv while Maven mode applies shell word-splitting
# and pathname expansion, and the two disagree about quoting. Excluding
# 'args' removes the question instead of answering it, so these tests
# check the exclusion holds rather than that a detector works.
#
# The step body comes out of action.yaml rather than living here twice,
# so this checks what the action runs. No credentials needed.

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

if [ ! -s "$WORK/scan-args.sh" ]; then
  echo "Error: could not extract the scan-args step body" >&2
  exit 1
fi

FAILURES=0

# Unmistakable in the output if it ever survived.
CANARY='s3cr3t-canary-value'

# The literal text a caller writes for a workspace variable. Held in
# a variable so the value stays unexpanded here: the step under test
# is what should resolve it.
# shellcheck disable=SC2016
WS_LITERAL='${GITHUB_WORKSPACE}'

# Every variable the step reads, so it runs outside a workflow. Named
# arguments keep the call sites readable as the input set grows.
run_step() {
  local base_args="$1" mode="$2" coverage="${3:-}" org="${4:-}"
  local key="${5:-}" gerrit="${6:-}" branch="${7:-}" target="${8:-}"
  # The resolved pair defaults to the overrides, but can be set apart
  # to model maven mode reading sonar-project.properties with no
  # override supplied.
  local resolved_org="${9:-$org}" resolved_key="${10:-$key}"
  : > "$WORK/out"
  BASE_ARGS="$base_args" \
  MAVEN_ARGS_INPUT='' \
  SONAR_ORG_OVERRIDE="$org" \
  PROJECT_KEY_OVERRIDE="$key" \
  BRANCH_NAME="$branch" \
  BRANCH_TARGET="$target" \
  GERRIT_PROJECT="$gerrit" \
  COVERAGE_REPORT_PATHS="$coverage" \
  SKIP_JRE='false' \
  GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-/tmp/ws}" \
  ANALYSIS_MODE="$mode" \
  RESOLVED_ORG="$resolved_org" \
  RESOLVED_KEY="$resolved_key" \
  GITHUB_OUTPUT="$WORK/out" \
    bash "$WORK/scan-args.sh" > "$WORK/log" 2>&1
}

# Read one delimiter-form value back out of the written output file.
read_output() {
  awk -v key="$1" '
    $0 ~ "^" key "<<" { delim = substr($0, length(key) + 3); next }
    delim && $0 == delim { exit }
    delim { print }
  ' "$WORK/out"
}

fail() {
  echo "FAIL: $1"
  FAILURES=$((FAILURES + 1))
}

# The caller's free-form args must reach the scan and never the output.
excluded() {
  local desc="$1" args="$2" mode="$3"
  if ! run_step "$args" "$mode"; then
    fail "${desc} (${mode}): step exited non-zero"
    cat "$WORK/log"
    return
  fi
  local scan_args published
  scan_args="$(read_output args)"
  published="$(read_output published_args)"

  # Redacting what the backend runs with would break the analysis
  # rather than protect anything, so the scan keeps the real value.
  case "${scan_args}" in
    *"${CANARY}"*) ;;
    *) fail "${desc} (${mode}): the scan lost the caller's value" ;;
  esac

  case "${published}" in
    *"${CANARY}"*) fail "${desc} (${mode}): args reached scanner_args" ;;
    *) echo "ok: ${desc} (${mode})" ;;
  esac
}

# Forms that defeated successive versions of the detector this design
# replaces. Each has to stay out of the output; none needs recognising
# any more, which is the point.
CR="$(printf '\r')"
VT="$(printf '\v')"

for mode in cli maven; do
  excluded 'plain credential property' \
    "-Dsonar.token=${CANARY}" "${mode}"
  excluded 'legacy sonar.login' \
    "-Dsonar.login=${CANARY}" "${mode}"
  excluded 'scanner transport password' \
    "-Dsonar.scanner.proxyPassword=${CANARY}" "${mode}"
  excluded 'quoted credential argument' \
    "\"-Dsonar.token=${CANARY}\"" "${mode}"
  excluded 'adjacent quoted arguments' \
    "\"-Da=1\"\"-Dsonar.token=${CANARY}\"" "${mode}"
  excluded 'quote inside the property name' \
    "-Dsonar.to\"ken=${CANARY}" "${mode}"
  excluded 'secret containing whitespace' \
    "-Dsonar.password=head ${CANARY}" "${mode}"
  excluded 'control-character separator' \
    "-Da=1${CR}-Dsonar.token=${CANARY}" "${mode}"
  excluded 'control character inside the value' \
    "-Dsonar.token=head${VT}${CANARY}" "${mode}"
  excluded 'glob form Maven would expand' \
    "-Dsonar.[t]oken=${CANARY}" "${mode}"
  excluded 'credential on the second line' \
    "$(printf -- '-Da=1\n-Dsonar.token=%s' "${CANARY}")" "${mode}"
  # An ordinary, non-credential argument is excluded too. The output
  # is not a filtered view of 'args'; it does not contain it at all.
  excluded 'ordinary argument also excluded' \
    "-Dsonar.verbose=${CANARY}" "${mode}"
done

# The typed inputs are what the output is for, so each has to appear.
#
# Checked in BOTH strings. Production appends to the scan arguments and
# to the published copy separately, so an edit touching one and not the
# other would leave the output claiming a property the backend never
# received -- or the reverse. Asserting only the published copy would
# not see it.
present() {
  local desc="$1" expect="$2"
  shift 2
  if ! run_step "$@"; then
    fail "${desc}: step exited non-zero"
    cat "$WORK/log"
    return
  fi
  local ok=1
  case "$(read_output published_args)" in
    *"${expect}"*) ;;
    *) fail "${desc}: ${expect} missing from scanner_args"; ok=0 ;;
  esac
  case "$(read_output args)" in
    *"${expect}"*) ;;
    *) fail "${desc}: ${expect} never reached the scan arguments"; ok=0 ;;
  esac
  [ "${ok}" -eq 1 ] && echo "ok: ${desc}"
  return 0
}

#        desc                     expect                        args mode  coverage org key gerrit branch target
present 'coverage paths reported' \
  '-Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml' \
  '' 'cli' 'target/site/jacoco/jacoco.xml'
present 'organization reported' '-Dsonar.organization=acme' \
  '' 'maven' '' 'acme' 'demo'
present 'project key reported' '-Dsonar.projectKey=demo' \
  '' 'maven' '' 'acme' 'demo'
present 'gerrit project reported' \
  '-Dsonar.analysis.gerritProjectName=widget' \
  '' 'cli' '' '' '' 'widget'
present 'branch name reported' '-Dsonar.branch.name=feature-x' \
  '' 'cli' '' '' '' '' 'feature-x'
present 'branch target reported' '-Dsonar.branch.target=main' \
  '' 'cli' '' '' '' '' 'feature-x' 'main'

# Workspace variables are expanded in the published copy as well as in
# the scan arguments. A caller asserting on a path written with
# ${GITHUB_WORKSPACE} compares against the resolved form, and the
# README says so, so the expansion has to actually happen here.
run_step '' 'cli' "${WS_LITERAL}/target/site/jacoco/jacoco.xml"
published="$(read_output published_args)"
case "${published}" in
  *"${WS_LITERAL}"*)
    fail "workspace variable left unexpanded: ${published}"
    ;;
  *"${GITHUB_WORKSPACE:-/tmp/ws}/target/site/jacoco/jacoco.xml"*)
    echo 'ok: workspace variables expanded in the published copy'
    ;;
  *)
    fail "unexpected published value: ${published}"
    ;;
esac

# The coverage path has its own expansion pass, so the case above does
# not reach the blanket one applied to the whole derived string. The
# identity properties are appended before it, so use one of those.
# Both copies must agree: a published value that still reads
# ${GITHUB_WORKSPACE} while the scan received the resolved path would
# make every assertion on it wrong.
run_step '' 'cli' '' '' '' "${WS_LITERAL}-widget"
published="$(read_output published_args)"
case "${published}" in
  *"${WS_LITERAL}"*)
    fail "derived string left unexpanded: ${published}"
    ;;
  *"${GITHUB_WORKSPACE:-/tmp/ws}-widget"*)
    echo 'ok: the derived string gets the same expansion as the scan'
    ;;
  *)
    fail "unexpected published value: ${published}"
    ;;
esac

# In maven mode the organization and project key are resolved from the
# repository's sonar-project.properties when the override inputs are
# empty. Those resolved values reach the scan but must NOT reach the
# output: they are caller-supplied file content, and the contract
# promises an empty value when no typed input was set.
run_step '' 'maven' '' '' '' '' '' '' 'from-file-org' 'from-file-key'
scan_args="$(read_output args)"
case "${scan_args}" in
  *-Dsonar.organization=from-file-org*)
    if [ -z "$(read_output published_args)" ]; then
      echo 'ok: maven-resolved org/key reach the scan, not the output'
    else
      fail "maven-resolved values leaked: $(read_output published_args)"
    fi
    ;;
  *)
    fail 'maven-resolved organization did not reach the scan'
    ;;
esac

# A run setting none of the typed inputs publishes nothing, rather
# than leaking the caller's args by default.
run_step "-Dsonar.token=${CANARY}" 'cli'
if [ -z "$(read_output published_args)" ]; then
  echo 'ok: no typed inputs yields an empty output'
else
  fail 'expected an empty output when no typed input was set'
fi

if [ "${FAILURES}" -ne 0 ]; then
  echo "${FAILURES} check(s) failed"
  exit 1
fi
echo 'All scanner_args exclusion checks passed'
