#!/usr/bin/env bash
# checkup.sh — every mechanical check of a Lutece 8 project in one pass, then a short summary.
#
#   checkup.sh [project_dir]
#
# Runs verify-migration.sh, scan-template-design.py, check-i18n-keys.sh and check-template-parse.sh on the project,
# keeps their full output under <project>/target/checkup/, and prints one block per tool: its verdict and the
# findings to act on (FAIL and WARN lines, INFO counted). Nothing is changed in the project. Exit 1 when a tool
# reports a blocking finding (a FAIL, an unresolved i18n key, a template that does not parse), else 0.
set -uo pipefail
ROOT=$(cd "${1:-.}" && pwd)
S="$(cd "$(dirname "$0")/../../lutece-migration-v8-agent-teams/scripts" && pwd)"
OUT="$ROOT/target/checkup"
mkdir -p "$OUT"
cd "$ROOT"
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
blocking=0

# Runs one tool and keeps its colour-free output.
run() {
    local name=$1; shift
    "$@" > "$OUT/$name.txt" 2>&1
    strip < "$OUT/$name.txt" > "$OUT/$name.clean.txt"
}

run verify bash "$S/verify-migration.sh" .
run scanner python3 "$S/scan-template-design.py" . --flat
run i18n bash "$S/check-i18n-keys.sh" .
run parse bash "$S/check-template-parse.sh" .

echo "== verify-migration"
V="$OUT/verify.clean.txt"
f=$(grep -cE "^\s+FAIL \[" "$V"); w=$(grep -cE "^\s+WARN \[" "$V")
echo "   $f FAIL, $w WARN"
grep -E "^\s+(FAIL|WARN) \[" "$V" | sed 's/^ */   /' | cut -c1-160
[ "$f" -eq 0 ] || blocking=1
grep -q "^RESULT:" "$V" || { echo "   stopped before the end:"; tail -3 "$V" | sed 's/^/   /'; blocking=1; }

echo "== scan-template-design"
C="$OUT/scanner.clean.txt"
w=$(grep -c " WARN " "$C"); i=$(grep -c " INFO " "$C")
echo "   $w WARN, $i INFO"
grep " WARN " "$C" | sed 's/^/   /' | cut -c1-160
[ "$i" -eq 0 ] || grep " INFO " "$C" | awk '{print $2}' | sort | uniq -c | sort -rn | awk '{printf "   INFO %s x%s\n", $2, $1}'
grep -q "scan not performed" "$C" && { grep -A3 "scan not performed" "$C" | sed 's/^/   /'; blocking=1; }

echo "== check-i18n-keys"
I="$OUT/i18n.clean.txt"
line=$(grep "^I18NKEYS" "$I" | tail -1)
echo "   ${line:-no summary line, see $I}"
u=$(echo "$line" | grep -o "unresolved=[0-9]*" | cut -d= -f2)
[ "${u:-1}" -eq 0 ] || { grep -E "unresolved|missing" "$I" | grep -v "^I18NKEYS" | head -10 | sed 's/^/   /'; blocking=1; }

echo "== check-template-parse"
P="$OUT/parse.clean.txt"
line=$(grep "^FMPARSE" "$P" | tail -1)
echo "   ${line:-no summary line, see $P}"
e=$(echo "$line" | grep -o "errors=[0-9]*" | cut -d= -f2)
[ "${e:-1}" -eq 0 ] || { grep -v "^FMPARSE" "$P" | head -10 | sed 's/^/   /'; blocking=1; }

echo "== full outputs: $OUT/{verify,scanner,i18n,parse}.txt"
exit $blocking
