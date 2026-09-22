#!/bin/bash
# check-template-parse.sh — parse every template with FreeMarker itself: a template that does not parse answers 500.
# Usage: check-template-parse.sh [project_root | template_file]
# Needs a JDK and the freemarker jar in ~/.m2 (any 2.3.x); compiles the helper on first use.
set -euo pipefail

ROOT="${1:-.}"
HERE="$(cd "$(dirname "$0")" && pwd)"
JAR=$(ls "$HOME"/.m2*/repository/org/freemarker/freemarker/2.3.*/freemarker-2.3.*.jar 2>/dev/null | grep -v sources | sort -V | tail -1 || true)
[ -n "$JAR" ] || { echo "FMPARSE skipped: no freemarker jar under ~/.m2 (build the project once)"; exit 0; }
command -v javac >/dev/null || { echo "FMPARSE skipped: no javac"; exit 0; }

compile() {
    [ -f "$HERE/fmparse/FmParse.class" ] && [ "$HERE/fmparse/FmParse.class" -nt "$HERE/fmparse/FmParse.java" ] && return
    javac -cp "$JAR" -d "$HERE/fmparse" "$HERE/fmparse/FmParse.java"
}

compile
DIRS=()
if [ -f "$ROOT" ]; then
    DIRS+=("$ROOT")
else
    for d in webapp/WEB-INF/templates/admin webapp/WEB-INF/templates/skin; do [ -d "$ROOT/$d" ] && DIRS+=("$ROOT/$d"); done
fi
[ ${#DIRS[@]} -gt 0 ] || { echo "FMPARSE files=0 errors=0"; exit 0; }
java -cp "$JAR:$HERE/fmparse" FmParse "${DIRS[@]}"
