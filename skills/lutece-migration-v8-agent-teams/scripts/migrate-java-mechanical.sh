#!/bin/bash
# migrate-java-mechanical.sh — Batch mechanical Java migration on a list of files
# Usage: bash migrate-java-mechanical.sh <file-list.txt|file1.java file2.java ...>
#   OR:  bash migrate-java-mechanical.sh --all <project_root>
# Combines: javax→jakarta + Spring→CDI annotations + commons-lang + FileItem + net.sf.json imports + JUnit 4→5
# Operates ONLY on provided files (parallelizable across teammates)

set -euo pipefail

# ─── Parse arguments ─────────────────────────────────────

FILES=()
# `migrate-java-mechanical.sh .` reads as a single file argument and reports "Processing 1 files, 0 replacements":
# a green that means nothing was migrated. A directory can only mean --all.
if [ $# -eq 1 ] && [ -d "$1" ]; then
    set -- --all "$1"
fi
if [ "$1" = "--all" ]; then
    PROJECT_ROOT="${2:-.}"
    while IFS= read -r f; do
        FILES+=("$f")
    done < <(find "$PROJECT_ROOT/src" -name "*.java" 2>/dev/null | sort)
elif [ -f "$1" ] && ! echo "$1" | grep -q '\.java$'; then
    # It's a file list
    while IFS= read -r f; do
        [ -n "$f" ] && FILES+=("$f")
    done < "$1"
else
    # Direct file arguments
    FILES=("$@")
fi

for f in "${FILES[@]}"; do
    case "$f" in
        *.java) [ -f "$f" ] || { echo "{\"error\": \"no such java file: $f\"}" >&2; exit 1; } ;;
        *) echo "{\"error\": \"not a java file nor a file list: $f (a directory means --all <dir>)\"}" >&2; exit 1 ;;
    esac
done

if [ ${#FILES[@]} -eq 0 ]; then
    echo '{"error": "No files to process"}' >&2
    exit 1
fi

TOTAL_REPLACEMENTS=0
TOTAL_FILES=${#FILES[@]}
MODIFIED_FILES=0

echo "=== Mechanical Java Migration ===" >&2
echo "Processing ${TOTAL_FILES} files" >&2

# ─── Process each file ───────────────────────────────────

for file in "${FILES[@]}"; do
    [ ! -f "$file" ] && continue
    REPLACEMENTS=0

    # --- javax → jakarta imports ---
    for pair in \
        'javax\.servlet:jakarta.servlet' \
        'javax\.validation:jakarta.validation' \
        'javax\.persistence:jakarta.persistence' \
        'javax\.annotation\.PostConstruct:jakarta.annotation.PostConstruct' \
        'javax\.annotation\.PreDestroy:jakarta.annotation.PreDestroy' \
        'javax\.inject:jakarta.inject' \
        'javax\.enterprise:jakarta.enterprise' \
        'javax\.ws\.rs:jakarta.ws.rs' \
        'javax\.xml\.bind:jakarta.xml.bind' \
        'javax\.transaction:jakarta.transaction'
    do
        PATTERN="${pair%%:*}"
        REPLACEMENT="${pair##*:}"
        # `grep -c` already prints 0 and exits 1 when nothing matches: an `|| echo 0` would append a second
        # line and the integer test below would fail.
        COUNT=$(grep -c "$PATTERN" "$file" 2>/dev/null) || COUNT=0
        if [ "$COUNT" -gt 0 ]; then
            sed -i "s/$PATTERN/$REPLACEMENT/g" "$file"
            REPLACEMENTS=$((REPLACEMENTS + COUNT))
        fi
    done

    # --- Spring annotation imports → CDI ---
    sed -i 's|import org\.springframework\.beans\.factory\.annotation\.Autowired;|import jakarta.inject.Inject;|g' "$file"
    sed -i 's|import org\.springframework\.stereotype\.Component;|import jakarta.enterprise.context.ApplicationScoped;|g' "$file"
    sed -i 's|import org\.springframework\.stereotype\.Service;|import jakarta.enterprise.context.ApplicationScoped;|g' "$file"
    sed -i 's|import org\.springframework\.stereotype\.Repository;|import jakarta.enterprise.context.ApplicationScoped;|g' "$file"
    sed -i 's|import org\.springframework\.transaction\.annotation\.Transactional;|import jakarta.transaction.Transactional;|g' "$file"
    sed -i '/import org\.springframework\.beans\.factory\.InitializingBean;/d' "$file"

    # --- Spring annotations → CDI annotations ---
    # @Autowired → @Inject
    if grep -q '@Autowired' "$file" 2>/dev/null; then
        sed -i 's/@Autowired/@Inject/g' "$file"
        REPLACEMENTS=$((REPLACEMENTS + 1))
    fi

    # Standalone @Component/@Service/@Repository → @ApplicationScoped
    if grep -qE '@Component$|@Component[[:space:]]' "$file" 2>/dev/null; then
        sed -i 's/@Component$/@ApplicationScoped/g; s/@Component[[:space:]]/@ApplicationScoped /g' "$file"
        REPLACEMENTS=$((REPLACEMENTS + 1))
    fi
    if grep -qE '@Service$|@Service[[:space:]]' "$file" 2>/dev/null; then
        sed -i 's/@Service$/@ApplicationScoped/g; s/@Service[[:space:]]/@ApplicationScoped /g' "$file"
        REPLACEMENTS=$((REPLACEMENTS + 1))
    fi
    if grep -qE '@Repository$|@Repository[[:space:]]' "$file" 2>/dev/null; then
        sed -i 's/@Repository$/@ApplicationScoped/g; s/@Repository[[:space:]]/@ApplicationScoped /g' "$file"
        REPLACEMENTS=$((REPLACEMENTS + 1))
    fi

    # @Transactional("beanManager") or @Transactional(SomeClass.CONSTANT) → @Transactional
    if grep -q '@Transactional( *[^)]' "$file" 2>/dev/null; then
        sed -i 's/@Transactional( *"[^"]*" *)/@Transactional/g' "$file"
        sed -i 's/@Transactional( *[A-Za-z_][A-Za-z0-9_.]*\.BEAN_TRANSACTION_MANAGER *)/@Transactional/g' "$file"
        REPLACEMENTS=$((REPLACEMENTS + 1))
    fi

    # --- implements InitializingBean → remove (import already deleted above) ---
    if grep -q 'implements.*InitializingBean' "$file" 2>/dev/null; then
        # Remove "InitializingBean, " or ", InitializingBean" or sole "implements InitializingBean"
        sed -i 's/implements  *InitializingBean  *,/implements/g' "$file"
        sed -i 's/,  *InitializingBean\b//g' "$file"
        sed -i 's/implements  *InitializingBean\b//g' "$file"
        REPLACEMENTS=$((REPLACEMENTS + 1))
    fi

    # --- commons-lang → commons-lang3 ---
    if grep -q 'org\.apache\.commons\.lang\.[^3]' "$file" 2>/dev/null; then
        sed -i 's/org\.apache\.commons\.lang\.\([^3]\)/org.apache.commons.lang3.\1/g' "$file"
        REPLACEMENTS=$((REPLACEMENTS + 1))
    fi

    # --- FileItem → MultipartItem ---
    if grep -q 'org\.apache\.commons\.fileupload\.FileItem' "$file" 2>/dev/null; then
        sed -i 's/org\.apache\.commons\.fileupload\.FileItem/fr.paris.lutece.portal.service.upload.MultipartItem/g' "$file"
        REPLACEMENTS=$((REPLACEMENTS + 1))
    fi
    if grep -q 'org\.apache\.commons\.fileupload2' "$file" 2>/dev/null; then
        sed -i 's/org\.apache\.commons\.fileupload2\.core\.FileItem/fr.paris.lutece.portal.service.upload.MultipartItem/g' "$file"
        REPLACEMENTS=$((REPLACEMENTS + 1))
    fi

    # --- net.sf.json → Jackson imports ---
    if grep -q 'import net\.sf\.json' "$file" 2>/dev/null; then
        sed -i 's|import net\.sf\.json\.JSONObject;|import com.fasterxml.jackson.databind.node.ObjectNode;|g' "$file"
        sed -i 's|import net\.sf\.json\.JSONArray;|import com.fasterxml.jackson.databind.node.ArrayNode;|g' "$file"
        sed -i 's|import net\.sf\.json\.JSONSerializer;|import com.fasterxml.jackson.databind.ObjectMapper;|g' "$file"
        sed -i 's|import net\.sf\.json\.JSON;|import com.fasterxml.jackson.databind.JsonNode;|g' "$file"
        sed -i 's|import net\.sf\.json\.JSONException;|import com.fasterxml.jackson.core.JsonProcessingException;|g' "$file"
        # Catch any remaining net.sf.json imports
        if grep -q 'import net\.sf\.json' "$file" 2>/dev/null; then
            echo "NOTE: $file still has net.sf.json imports requiring manual migration" >&2
        fi
        REPLACEMENTS=$((REPLACEMENTS + 1))
    fi

    # --- JUnit 4 → 5 (for test files) ---
    if echo "$file" | grep -q 'src/test/'; then
        sed -i 's|import org\.junit\.Test;|import org.junit.jupiter.api.Test;|g' "$file"
        sed -i 's|import org\.junit\.Before;|import org.junit.jupiter.api.BeforeEach;|g' "$file"
        sed -i 's|import org\.junit\.After;|import org.junit.jupiter.api.AfterEach;|g' "$file"
        sed -i 's|import org\.junit\.BeforeClass;|import org.junit.jupiter.api.BeforeAll;|g' "$file"
        sed -i 's|import org\.junit\.AfterClass;|import org.junit.jupiter.api.AfterAll;|g' "$file"
        sed -i 's|import org\.junit\.Assert;|import org.junit.jupiter.api.Assertions;|g' "$file"
        sed -i 's|import org\.junit\.Ignore;|import org.junit.jupiter.api.Disabled;|g' "$file"
        # Static imports: import static org.junit.Assert.X → import static org.junit.jupiter.api.Assertions.X
        sed -i 's|import static org\.junit\.Assert\.|import static org.junit.jupiter.api.Assertions.|g' "$file"
        sed -i 's|@Before$|@BeforeEach|g; s|@Before[[:space:]]|@BeforeEach |g' "$file"
        sed -i 's|@After$|@AfterEach|g; s|@After[[:space:]]|@AfterEach |g' "$file"
        sed -i 's|@BeforeClass|@BeforeAll|g' "$file"
        sed -i 's|@AfterClass|@AfterAll|g' "$file"
        sed -i 's|@Ignore|@Disabled|g' "$file"

        # Mock renames
        sed -i 's|MokeHttpServletRequest|MockHttpServletRequest|g' "$file"
        sed -i 's|import org\.springframework\.mock\.web|import fr.paris.lutece.test.mocks|g' "$file"
    fi

    if [ "$REPLACEMENTS" -gt 0 ]; then
        MODIFIED_FILES=$((MODIFIED_FILES + 1))
        TOTAL_REPLACEMENTS=$((TOTAL_REPLACEMENTS + REPLACEMENTS))
    fi
done

# ─── Safety check — no accidental JDK javax replacements ─

SAFETY_ISSUES=0
for file in "${FILES[@]}"; do
    [ ! -f "$file" ] && continue
    if grep -q 'import jakarta\.cache\|import jakarta\.xml\.transform\|import jakarta\.xml\.parsers\|import jakarta\.crypto\|import jakarta\.net\.\|import jakarta\.sql\.\|import jakarta\.naming\.' "$file" 2>/dev/null; then
        echo "WARNING: Accidental JDK javax replacement in $file" >&2
        SAFETY_ISSUES=$((SAFETY_ISSUES + 1))
    fi
done

if [ "$SAFETY_ISSUES" -gt 0 ]; then
    echo "CRITICAL: $SAFETY_ISSUES files have accidental javax→jakarta replacements of JDK packages" >&2
fi

# ─── Report ──────────────────────────────────────────────

echo "=== Mechanical Migration Report ===" >&2
echo "  Files processed: $TOTAL_FILES" >&2
echo "  Files modified: $MODIFIED_FILES" >&2
echo "  Total replacements: $TOTAL_REPLACEMENTS" >&2
echo "  Safety issues: $SAFETY_ISSUES" >&2

# JSON output to stdout
cat << ENDJSON
{
  "filesProcessed": $TOTAL_FILES,
  "filesModified": $MODIFIED_FILES,
  "totalReplacements": $TOTAL_REPLACEMENTS,
  "safetyIssues": $SAFETY_ISSUES
}
ENDJSON
