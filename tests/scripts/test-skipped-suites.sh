#!/usr/bin/env bash
# Checks skipped_suites of run.sh: a front-office JSP of the artefact without page= or page_id= (an endpoint the
# scenarios prove) does not ask for the fo suite, a front-office page of the artefact does.
set -u
. "$(dirname "$0")/../../tools/python.sh"
BENCH=$(cd "$(dirname "$0")/../../skills/lutece-e2e" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1 E2E_DIR="$T"
eval "$(awk '/^skipped_suites\(\) \{/,/^}/' "$BENCH/run.sh")"
fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
mkdir -p "$T/artifacts" "$T/scenarios"
printf '%s\n' '<testsuites><testsuite name="pytest" tests="1" skipped="1"><testcase name="test_fo_screen[NOTSET]"><skipped message="got empty parameter set for (target)"/></testcase></testsuite></testsuites>' > "$T/artifacts/junit-fo.xml"
inventory() {
  printf '{"features": [{"plugin": "mylutece", "origin": "target"}], "actions": [], "screens": [
    {"url": "jsp/site/Portal.jsp?page=mylutece", "surface": "fo", "origin": "env"},
    {"url": "%s", "surface": "fo", "origin": "target"}]}\n' "$1" > "$T/artifacts/inventory.json"
}
inventory "jsp/site/plugins/mylutece/modules/openam/IsUserAuthenticatedJson.jsp"
OUT=$(cd "$T" && skipped_suites 2>&1); RC=$?
check "a front-office JSP without page= does not ask for the fo suite" "[ $RC -eq 0 ]"
inventory "jsp/site/Portal.jsp?page=openam"
OUT=$(cd "$T" && skipped_suites 2>&1); RC=$?
check "a front-office page of the artefact the fo suite skipped entirely fails" "[ $RC -ne 0 ] && echo \"\$OUT\" | grep -q 'ENTIRELY SKIPPED.*fo'"
[ $fail -eq 0 ] || exit 1
