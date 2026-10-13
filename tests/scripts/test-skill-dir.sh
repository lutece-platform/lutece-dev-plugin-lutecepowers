#!/usr/bin/env bash
# Checks that the e2e tools never write in the skill's folder: review.py --help prints its usage and exits 0, and every
# tool run from the skill without E2E_DIR refuses it, leaving no artifacts behind.
set -u
. "$(dirname "$0")/../../tools/python.sh"
SKILL=$(cd "$(dirname "$0")/../../skills/lutece-e2e" && pwd)
export PYTHONDONTWRITEBYTECODE=1
fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
before=$(cd "$SKILL" && find . -path '*/__pycache__' -prune -o -type f -print | sort | sha1sum)
OUT=$(cd "$SKILL" && env -u E2E_DIR python3 tools/review.py --help 2>&1); RC=$?
check "review.py --help prints its usage and exits 0" "[ $RC -eq 0 ] && echo \"\$OUT\" | grep -q '^usage: review.py'"
for t in review.py causes.py report.py coverage.py; do
  ERR=$(cd "$SKILL" && env -u E2E_DIR python3 "tools/$t" 2>&1 > /dev/null); RC=$?
  check "$t run from the skill without E2E_DIR refuses it" "[ $RC -ne 0 ] && echo \"\$ERR\" | grep -q 'is the skill, not a project'"
done
after=$(cd "$SKILL" && find . -path '*/__pycache__' -prune -o -type f -print | sort | sha1sum)
check "nothing written in the skill's folder" "[ '$before' = '$after' ] && [ ! -e '$SKILL/artifacts' ]"
[ $fail -eq 0 ] || exit 1
