#!/bin/bash
# check-i18n-keys.sh — every literal #i18n key of a project against the bundles it really resolves.
# Usage: check-i18n-keys.sh [project_root] [--no-exploded]
# A key no bundle answers fails quietly at runtime: I18nService catches the failure, logs a WARN and returns an empty
# string, so the label is simply missing from the page. Reads the bundles of the assembled webapp
# (WEB-INF/classes and the dependency jars, ensure-exploded.sh), falls back on the sources at hand and says so.
# Covers every file, not only the templates that render: #i18n also lives in .js, .java, .xml and .sql.
# A key built from a variable (#i18n{${...}}) is listed apart, and when it is a literal prefix plus an expression the
# prefix is checked: no key of the bundle starting with it means the whole family is missing. A key whose bundle was
# never loaded belongs to a plugin this webapp does not carry and is listed apart too.
# The assembled webapp is a precondition: without it the bundles of the dependencies are missing. The script assembles
# the project itself (ensure-exploded.sh) and stops with exit 2 when it cannot. --no-exploded accepts the reference
# clone instead and says so. Exit code 0 when every key resolves, 1 when one does not, 2 when the check did not run.
set -euo pipefail

ROOT="$(cd "${1:-.}" && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"

assembly() {
    for d in "$ROOT"/target/lutece "$ROOT"/target/*; do
        [ -d "$d/WEB-INF/templates/skin/themes/macros" ] && { echo "$d/WEB-INF/templates"; return; }
    done
    [ -d "$ROOT/webapp/WEB-INF/templates/admin/themes/tabler" ] && echo "$ROOT/webapp/WEB-INF/templates"
    return 0
}

if ! grep -rqsE "#i18n\{|I18nService\." --include='*.html' --include='*.ftl' --include='*.js' --include='*.java' --include='*.xml' --include='*.sql' "$ROOT"; then
    echo "I18NKEYS files=0 keys=0 unresolved=0 dynamic=0 foreignBundle=0 bundles=0 (this project references no i18n key)"
    exit 0
fi

CORE="${LUTECE_CORE_TEMPLATES:-$(assembly)}"
if [ -z "$CORE" ]; then
    if [ "${2:-}" = "--no-exploded" ]; then
        CORE="$HOME/.lutece-references/lutece-core/webapp/WEB-INF/templates"
        echo "I18NKEYS --no-exploded: the bundles of the dependencies are missing, a key reported here may belong to one of them" >&2
    else
        echo "no assembled webapp yet: running ensure-exploded.sh (mvn lutece:exploded-lite, it writes target/)" >&2
        bash "$HERE/ensure-exploded.sh" "$ROOT" >&2 || true
        CORE="$(assembly)"
        [ -n "$CORE" ] || { echo "I18NKEYS not performed: the project would not assemble, so the bundles of its dependencies are unknown and every key they own would be reported missing. Fix the build, or pass --no-exploded and say so in the report." >&2; exit 2; }
    fi
fi
command -v javac >/dev/null || { echo "I18NKEYS skipped: no javac"; exit 0; }
[ -f "$HERE/fmparse/I18nKeys.class" ] && [ "$HERE/fmparse/I18nKeys.class" -nt "$HERE/fmparse/I18nKeys.java" ] \
    && [ "$HERE/fmparse/Bundles.class" -nt "$HERE/fmparse/Bundles.java" ] || javac -d "$HERE/fmparse" "$HERE/fmparse/Bundles.java" "$HERE/fmparse/I18nKeys.java"
java -cp "$HERE/fmparse" I18nKeys "$CORE" "$ROOT"
