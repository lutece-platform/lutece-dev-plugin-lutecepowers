#!/bin/bash
# restore-line-endings.sh — Restore the line endings a file had before the migration.
# Usage: bash restore-line-endings.sh [project_root]
#
# An editor that saves in the other convention rewrites every line of the file: the diff then shows the whole
# file and the migration is invisible in it, so the review cannot happen. This restores the endings HEAD has,
# on the files where the diff is mostly endings (verify-migration.sh, check LE01), and leaves the content alone.

set -uo pipefail
cd "${1:-.}" || exit 1
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git work tree"; exit 2; }

# Same rule as LE01: the file counts as converted when HEAD and the work tree disagree on carriage returns,
# whatever else changed in it. The content is left alone, only the endings move.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git diff HEAD --name-only --diff-filter=M > "$TMP/files"

N=0
while read -r f; do
    [ -f "$f" ] || continue
    head_cr=$(git show "HEAD:$f" 2>/dev/null | head -c 20000 | grep -c $'\r' || true)
    work_cr=$(head -c 20000 "$f" | grep -c $'\r' || true)
    if [ "$head_cr" -gt 0 ] && [ "$work_cr" -eq 0 ]; then
        perl -pi -e 's/\n/\r\n/ unless /\r\n$/' "$f"; N=$((N+1)); echo "  LF -> CRLF  $f"
    elif [ "$head_cr" -eq 0 ] && [ "$work_cr" -gt 0 ]; then
        perl -pi -e 's/\r\n/\n/' "$f"; N=$((N+1)); echo "  CRLF -> LF  $f"
    fi
done < "$TMP/files"
echo "$N file(s) restored — run verify-migration.sh again, LE01 must pass"
