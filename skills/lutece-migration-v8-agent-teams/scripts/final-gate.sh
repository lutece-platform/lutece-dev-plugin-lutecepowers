#!/bin/bash
# final-gate.sh — the postcondition of a migration. Run it after EVERY batch of fixes, never once at the end.
#
#   final-gate.sh [project_dir] [--no-e2e]
#
# Re-measures the three things a fix can silently invalidate, and fails on the first one that is not clean:
#   1. verify-migration.sh          — 0 FAIL
#   2. unit tests                   — 0 failures and 0 errors read from surefire, NOT from BUILD SUCCESS
#                                     (the 8.x parent sets testFailureIgnore, so the build status means nothing)
#   3. e2e bench, when e2e/ exists  — every suite green
#
# Why a script and not a rule: a rule is skipped by whoever is convinced their last edit was harmless. A fix to a
# portlet invalidates the unit tests that asserted on its rendering, and a fix to a defect turns the scenario that
# pinned it red.
set -uo pipefail

case "${1:-}" in
  -h|--help)
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
esac

PROJECT="${1:-.}"
[ "$PROJECT" = "--no-e2e" ] && PROJECT="."
RUN_E2E=true
for a in "$@"; do [ "$a" = "--no-e2e" ] && RUN_E2E=false; done

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${E2E_MVN_SETTINGS:-$HOME/.m2/settings.xml}"
cd "$PROJECT" || { echo "no such directory: $PROJECT"; exit 2; }

FAILED=0
step( ) { printf '\n\033[1m== %s\033[0m\n' "$1"; }
bad( ) { printf '\033[0;31mFAIL\033[0m %s\n' "$1"; FAILED=1; }
good( ) { printf '\033[0;32mOK\033[0m   %s\n' "$1"; }

step "1/4 migration checks"
if bash "$SKILL_DIR/verify-migration.sh" . > /tmp/final-gate-verify.log 2>&1; then
    good "verify-migration.sh: 0 FAIL"
else
    grep -E "^  .*FAIL" /tmp/final-gate-verify.log | head -10
    bad "verify-migration.sh reports failures (full log: /tmp/final-gate-verify.log)"
fi

# A migration is the moment the compiler's warnings get fixed: deprecation, unchecked, rawtypes, serial, the
# lot. Left in place they hide the next real one, and nobody comes back for them later. Only the plugin's own
# sources count (src/), never the generated or the dependencies'.
step "2/4 compiler warnings"
mvn -B -s "$SETTINGS" clean compile -Dmaven.compiler.showWarnings=true -Dmaven.compiler.showDeprecation=true > /tmp/final-gate-compile.log 2>&1 || true
WARNS=$(grep -E "^\[WARNING\] .*/src/.*\.java" /tmp/final-gate-compile.log | sed 's|^\[WARNING\] ||; s|^.*/src/|src/|' | sort -u)
NW=$(printf '%s' "$WARNS" | grep -c . || true)
if grep -q "BUILD FAILURE" /tmp/final-gate-compile.log; then
    grep -E "^\[ERROR\]" /tmp/final-gate-compile.log | head -8
    bad "the project does not compile (full log: /tmp/final-gate-compile.log)"
elif [ "$NW" -eq 0 ]; then
    good "compiler: 0 warning in the plugin's sources"
else
    printf '%s\n' "$WARNS" | head -12
    bad "compiler: $NW warning(s) in the plugin's sources — fix them, a migration leaves none behind (full log: /tmp/final-gate-compile.log)"
fi

step "3/4 unit tests"
if [ -d src/test/java ] && find src/test/java -name "*Test.java" | grep -q .; then
    # lutece:exploded only exists for a core, a plugin or a site: a library runs its tests plainly.
    if grep -q "<packaging>jar</packaging>" pom.xml 2>/dev/null; then
        mvn -B -s "$SETTINGS" clean test > /tmp/final-gate-tests.log 2>&1
    else
        mvn -B -s "$SETTINGS" clean lutece:exploded antrun:run -Dlutece-test-hsql test > /tmp/final-gate-tests.log 2>&1
    fi
    # Every surefire file, never just the last one: with two test classes, reading `tail -1` reported the second
    # one's clean summary while the first was red, and the gate passed on a failing build.
    SUMS=$(grep -hE "^Tests run:" target/surefire-reports/*.txt 2>/dev/null)
    DIRTY=$(echo "$SUMS" | grep -vE "Failures: 0, Errors: 0" | grep -E "^Tests run:")
    TOTAL=$(echo "$SUMS" | awk -F'[ ,]+' '{r+=$3; f+=$5; e+=$7; s+=$9} END {printf "%d tests, %d failures, %d errors, %d skipped, in %d class(es)", r, f, e, s, NR}')
    if [ -z "$SUMS" ]; then
        tail -5 /tmp/final-gate-tests.log
        bad "no surefire report produced (full log: /tmp/final-gate-tests.log)"
    elif [ -z "$DIRTY" ]; then
        good "unit tests: $TOTAL"
    else
        grep -hE "^Tests run:|<<< (FAILURE|ERROR)" target/surefire-reports/*.txt 2>/dev/null | head -8
        bad "unit tests: $TOTAL (BUILD SUCCESS means nothing here, the parent sets testFailureIgnore)"
    fi
else
    good "unit tests: none in this project"
fi

step "4/4 e2e bench"
if ! $RUN_E2E; then
    good "e2e: skipped on request"
elif [ -x e2e/run.sh ]; then
    if KEEP=1 ./e2e/run.sh > /tmp/final-gate-e2e.log 2>&1; then
        grep -E "passed|failed" /tmp/final-gate-e2e.log | tail -4
        good "e2e bench: rc=0"
    else
        grep -E "FAILED|passed|failed" /tmp/final-gate-e2e.log | tail -8
        bad "e2e bench failed (full log: /tmp/final-gate-e2e.log)"
    fi
elif [ ! -d webapp ] && grep -q "<packaging>jar</packaging>" pom.xml 2>/dev/null; then
    # A library has no screen: a bench of its own would prove nothing. Its proof is that a plugin depending on it
    # still passes its own bench, which happens when that plugin is migrated. Say so rather than fake a bench.
    good "e2e: none, this artefact is a library — prove it through a consumer plugin's bench"
else
    bad "no e2e bench: Phase G of the skill builds one with lutece-e2e, the gate is not complete without it (--no-e2e to skip while iterating)"
fi

step "untracked files created by the migration"
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    UNTRACKED=$(git status --porcelain | grep '^??' | grep -vE '^\?\? (target/|logs/|e2e/artifacts/|java\.io\.tmpdir/)' || true)
    if [ -n "$UNTRACKED" ]; then
        echo "$UNTRACKED"
        echo "  stage them with 'git add -A', never 'git commit -a': it leaves new files behind."
    else
        good "nothing untracked outside build output"
    fi
fi

printf '\n'
if [ "$FAILED" -eq 0 ]; then
    printf '\033[0;32mGATE PASSED\033[0m — every check re-measured after the last edit\n'
    exit 0
fi
printf '\033[0;31mGATE FAILED\033[0m — do not report this migration as done\n'
exit 1
