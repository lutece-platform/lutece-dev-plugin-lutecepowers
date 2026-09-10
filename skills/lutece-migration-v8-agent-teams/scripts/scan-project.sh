#!/bin/bash
# scan-project.sh — Scan a Lutece project and output a structured JSON migration inventory
# Usage: bash scan-project.sh [project_root]
# Output: JSON to stdout (pipe to .migration/scan.json)
# Dependencies: jq (optional, falls back to manual JSON)

set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT"

if [ ! -f "pom.xml" ]; then
    echo '{"error": "No pom.xml found"}' >&2
    exit 1
fi

# ─── Helpers ─────────────────────────────────────────────

json_escape() {
    printf '%s' "$1" | tr -d '\r' | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' '
}

# Safe grep-count: returns 0 when no match instead of crashing with pipefail
gcount() { { grep "$@" || true; } | wc -l; }
gfiles() { { grep "$@" || true; } | sort; }

# ─── Project Info ────────────────────────────────────────

PROJECT_TYPE="unknown"
grep -q '<type>lutece-plugin</type>\|<packaging>lutece-plugin</packaging>' pom.xml 2>/dev/null && PROJECT_TYPE="plugin"
grep -q '<type>lutece-module</type>\|<packaging>lutece-module</packaging>' pom.xml 2>/dev/null && PROJECT_TYPE="module"
grep -q '<type>lutece-library</type>\|<packaging>lutece-library</packaging>' pom.xml 2>/dev/null && PROJECT_TYPE="library"
# Detect libraries using jar packaging with library- artifactId convention
if [ "$PROJECT_TYPE" = "unknown" ]; then
    grep -q '<packaging>jar</packaging>' pom.xml 2>/dev/null && grep -q 'library-' pom.xml 2>/dev/null && PROJECT_TYPE="library"
fi

ARTIFACT=$(sed '/<parent>/,/<\/parent>/d' pom.xml | grep -m1 '<artifactId>' | sed 's/.*<artifactId>\(.*\)<\/artifactId>.*/\1/' | tr -d ' \r')
VERSION=$(sed '/<parent>/,/<\/parent>/d' pom.xml | grep -m1 '<version>' | sed 's/.*<version>\(.*\)<\/version>.*/\1/' | tr -d ' \r')
PARENT_VERSION=$(sed -n '/<parent>/,/<\/parent>/p' pom.xml | grep '<version>' | head -1 | sed 's/.*<version>\(.*\)<\/version>.*/\1/' | tr -d ' \r')

# ─── Lutece Dependencies ────────────────────────────────

DEPS_JSON="["
FIRST_DEP=true
# Extract artifactId + version pairs for fr.paris.lutece dependencies
while IFS= read -r dep_line; do
    [ -z "$dep_line" ] && continue
    DEP_AID=$(echo "$dep_line" | grep -oP '(?<=<artifactId>)[^<]+' | tr -d '\r' || true)
    DEP_VER=$(echo "$dep_line" | grep -oP '(?<=<version>)[^<]+' | tr -d '\r' || true)
    DEP_TYPE=$(echo "$dep_line" | grep -oP '(?<=<type>)[^<]+' | tr -d '\r' || true)
    [ -z "$DEP_AID" ] && continue
    [ "$DEP_AID" = "lutece-global-pom" ] && continue
    $FIRST_DEP || DEPS_JSON="$DEPS_JSON,"
    FIRST_DEP=false

    # Check if v8 version exists in references
    V8_STATUS="unknown"
    V8_BRANCH=""
    V8_VERSION=""
    if [ -d "$HOME/.lutece-references/$DEP_AID" ]; then
        V8_STATUS="available"
        V8_BRANCH=$(cd "$HOME/.lutece-references/$DEP_AID" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        V8_VERSION=$(grep -oP '(?<=<version>)[^<]+' "$HOME/.lutece-references/$DEP_AID/pom.xml" 2>/dev/null | head -1 | tr -d '\r' || true)
    fi

    DEPS_JSON="$DEPS_JSON{\"artifactId\":\"$DEP_AID\",\"version\":\"${DEP_VER:-unspecified}\",\"type\":\"${DEP_TYPE:-jar}\",\"v8Status\":\"$V8_STATUS\",\"v8Branch\":\"$V8_BRANCH\",\"v8Version\":\"$V8_VERSION\"}"
done < <(
    # Extract dependency blocks for fr.paris.lutece
    awk '/<dependency>/{block=""} /<dependency>/,/<\/dependency>/{block=block $0 "\n"} /<\/dependency>/{if(block ~ /fr\.paris\.lutece/) print block}' pom.xml
)
DEPS_JSON="$DEPS_JSON]"

# ─── Java Files Analysis ────────────────────────────────

JAVA_JSON="["
TEST_JSON="["
FIRST_JAVA=true
FIRST_TEST=true

while IFS= read -r file; do
    [ -z "$file" ] && continue

    # Determine if test file
    IS_TEST=false
    echo "$file" | grep -q 'src/test/' && IS_TEST=true

    # Package extraction
    PKG=$(grep -m1 '^package ' "$file" 2>/dev/null | sed 's/package \(.*\);/\1/' | tr -d ' \r' || echo "")

    # Counts
    JAVAX_COUNT=$(grep -c 'import javax\.\(servlet\|validation\|annotation\.PostConstruct\|annotation\.PreDestroy\|inject\|enterprise\|ws\.rs\|xml\.bind\)' "$file" 2>/dev/null || true)
    SPRING_COUNT=$(grep -c 'import org\.springframework' "$file" 2>/dev/null || true)
    SPRING_LOOKUP=$(grep -c 'SpringContextService' "$file" 2>/dev/null || true)
    GETINSTANCE_COUNT=$(grep -c '\.getInstance( )' "$file" 2>/dev/null || true)

    # Flags
    HAS_EVENTS=false
    grep -q 'EventRessourceListener\|LuteceUserEventManager\|QueryListenersService\|AbstractEventManager' "$file" 2>/dev/null && HAS_EVENTS=true

    HAS_CACHE=false
    grep -q 'AbstractCacheableService\|net\.sf\.ehcache\|putInCache\|getFromCache\|removeKey' "$file" 2>/dev/null && HAS_CACHE=true

    HAS_REST=false
    grep -q '@Path\|@GET\|@POST\|@PUT\|@DELETE' "$file" 2>/dev/null && HAS_REST=true

    HAS_CDI=false
    grep -q '@ApplicationScoped\|@RequestScoped\|@SessionScoped\|@Dependent\|@Inject\|@Named\|@Produces' "$file" 2>/dev/null && HAS_CDI=true

    HAS_PAGINATION=false
    grep -q '_strCurrentPageIndex\|_nItemsPerPage\|new LocalizedPaginator\|new Paginator\|AbstractPaginator\.getPageIndex\|AbstractPaginatorJspBean' "$file" 2>/dev/null && HAS_PAGINATION=true

    # Deprecated patterns
    DEPRECATED="["
    FIRST_DP=true
    grep -q 'getModel( )' "$file" 2>/dev/null && { $FIRST_DP || DEPRECATED="$DEPRECATED,"; FIRST_DP=false; DEPRECATED="$DEPRECATED\"getModel\""; }
    grep -q 'daoUtil\.free( )' "$file" 2>/dev/null && { $FIRST_DP || DEPRECATED="$DEPRECATED,"; FIRST_DP=false; DEPRECATED="$DEPRECATED\"daoUtilFree\""; }
    grep -q '\.getInstance( )' "$file" 2>/dev/null && { $FIRST_DP || DEPRECATED="$DEPRECATED,"; FIRST_DP=false; DEPRECATED="$DEPRECATED\"getInstance\""; }
    grep -q 'new HashMap' "$file" 2>/dev/null && grep -q 'MVCAdminJspBean\|MVCApplication' "$file" 2>/dev/null && { $FIRST_DP || DEPRECATED="$DEPRECATED,"; FIRST_DP=false; DEPRECATED="$DEPRECATED\"newHashMap\""; }
    grep -q 'SecurityTokenService' "$file" 2>/dev/null && { $FIRST_DP || DEPRECATED="$DEPRECATED,"; FIRST_DP=false; DEPRECATED="$DEPRECATED\"securityToken\""; }
    grep -q 'org\.apache\.commons\.fileupload' "$file" 2>/dev/null && { $FIRST_DP || DEPRECATED="$DEPRECATED,"; FIRST_DP=false; DEPRECATED="$DEPRECATED\"fileupload\""; }
    grep -q 'AbstractPaginatorJspBean' "$file" 2>/dev/null && { $FIRST_DP || DEPRECATED="$DEPRECATED,"; FIRST_DP=false; DEPRECATED="$DEPRECATED\"abstractPaginator\""; }
    DEPRECATED="$DEPRECATED]"

    # Class type detection
    CLASS_TYPE="other"
    grep -q 'class.*DAO\b\|implements.*IDAO\|implements.*I[A-Z].*DAO' "$file" 2>/dev/null && CLASS_TYPE="dao"
    grep -q 'extends.*MVCAdminJspBean\|JspBean' "$file" 2>/dev/null && CLASS_TYPE="jspbean"
    grep -q 'extends.*MVCApplication\|XPage' "$file" 2>/dev/null && CLASS_TYPE="xpage"
    grep -q 'class.*Service\b' "$file" 2>/dev/null && [ "$CLASS_TYPE" = "other" ] && CLASS_TYPE="service"
    grep -q 'extends.*PluginDefaultImplementation' "$file" 2>/dev/null && CLASS_TYPE="plugin"
    grep -q 'extends.*AbstractEntryType' "$file" 2>/dev/null && CLASS_TYPE="entrytype"
    grep -q 'extends.*AbstractDaemonThread\|extends.*Daemon\b' "$file" 2>/dev/null && CLASS_TYPE="daemon"
    # Test class detection
    $IS_TEST && CLASS_TYPE="test"
    # Interface detection
    grep -q '^public interface\|^protected interface' "$file" 2>/dev/null && CLASS_TYPE="interface"
    # Home class detection (static facade)
    grep -q 'class.*Home\b' "$file" 2>/dev/null && grep -q 'private.*Home( )' "$file" 2>/dev/null && CLASS_TYPE="home"

    FILE_JSON="{\"path\":\"$file\",\"classType\":\"$CLASS_TYPE\",\"package\":\"$PKG\",\"javaxImports\":$JAVAX_COUNT,\"springImports\":$SPRING_COUNT,\"springLookups\":$SPRING_LOOKUP,\"getInstanceCalls\":$GETINSTANCE_COUNT,\"eventPatterns\":$HAS_EVENTS,\"cachePatterns\":$HAS_CACHE,\"restPatterns\":$HAS_REST,\"paginationPatterns\":$HAS_PAGINATION,\"existingCDI\":$HAS_CDI,\"deprecatedPatterns\":$DEPRECATED}"

    if $IS_TEST; then
        $FIRST_TEST || TEST_JSON="$TEST_JSON,"
        FIRST_TEST=false
        TEST_JSON="$TEST_JSON$FILE_JSON"
    else
        $FIRST_JAVA || JAVA_JSON="$JAVA_JSON,"
        FIRST_JAVA=false
        JAVA_JSON="$JAVA_JSON$FILE_JSON"
    fi
done < <(find src/ -name "*.java" 2>/dev/null | sort)
JAVA_JSON="$JAVA_JSON]"
TEST_JSON="$TEST_JSON]"

# ─── Context XML Files ──────────────────────────────────

CTX_JSON="["
FIRST_CTX=true
while IFS= read -r file; do
    [ -z "$file" ] && continue
    BEAN_COUNT=$(grep -c '<bean ' "$file" 2>/dev/null || true)
    $FIRST_CTX || CTX_JSON="$CTX_JSON,"
    FIRST_CTX=false
    CTX_JSON="$CTX_JSON{\"path\":\"$file\",\"beanCount\":$BEAN_COUNT}"
done < <({ find webapp/ -name "*_context.xml" 2>/dev/null || true; } | sort)
CTX_JSON="$CTX_JSON]"

# ─── Reflection-instantiated classes (from plugin.xml) ──

REFLECTION_JSON="["
FIRST_REFL=true
if [ -d "webapp/WEB-INF/plugins/" ]; then
    for tag in content-service-class search-indexer-class rbac-resource-type-class filter-class servlet-class listener-class page-include-service-class dashboard-component-class; do
        while IFS= read -r class_name; do
            [ -z "$class_name" ] && continue
            class_name=$(echo "$class_name" | tr -d ' \r\t')
            [ -z "$class_name" ] && continue
            $FIRST_REFL || REFLECTION_JSON="$REFLECTION_JSON,"
            FIRST_REFL=false
            REFLECTION_JSON="$REFLECTION_JSON{\"class\":\"$class_name\",\"tag\":\"$tag\"}"
        done < <(grep -h "<${tag}>" webapp/WEB-INF/plugins/*.xml 2>/dev/null | sed "s|.*<${tag}>||; s|</${tag}>.*||" | tr -d ' \r')
    done
fi
REFLECTION_JSON="$REFLECTION_JSON]"

# ─── Admin Templates ────────────────────────────────────

ADMIN_TPL_JSON="["
FIRST_AT=true
while IFS= read -r file; do
    [ -z "$file" ] && continue
    FLAGS="["
    FIRST_FL=true
    grep -q 'jQuery\|\$(' "$file" 2>/dev/null && { $FIRST_FL || FLAGS="$FLAGS,"; FIRST_FL=false; FLAGS="$FLAGS\"jquery\""; }
    grep -q 'class="panel\|class="btn ' "$file" 2>/dev/null && { $FIRST_FL || FLAGS="$FLAGS,"; FIRST_FL=false; FLAGS="$FLAGS\"bootstrap3\""; }
    grep -q '@pageContainer\|@tform\|@table' "$file" 2>/dev/null && { $FIRST_FL || FLAGS="$FLAGS,"; FIRST_FL=false; FLAGS="$FLAGS\"v8macros\""; }
    grep -q 'autocomplete-js\.jsp\|createAutocomplete\|\.autocomplete(' "$file" 2>/dev/null && { $FIRST_FL || FLAGS="$FLAGS,"; FIRST_FL=false; FLAGS="$FLAGS\"old_suggestpoi\""; }
    grep -q '@suggestPOIInput\|@setupSuggestPOI' "$file" 2>/dev/null && { $FIRST_FL || FLAGS="$FLAGS,"; FIRST_FL=false; FLAGS="$FLAGS\"v8_suggestpoi\""; }
    FLAGS="$FLAGS]"
    $FIRST_AT || ADMIN_TPL_JSON="$ADMIN_TPL_JSON,"
    FIRST_AT=false
    ADMIN_TPL_JSON="$ADMIN_TPL_JSON{\"path\":\"$file\",\"flags\":$FLAGS}"
done < <({ find webapp/WEB-INF/templates/admin/ -name "*.html" 2>/dev/null || true; } | sort)
ADMIN_TPL_JSON="$ADMIN_TPL_JSON]"

# ─── Skin Templates ─────────────────────────────────────

SKIN_TPL_JSON="["
FIRST_ST=true
while IFS= read -r file; do
    [ -z "$file" ] && continue
    FLAGS="["
    FIRST_FL=true
    grep -q 'jQuery\|\$(' "$file" 2>/dev/null && { $FIRST_FL || FLAGS="$FLAGS,"; FIRST_FL=false; FLAGS="$FLAGS\"jquery\""; }
    grep -q '<@cTpl>' "$file" 2>/dev/null && { $FIRST_FL || FLAGS="$FLAGS,"; FIRST_FL=false; FLAGS="$FLAGS\"v8wrap\""; }
    FLAGS="$FLAGS]"
    $FIRST_ST || SKIN_TPL_JSON="$SKIN_TPL_JSON,"
    FIRST_ST=false
    SKIN_TPL_JSON="$SKIN_TPL_JSON{\"path\":\"$file\",\"flags\":$FLAGS}"
done < <({ find webapp/WEB-INF/templates/skin/ -name "*.html" 2>/dev/null || true; } | sort)
SKIN_TPL_JSON="$SKIN_TPL_JSON]"

# ─── JSP Files ───────────────────────────────────────────

JSP_JSON="["
FIRST_JSP=true
while IFS= read -r file; do
    [ -z "$file" ] && continue
    FLAGS="["
    FIRST_FL=true
    grep -q 'jsp:useBean' "$file" 2>/dev/null && { $FIRST_FL || FLAGS="$FLAGS,"; FIRST_FL=false; FLAGS="$FLAGS\"useBean\""; }
    grep -q '<%[^@-]' "$file" 2>/dev/null && { $FIRST_FL || FLAGS="$FLAGS,"; FIRST_FL=false; FLAGS="$FLAGS\"scriptlet\""; }
    grep -q '\${' "$file" 2>/dev/null && { $FIRST_FL || FLAGS="$FLAGS,"; FIRST_FL=false; FLAGS="$FLAGS\"EL\""; }
    FLAGS="$FLAGS]"
    $FIRST_JSP || JSP_JSON="$JSP_JSON,"
    FIRST_JSP=false
    JSP_JSON="$JSP_JSON{\"path\":\"$file\",\"flags\":$FLAGS}"
done < <({ find webapp/ -name "*.jsp" 2>/dev/null || true; } | sort)
JSP_JSON="$JSP_JSON]"

# ─── SQL Files ───────────────────────────────────────────

SQL_JSON="["
FIRST_SQL=true
while IFS= read -r file; do
    [ -z "$file" ] && continue
    HAS_HEADER=false
    head -1 "$file" 2>/dev/null | grep -q 'liquibase formatted sql' && HAS_HEADER=true
    $FIRST_SQL || SQL_JSON="$SQL_JSON,"
    FIRST_SQL=false
    SQL_JSON="$SQL_JSON{\"path\":\"$file\",\"liquibaseHeader\":$HAS_HEADER}"
done < <(find src/ -name "*.sql" 2>/dev/null | sort)
SQL_JSON="$SQL_JSON]"

# ─── REST Files ──────────────────────────────────────────

REST_JSON="["
FIRST_REST=true
while IFS= read -r file; do
    [ -z "$file" ] && continue
    $FIRST_REST || REST_JSON="$REST_JSON,"
    FIRST_REST=false
    REST_JSON="$REST_JSON\"$file\""
done < <(gfiles -rln '@Path\|@GET\|@POST\|@PUT\|@DELETE' src/ --include="*.java" 2>/dev/null)
REST_JSON="$REST_JSON]"

# ─── Properties Files ───────────────────────────────────

PROPS_JSON="["
FIRST_PROP=true
while IFS= read -r file; do
    [ -z "$file" ] && continue
    $FIRST_PROP || PROPS_JSON="$PROPS_JSON,"
    FIRST_PROP=false
    PROPS_JSON="$PROPS_JSON\"$file\""
done < <({ find src/ webapp/ -name "*.properties" 2>/dev/null || true; } | sort)
PROPS_JSON="$PROPS_JSON]"

# ─── Summary Counts ──────────────────────────────────────

JAVA_FILES=$(find src/ -name "*.java" -not -path '*/test/*' 2>/dev/null | wc -l)
TEST_FILES=$(find src/ -name "*.java" -path '*/test/*' 2>/dev/null | wc -l)
CONTEXT_FILES=$({ find webapp/ -name "*_context.xml" 2>/dev/null || true; } | wc -l)
SPRING_LOOKUPS=$(gcount -rn 'SpringContextService' src/ --include="*.java" 2>/dev/null)
GETINSTANCE_CALLS=$(gcount -rn '\.getInstance( )' src/ --include="*.java" 2>/dev/null)
JAVAX_IMPORTS=$(gcount -rn 'import javax\.\(servlet\|validation\|annotation\.PostConstruct\|annotation\.PreDestroy\|inject\|enterprise\|ws\.rs\|xml\.bind\)' src/ --include="*.java" 2>/dev/null)
EVENT_LISTENERS=$(gcount -rln 'EventRessourceListener\|LuteceUserEventManager\|QueryListenersService\|AbstractEventManager' src/ --include="*.java" 2>/dev/null)
CACHE_SERVICES=$(gcount -rln 'AbstractCacheableService\|net\.sf\.ehcache' src/ --include="*.java" 2>/dev/null)
ADMIN_TEMPLATES=$({ find webapp/WEB-INF/templates/admin/ -name "*.html" 2>/dev/null || true; } | wc -l)
SKIN_TEMPLATES=$({ find webapp/WEB-INF/templates/skin/ -name "*.html" 2>/dev/null || true; } | wc -l)
JSP_COUNT=$({ find webapp/ -name "*.jsp" 2>/dev/null || true; } | wc -l)
SQL_COUNT=$(find src/ -name "*.sql" 2>/dev/null | wc -l)
REST_COUNT=$(gcount -rln '@Path\|@GET\|@POST\|@PUT\|@DELETE' src/ --include="*.java" 2>/dev/null)
DAO_FREE=$(gcount -rn 'daoUtil\.free( )' src/ --include="*.java" 2>/dev/null)
DEPRECATED_GETMODEL=$(gcount -rn 'getModel( )' src/ --include="*.java" 2>/dev/null)
DEPRECATED_HASHMAP=$({ grep -rln 'new HashMap' src/ --include="*.java" -not -path '*/test/*' 2>/dev/null || true; } | while read -r f; do grep -l 'MVCAdminJspBean\|MVCApplication' "$f" 2>/dev/null; done | wc -l)
FILEUPLOAD_REFS=$(gcount -rn 'org\.apache\.commons\.fileupload' src/ --include="*.java" 2>/dev/null)
SHUTDOWN_SERVICE_IMPLS=$(gcount -rn 'implements\s\+\(.*,\s*\)*ShutdownService\b' src/ --include="*.java" 2>/dev/null)

TOTAL_ISSUES=$((SPRING_LOOKUPS + GETINSTANCE_CALLS + JAVAX_IMPORTS + EVENT_LISTENERS + CACHE_SERVICES + DAO_FREE + DEPRECATED_GETMODEL + FILEUPLOAD_REFS + SHUTDOWN_SERVICE_IMPLS))

# Migration scope
SCOPE="ALREADY_MIGRATED"
[ "$TOTAL_ISSUES" -gt 0 ] && SCOPE="SMALL"
[ "$TOTAL_ISSUES" -ge 20 ] && SCOPE="MEDIUM"
[ "$TOTAL_ISSUES" -ge 100 ] && SCOPE="LARGE"

# Test dependency check
HAS_UNIT_TESTING_DEP=false
grep -q 'library-lutece-unit-testing' pom.xml 2>/dev/null && HAS_UNIT_TESTING_DEP=true
USES_LUTECE_TEST_CASE=$({ grep -rl 'LuteceTestCase' src/test/ 2>/dev/null || true; } | wc -l)

# ─── Recommended Teammates ───────────────────────────────

JAVA_TEAMMATES=1
[ "$JAVA_FILES" -gt 30 ] && JAVA_TEAMMATES=2
[ "$JAVA_FILES" -gt 60 ] && JAVA_TEAMMATES=3

TEMPLATE_TEAMMATES=0
[ $((ADMIN_TEMPLATES + SKIN_TEMPLATES + JSP_COUNT)) -gt 0 ] && TEMPLATE_TEAMMATES=1

TEST_TEAMMATES=0
[ "$TEST_FILES" -gt 0 ] && TEST_TEAMMATES=1

TOTAL_TEAMMATES=$((1 + JAVA_TEAMMATES + TEMPLATE_TEAMMATES + TEST_TEAMMATES + 1))

# ─── Output JSON ─────────────────────────────────────────

cat << ENDJSON
{
  "project": {
    "type": "$PROJECT_TYPE",
    "artifact": "$ARTIFACT",
    "version": "$VERSION",
    "parentVersion": "$PARENT_VERSION"
  },
  "dependencies": $DEPS_JSON,
  "files": {
    "java": $JAVA_JSON,
    "tests": $TEST_JSON,
    "contextXml": $CTX_JSON,
    "reflectionInstantiated": $REFLECTION_JSON,
    "adminTemplates": $ADMIN_TPL_JSON,
    "skinTemplates": $SKIN_TPL_JSON,
    "jsp": $JSP_JSON,
    "sql": $SQL_JSON,
    "rest": $REST_JSON,
    "properties": $PROPS_JSON
  },
  "summary": {
    "javaFiles": $JAVA_FILES,
    "testFiles": $TEST_FILES,
    "contextXmlFiles": $CONTEXT_FILES,
    "springLookups": $SPRING_LOOKUPS,
    "getInstanceCalls": $GETINSTANCE_CALLS,
    "javaxImports": $JAVAX_IMPORTS,
    "eventListeners": $EVENT_LISTENERS,
    "cacheServices": $CACHE_SERVICES,
    "adminTemplates": $ADMIN_TEMPLATES,
    "skinTemplates": $SKIN_TEMPLATES,
    "jspFiles": $JSP_COUNT,
    "sqlFiles": $SQL_COUNT,
    "restFiles": $REST_COUNT,
    "daoFreeCalls": $DAO_FREE,
    "deprecatedGetModel": $DEPRECATED_GETMODEL,
    "deprecatedNewHashMap": $DEPRECATED_HASHMAP,
    "shutdownServiceImpls": $SHUTDOWN_SERVICE_IMPLS,
    "fileuploadRefs": $FILEUPLOAD_REFS,
    "totalMigrationPoints": $TOTAL_ISSUES,
    "scope": "$SCOPE",
    "hasUnitTestingDep": $HAS_UNIT_TESTING_DEP,
    "usesLuteceTestCase": $USES_LUTECE_TEST_CASE,
    "recommendedTeammates": {
      "config": 1,
      "java": $JAVA_TEAMMATES,
      "template": $TEMPLATE_TEAMMATES,
      "test": $TEST_TEAMMATES,
      "verifier": 1,
      "total": $TOTAL_TEAMMATES
    }
  }
}
ENDJSON
