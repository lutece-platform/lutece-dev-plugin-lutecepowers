#!/bin/bash
# render-template.sh — render plugin templates offline with the real core macros, no server.
# Usage: render-template.sh [project_root] [template ...]
#   template  path relative to webapp/WEB-INF/templates (default: every admin and skin template of the project)
# Model: every variable a template reads is empty unless .migration/render/<path with / as _>.json defines it
# ({"$date": "yyyy-MM-dd"} is a date, so ?date and ?is_date branches render)
# (a JSON object: strings, numbers, booleans, lists, nested objects). Output goes to .migration/render/.
# Proves the macro calls resolve, their arguments are declared (the core macros print an HTML warning comment
# for a wrong argument, counted as wrongArguments) and the empty branches render. The #i18n keys of the output are
# then resolved the way AppTemplateService does, in French, against the bundles of the assembled webapp: a key that
# resolves to nothing is named, because the core swallows the failure and writes an empty string, so the label is
# simply absent from the page with nothing in the logs. A macro defined in a template
# that is not auto-included (adminHeader, page blocks) renders a marker, counted as unresolvedMacros: check it
# exists before calling it a defect. A macro a descriptor declares as a freemarker-macro-file is known and left
# alone, and a template whose rendering needs a real boolean (?boolean accepts only "true" and "false") is counted
# apart as needModel rather than as an error: write it a JSON model to render it. Theme overrides (skin/themes/<code>/tpl/**) are hidden so the plugin's own file
# renders; an OVERRIDE line says when one exists. Does not prove CSS or JavaScript.
# Needs a JDK, the freemarker jar in ~/.m2 and the core reference clone (~/.lutece-references/lutece-core).
set -euo pipefail

ROOT="${1:-.}"
shift || true
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="${LUTECE_CORE_TEMPLATES:-$HOME/.lutece-references/lutece-core/webapp/WEB-INF/templates}"
if [ -z "${LUTECE_CORE_TEMPLATES:-}" ]; then
    # The assembled webapp first: it carries the core, every dependency and the project, at the resolved versions
    # (ensure-exploded.sh). Then a project that ships both macro families, which is its own source (the core).
    for d in "$ROOT"/target/lutece "$ROOT"/target/*; do
        [ -d "$d/WEB-INF/templates/skin/themes/macros" ] && CORE="$d/WEB-INF/templates" && break
    done
    [ -d "$ROOT/webapp/WEB-INF/templates/admin/themes/tabler" ] && CORE="$ROOT/webapp/WEB-INF/templates"
fi
JAR=$(ls "$HOME"/.m2*/repository/org/freemarker/freemarker/2.3.*/freemarker-2.3.*.jar 2>/dev/null | grep -v sources | sort -V | tail -1 || true)
[ -n "$JAR" ] || { echo "RENDER skipped: no freemarker jar under ~/.m2 (build the project once)"; exit 0; }
[ -d "$CORE" ] || { echo "RENDER skipped: core templates not found at $CORE"; exit 0; }
command -v javac >/dev/null || { echo "RENDER skipped: no javac"; exit 0; }

compile() {
    [ -f "$HERE/fmparse/Render.class" ] && [ "$HERE/fmparse/Render.class" -nt "$HERE/fmparse/Render.java" ] \
        && [ -f "$HERE/fmparse/Bundles.class" ] && [ "$HERE/fmparse/Bundles.class" -nt "$HERE/fmparse/Bundles.java" ] && return
    javac -cp "$JAR" -d "$HERE/fmparse" "$HERE/fmparse/Bundles.java" "$HERE/fmparse/Render.java"
}

compile
TEMPLATES="$ROOT/webapp/WEB-INF/templates"
[ -d "$TEMPLATES" ] || { echo "RENDER templates=0 errors=0 wrongArguments=0"; exit 0; }
OUT="$ROOT/.migration/render"
mkdir -p "$OUT"
if [ $# -eq 0 ]; then
    mapfile -t FILES < <(cd "$TEMPLATES" && find admin skin \( -name '*.html' -o -name '*.xml' -o -name '*.txt' -o -name '*.json' \) -not -path '*/themes/*' 2>/dev/null | sort)
else
    FILES=("$@")
fi
for f in "${FILES[@]}"; do
    case "$f" in skin/*) for o in "$CORE"/skin/themes/*/tpl/"${f#skin/}" "$TEMPLATES"/skin/themes/*/tpl/"${f#skin/}"; do
        [ -f "$o" ] && echo "OVERRIDE $f: a theme override exists at ${o#"$CORE"/}; a site on that theme never renders the plugin file (rendered here: the plugin file)"; done;; esac
done
# A plugin declares its shared macros as freemarker-macro-files in its descriptor, and the application includes
# them globally. Auto-including them here would also run their top-level code against an empty model, which fails
# for reasons that have nothing to do with the template under test; so they are only read for the macro names they
# define, and a call to one of those is left alone instead of being counted as unresolved.
KNOWN=$(cat "$CORE"/../plugins/*.xml "$CORE"/../conf/*.xml "$ROOT"/webapp/WEB-INF/plugins/*.xml 2>/dev/null \
    | grep -o "<freemarker-macro-file>[^<]*" | sed 's|<freemarker-macro-file>||' | sort -u | paste -sd, - || true)
java -cp "$JAR:$HERE/fmparse" Render "$CORE" "$TEMPLATES" "$OUT" "${KNOWN:-}" "${FILES[@]}"
