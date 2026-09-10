#!/bin/bash
# add-liquibase-headers.sh — Add Liquibase headers to all SQL files
# Usage: bash add-liquibase-headers.sh [project_root] [plugin_name]
# The changeset author is the plugin name: <name> of webapp/WEB-INF/plugins/*.xml,
# else the project artifactId without its plugin-/module-/library- prefix.

set -euo pipefail

PROJECT_ROOT="${1:-.}"
PLUGIN_NAME="${2:-}"

# Prints the <name> of the first plugin descriptor found under webapp/WEB-INF/plugins.
plugin_name_from_descriptor() {
    local f
    f=$(find "$PROJECT_ROOT/webapp/WEB-INF/plugins" -maxdepth 1 -name '*.xml' 2>/dev/null | sort | head -1)
    [ -n "$f" ] || return 0
    grep -m1 -o '<name>[^<]*</name>' "$f" | sed 's/<[^>]*>//g' | tr -d ' \r'
}

# Prints the project artifactId (the one outside <parent>) stripped of its plugin-/module-/library- prefix.
plugin_name_from_pom() {
    [ -f "$PROJECT_ROOT/pom.xml" ] || return 0
    sed '/<parent>/,/<\/parent>/d' "$PROJECT_ROOT/pom.xml" \
        | grep -m1 -o '<artifactId>[^<]*</artifactId>' \
        | sed 's/<[^>]*>//g; s/^\(plugin\|module\|library\)-//' | tr -d ' \r'
}

[ -n "$PLUGIN_NAME" ] || PLUGIN_NAME=$(plugin_name_from_descriptor)
[ -n "$PLUGIN_NAME" ] || PLUGIN_NAME=$(plugin_name_from_pom)
if [ -z "$PLUGIN_NAME" ]; then
    echo "ERROR: cannot determine the plugin name; pass it as second argument" >&2
    exit 1
fi

echo "=== Liquibase Header Insertion ==="
echo "Project: $PROJECT_ROOT"
echo "Plugin: $PLUGIN_NAME"
echo ""

TOTAL=0

while read -r file; do
    [ -z "$file" ] && continue
    if head -1 "$file" | grep -q 'liquibase formatted sql'; then
        echo "  SKIP: $file (header exists)"
        continue
    fi

    SCRIPT_NAME=$(basename "$file")
    sed -i "1i\\-- liquibase formatted sql\\n-- changeset ${PLUGIN_NAME}:${SCRIPT_NAME}\\n-- preconditions onFail:MARK_RAN onError:WARN" "$file"

    echo "  ADDED: $file"
    TOTAL=$((TOTAL + 1))
done < <(find "$PROJECT_ROOT/src" -name "*.sql" 2>/dev/null | sort)

echo ""
echo "=== RESULT ==="
echo "Files modified: $TOTAL"
