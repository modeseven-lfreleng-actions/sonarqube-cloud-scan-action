#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation
#
# Checks the workspace-variable expansion the action applies to the
# scanner and Maven arguments. The list of names it expands is a
# security boundary: the scan step holds SONAR_TOKEN, so a typo that
# widened the list, or a change that swapped the allowlist for a blanket
# expansion, would place a credential on a command line.
#
# The function comes out of action.yaml rather than living here twice,
# so this checks what the action runs.

# Single quotes throughout the cases below: the point is to hand the
# function the literal text a caller writes, and let it do the
# expanding. SC2016 reads that as a mistake.
# shellcheck disable=SC2016

set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${SCRIPT_DIR}/../action.yaml"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A composite action gives each step its own shell, so the helper appears
# once per step that needs it: the scan-args step, which serves both
# analysis modes, and the Maven step, which handles maven_args. Pull out
# every copy and require them to agree, so a typo in one cannot leave
# that step expanding a different set of names from the other.
awk -v out="$WORK" '
  /^        expand_workspace_vars\(\) \{/ { n++; f = 1 }
  f { print > (out "/fn" n ".sh") }
  f && /^        \}$/ { f = 0 }
  END { print n }
' "$ACTION" | tail -n1 > "$WORK/count"
COPIES="$(cat "$WORK/count")"

EXPECTED_COPIES=2
if [ "${COPIES:-0}" -ne "$EXPECTED_COPIES" ]; then
  echo "Found ${COPIES:-0} copies of expand_workspace_vars in" >&2
  echo "${ACTION}; expected ${EXPECTED_COPIES}." >&2
  echo 'Adjust EXPECTED_COPIES once the step count changes.' >&2
  exit 1
fi

for copy in "$WORK"/fn*.sh; do
  sed -i 's/^        //' "$copy"
  if ! cmp -s "$WORK/fn1.sh" "$copy"; then
    echo "Copies of expand_workspace_vars differ: fn1 vs $(basename "$copy")" >&2
    diff "$WORK/fn1.sh" "$copy" >&2 || true
    exit 1
  fi
done

# shellcheck source=/dev/null
. "$WORK/fn1.sh"

export GITHUB_WORKSPACE=/home/runner/work/p/p
export GITHUB_REPOSITORY=org/proj
export GITHUB_REF_NAME=main
export GITHUB_SHA=deadbeef
export GITHUB_RUN_ID=42
export RUNNER_TEMP=/tmp/rt
export RUNNER_OS=Linux
# Stand-ins for the credentials the scan step holds.
export GITHUB_TOKEN=token-must-not-appear
export SONAR_TOKEN=token-must-not-appear
export GITHUB_REPOSITORY_OWNER=org
export CALLER_SECRET=token-must-not-appear

passed=0
failed=0

check() {
  local input="$1" want="$2" got
  got="$(expand_workspace_vars "$input")"
  if [ "$got" = "$want" ]; then
    passed=$((passed + 1))
    echo "ok   ${input}"
  else
    failed=$((failed + 1))
    echo "FAIL ${input}"
    echo "       want: ${want}"
    echo "       got : ${got}"
  fi
}

echo '--- the allowed names expand'
check '-Dsonar.coverage.jacoco.xmlReportPaths=${GITHUB_WORKSPACE}/t.xml' \
  '-Dsonar.coverage.jacoco.xmlReportPaths=/home/runner/work/p/p/t.xml'
check '-Dx=$GITHUB_WORKSPACE/a' '-Dx=/home/runner/work/p/p/a'
check '-Dr=${GITHUB_REPOSITORY} -Db=${GITHUB_REF_NAME}' \
  '-Dr=org/proj -Db=main'
check '-Ds=${GITHUB_SHA} -Di=${GITHUB_RUN_ID}' '-Ds=deadbeef -Di=42'
check '${RUNNER_TEMP}/x ${RUNNER_OS}' '/tmp/rt/x Linux'

echo '--- credentials stay literal'
check '-Dt=${SONAR_TOKEN}' '-Dt=${SONAR_TOKEN}'
check '-Dt=$SONAR_TOKEN' '-Dt=$SONAR_TOKEN'
check '-Dt=${GITHUB_TOKEN}' '-Dt=${GITHUB_TOKEN}'
check '-Dt=${CALLER_SECRET}' '-Dt=${CALLER_SECRET}'

echo '--- a name sharing a prefix with an allowed one stays literal'
check '-Do=$GITHUB_REPOSITORY_OWNER' '-Do=$GITHUB_REPOSITORY_OWNER'
check '-Do=${GITHUB_REPOSITORY_OWNER}' '-Do=${GITHUB_REPOSITORY_OWNER}'

echo '--- Maven placeholders reach Maven'
check '-Dd=${project.build.directory}' '-Dd=${project.build.directory}'
check '-Ds=${settings.localRepository}' '-Ds=${settings.localRepository}'
check '-Dj=${jacoco.destFile}' '-Dj=${jacoco.destFile}'

echo '--- nothing runs'
check '-Dx=$(id -u)' '-Dx=$(id -u)'
check '-Dx=`id -u`' '-Dx=`id -u`'
check '-Dx=$((1+1))' '-Dx=$((1+1))'
check '-Dx=$1 $9 $@ $*' '-Dx=$1 $9 $@ $*'

echo '--- edges'
check 'a$GITHUB_RUN_ID-b${GITHUB_RUN_ID}c$(x)' 'a42-b42c$(x)'
check '$$GITHUB_RUN_ID' '$42'
check 'no dollars here' 'no dollars here'
check '' ''
check '$' '$'
check '${' '${'
check '${GITHUB_WORKSPACE' '${GITHUB_WORKSPACE'
check "$(printf 'x\n-Dy=${GITHUB_WORKSPACE}/z')" \
  "$(printf 'x\n-Dy=/home/runner/work/p/p/z')"

# A name on the list carrying no value gives an empty string, which
# reads as the caller asking for one, rather than the literal text.
if [ "$(RUNNER_OS='' expand_workspace_vars '[${RUNNER_OS}]')" = '[]' ]; then
  passed=$((passed + 1))
  echo 'ok   an empty allowed name gives an empty string'
else
  failed=$((failed + 1))
  echo 'FAIL an empty allowed name gives an empty string'
fi

echo "---- passed=${passed} failed=${failed}"
[ "$failed" -eq 0 ]
