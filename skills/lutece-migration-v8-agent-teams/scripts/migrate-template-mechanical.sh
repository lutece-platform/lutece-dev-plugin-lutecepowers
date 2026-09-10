#!/bin/bash
# migrate-template-mechanical.sh — Batch mechanical template migration
# Usage: bash migrate-template-mechanical.sh [--no-webxml] [project_root]
#   --no-webxml   skip the web.xml rewrite (web.xml is owned by the Config Migrator)
# Handles: BO upload macro renames, null-safety for errors/infos/warnings,
#          ${error} -> ${error.message} inside <#list errors as error> blocks,
#          web.xml Jakarta EE 10 namespace (unless --no-webxml)

set -euo pipefail

DO_WEBXML=1
PROJECT_ROOT="."
for arg in "$@"; do
    case "$arg" in
        --no-webxml) DO_WEBXML=0 ;;
        -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
        *) PROJECT_ROOT="$arg" ;;
    esac
done

TEMPLATES_DIR="$PROJECT_ROOT/webapp/WEB-INF/templates"
WEBAPP_DIR="$PROJECT_ROOT/webapp"

TOTAL=0

replace_and_count() {
    local dir="$1"
    local ext="$2"
    local pattern="$3"
    local replacement="$4"
    local label="$5"
    local count
    count=$({ grep -rl "$pattern" "$dir" --include="*.$ext" 2>/dev/null || true; } | wc -l)
    if [ "$count" -gt 0 ]; then
        find "$dir" -name "*.$ext" -exec sed -i "s|$pattern|$replacement|g" {} +
        echo "  $label: $count files" >&2
        TOTAL=$((TOTAL + count))
    fi
}

echo "=== Mechanical Template Migration ===" >&2

if [ -d "$TEMPLATES_DIR/admin/" ]; then
    echo "--- Admin template BO upload macro renames (plugin-asynchronousupload) ---" >&2
    replace_and_count "$TEMPLATES_DIR/admin" "html" '<@addRequiredJsFiles' '<@addRequiredBOJsFiles' '@addRequiredJsFiles → @addRequiredBOJsFiles'
    replace_and_count "$TEMPLATES_DIR/admin" "html" '<@addFileInput ' '<@addFileBOInput ' '@addFileInput → @addFileBOInput'
    replace_and_count "$TEMPLATES_DIR/admin" "html" '<@addUploadedFilesBox' '<@addBOUploadedFilesBox' '@addUploadedFilesBox → @addBOUploadedFilesBox'
    replace_and_count "$TEMPLATES_DIR/admin" "html" '<@addFileInputAndfilesBox' '<@addFileBOInputAndfilesBox' '@addFileInputAndfilesBox → @addFileBOInputAndfilesBox'
fi

if [ -d "$TEMPLATES_DIR" ]; then
    echo "--- Null-safety for errors/infos/warnings ---" >&2

    for var in errors infos warnings; do
        COUNT=$({ grep -rl "${var}?size\|${var}?has_content" "$TEMPLATES_DIR" --include="*.html" 2>/dev/null \
            | while read -r f; do grep -l "${var}?size\|${var}?has_content" "$f" | grep -v "(${var}!)" 2>/dev/null; done || true; } | sort -u | wc -l)
        if [ "$COUNT" -gt 0 ]; then
            find "$TEMPLATES_DIR" -name "*.html" -exec sed -i \
                "s/${var}?size/(${var}!)?size/g; s/${var}?has_content/(${var}!)?has_content/g" {} +
            find "$TEMPLATES_DIR" -name "*.html" -exec sed -i \
                "s/((${var}!)!)/($var!)/g" {} +
            echo "  ${var} null-safety: $COUNT files" >&2
            TOTAL=$((TOTAL + COUNT))
        fi
    done

    for var in errors infos warnings; do
        COUNT=$({ grep -rl "<#list ${var} as\b" "$TEMPLATES_DIR" --include="*.html" 2>/dev/null || true; } | wc -l)
        if [ "$COUNT" -gt 0 ]; then
            find "$TEMPLATES_DIR" -name "*.html" -exec sed -i \
                "s/<#list ${var} as/<#list (${var}![]) as/g" {} +
            echo "  <#list ${var} null-safety: $COUNT files" >&2
            TOTAL=$((TOTAL + COUNT))
        fi
    done
fi

if [ -d "$TEMPLATES_DIR" ]; then
    echo '--- MVCMessage: ${error} → ${error.message} inside <#list errors as error> blocks ---' >&2
    COUNT=0
    while IFS= read -r f; do
        if perl -0777 -ne 'exit(!(/<#list \(?errors!?\[?\]?\)? as error>.*?\$\{error\}.*?<\/#list>/s))' "$f"; then
            perl -0777 -i -pe 's{(<#list \(?errors!?\[?\]?\)? as error>)(.*?)(</#list>)}{ my ($o,$b,$c)=($1,$2,$3); $b =~ s/\$\{error\}/\$\{error.message\}/g; "$o$b$c" }gse' "$f"
            COUNT=$((COUNT + 1))
        fi
    done < <(grep -rl '${error}' "$TEMPLATES_DIR" --include="*.html" 2>/dev/null || true)
    if [ "$COUNT" -gt 0 ]; then
        echo "  MVCMessage error fix: $COUNT files" >&2
        TOTAL=$((TOTAL + COUNT))
    fi
fi

if [ "$DO_WEBXML" -eq 1 ] && [ -f "$WEBAPP_DIR/WEB-INF/web.xml" ]; then
    WEBXML="$WEBAPP_DIR/WEB-INF/web.xml"
    if grep -q 'java\.sun\.com/xml/ns/javaee\|xmlns\.jcp\.org/xml/ns/javaee' "$WEBXML" 2>/dev/null; then
        sed -i 's|http://java\.sun\.com/xml/ns/javaee|https://jakarta.ee/xml/ns/jakartaee|g; s|http://xmlns\.jcp\.org/xml/ns/javaee|https://jakarta.ee/xml/ns/jakartaee|g' "$WEBXML"
        sed -i 's|jakartaee/web-app_[0-9]_[0-9]\.xsd|jakartaee/web-app_6_0.xsd|g' "$WEBXML"
        perl -0777 -i -pe 's{(<web-app\b[^>]*?)version="[0-9.]+"}{$1version="6.0"}s' "$WEBXML"
        echo "  web.xml Jakarta EE 10 namespace (web-app_6_0.xsd, version 6.0): 1 file" >&2
        TOTAL=$((TOTAL + 1))
    fi
fi

echo "" >&2
echo "=== RESULT: $TOTAL files modified ===" >&2

cat << ENDJSON
{
  "filesModified": $TOTAL
}
ENDJSON
