#!/bin/bash
# verify-migration.sh — Run all migration verification checks (70+ checks)
# Usage: bash verify-migration.sh [project_root] [--json]
# Exit code: 0 if all PASS, 1 if any FAIL
# --json flag: output JSON instead of colored text (writes to .migration/verify-latest.json)

set -uo pipefail

PROJECT_ROOT="${1:-.}"
JSON_MODE=false
[ "${2:-}" = "--json" ] && JSON_MODE=true
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$PROJECT_ROOT"

# A verification that could not run must never look like one that passed. The template checks read the macro
# signatures, the icon font and the dependency templates from the assembled webapp, so the precondition is
# settled here, before any check, and its failure stops the script with the reason rather than turning green.
if [ -d "webapp/WEB-INF/templates" ]; then
    if ! EXPLODED_OUT=$(bash "$SCRIPT_DIR/ensure-exploded.sh" . 2>&1); then
        echo "$EXPLODED_OUT" >&2
        echo "" >&2
        echo "verify-migration stopped: this project does not assemble, so TM08 and TM09 cannot be evaluated and" >&2
        echo "the rest of the report would read as a clean bill of health it has not earned. Fix the build first." >&2
        exit 2
    fi
fi

PASS=0
FAIL=0
WARN=0
TOTAL=0

JSON_CHECKS="["
FIRST_CHECK=true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ─── Helper functions ────────────────────────────────────

emit() {
    local id="$1" status="$2" description="$3" count="${4:-0}" matches="${5:-}"

    TOTAL=$((TOTAL + 1))

    if $JSON_MODE; then
        $FIRST_CHECK || JSON_CHECKS="$JSON_CHECKS,"
        FIRST_CHECK=false
        ESCAPED_DESC=$(printf '%s' "$description" | sed 's/"/\\"/g')
        JSON_CHECKS="$JSON_CHECKS{\"id\":\"$id\",\"status\":\"$status\",\"description\":\"$ESCAPED_DESC\",\"count\":$count}"
    fi

    case "$status" in
        PASS) echo -e "  ${GREEN}PASS${NC} [$id] $description"; PASS=$((PASS + 1)) ;;
        FAIL) echo -e "  ${RED}FAIL${NC} [$id] $description ($count matches)"; FAIL=$((FAIL + 1))
              [ -n "$matches" ] && echo "$matches" | head -20 | sed 's/^/    /' ;;
        WARN) echo -e "  ${YELLOW}WARN${NC} [$id] $description ($count matches)"; WARN=$((WARN + 1))
              [ -n "$matches" ] && echo "$matches" | head -15 | sed 's/^/    /' ;;
    esac
}

check_grep() {
    local id="$1" pattern="$2" path="$3" severity="$4" description="$5" includes="${6:---include=*.java --include=*.xml --include=*.html --include=*.jsp}"

    if [ ! -d "$path" ]; then
        emit "$id" "PASS" "$description" 0
        return
    fi

    local matches count=0
    matches=$(eval "grep -rn '$pattern' '$path' $includes 2>/dev/null") || true
    [ -n "$matches" ] && count=$(echo "$matches" | wc -l)

    if [ "$count" -eq 0 ]; then
        emit "$id" "PASS" "$description" 0
    else
        emit "$id" "$severity" "$description" "$count" "$matches"
    fi
}

check_pom() {
    local id="$1" pattern="$2" severity="$3" description="$4"

    if [ ! -f "pom.xml" ]; then
        emit "$id" "PASS" "$description" 0
        return
    fi

    local matches count=0
    matches=$(grep -n "$pattern" pom.xml 2>/dev/null) || true
    [ -n "$matches" ] && count=$(echo "$matches" | wc -l)

    if [ "$count" -eq 0 ]; then
        emit "$id" "PASS" "$description" 0
    else
        emit "$id" "$severity" "$description" "$count" "$matches"
    fi
}

# JP05: named parameters (:name) inside native SQL strings; EclipseLink binds positional parameters only in native queries.
check_named_native_params() {
    local matches count=0
    matches=$({ grep -rl 'createNativeQuery' src/ --include="*.java" 2>/dev/null || true; } | xargs -r grep -n '"[^"]*[=(, ]:[a-zA-Z_][a-zA-Z0-9_]*' 2>/dev/null | grep -v '::\|://\|createQuery(\|\.class\|\(FROM\|UPDATE\|JOIN\) [A-Z][a-zA-Z]* ' || true)
    [ -n "$matches" ] && count=$(echo "$matches" | wc -l)
    if [ "$count" -eq 0 ]; then
        emit "JP05" "PASS" "Named parameters in native SQL" 0
    else
        emit "JP05" "WARN" "Named parameters in native SQL -> positional ?n (heuristic on string literals)" "$count" "$matches"
    fi
}

# JP06: a JPA unit declares its shared cache mode; EclipseLink caches entities across transactions by default.
check_persistence_xml() {
    local px="src/main/resources/META-INF/persistence.xml"
    if [ ! -f "$px" ]; then
        emit "JP06" "PASS" "persistence.xml shared-cache-mode (no persistence unit)" 0
        return
    fi
    if grep -q '<shared-cache-mode>' "$px" 2>/dev/null; then
        emit "JP06" "PASS" "persistence.xml declares shared-cache-mode" 0
    else
        emit "JP06" "WARN" "persistence.xml without shared-cache-mode (EclipseLink shared cache on by default; NONE unless entities are @Cacheable)" 1 "$px"
    fi
}

check_file_exists() {
    local id="$1" filepath="$2" severity="$3" description="$4"
    if [ -f "$filepath" ]; then
        emit "$id" "PASS" "$description" 0
    else
        emit "$id" "$severity" "$description (file not found: $filepath)" 1
    fi
}

echo "=== MIGRATION VERIFICATION REPORT ==="
echo "Project: $(pwd)"
echo ""

# ─── POM ─────────────────────────────────────────────────
echo "CATEGORY: POM dependencies"
check_pom "PM01" 'org\.springframework' "FAIL" "Spring dependencies in pom.xml"
check_pom "PM02" 'net\.sf\.ehcache' "FAIL" "EhCache dependencies in pom.xml"
check_pom "PM03" 'com\.sun\.mail' "FAIL" "javax.mail dependency in pom.xml"
check_pom "PM04" 'org\.glassfish\.jersey' "FAIL" "Jersey dependencies in pom.xml"
check_pom "PM05" 'net\.sf\.json-lib' "FAIL" "json-lib in pom.xml (use Jackson)"
check_pom "PM07" '<springVersion>' "FAIL" "springVersion property in pom.xml"
check_pom "PM08" '<jiraProjectName>\|<jiraComponentId>' "WARN" "Jira properties in pom.xml (remove)"

# PM09: bounded version ranges [X,Y) should be open [X,)
if [ -f "pom.xml" ]; then
    BOUNDED=$(grep -c ',[0-9].*)</version>' pom.xml 2>/dev/null || true)
    if [ "$BOUNDED" -gt 0 ]; then
        emit "PM09" "WARN" "$BOUNDED bounded version range(s) found — convert to open [X,)" 0
    else
        emit "PM09" "PASS" "No bounded version ranges" 0
    fi
else
    emit "PM09" "PASS" "No bounded version ranges (no pom.xml)" 0
fi

# PM06: parent version must start with 8.
if [ -f "pom.xml" ]; then
    PARENT_VER=$(sed -n '/<parent>/,/<\/parent>/p' pom.xml | grep '<version>' | head -1 | sed 's/.*<version>\(.*\)<\/version>.*/\1/' | tr -d ' \r')
    if [[ "$PARENT_VER" == 8.* ]]; then
        emit "PM06" "PASS" "Parent version is $PARENT_VER" 0
    else
        emit "PM06" "FAIL" "Parent version is '$PARENT_VER' (must start with 8.)" 1
    fi
else
    emit "PM06" "PASS" "Parent version check (no pom.xml)" 0
fi

# PM10: EL implementation must match what the parent manages.
#   parent >= 8.0.2 manages org.glassfish.expressly:expressly (org.glassfish:jakarta.el stopped at 5.0.0-M1)
#   parent 8.0.0 / 8.0.1 manages org.glassfish:jakarta.el only
# PM11: explicit <version> on a dependency the parent manages (list depends on the parent)
# PM12: Jakarta EE 11 artifact on the EE 10 baseline
# Only <dependency> blocks outside <dependencyManagement> are inspected.
PARENT_GE_802=false
[ -n "${PARENT_VER:-}" ] && [ "$(printf '%s\n' "8.0.2" "$PARENT_VER" | sort -V | head -1)" = "8.0.2" ] && PARENT_GE_802=true
MANAGED='library-lutece-unit-testing|hibernate-validator|jaxb-runtime|jakarta.el|expressly'
$PARENT_GE_802 && MANAGED="$MANAGED|jboss-logging|jakarta.el-api|jakarta.annotation-api"
PM10_COUNT=0; PM10_MATCHES=""
PM11_COUNT=0; PM11_MATCHES=""
PM12_COUNT=0; PM12_MATCHES=""
if [ -f "pom.xml" ]; then
    DEP_BLOCKS=$(awk '
        /<dependencyManagement>/ {dm=1}
        /<\/dependencyManagement>/ {dm=0; next}
        dm {next}
        /<dependency>/ {f=1; b=""}
        f {b = b " " $0}
        /<\/dependency>/ {if (f) print b; f=0}
    ' pom.xml 2>/dev/null) || true

    while IFS= read -r blk; do
        [ -z "$blk" ] && continue
        GID=$(printf '%s' "$blk" | sed -n 's/.*<groupId>\([^<]*\)<\/groupId>.*/\1/p' | head -1)
        AID=$(printf '%s' "$blk" | sed -n 's/.*<artifactId>\([^<]*\)<\/artifactId>.*/\1/p' | head -1)
        VER=$(printf '%s' "$blk" | sed -n 's/.*<version>\([^<]*\)<\/version>.*/\1/p' | head -1)

        case "$GID:$AID" in
            org.glassfish:jakarta.el)
                $PARENT_GE_802 && { PM10_COUNT=$((PM10_COUNT + 1)); PM10_MATCHES="${PM10_MATCHES}org.glassfish:jakarta.el is not managed by parent $PARENT_VER, use org.glassfish.expressly:expressly"$'\n'; } ;;
            org.glassfish.expressly:expressly)
                $PARENT_GE_802 || { PM10_COUNT=$((PM10_COUNT + 1)); PM10_MATCHES="${PM10_MATCHES}org.glassfish.expressly:expressly is not managed by parent $PARENT_VER, use org.glassfish:jakarta.el"$'\n'; } ;;
        esac

        if [ -n "$VER" ] && printf '%s' "$AID" | grep -qE "^($MANAGED)$"; then
            PM11_COUNT=$((PM11_COUNT + 1))
            PM11_MATCHES="$PM11_MATCHES$AID -> $VER"$'\n'
        fi

        case "$AID:$VER" in
            jakarta.annotation-api:3.*|weld-junit5:5.*|jakarta.el-api:6.*)
                PM12_COUNT=$((PM12_COUNT + 1))
                PM12_MATCHES="$PM12_MATCHES$AID -> $VER"$'\n' ;;
        esac
    done <<< "$DEP_BLOCKS"
fi

if [ "$PM10_COUNT" -eq 0 ]; then
    emit "PM10" "PASS" "EL implementation matches the parent (${PARENT_VER:-none})" 0
else
    emit "PM10" "FAIL" "EL implementation not managed by parent ${PARENT_VER:-?}" "$PM10_COUNT" "$PM10_MATCHES"
fi

if [ "$PM11_COUNT" -eq 0 ]; then
    emit "PM11" "PASS" "No explicit version on a parent-managed dependency" 0
else
    emit "PM11" "WARN" "Explicit version on a parent-managed dependency (remove it)" "$PM11_COUNT" "$PM11_MATCHES"
fi

if [ "$PM12_COUNT" -eq 0 ]; then
    emit "PM12" "PASS" "No Jakarta EE 11 artifact (EE 10 baseline)" 0
else
    emit "PM12" "FAIL" "Jakarta EE 11 artifact on an EE 10 baseline" "$PM12_COUNT" "$PM12_MATCHES"
fi
echo ""

# ─── javax Residues ──────────────────────────────────────
echo "CATEGORY: javax residues"
check_grep "JX01" 'javax\.servlet' "src/" "FAIL" "javax.servlet -> jakarta.servlet"
check_grep "JX02" 'javax\.validation' "src/" "FAIL" "javax.validation -> jakarta.validation"
check_grep "JX03" 'javax\.annotation\.PostConstruct\|javax\.annotation\.PreDestroy' "src/" "FAIL" "javax.annotation PostConstruct/PreDestroy -> jakarta"
check_grep "JX04" 'javax\.inject' "src/" "FAIL" "javax.inject -> jakarta.inject"
check_grep "JX05" 'javax\.enterprise' "src/" "FAIL" "javax.enterprise -> jakarta.enterprise"
check_grep "JX06" 'javax\.ws\.rs' "src/" "FAIL" "javax.ws.rs -> jakarta.ws.rs"
check_grep "JX07" 'javax\.xml\.bind' "src/" "FAIL" "javax.xml.bind -> jakarta.xml.bind"
check_grep "JX09" 'javax\.persistence' "src/" "FAIL" "javax.persistence -> jakarta.persistence"
check_grep "JX08" 'javax\.transaction\.Transactional\|import javax\.transaction\.[^x]' "src/" "FAIL" "javax.transaction -> jakarta.transaction"
echo ""

# ─── Spring Residues ─────────────────────────────────────
echo "CATEGORY: Spring residues"
check_grep "SP01" 'SpringContextService' "src/" "FAIL" "SpringContextService -> CDI"
check_grep "SP02" 'org\.springframework' "src/" "FAIL" "Spring imports"
check_grep "SP03" '_context\.xml' "webapp/" "FAIL" "Spring context XML files"
check_grep "SP04" '@Autowired' "src/" "FAIL" "@Autowired -> @Inject"
check_grep "SP05" 'implements.*InitializingBean' "src/" "FAIL" "InitializingBean -> @PostConstruct"
check_grep "SP06" '@Component(' "src/" "FAIL" "@Component(name) -> @ApplicationScoped @Named(name)"
check_grep "SP07" '@Service(' "src/" "FAIL" "@Service(name) -> @ApplicationScoped @Named(name)"
check_grep "SP08" '@Repository(' "src/" "FAIL" "@Repository(name) -> @ApplicationScoped @Named(name)"
echo ""

# ─── Deprecated Libraries ────────────────────────────────
echo "CATEGORY: Deprecated libraries"
check_grep "DL01" 'net\.sf\.json' "src/" "FAIL" "net.sf.json -> com.fasterxml.jackson"
echo ""

# ─── Event Residues ──────────────────────────────────────
echo "CATEGORY: Event residues"
check_grep "EV01" 'ResourceEventManager' "src/" "FAIL" "ResourceEventManager -> CDI events"
check_grep "EV02" 'EventRessourceListener' "src/" "FAIL" "EventRessourceListener -> @Observes"
check_grep "EV03" 'LuteceUserEventManager' "src/" "FAIL" "LuteceUserEventManager -> CDI events"
check_grep "EV04" 'QueryListenersService' "src/" "FAIL" "QueryListenersService -> CDI events"
check_grep "EV05" 'AbstractEventManager' "src/" "FAIL" "AbstractEventManager -> CDI events"
echo ""

# ─── Cache Residues ──────────────────────────────────────
echo "CATEGORY: Cache residues"
check_grep "CA01" 'net\.sf\.ehcache' "src/" "FAIL" "EhCache -> JCache"
check_grep "CA02" 'putInCache\|getFromCache\|removeKey' "src/" "FAIL" "Deprecated cache methods"
check_grep "CA03" 'extends AbstractCacheableService[^<]' "src/" "FAIL" "Raw AbstractCacheableService (needs type params)"

# CA04: AbstractCacheableService whose overrides do not guard on isCacheEnable( ).
# The JCache methods it inherits (get, put, remove, ...) dereference _cache, which is null while the cache is
# disabled — the default state. isCacheEnable( ) is the guard: in lutece-core it already reads
# `_cache != null && !_cache.isClosed( )`. There is no isCacheAvailable( ): an earlier version of this check
# asked for one, and a cache written to satisfy it did not compile.
CA04_MATCHES=""
if [ -d "src/" ]; then
    CA04_MATCHES=$(grep -rln 'extends AbstractCacheableService' src/ --include="*.java" 2>/dev/null | while read -r f; do
        if ! grep -q 'isCacheEnable' "$f" 2>/dev/null; then
            echo "$f: extends AbstractCacheableService without an isCacheEnable( ) guard on its overrides"
        fi
    done) || CA04_MATCHES=""
fi
COUNT=0; [ -n "$CA04_MATCHES" ] && COUNT=$(echo "$CA04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then
    emit "CA04" "PASS" "CacheService guards its overrides with isCacheEnable( )" 0
else
    emit "CA04" "WARN" "CacheService guards its overrides with isCacheEnable( )" "$COUNT" "$CA04_MATCHES"
fi
echo ""

# ─── Deprecated API ──────────────────────────────────────
echo "CATEGORY: Deprecated API"
check_grep "DP01" 'AccessControlService\.getInstance\|AccessLogService\.getInstance\|AdminDashboardService\.getInstance\|AttributeFieldService\.getInstance\|AttributeService\.getInstance\|AttributeTypeService\.getInstance\|DashboardService\.getInstance\|EditorBbcodeService\.getInstance\|ExtendableResourceActionHit\.getInstance\|FileImagePublicService\.getInstance\|FileImageService\.getInstance\|FileService\.getInstance\|FilterService\.getInstance\|LuteceUserCacheService\.getInstance\|PortalMenuService\.getInstance\|PortletService\.getInstance\|ProgressManagerService\.getInstance\|QueryListenersService\.getInstance\|RegularExpressionService\.getInstance\|RSAKeyPairUtil\.getInstance\|SecurityTokenService\.getInstance\|ServletService\.getInstance\|WorkflowService\.getInstance' "src/" "FAIL" "Deprecated core getInstance() calls (23 @Deprecated(since=8.0) in lutece-core; SecurityService/AdminAuthenticationService are not deprecated)"
check_grep "DP02" 'FileImagePublicService\.init\|FileImageService\.init' "src/" "FAIL" "Deprecated init() calls (auto-registered in v8)"
check_grep "DP03" '\(^\|[^.A-Za-z0-9_]\)getModel([[:space:]]*)' "src/" "FAIL" "MANDATORY: getModel() -> Models parameter (excludes DTO getters like request.getModel())"
echo ""

# ─── DAO ─────────────────────────────────────────────────
echo "CATEGORY: DAO"
check_grep "DA01" 'daoUtil\.free( )' "src/" "FAIL" "daoUtil.free() -> try-with-resources"

# DA02: a DAOUtil opened outside a try-with-resources: an exception between the constructor and free() leaks the
# connection (rules/dao-patterns.md: always try ( DAOUtil daoUtil = new DAOUtil( … ) ) ). A factory method that returns
# the DAOUtil it built to a caller's try-with-resources is exempt.
DA02_MATCHES=""
if [ -d "src/" ]; then
    DA02_MATCHES=$(grep -rn "new DAOUtil(" src/ --include="*.java" 2>/dev/null | grep -v "try *(" | python3 -c '
import re, sys
for hit in sys.stdin:
    path, line = hit.split(":", 2)[:2]
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    n = int(line) - 1
    var = re.search(r"(\w+)\s*=\s*new DAOUtil\(", lines[n])
    head = next((l for l in reversed(lines[:n]) if re.search(r"\)\s*$|\(\s*$|^\s*(public|private|protected|static)\b.*\(", l) and re.search(r"\b(public|private|protected|static)\b", l)), "")
    body = []
    for l in lines[n + 1:]:
        if re.search(r"^\s*(public|private|protected)\b.*\(", l):
            break
        body.append(l)
    returned = var and re.search(r"\bDAOUtil\s+\w+\s*\(", head) and any(re.search(r"^\s*return\s+%s\s*;" % var.group(1), l) for l in body)
    if not returned:
        sys.stdout.write(hit)
') || DA02_MATCHES=""
fi
COUNT=0; [ -n "$DA02_MATCHES" ] && COUNT=$(echo "$DA02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "DA02" "PASS" "Every DAOUtil lives in a try-with-resources" 0
else emit "DA02" "FAIL" "DAOUtil outside try-with-resources: the connection leaks on an exception" "$COUNT" "$DA02_MATCHES"; fi

# SQ05: a value glued into a SQL literal in a DAO ("… LIKE '%" + str + "%'", "col = '" + value + "'"): an injection
# point, and a quote in the value breaks the query. Bind it with daoUtil.setString.
SQ05_MATCHES=""
if [ -d "src/" ]; then
    SQ05_MATCHES=$(grep -rnE "'[%_]*\"[[:space:]]*\+[[:space:]]*[A-Za-z_]" src/ --include="*DAO.java" 2>/dev/null) || SQ05_MATCHES=""
fi
COUNT=0; [ -n "$SQ05_MATCHES" ] && COUNT=$(echo "$SQ05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ05" "PASS" "No value concatenated into a SQL literal" 0
else emit "SQ05" "FAIL" "Value concatenated into a SQL literal: bind it (setString), it is an injection point" "$COUNT" "$SQ05_MATCHES"; fi
echo ""

# ─── JPA ─────────────────────────────────────────────────
echo "CATEGORY: JPA (persistence-patterns.md)"
check_grep "JP01" 'import org\.hibernate\.[^v]' "src/" "FAIL" "Hibernate imports -> jakarta.persistence API only (EclipseLink of the container)"
check_pom "JP02" 'hibernate-core\|hibernate-entitymanager\|module-jpa-hibernate\|spring-orm\|spring-data-jpa' "FAIL" "JPA provider in pom.xml (the container provides EclipseLink)"
check_grep "JP03" 'hibernate\.\|HibernatePersistenceProvider' "src/main/resources/META-INF/" "FAIL" "Hibernate settings in persistence.xml" "--include=persistence.xml"
check_grep "JP04" 'IN (:\|IN (?\|IN(:\|IN(?' "src/" "FAIL" "Parenthesised collection parameter -> IN :param"
check_named_native_params
check_persistence_xml
check_grep "JP07" 'persistenceContainer-3\.1' "src/main/liberty/" "WARN" "persistenceContainer-3.1 in server.xml (norm: persistence-3.1)" "--include=server.xml"
echo ""

# ─── CDI Patterns ────────────────────────────────────────
echo "CATEGORY: CDI patterns"

# CD01: static _instance/_singleton on CDI-managed classes
CD01_MATCHES=""
if [ -d "src/" ]; then
    CD01_MATCHES=$(grep -rn 'private static.*_instance\|private static.*_singleton' src/ --include="*.java" 2>/dev/null | while read -r line; do
        FILE=$(echo "$line" | cut -d: -f1)
        if grep -q '@ApplicationScoped\|@RequestScoped\|@SessionScoped\|@Dependent' "$FILE" 2>/dev/null; then
            echo "$line"
        fi
    done) || CD01_MATCHES=""
fi
COUNT=0; [ -n "$CD01_MATCHES" ] && COUNT=$(echo "$CD01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "CD01" "PASS" "Static _instance/_singleton on CDI-managed classes" 0
else emit "CD01" "FAIL" "Static _instance/_singleton on CDI-managed classes" "$COUNT" "$CD01_MATCHES"; fi

check_grep "CD02" 'new CaptchaSecurityService()' "src/" "FAIL" "new CaptchaSecurityService() -> @Inject"
check_grep "CD03" 'CompletableFuture\.runAsync( ( ) ->[^,]*$\|CompletableFuture\.runAsync( [^,]*$' "src/" "WARN" "CompletableFuture.runAsync without explicit executor -> use a managed ExecutorService or @Asynchronous"
check_grep "CD04" 'org\.apache\.commons\.fileupload' "src/" "FAIL" "commons.fileupload -> MultipartItem"

# CD05: Constructor self-registration without @Observes @Initialized (lazy CDI bean trap)
CD05_MATCHES=""
if [ -d "src/" ]; then
    CD05_MATCHES=$(grep -rln 'registerIndexer\|registerCacheableService\|registerProvider\|IndexationService\.register\|CacheService\.register\|ImageResourceManager\.register' src/ --include="*.java" 2>/dev/null | while read -r f; do
        if ! grep -q '@Observes' "$f" 2>/dev/null; then
            echo "$f: self-registration without @Observes @Initialized (CDI bean is lazy, constructor never called)"
        fi
    done) || CD05_MATCHES=""
fi
COUNT=0; [ -n "$CD05_MATCHES" ] && COUNT=$(echo "$CD05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "CD05" "PASS" "No lazy bean self-registration trap" 0
else emit "CD05" "WARN" "Constructor self-registration without @Observes @Initialized" "$COUNT" "$CD05_MATCHES"; fi
echo ""

# ─── MVC / New Patterns (v2 additions) ──────────────────
echo "CATEGORY: MVC / New patterns"

# MV01: new HashMap in JspBean/XPage (should use @Inject Models)
MV01_MATCHES=""
if [ -d "src/" ]; then
    MV01_MATCHES=$({ grep -rln 'new HashMap' src/ --include="*.java" -not -path '*/test/*' 2>/dev/null || true; } | while read -r f; do
        if grep -q 'MVCAdminJspBean\|MVCApplication' "$f" 2>/dev/null; then
            grep -n 'new HashMap' "$f" | head -3 | sed "s|^|$f:|"
        fi
    done) || MV01_MATCHES=""
fi
COUNT=0; [ -n "$MV01_MATCHES" ] && COUNT=$(echo "$MV01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "MV01" "PASS" "new HashMap in JspBean/XPage (use @Inject Models)" 0
else emit "MV01" "FAIL" "new HashMap in JspBean/XPage (use @Inject Models)" "$COUNT" "$MV01_MATCHES"; fi

check_grep "MV02" 'AbstractPaginatorJspBean' "src/" "FAIL" "AbstractPaginatorJspBean -> @Pager IPager"
# MV03: an MVC bean gets its CSRF token from the framework; carrying it by hand there means the framework's own
# token is off or duplicated. A bean that is not MVC (a portlet admin bean, a servlet) has no framework token and
# must carry it by hand: that is the pattern, not a finding. An explicitly disabled token is always one.
MV03_TOKEN='SecurityTokenService\.MARK_TOKEN|getSecurityTokenService\( \)\.(getToken|validate)|_securityTokenService\.(getToken|validate)'
MV03_MATCHES=""
if [ -d "src/" ]; then
    MV03_MATCHES=$({ grep -rlE "$MV03_TOKEN" src/ --include="*.java" 2>/dev/null || true; } | while read -r f; do
        if grep -qE '@Controller|MVCAdminJspBean|MVCApplication' "$f" 2>/dev/null; then
            grep -nE "$MV03_TOKEN" "$f" | head -3 | sed "s|^|$f:|"
        fi
    done)
    MV03_OFF=$({ grep -rnE 'securityTokenEnabled[[:space:]]*=[[:space:]]*false' src/ --include="*.java" 2>/dev/null || true; })
    [ -n "$MV03_OFF" ] && MV03_MATCHES="$MV03_MATCHES${MV03_MATCHES:+$'\n'}$MV03_OFF"
fi
COUNT=0; [ -n "$MV03_MATCHES" ] && COUNT=$(echo "$MV03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "MV03" "PASS" "CSRF token left to the framework in the MVC beans" 0
else emit "MV03" "WARN" "Manual CSRF token in an MVC bean, or securityTokenEnabled=false (the framework owns the token there)" "$COUNT" "$MV03_MATCHES"; fi

# MV04: FileItem still used (not MultipartItem). Excludes MemoryFileItem from library-httpaccess (v8 in-memory helper).
check_grep "MV04" 'import\s\+org\.apache\.commons\.fileupload[0-9]*\(\.core\)\?\.FileItem' "src/" "FAIL" "FileItem -> MultipartItem (use MemoryFileItem from library-httpaccess for in-memory cases)" "--include=*.java"
echo ""

# ─── Web / Config ────────────────────────────────────────
echo "CATEGORY: Web / Config"
check_grep "WB01" 'java\.sun\.com/xml/ns/javaee' "webapp/" "FAIL" "Old Java EE namespace -> Jakarta EE"
check_grep "WB02" '<application-class>' "webapp/WEB-INF/plugins/" "FAIL" "application-class -> CDI auto-discovery"
check_grep "WB03" 'ContextLoaderListener' "webapp/" "FAIL" "Spring ContextLoaderListener in web.xml"

# WB04: min-core-version not set to 8.0.0
WB04_MATCHES=""
if [ -d "webapp/WEB-INF/plugins/" ]; then
    WB04_MATCHES=$(grep -rn '<min-core-version>' webapp/WEB-INF/plugins/ --include="*.xml" 2>/dev/null | grep -v '8\.0\.0') || WB04_MATCHES=""
fi
COUNT=0; [ -n "$WB04_MATCHES" ] && COUNT=$(echo "$WB04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB04" "PASS" "min-core-version set to 8.0.0" 0
else emit "WB04" "WARN" "min-core-version not set to 8.0.0" "$COUNT" "$WB04_MATCHES"; fi

# WB05: a descriptor filter mapped under the JAX-RS application path never fires in v8.
# MainFilter.matchMapping compares the url-pattern to request.getServletPath( ), which is "/rest" for every call
# routed to the application mounted by @ApplicationPath( "/rest/" ). A pattern deeper than that can never match,
# so the filter is registered at startup and silently never runs: measured 401 on a v7 site, 200 on v8.
# Replace it with a @NameBinding ContainerRequestFilter on the resource (patterns/rest-patterns.md 3 and 6).
WB05_MATCHES=""
if [ -d "webapp/WEB-INF/plugins/" ]; then
    WB05_MATCHES=$(grep -rn '<url-pattern>/rest/..*</url-pattern>' webapp/WEB-INF/plugins/ --include="*.xml" 2>/dev/null | grep -v '<url-pattern>/rest/\*</url-pattern>') || WB05_MATCHES=""
fi
COUNT=0; [ -n "$WB05_MATCHES" ] && COUNT=$(echo "$WB05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB05" "PASS" "no descriptor filter mapped under the JAX-RS application path" 0
else emit "WB05" "FAIL" "descriptor filter under /rest/ never fires in v8 -> @NameBinding ContainerRequestFilter" "$COUNT" "$WB05_MATCHES"; fi

check_file_exists "ST01" "src/main/resources/META-INF/beans.xml" "FAIL" "beans.xml exists"
echo ""

# ─── Structure ───────────────────────────────────────────
echo "CATEGORY: Structure"

# ST02: final on a CDI-managed class that is resolved by its concrete type
# final is legal when the bean is only resolved through its interface (cdi-patterns.md §1):
# core DAOs are @ApplicationScoped public final class. Only flag a class the code injects
# or selects by its concrete type, which is the case that cannot be proxied.
ST02_MATCHES=""
if [ -d "src/" ]; then
    ST02_MATCHES=$(grep -rn 'public final class' src/ --include="*.java" 2>/dev/null | while read -r line; do
        FILE=$(echo "$line" | cut -d: -f1)
        grep -q '@ApplicationScoped\|@RequestScoped\|@SessionScoped\|@Dependent' "$FILE" 2>/dev/null || continue
        CLS=$(echo "$line" | sed 's/.*public final class \([A-Za-z0-9_]*\).*/\1/')
        [ -z "$CLS" ] && continue
        if grep -rq "select( *${CLS}\.class" src/ --include="*.java" 2>/dev/null \
           || { grep -rA2 '@Inject' src/ --include="*.java" 2>/dev/null | grep -q "[[:space:]]${CLS}[[:space:]]\+[_a-zA-Z]"; }; then
            echo "$line -> resolved by concrete type, not proxyable"
        fi
    done) || ST02_MATCHES=""
fi
COUNT=0; [ -n "$ST02_MATCHES" ] && COUNT=$(echo "$ST02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "ST02" "PASS" "No final keyword on a CDI class resolved by its concrete type" 0
else emit "ST02" "FAIL" "final keyword on a CDI class resolved by its concrete type" "$COUNT" "$ST02_MATCHES"; fi

# ST03: DAO classes without @ApplicationScoped
ST03_MATCHES=""
if [ -d "src/" ]; then
    # Only a file that DECLARES a DAO class. The former pattern, `class.*DAO`, also matched any line mentioning
    # a DAO after the word class — `select( ICityDAO.class, NamedLiteral.of( "myplugin.cityDAO" ) )` in a Home,
    # for instance — and reported Home facades, which are static by design and carry no scope.
    ST03_MATCHES=$(grep -rlE '^[[:space:]]*(public|final|abstract|public final|public abstract)[[:space:]]+class[[:space:]]+[A-Za-z0-9_]*DAO\b' src/ --include="*.java" 2>/dev/null | while read -r f; do
        grep -q 'public interface\|protected interface' "$f" 2>/dev/null && continue
        if ! grep -q '@ApplicationScoped\|@RequestScoped\|@SessionScoped\|@Dependent' "$f" 2>/dev/null; then
            echo "$f: DAO class without CDI scope annotation"
        fi
    done) || ST03_MATCHES=""
fi
COUNT=0; [ -n "$ST03_MATCHES" ] && COUNT=$(echo "$ST03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "ST03" "PASS" "DAO classes have CDI scope" 0
else emit "ST03" "FAIL" "DAO classes without @ApplicationScoped" "$COUNT" "$ST03_MATCHES"; fi

# ST04: Service classes without CDI scope
ST04_MATCHES=""
if [ -d "src/" ]; then
    ST04_MATCHES=$({ grep -rln 'class.*Service\b' src/ --include="*.java" -not -path '*/test/*' 2>/dev/null || true; } | while read -r f; do
        grep -q 'public interface\|protected interface' "$f" 2>/dev/null && continue
        grep -q 'class.*Home\b' "$f" 2>/dev/null && continue
        if ! grep -q '@ApplicationScoped\|@RequestScoped\|@SessionScoped\|@Dependent' "$f" 2>/dev/null; then
            echo "$f: Service class without CDI scope annotation"
        fi
    done) || ST04_MATCHES=""
fi
COUNT=0; [ -n "$ST04_MATCHES" ] && COUNT=$(echo "$ST04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "ST04" "PASS" "Service classes have CDI scope" 0
else emit "ST04" "FAIL" "Service classes without CDI scope" "$COUNT" "$ST04_MATCHES"; fi

# ST05: files created by the migration must be able to reach the repository. ST01 only proves the file is on
# disk; a file that .gitignore excludes never will, and the plugin ships without its CDI descriptor (the Home
# static initializer then fails with UnsatisfiedResolutionException at the next clone). Untracked is fine here:
# the skill stages with `git add -A` at the very end, after this gate.
ST05_MATCHES=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    for f in src/main/resources/META-INF/beans.xml src/test/resources/META-INF/microprofile-config.properties; do
        [ -f "$f" ] || continue
        git check-ignore -q "$f" 2>/dev/null && ST05_MATCHES="$ST05_MATCHES$f: excluded by .gitignore, will never be committed"$'\n'
    done
    ST05_MATCHES=$(printf '%s' "$ST05_MATCHES")
fi
COUNT=0; [ -n "$ST05_MATCHES" ] && COUNT=$(echo "$ST05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "ST05" "PASS" "Files created by the migration are not ignored by git" 0
else emit "ST05" "FAIL" "Files created by the migration are excluded by .gitignore" "$COUNT" "$ST05_MATCHES"; fi


# LE01: a converted line ending rewrites every line of the file and hides the migration in the diff. A file counts
# as converted when HEAD and the work tree disagree on carriage returns, whatever else changed in it: the files
# that also carry real changes are the ones where the review matters most. A file left with no line break at all
# (a one-line JSP that streams a download, whose trailing newline would be written after the file) is not converted.
# Line-ending style of stdin: CRLF, LF, CR (old Mac, a file most tools read as one line) or mixed -- leaving either is a repair --,
# mixed, or none.
line_endings() {
    python3 -c 'import sys
d = sys.stdin.buffer.read()
crlf = d.count(b"\r\n"); cr = d.count(b"\r") - crlf; lf = d.count(b"\n") - crlf
kinds = [k for k, n in (("CRLF", crlf), ("CR", cr), ("LF", lf)) if n]
print(kinds[0] if len(kinds) == 1 else ("mixed" if kinds else "none"))'
}
LE01_MATCHES=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    LE01_MATCHES=$(git diff HEAD --name-only --diff-filter=M 2>/dev/null | while read -r f; do
        [ -f "$f" ] || continue
        head_le=$(git show "HEAD:$f" 2>/dev/null | head -c 20000 | line_endings)
        work_le=$(head -c 20000 "$f" | line_endings)
        [ "$head_le" = "$work_le" ] || [ "$head_le" = "CR" ] || [ "$head_le" = "mixed" ] || [ "$head_le" = "none" ] || [ "$work_le" = "none" ] || echo "$f: $head_le in HEAD, $work_le now"
    done)
fi
COUNT=0; [ -n "$LE01_MATCHES" ] && COUNT=$(echo "$LE01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "LE01" "PASS" "No file had its line endings converted" 0
else emit "LE01" "FAIL" "Line endings converted: run restore-line-endings.sh, the diff must show the migration, not the whole file" "$COUNT" "$LE01_MATCHES"; fi

# XT01: the XSL machinery left the core (LUT-32172): XmlTransformerService and the core_style* tables live in
# plugin-xmltransformer. Code or SQL that still uses them needs that dependency declared — or, for a portlet, the
# port to HTML (XS01).
XT01_MATCHES=""
if ! grep -q '<artifactId>plugin-xmltransformer</artifactId>' pom.xml 2>/dev/null; then
    XT01_MATCHES=$({ grep -rlE 'XmlTransformerService|XmlTransformer\b|XslExportService' src/ --include="*.java" 2>/dev/null || true; } | sed 's/$/: uses the XSL services that moved to plugin-xmltransformer, undeclared/')
    # Statements only: a leftover `-- Dumping data for table core_style` comment writes nothing. An upgrade statement
    # sitting in a changeset guarded by a precondition on those tables is a legacy step kept for the sites that have
    # them (XT03 checks the guard): it needs no dependency and is not counted here.
    SQL_XT=$({ find src/sql -name '*.sql' 2>/dev/null | sort | while read -r f; do
        awk 'BEGIN{IGNORECASE=1; g=0; found=0} /^--[[:space:]]*changeset/ {g=0} /^--[[:space:]]*precondition-sql-check/ {g=1}
             /^[[:space:]]*(INSERT|UPDATE|DELETE|ALTER|CREATE)[^;]*core_style/ && !g {found=1} END{exit !found}' "$f" && echo "$f"
    done; } | sed 's/$/: writes core_style* tables the core no longer has (plugin-xmltransformer, or drop with the XSL portlet)/')
    [ -n "$SQL_XT" ] && XT01_MATCHES="$XT01_MATCHES${XT01_MATCHES:+$'\n'}$SQL_XT"
fi
COUNT=0; [ -n "$XT01_MATCHES" ] && COUNT=$(echo "$XT01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "XT01" "PASS" "No use of the XSL services and tables that left the core" 0
else emit "XT01" "FAIL" "XSL services or core_style* used without plugin-xmltransformer (patterns/core-8x-moves.md)" "$COUNT" "$XT01_MATCHES"; fi

# XT02: a plugin that keeps XSL declares plugin-xmltransformer, and then its install scripts write to tables that
# plugin creates. Without `-- lutece runAfter:xmltransformer` the order of installation is not guaranteed and the
# inserts land before the tables exist; the v7 Ant install went on past that error, Liquibase does not.
XT02_MATCHES=""
if grep -q '<artifactId>plugin-xmltransformer</artifactId>' pom.xml 2>/dev/null && [ -d src/sql ]; then
    XT02_MATCHES=$(find src/sql -name '*.sql' -not -path '*/upgrade/*' | sort | while read -r f; do
        grep -qE '^[[:space:]]*(INSERT|UPDATE|DELETE)[^;]*core_style' "$f" || continue
        grep -qiE '^--[[:space:]]*lutece runAfter:xmltransformer' "$f" || echo "$f: writes core_style* but has no '-- lutece runAfter:xmltransformer' header"
    done)
fi
COUNT=0; [ -n "$XT02_MATCHES" ] && COUNT=$(echo "$XT02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "XT02" "PASS" "Install scripts writing core_style* run after xmltransformer" 0
else emit "XT02" "FAIL" "Install scripts write core_style* without runAfter:xmltransformer (sql-liquibase.md)" "$COUNT" "$XT02_MATCHES"; fi

# XT03: an upgrade script that writes to core_style* runs on every site that migrates, including the ones where
# those tables are gone. Unguarded, its first statement stops the whole Liquibase update, the core's own upgrade
# included. The statement must sit in a changeset opened by a precondition on the presence of the tables.
XT03_MATCHES=""
if [ -d src/sql ]; then
    XT03_MATCHES=$(find src/sql -path '*/upgrade/*' -name '*.sql' | sort | while read -r f; do
        awk -v F="$f" 'BEGIN{IGNORECASE=1; guarded=0}
            /^--[[:space:]]*changeset/ {guarded=0}
            /^--[[:space:]]*precondition-sql-check/ {guarded=1}
            /^[[:space:]]*(INSERT|UPDATE|DELETE|ALTER)[^;]*core_style/ && !guarded {print F": "NR": statement on core_style* in a changeset without precondition-sql-check"}' "$f"
    done)
fi
COUNT=0; [ -n "$XT03_MATCHES" ] && COUNT=$(echo "$XT03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "XT03" "PASS" "Upgrade statements on core_style* are guarded by a precondition" 0
else emit "XT03" "FAIL" "Upgrade statements on core_style* without a precondition on the tables (sql-liquibase.md)" "$COUNT" "$XT03_MATCHES"; fi

# SQ03: adding AUTO_INCREMENT to a column whose rows include a 0 makes MariaDB and MySQL renumber that 0 into 1
# and fail on the duplicate key. Reference rows shipped with id 0 are common in older init scripts. The ALTER needs
# `SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO'` in the same changeset, restricted to dbms:mariadb,mysql.
SQ03_MATCHES=""; SQ03_ZERO=0
if [ -d src/sql ]; then
    SQ03_MATCHES=$(find src/sql -path '*/upgrade/*' -name '*.sql' | sort | while read -r f; do
        awk -v F="$f" 'BEGIN{IGNORECASE=1; safe=0}
            /^--[[:space:]]*changeset/ {safe=0}
            /NO_AUTO_VALUE_ON_ZERO/ {safe=1}
            /^[[:space:]]*ALTER[[:space:]]+TABLE[[:space:]]+[A-Za-z0-9_]+[[:space:]]+(MODIFY|CHANGE|ADD)[^;]*AUTO_INCREMENT/ && !safe {
                t=$3; print F": "NR": AUTO_INCREMENT added to "t" without NO_AUTO_VALUE_ON_ZERO in the changeset"}' "$f"
    done)
    if [ -n "$SQ03_MATCHES" ]; then
        for tbl in $(echo "$SQ03_MATCHES" | sed -n 's/.*added to \([A-Za-z0-9_]*\) .*/\1/p' | sort -u); do
            if find src/sql -name '*.sql' -not -path '*/upgrade/*' -print0 | xargs -0 grep -qiE "INSERT INTO[[:space:]]+$tbl\b[^;]*VALUES[[:space:]]*\(0," 2>/dev/null; then
                SQ03_ZERO=1; SQ03_MATCHES="$SQ03_MATCHES"$'\n'"$tbl: the install data ships a row with id 0 — this upgrade fails on every existing site"
            fi
        done
    fi
fi
COUNT=0; [ -n "$SQ03_MATCHES" ] && COUNT=$(echo "$SQ03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ03" "PASS" "No AUTO_INCREMENT added without NO_AUTO_VALUE_ON_ZERO" 0
elif [ "$SQ03_ZERO" -eq 1 ]; then emit "SQ03" "FAIL" "AUTO_INCREMENT added to a table shipped with an id 0, without NO_AUTO_VALUE_ON_ZERO (sql-liquibase.md)" "$COUNT" "$SQ03_MATCHES"
else emit "SQ03" "WARN" "AUTO_INCREMENT added without NO_AUTO_VALUE_ON_ZERO: fails on a site whose older data holds an id 0 (sql-liquibase.md)" "$COUNT" "$SQ03_MATCHES"; fi

# CS02: ContentService no longer extends AbstractCacheableService in v8: initCache/getFromCache/putInCache on a
# content service do not compile. The cache, if still wanted, is a service of its own (lutece-cache skill).
CS02_MATCHES=""
if [ -d "src/" ]; then
    CS02_MATCHES=$({ grep -rl 'extends ContentService\b' src/ --include="*.java" 2>/dev/null || true; } | while read -r f; do
        grep -qE '(^|[^.[:alnum:]_])(this\.)?(initCache|getFromCache|putInCache)[[:space:]]*\(' "$f" && echo "$f: content service using the cache methods v8 removed from ContentService"
    done)
fi
COUNT=0; [ -n "$CS02_MATCHES" ] && COUNT=$(echo "$CS02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "CS02" "PASS" "No content service relies on the removed ContentService cache" 0
else emit "CS02" "FAIL" "ContentService cache methods used (removed in v8, patterns/core-8x-moves.md)" "$COUNT" "$CS02_MATCHES"; fi
echo ""

# ─── v8 core changes ─────────────────────────────────────
echo "CATEGORY: v8 core changes"

# XS01: a portlet still rendered by XSL. Must be ported to HTML, there is no second option:
# the style tables left the core for plugin-xmltransformer, PortletStyleDAO in the core is a
# stub, and since LUT-32172 the back office cannot create an XSL portlet whose type is not
# DOCUMENT* (MANDATORY_FIELDS, whatever is installed). Port per mvc-patterns.md §10:
# extend PortletHtmlContent, implement getHtmlContent(), delete the XSL and the core_style rows.
XS01_MATCHES=""
if [ -d "src/" ]; then
    XS01_MATCHES=$({ grep -rln 'getXmlDocument\|public String getXml(' src/ --include="*.java" 2>/dev/null || true; } | while read -r f; do
        grep -q 'extends PortletHtmlContent' "$f" 2>/dev/null && continue
        grep -q 'class .*Portlet\b' "$f" 2>/dev/null || continue
        echo "$f: portlet still rendered by XSL, port it to PortletHtmlContent"
    done) || XS01_MATCHES=""
fi
if [ -d "src/sql" ]; then
    SQL_STYLES=$(grep -rlEi '^[[:space:]]*INSERT INTO[[:space:]]+`?core_(style|stylesheet|style_mode_stylesheet)`?[[:space:]]' src/sql 2>/dev/null | while read -r f; do
        echo "$f: inserts into style tables that no longer exist in the core"
    done)
    [ -n "$SQL_STYLES" ] && XS01_MATCHES="$XS01_MATCHES${XS01_MATCHES:+$'\n'}$SQL_STYLES"
fi
COUNT=0; [ -n "$XS01_MATCHES" ] && COUNT=$(echo "$XS01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "XS01" "PASS" "No portlet left on XSL rendering" 0
else emit "XS01" "FAIL" "Portlet still rendered by XSL (port to HTML, mvc-patterns.md 10)" "$COUNT" "$XS01_MATCHES"; fi

# SQ01: every SQL file must start with the Liquibase header. v7 installed through Ant and ran headerless files;
# v8 installs through plugin-liquibase only, which drops them without a log line (sql-liquibase.md).
SQ01_MATCHES=""
if [ -d "src/sql" ]; then
    SQ01_MATCHES=$(find src/sql -name '*.sql' -size +0 | sort | while read -r f; do
        grep -m1 -v '^[[:space:]]*$' "$f" | grep -q 'liquibase formatted sql' || echo "$f: no '-- liquibase formatted sql' first line"
    done)
fi
COUNT=0; [ -n "$SQ01_MATCHES" ] && COUNT=$(echo "$SQ01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ01" "PASS" "Every SQL file carries the Liquibase header" 0
else emit "SQ01" "FAIL" "SQL files Liquibase will ignore (sql-liquibase.md)" "$COUNT" "$SQ01_MATCHES"; fi

# SQ02: what the creation script gained since the last commit, an existing site never gets. A column or a table
# added to create_db_*.sql is green on every fresh bench and breaks the first migrated site (seen with a v8
# DAO writing a new column into a history table the v7 base did not have). Each addition needs an
# upgrade script under src/sql/**/upgrade/ that creates it, with a real precondition (sql-liquibase.md).
SQ02_MATCHES=""
if [ -d "src/sql" ] && git rev-parse -q --verify HEAD >/dev/null 2>&1; then
    columns() { awk 'BEGIN{IGNORECASE=1} /CREATE TABLE/{t=$0; sub(/.*CREATE TABLE[[:space:]]+(IF NOT EXISTS[[:space:]]+)?/,"",t); sub(/[[:space:]]*\(.*/,"",t); gsub(/`/,"",t); in_t=1; next}
        in_t && /^[[:space:]]*\)/{in_t=0} in_t{c=$1; gsub(/[`,]/,"",c); if (c!="" && c !~ /^(PRIMARY|KEY|CONSTRAINT|UNIQUE|INDEX|FOREIGN|\)|\()$/) print tolower(t)"."tolower(c)}' "$@" 2>/dev/null | sort -u; }
    SQ02_MATCHES=$(find src/sql -path '*/plugin/*' -name 'create_db_*.sql' | sort | while read -r f; do
        git cat-file -e "HEAD:$f" 2>/dev/null || continue
        comm -13 <(columns <(git show "HEAD:$f")) <(columns "$f") | while IFS=. read -r table col; do
            # Covered when an upgrade script adds the column, or (re)creates the table WITH it — an older
            # upgrade that created the table without the column proves nothing, it is how the first case broke.
            if grep -rqiE "ALTER TABLE \`?$table\`?.*ADD (COLUMN )?\`?$col\`?\b" src/sql --include='update_db_*.sql' 2>/dev/null; then continue; fi
            if grep -rliE "CREATE TABLE (IF NOT EXISTS )?\`?$table\`?\b" src/sql --include='update_db_*.sql' 2>/dev/null | xargs -r cat | columns | grep -qx "$table.$col"; then continue; fi
            echo "$f: $table.$col is new here and no upgrade script under src/sql/**/upgrade/ adds it"
        done
    done)
fi
COUNT=0; [ -n "$SQ02_MATCHES" ] && COUNT=$(echo "$SQ02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ02" "PASS" "Every column or table the creation script gained has its upgrade script" 0
else emit "SQ02" "FAIL" "Schema gained by create_db without an upgrade script for existing sites (sql-liquibase.md)" "$COUNT" "$SQ02_MATCHES"; fi

# TL01: ThreadLocal must be cleared with remove() in a finally block, never reassigned.
# Reassigning keeps one entry per pooled thread for the whole application lifetime
# (LUT-31201, see the scalability skill). Applies to migration, not only to scaling work.
TL01_MATCHES=""
if [ -d "src/" ]; then
    TL01_MATCHES=$({ grep -rln 'ThreadLocal' src/ --include="*.java" 2>/dev/null || true; } | while read -r f; do
        grep -q '\.remove( *)' "$f" 2>/dev/null && continue
        echo "$f: ThreadLocal never cleared with remove()"
    done) || TL01_MATCHES=""
fi
COUNT=0; [ -n "$TL01_MATCHES" ] && COUNT=$(echo "$TL01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TL01" "PASS" "ThreadLocal cleared with remove()" 0
else emit "TL01" "FAIL" "ThreadLocal not cleared with remove()" "$COUNT" "$TL01_MATCHES"; fi

# CS01: a portlet JspBean must carry its own CSRF token. The platform filter only protects MVC actions
# (@Action / @View on MVCAdminJspBean or XPage); a PortletJspBean is the one legacy path outside it, and the
# core's create_portlet.html / modify_portlet.html emit no token. The plugin can still do it: its specific
# template is included INSIDE the core form and getCreateTemplate/getModifyTemplate take a model.
# Pattern: model.put( SecurityTokenService.MARK_TOKEN, getSecurityTokenService( ).getToken( request, ACTION ) )
# in getCreate/getModify, a hidden input in the specific template, validate( request, ACTION ) in every do*.
CS01_MATCHES=""
if [ -d "src/" ]; then
    CS01_MATCHES=$({ grep -rln 'extends PortletJspBean' src/ --include="*.java" 2>/dev/null || true; } | while read -r f; do
        python3 - "$f" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8", errors="replace").read()
for m in re.finditer(r"public\s+String\s+(do\w+)\s*\([^)]*\)[^{]*\{", text):
    depth, i = 1, m.end()
    while depth and i < len(text):
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        i += 1
    if not re.search(r"\.validate\s*\(\s*request", text[m.end():i]):
        print("%s: %s() is public and validates no token (reachable or not, a public do* is a mutation entry)" % (path, m.group(1)))
PY
    done) || CS01_MATCHES=""
fi
COUNT=0; [ -n "$CS01_MATCHES" ] && COUNT=$(echo "$CS01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "CS01" "PASS" "Portlet JspBean mutations carry a CSRF token" 0
else emit "CS01" "FAIL" "Portlet JspBean without CSRF token (mvc-patterns.md 11)" "$COUNT" "$CS01_MATCHES"; fi

# I18N01: a key of <plugin>_messages.properties is relative to the bundle, so it never repeats the plugin name.
# Writing <plugin>.message.x in <plugin>_messages.properties resolves as <plugin>.<plugin>.message.x and
# the message silently renders as the raw key. The same grep catches a key appended without a newline, glued to
# the value of the line above, which corrupts both entries at once.
I18N01_MATCHES=""
if [ -d "src/java" ]; then
    I18N01_MATCHES=$(find src/java -name "*_messages*.properties" 2>/dev/null | while read -r f; do
        PLUGIN=$(basename "$f" | sed 's/_messages.*//')
        [ -n "$PLUGIN" ] || continue
        # The plugin name must be followed by a key and an '=': without that, a value ending with a sentence
        # such as "CSS style to apply to the links." is flagged as a key, which it is not.
        grep -nE "(^|[^A-Za-z0-9_.])$PLUGIN\.[A-Za-z0-9_.]*[A-Za-z0-9_] *=" "$f" 2>/dev/null | while read -r line; do
            echo "$f:$line"
        done
    done) || I18N01_MATCHES=""
fi
COUNT=0; [ -n "$I18N01_MATCHES" ] && COUNT=$(echo "$I18N01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N01" "PASS" "No i18n key repeating the plugin prefix" 0
else emit "I18N01" "FAIL" "i18n key repeats the plugin prefix (or glued to the line above): it never resolves (fix-i18n-bundles.py)" "$COUNT" "$I18N01_MATCHES"; fi
echo ""

# I18N02: a key a template or a message constant asks for, that no bundle of this plugin declares. Lutece then
# renders the raw key on screen and nothing fails at build time. Unambiguous sources only: `#i18n{}` in the
# templates, the Java constants whose name says they hold a message key (MESSAGE_, INFO_, ERROR_, WARNING_, TITLE_,
# PROPERTY_PAGE_TITLE_), the label tags of the plugin descriptor (feature, portlet type, daemon, description) and the
# name/description of the core_admin_right and core_portlet_type rows the SQL inserts. Bean names and CSRF action names are strings too, and are not keys.
# Every grep here is `-a`: a bundle written in ISO-8859 counts as binary for grep, which then reports nothing and
# the check would silently pass — the same trap applies to any manual search in these files.
I18N02_MATCHES=""
if [ -d "src/java" ]; then
    BUNDLE=$(find src/java -name "*_messages.properties" 2>/dev/null | head -1)
    PLUGIN=$(basename "${BUNDLE:-}" 2>/dev/null | sed 's/_messages.properties//')
    if [ -n "$PLUGIN" ] && [ -n "$BUNDLE" ]; then
        DECLARED=$(mktemp); ASKED=$(mktemp)
        SCRIPT_DIR="$SCRIPT_DIR" python3 -c 'import glob, os, sys; sys.path.insert(0, os.environ["SCRIPT_DIR"]); from bundles import keys; print("\n".join(k for f in glob.glob("src/java/**/*_messages*.properties", recursive=True) for k in keys(f)))' | LC_ALL=C sort -u > "$DECLARED"
        grep -arhoE "#i18n\{$PLUGIN\.[A-Za-z0-9_.-]+\}" webapp src 2>/dev/null | sed -E "s/^#i18n\{$PLUGIN\.//; s/\}$//" >> "$ASKED"
        grep -arhoE "(MESSAGE|INFO|ERROR|WARNING|TITLE|PROPERTY_PAGE_TITLE)_[A-Z0-9_]+ *= *\"$PLUGIN\.[A-Za-z0-9_.-]+\"" src/java --include="*.java" 2>/dev/null \
            | grep -oE "\"$PLUGIN\.[A-Za-z0-9_.-]+\"" | tr -d '"' | sed -E "s/^$PLUGIN\.//" >> "$ASKED"
        grep -ahoE "<(description|feature-title|feature-description|portlet-type-name|daemon-name|daemon-description|insert-service-label)>$PLUGIN\.[A-Za-z0-9_.-]+<" webapp/WEB-INF/plugins/*.xml 2>/dev/null \
            | sed -E "s/^<[a-z-]+>$PLUGIN\.//; s/<$//" >> "$ASKED"
        grep -rahiE "INSERT +INTO +core_(portlet_type|admin_right)\b" src/sql --include="*.sql" 2>/dev/null \
            | grep -oE "'$PLUGIN\.[A-Za-z0-9_.-]+'" | tr -d "'" | sed -E "s/^$PLUGIN\.//" >> "$ASKED"
        I18N02_MATCHES=$(sort -u "$ASKED" | while read -r k; do
            [ -n "$k" ] || continue
            grep -qxF "$k" "$DECLARED" || echo "$PLUGIN.$k: asked for by a template, a message constant, the plugin descriptor or a right/portlet type row, declared in no bundle"
        done)
        rm -f "$DECLARED" "$ASKED"
    fi
fi
COUNT=0; [ -n "$I18N02_MATCHES" ] && COUNT=$(echo "$I18N02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N02" "PASS" "Every i18n key the plugin asks for is declared" 0
else emit "I18N02" "WARN" "i18n key asked for but declared nowhere: the raw key shows on screen" "$COUNT" "$I18N02_MATCHES"; fi
echo ""

# ─── JSP ─────────────────────────────────────────────────
# SQ04: an INSERT into a core table without its column list. The core adds columns across 8.0.x (core_portlet gained
# id_template in 8.0.2): a positional VALUES list then fails with "Column count doesn't match value count", Liquibase
# stops and the site never starts. Name the columns.
SQ04_MATCHES=""
if [ -d "src/sql" ]; then
    SQ04_MATCHES=$(grep -rniE "INSERT +INTO +core_[a-z0-9_]+ +VALUES" src/sql --include="*.sql" 2>/dev/null) || SQ04_MATCHES=""
fi
COUNT=0; [ -n "$SQ04_MATCHES" ] && COUNT=$(echo "$SQ04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ04" "PASS" "INSERTs into core tables name their columns" 0
else emit "SQ04" "FAIL" "INSERT into a core table without column list: breaks when the core adds a column. In a script already released with a liquibase header, keep the old checksums valid: liquibase-checksum.sh <file> <release tag>, then -- validCheckSum: lines" "$COUNT" "$SQ04_MATCHES"; fi
echo ""

# I18N03: a key the default bundle carries and _fr does not, or the reverse (the two languages the core ships): the
# missing language falls back, a French user reads the English text, nothing logs it. I18N04: the other languages.
I18N03_MATCHES=""
if [ -d "src/java" ]; then
    I18N03_MATCHES=$(SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'PY'
import glob, os, sys
sys.path.insert(0, os.environ["SCRIPT_DIR"])
from bundles import keys
for base in glob.glob("src/java/**/*_messages.properties", recursive=True):
    stem = base[:-len(".properties")]
    variants = [base] + sorted(glob.glob(stem + "_*.properties"))
    if len(variants) < 2:
        continue
    fr = stem + "_fr.properties"
    if os.path.isfile(fr):
        dk, fk = keys(base), keys(fr)
        for k in sorted(fk - dk):
            print("%s: %s missing (present in %s)" % (base, k, os.path.basename(fr)))
        for k in sorted(dk - fk):
            print("%s: %s missing (present in %s)" % (fr, k, os.path.basename(base)))
PY
) || I18N03_MATCHES=""
    I18N03_OTHERS=$(SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'PY'
import glob, os, sys
sys.path.insert(0, os.environ["SCRIPT_DIR"])
from bundles import keys
for base in glob.glob("src/java/**/*_messages.properties", recursive=True):
    stem = base[:-len(".properties")]
    ref = keys(base)
    for v in sorted(glob.glob(stem + "_*.properties")):
        if v.endswith("_fr.properties"):
            continue
        missing = len(ref - keys(v))
        if missing:
            print("%s: %d key(s) of the default bundle not translated" % (v, missing))
PY
) || I18N03_OTHERS=""
fi
COUNT=0; [ -n "$I18N03_MATCHES" ] && COUNT=$(echo "$I18N03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N03" "PASS" "Every bundle key exists in every language of the bundle" 0
else emit "I18N03" "FAIL" "i18n key in the default bundle and not in _fr, or the reverse: that language shows the fallback text" "$COUNT" "$I18N03_MATCHES"; fi
COUNT=0; [ -n "${I18N03_OTHERS:-}" ] && COUNT=$(echo "$I18N03_OTHERS" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N04" "PASS" "The other languages of the bundles carry every key" 0
else emit "I18N04" "WARN" "Other languages (beyond the default bundle and _fr, the two the core ships) lack keys: they show the default text" "$COUNT" "$I18N03_OTHERS"; fi

# I18N09: a translation key the default bundle does not declare (a translated key name, a key renamed or removed since):
# nothing asks for it, it never shows. fix-i18n-bundles.py removes them.
I18N09_MATCHES=""
if [ -d "src/java" ]; then
    I18N09_MATCHES=$(SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'PY'
import glob, os, sys
sys.path.insert(0, os.environ["SCRIPT_DIR"])
from bundles import entries, keys
for base in sorted(glob.glob("src/java/**/*_messages.properties", recursive=True)):
    ref = keys(base)
    for v in sorted(glob.glob(base[:-len(".properties")] + "_*.properties")):
        for n, k, _ in entries(v):
            if k not in ref:
                print("%s:%d: %s" % (v, n, k[:80]))
PY
) || I18N09_MATCHES=""
fi
COUNT=0; [ -n "$I18N09_MATCHES" ] && COUNT=$(echo "$I18N09_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N09" "PASS" "Every translation key exists in the default bundle" 0
else emit "I18N09" "WARN" "Translation key the default bundle does not declare: it never shows (fix-i18n-bundles.py)" "$COUNT" "$I18N09_MATCHES"; fi
echo ""

# I18N10: a key declared twice in the same bundle. java.util.Properties keeps the last value: the first one is dead,
# and whoever edits it sees no change. fix-i18n-bundles.py keeps the last occurrence, which is what already shows.
I18N10_MATCHES=""
if [ -d "src/java" ]; then
    I18N10_MATCHES=$(SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'PY'
import glob, os, sys
sys.path.insert(0, os.environ["SCRIPT_DIR"])
from bundles import entries
for path in sorted(glob.glob("src/java/**/*_messages*.properties", recursive=True)):
    seen = {}
    for n, k, _ in entries(path):
        if k in seen:
            print("%s:%d: %s (also line %d, the last one wins)" % (path, seen[k], k[:80], n))
        seen[k] = n
PY
) || I18N10_MATCHES=""
fi
COUNT=0; [ -n "$I18N10_MATCHES" ] && COUNT=$(echo "$I18N10_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N10" "PASS" "No key declared twice in a bundle" 0
else emit "I18N10" "WARN" "Key declared twice in a bundle: the first value never shows (fix-i18n-bundles.py)" "$COUNT" "$I18N10_MATCHES"; fi
echo ""

# I18N05: a bundle suffixed with a country code where Java expects a language code (_cz for Czech is _cs, _dk is _da,
# _se is _sv…): ResourceBundle never loads it, the file is dead and its language falls back.
I18N05_MATCHES=""
if [ -d "src/java" ]; then
    I18N05_MATCHES=$(find src/java -name "*_messages_*.properties" 2>/dev/null | while read -r f; do
        lang=$(basename "$f" .properties | sed -E 's/.*_messages_([A-Za-z]+).*/\1/')
        case "$lang" in
            cz) echo "$f: _cz is a country, Czech is _cs";; dk) echo "$f: _dk is a country, Danish is _da";;
            se) echo "$f: _se is a country, Swedish is _sv";; gr) echo "$f: _gr is a country, Greek is _el";;
            jp) echo "$f: _jp is a country, Japanese is _ja";; cn) echo "$f: _cn is a country, Chinese is _zh";;
            ua) echo "$f: _ua is a country, Ukrainian is _uk";; kr) echo "$f: _kr is a country, Korean is _ko";;
            ee) echo "$f: _ee is a country, Estonian is _et";; si) echo "$f: _si is a country, Slovenian is _sl";;
            rs) echo "$f: _rs is a country, Serbian is _sr";; al) echo "$f: _al is a country, Albanian is _sq";;
        esac
    done) || I18N05_MATCHES=""
fi
COUNT=0; [ -n "$I18N05_MATCHES" ] && COUNT=$(echo "$I18N05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N05" "PASS" "Bundle suffixes are language codes" 0
else emit "I18N05" "FAIL" "Bundle suffixed with a country code: Java never loads it (fix-i18n-bundles.py)" "$COUNT" "$I18N05_MATCHES"; fi
echo ""

# I18N06: a bundle line with no = or : separator (key>value, a pasted sentence): Java reads the whole line as a key with
# an empty value, so the intended key answers nothing. Continuation lines (after a trailing backslash) are skipped.
I18N06_MATCHES=""
if [ -d "src/java" ]; then
    I18N06_MATCHES=$(python3 - <<'PY'
import glob, re
for f in sorted(glob.glob("src/java/**/*_messages*.properties", recursive=True)):
    cont = False
    for n, line in enumerate(open(f, encoding="latin-1"), 1):
        raw = line.rstrip("\r\n")
        s = raw.strip()
        if cont:
            cont = raw.endswith("\\")
            continue
        cont = raw.endswith("\\")
        if not s or s[0] in "#!":
            continue
        if not re.search(r"(?<!\\)[=:]", s) and not re.match(r"^\S+\s+\S", s):
            print("%s:%d: no separator: %s" % (f, n, s[:80]))
        elif re.match(r"^[^=:\s]*>[^=:]*$", s):
            print("%s:%d: '>' used as a separator: %s" % (f, n, s[:80]))
PY
) || I18N06_MATCHES=""
fi
COUNT=0; [ -n "$I18N06_MATCHES" ] && COUNT=$(echo "$I18N06_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N06" "PASS" "Every bundle line is key=value" 0
else emit "I18N06" "FAIL" "Bundle line without = or : separator: Java reads it as a key with an empty value (fix-i18n-bundles.py)" "$COUNT" "$I18N06_MATCHES"; fi

# I18N07: French value with a common spelling error (Etes vous, sur de vouloir) or a Java class name left from a
# generator (supprimer ce PollFormQuestion): the user reads it as is.
I18N07_MATCHES=""
if [ -d "src/java" ]; then
    I18N07_MATCHES=$(SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'PY'
import glob, os, re, sys
sys.path.insert(0, os.environ["SCRIPT_DIR"])
from bundles import entries
BAD = re.compile(r"\b[EÉ]tes[ -]vous\b(?<!Êtes-vous)|\bsur de vouloir\b|\b(ce|cette|le|la|un|une)\s+[A-Z][a-z]+[A-Z]\w*")
for f in sorted(glob.glob("src/java/**/*_messages_fr.properties", recursive=True)):
    for n, key, value in entries(f):
        value = re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), value)
        if BAD.search(value):
            print("%s:%d: %s=%s" % (f, n, key, value[:100]))
PY
) || I18N07_MATCHES=""
fi
COUNT=0; [ -n "$I18N07_MATCHES" ] && COUNT=$(echo "$I18N07_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N07" "PASS" "No common spelling error in French values" 0
else emit "I18N07" "WARN" "French value with a spelling error (Êtes-vous, sûr) or a leftover class name" "$COUNT" "$I18N07_MATCHES"; fi

# I18N08: a key of the default bundle nothing uses (generator leftovers the translators keep paying for).
# i18n_unused.py has the exact rules: runtime-read families, stems built in Java or templates, other repositories.
I18N08_MATCHES=""
[ -d "src/java" ] && { I18N08_MATCHES=$(python3 "$SCRIPT_DIR/i18n_unused.py" . 2>/dev/null) || true; }
COUNT=0; [ -n "$I18N08_MATCHES" ] && COUNT=$(echo "$I18N08_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N08" "PASS" "Every bundle key is used" 0
else emit "I18N08" "WARN" "Bundle key no file names: remove it in every language, unless built at runtime" "$COUNT" "$I18N08_MATCHES"; fi
echo ""

# WB06: an <admin-feature> whose <feature-group> is not the group its install SQL gives it. Reinstalling the plugin from
# the Plugins screen rebuilds its rights from the descriptor (Plugin.install -> registerRights), so the feature moves
# (tagcloud: CONTENT -> NULL, then shown in the last menu group). A NULL group in both is consistent (plugin-forms).
WB06_MATCHES=""
if [ -d "webapp/WEB-INF/plugins" ]; then
    WB06_MATCHES=$(python3 - <<'PY'
import glob, re
sql = " ".join(open(f, encoding="utf-8", errors="replace").read() for f in glob.glob("src/sql/**/*.sql", recursive=True) if "/upgrade/" not in f)
def sql_group(fid):
    for ins in re.finditer(r"INSERT INTO core_admin_right\s*\(([^)]*)\)\s*VALUES\s*\((.*?)\)\s*;", sql, re.S | re.I):
        vals = [v.strip().strip("'") for v in re.split(r",(?=(?:[^']*'[^']*')*[^']*$)", ins.group(2))]
        cols = [c.strip().lower() for c in ins.group(1).split(",")]
        if vals and vals[0] == fid and "id_feature_group" in cols and len(vals) == len(cols):
            g = vals[cols.index("id_feature_group")]
            return None if g.upper() == "NULL" else g
    return None
for f in sorted(glob.glob("webapp/WEB-INF/plugins/*.xml")):
    text = open(f, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"<admin-feature>(.*?)</admin-feature>", text, re.S):
        fid = re.search(r"<feature-id>\s*([^<\s]+)", m.group(1))
        fid = fid.group(1) if fid else "?"
        xml = re.search(r"<feature-group>\s*([^<\s]+)", m.group(1))
        want = sql_group(fid)
        if want and (not xml or xml.group(1) != want):
            print("%s: admin-feature %s: the install SQL puts it in %s, the descriptor says %s: a reinstall rebuilds it from the descriptor" % (f, fid, want, xml.group(1) if xml else "nothing"))
PY
) || WB06_MATCHES=""
fi
WB07_MATCHES=""
if [ -d "webapp/WEB-INF/plugins" ]; then
    WB07_MATCHES=$(python3 - <<'PY'
import glob, re
for f in sorted(glob.glob("webapp/WEB-INF/plugins/*.xml")):
    text = open(f, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"<admin-feature>(.*?)</admin-feature>", text, re.S):
        if "<feature-icon-url>" in m.group(1) and "<icon-url>" not in m.group(1):
            fid = re.search(r"<feature-id>\s*([^<\s]+)", m.group(1))
            print("%s: admin-feature %s carries its icon in <feature-icon-url>, which the core digester ignores (it reads <icon-url>): a reinstall resets icon_url to NULL" % (f, fid.group(1) if fid else "?"))
PY
) || WB07_MATCHES=""
fi
COUNT=0; [ -n "$WB06_MATCHES" ] && COUNT=$(echo "$WB06_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB06" "PASS" "Every admin feature declares its menu group" 0
else emit "WB06" "FAIL" "admin-feature whose descriptor group differs from its install SQL: a reinstall moves it" "$COUNT" "$WB06_MATCHES"; fi
COUNT=0; [ -n "$WB07_MATCHES" ] && COUNT=$(echo "$WB07_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB07" "PASS" "Admin feature icons survive a reinstall" 0
else emit "WB07" "WARN" "Icon in <feature-icon-url>: the core digester reads <icon-url> (core inconsistency with the DTD, reported upstream)" "$COUNT" "$WB07_MATCHES"; fi
echo ""

# ST07: a production class whose name matches the surefire test patterns (Test*, *Test, *Tests, *TestCase).
# `lutece:exploded … test` puts it in WEB-INF/classes, surefire collects it as a test and the fork fails
# ("wrong name", "There was an error in the forked process").
ST07_MATCHES=""
if [ -d "src/java" ]; then
    ST07_MATCHES=$(find src/java -name "*.java" 2>/dev/null | grep -E "/(Test[^/]*|[^/]*Test|[^/]*Tests|[^/]*TestCase)\.java$") || ST07_MATCHES=""
fi
COUNT=0; [ -n "$ST07_MATCHES" ] && COUNT=$(echo "$ST07_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "ST07" "PASS" "No production class named like a test" 0
else emit "ST07" "FAIL" "Production class named like a test: surefire collects it from WEB-INF/classes and the test run breaks" "$COUNT" "$ST07_MATCHES"; fi
echo ""

# PV01: the pom and the plugin descriptor disagree on the version: the plugin screen, the upgrade scripts (Liquibase
# compares the installed version with the scripts' target) and the release read different ones.
# PV02: the v8 version is not above the last released tag: a site already on that release is "up to date", so the new
# upgrade scripts are silently NOT included (workflow-rest: 2.0.0-SNAPSHOT after a 2.1.x release).
PV_MATCHES=$(python3 - <<'PY'
import glob, re, subprocess
def version(v):
    return tuple(int(x) for x in re.findall(r"\d+", v.split("-")[0])[:3])
pom = open("pom.xml", encoding="utf-8").read() if __import__("os").path.isfile("pom.xml") else ""
own = re.sub(r"<parent>.*?</parent>", "", pom, flags=re.S)
m = re.search(r"<version>([^<]+)</version>", own)
if not m:
    raise SystemExit
pv = m.group(1).strip()
for x in glob.glob("webapp/WEB-INF/plugins/*.xml"):
    xv = re.search(r"<version>([^<]+)</version>", open(x, encoding="utf-8", errors="replace").read())
    if xv and "${" not in xv.group(1) and xv.group(1).strip() != pv:
        print("PV01 %s: <version>%s</version>, the pom says %s" % (x, xv.group(1).strip(), pv))
try:
    tags = subprocess.run(["git", "tag"], capture_output=True, text=True).stdout.split()
except OSError:
    tags = []
released = [(version(t.rsplit("-", 1)[-1] if re.search(r"-\d+\.\d+", t) else t), t) for t in tags if re.search(r"\d+\.\d+", t)]
released = [(v, t) for v, t in released if v]
if released:
    last = max(released)
    if version(pv) <= last[0]:
        print("PV02 pom.xml: version %s is not above the last release %s: a site on that release never runs the new upgrade scripts" % (pv, last[1]))
PY
) || PV_MATCHES=""
PV01_MATCHES=$(echo "$PV_MATCHES" | grep "^PV01" | sed 's/^PV01 //'); PV02_MATCHES=$(echo "$PV_MATCHES" | grep "^PV02" | sed 's/^PV02 //')
COUNT=0; [ -n "$PV01_MATCHES" ] && COUNT=$(echo "$PV01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "PV01" "PASS" "pom and plugin descriptor carry the same version" 0
else emit "PV01" "FAIL" "pom and plugin descriptor versions differ" "$COUNT" "$PV01_MATCHES"; fi
COUNT=0; [ -n "$PV02_MATCHES" ] && COUNT=$(echo "$PV02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "PV02" "PASS" "The version is above the last release" 0
else emit "PV02" "FAIL" "Version not above the last release: the upgrade scripts are skipped on upgraded sites" "$COUNT" "$PV02_MATCHES"; fi
echo ""

echo "CATEGORY: JSP"
check_grep "JS01" 'jsp:useBean' "webapp/" "FAIL" "jsp:useBean -> CDI-managed beans"

JS02_MATCHES=""
if [ -d "webapp/" ]; then
    JS02_MATCHES=$(grep -rn '<%[^@-]' webapp/ --include="*.jsp" 2>/dev/null) || JS02_MATCHES=""
fi
COUNT=0; [ -n "$JS02_MATCHES" ] && COUNT=$(echo "$JS02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JS02" "PASS" "No JSP scriptlets" 0
else emit "JS02" "FAIL" "Old JSP scriptlets -> EL expressions; a JSP writing its own <head> gets the base href from AdminHeader.jsp, not from a scriptlet" "$COUNT" "$JS02_MATCHES"; fi

# JS03: an EL call written with the class name resolves only static methods (StaticFieldELResolver), so an
# instance method fails at runtime with MethodNotFoundException while everything compiled. A JspBean called
# from a JSP is @Named and called by its bean name, the decapitalized class name.
JS03_MATCHES=""
if [ -d "webapp/" ]; then
    JS03_MATCHES=$(grep -rnE '\$\{[^}]*\b[A-Z][A-Za-z0-9_]*(JspBean|Bean)\.[a-z][A-Za-z0-9_]*\(' webapp/ --include="*.jsp" 2>/dev/null) || JS03_MATCHES=""
fi
COUNT=0; [ -n "$JS03_MATCHES" ] && COUNT=$(echo "$JS03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JS03" "PASS" "EL calls a bean by its CDI name" 0
else emit "JS03" "FAIL" "EL call by class name resolves only static methods (use the bean name)" "$COUNT" "$JS03_MATCHES"; fi

# JS05: an admin JSP writing its own HTML. A v8 admin JSP is an entry point (errorPage, header, processController,
# footer); the screen is a template the bean renders, where the macros, the i18n, the token and the scanner apply.
# Markup written in a JSP escapes all of them (labels pointing at missing ids, v5 classes, no token).
JS05_MATCHES=""
if [ -d "webapp/jsp/admin" ]; then
    JS05_MATCHES=$(grep -rnE "<(form|table|div|input|select|textarea|html|body|button|label|ul|p|h[1-6])[ >]" webapp/jsp/admin --include="*.jsp" 2>/dev/null | awk -F: '!seen[$1]++ {print $1": writes its own HTML (line "$2"): move the markup to a template rendered by a @View"}') || JS05_MATCHES=""
fi
COUNT=0; [ -n "$JS05_MATCHES" ] && COUNT=$(echo "$JS05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JS05" "PASS" "Admin JSPs are entry points, the markup lives in templates" 0
else emit "JS05" "FAIL" "Admin JSP writing its own HTML: move it to a template rendered by the bean" "$COUNT" "$JS05_MATCHES"; fi

# JS06: a JSP that streams a file (download, export) and leaves template text. The bean writes the bytes through
# getOutputStream(); at the end of the page the JSP flushes its own text through getWriter() and the container throws
# "OutputStream already obtained" on every download. Only directives, JSP comments and the EL call may remain: a
# newline between them is template text too, and trimDirectiveWhitespaces="true" does not remove it on Liberty
# (observed on the blobstore bench: 47 exceptions with the newline, 0 once it sat inside a JSP comment).
JS06_MATCHES=""
if [ -d "webapp/jsp" ]; then
    JS06_MATCHES=$(python3 - <<'PY'
import glob, re
for f in sorted(glob.glob("webapp/jsp/**/*.jsp", recursive=True)):
    text = open(f, encoding="utf-8", errors="replace").read()
    if not re.search(r"\.\s*(do)?(download|export|getFile|getBlob)\w*\s*\(", text, re.I):
        continue
    rest = re.sub(r"<%--.*?--%>|<%@.*?%>|\$\{.*?\}", "", text, flags=re.S)
    if rest.strip():
        print("%s: streams a file and leaves template text (%r)" % (f, rest.strip()[:40]))
    elif rest:
        print("%s: streams a file and leaves %d whitespace character(s) outside its directives: glue them (<%%@ … %%><%%-- newline --%%>${ … }, no final newline); trimDirectiveWhitespaces does not remove them on Liberty" % (f, len(rest)))
PY
) || JS06_MATCHES=""
fi
COUNT=0; [ -n "$JS06_MATCHES" ] && COUNT=$(echo "$JS06_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JS06" "PASS" "Download JSPs write nothing after the stream" 0
else emit "JS06" "FAIL" "Download JSP leaving template text: 'OutputStream already obtained' on every download" "$COUNT" "$JS06_MATCHES"; fi

# JS04: an admin JSP driving a bean that is not a @Controller. v8 dispatches views and actions through
# processController() on one JSP per controller, and the automatic CSRF filter only covers those actions: a legacy
# DoXxx.jsp calling bean.doXxx( request ) accepts a forged call unless the bean validates a token itself. Portlet
# JspBeans are the one legacy path the platform keeps (CS01 covers their token).
JS04_MATCHES=""
if [ -d "webapp/jsp/admin" ] && [ -d "src/java" ]; then
    JS04_MATCHES=$(grep -rlE '\$\{ *[a-z][A-Za-z0-9_]*JspBean\.' webapp/jsp/admin --include="*.jsp" 2>/dev/null | while read -r jsp; do
        grep -q 'processController' "$jsp" && continue
        bean=$(grep -oE '\$\{ *[a-z][A-Za-z0-9_]*JspBean\.' "$jsp" | head -1 | sed -E 's/\$\{ *//; s/\.$//')
        cls=$(printf '%s' "$bean" | sed -E 's/^(.)/\U\1/')
        src=$(grep -rlE "class $cls\b" src/java --include="*.java" 2>/dev/null | head -1)
        [ -n "$src" ] || continue
        legacy=1
        for _ in 1 2 3 4 5; do
            grep -qE 'extends +PortletJspBean\b|@Controller' "$src" && { legacy=0; break; }
            parent=$(grep -oE 'class +[A-Za-z0-9_]+(<[^>]*>)? +extends +[A-Za-z0-9_]+' "$src" | head -1 | sed -E 's/.* extends +//')
            [ -n "$parent" ] || break
            src=$(grep -rlE "class +$parent\b" src/java --include="*.java" 2>/dev/null | head -1)
            [ -n "$src" ] || break
        done
        [ "$legacy" = 0 ] && continue
        echo "$jsp: calls $bean, a JspBean without @Controller: port it to MVCAdminJspBean, one JSP with processController"
    done) || JS04_MATCHES=""
fi
COUNT=0; [ -n "$JS04_MATCHES" ] && COUNT=$(echo "$JS04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JS04" "PASS" "Admin JSPs dispatch through a @Controller" 0
else emit "JS04" "FAIL" "Legacy admin JSP on a non-MVC bean: no v8 dispatch, no automatic CSRF (rules/jsp-admin.md)" "$COUNT" "$JS04_MATCHES"; fi
echo ""

# JS07: a static script of the plugin that does not parse. The browser drops the whole file on the first syntax error
# (an extra brace, a truncated line), so every function it declares is missing on the page and nothing fails in the
# build. Checked with node --check when node is installed; FreeMarker templates under WEB-INF and minified vendor files
# are left out.
JS07_MATCHES=""
if [ -d "webapp" ] && command -v node >/dev/null 2>&1; then
    JS07_MATCHES=$(find webapp -path webapp/WEB-INF -prune -o -name "*.js" ! -name "*.min.js" ! -path "*/lib/*" ! -path "*/vendor/*" -print 2>/dev/null | while read -r js; do
        out=$(node --check "$js" 2>&1) || echo "$js: $(printf '%s\n' "$out" | grep -m1 -E 'SyntaxError')"
    done) || JS07_MATCHES=""
fi
COUNT=0; [ -n "$JS07_MATCHES" ] && COUNT=$(echo "$JS07_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JS07" "PASS" "Static scripts parse" 0
else emit "JS07" "FAIL" "Script that does not parse: the browser drops the whole file" "$COUNT" "$JS07_MATCHES"; fi
echo ""

# ─── Templates ───────────────────────────────────────────
echo "CATEGORY: Templates"
check_grep "TM01" 'class="panel' "webapp/WEB-INF/templates/admin/" "FAIL" "Old Bootstrap panels -> v8 macros"
# VL01: a copy of jQuery or of a jQuery-era upload widget shipped under webapp/: nothing updates it (jQuery before 3.5
# carries known XSS flaws) and v8 has the component the widget stood for (plugin-asynchronousupload).
VL01_MATCHES=""
if [ -d "webapp/" ]; then
    VL01_MATCHES=$(find webapp -path webapp/WEB-INF -prune -o \( -iname 'jquery.js' -o -iname 'jquery.min.js' -o -iname 'jquery-[0-9]*.js' -o -iname '*jquery*file*upload*' -o -iname '*swfupload*' -o -iname '*plupload*' -o -iname '*uploadify*' \) -print 2>/dev/null | grep -v '^webapp/WEB-INF$'; grep -rlE '(\$|jQuery)\.fn\.([A-Za-z_$][A-Za-z0-9_$]* *=|extend\()' webapp --include='*.js' 2>/dev/null | grep -v '^webapp/WEB-INF/' | grep -viE 'jquery[-.]?[0-9]|jquery(\.min)?\.js$|file[-.]?upload|swfupload|plupload|uploadify') || VL01_MATCHES=""
fi
COUNT=0; [ -n "$VL01_MATCHES" ] && COUNT=$(echo "$VL01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "VL01" "PASS" "No vendored jQuery or upload widget" 0
else emit "VL01" "FAIL" "Vendored jQuery or jQuery-era upload widget: port to vanilla JS / plugin-asynchronousupload, delete the copy" "$COUNT" "$VL01_MATCHES"; fi

# TM10 / TM11 / TM12: house rules on templates, read with FreeMarker and HTML comments blanked.
# TM10: no offcanvas. Content written in the page -> @modal / @cModal; content loaded from another page -> a plain link.
# TM11: every front-office form is a @cForm, which loads the core's form validation (theme-form-validation); a raw
#       <form>, a back-office @tform in a skin template, or foValidation=false leaves the form without it.
# TM12: no inline form laying three visible fields or more side by side (template_rules.py has the exact rules).
template_rules() {
    python3 "$(dirname "${BASH_SOURCE[0]}")/template_rules.py" "$1" . || true
}
TM10_MATCHES=$(template_rules offcanvas 2>/dev/null) || TM10_MATCHES=""
COUNT=0; [ -n "$TM10_MATCHES" ] && COUNT=$(echo "$TM10_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM10" "PASS" "No offcanvas" 0
else emit "TM10" "FAIL" "Offcanvas: content of the page -> @modal / @cModal, another page -> a plain link to it" "$COUNT" "$TM10_MATCHES"; fi
TM11_MATCHES=$(template_rules fo-forms 2>/dev/null) || TM11_MATCHES=""
COUNT=0; [ -n "$TM11_MATCHES" ] && COUNT=$(echo "$TM11_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM11" "PASS" "Front-office forms are @cForm with the core form validation" 0
else emit "TM11" "FAIL" "Front-office form without the core form validation: use @cForm, never foValidation=false" "$COUNT" "$TM11_MATCHES"; fi
TM12_MATCHES=$(template_rules inline-forms 2>/dev/null) || TM12_MATCHES=""
COUNT=0; [ -n "$TM12_MATCHES" ] && COUNT=$(echo "$TM12_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM12" "PASS" "No inline form" 0
else emit "TM12" "FAIL" "Inline form (fields side by side): one field per row, the standard form layout" "$COUNT" "$TM12_MATCHES"; fi

# TM13: a back-office form field named `page`: SecurityTokenHandler reads the page parameter and takes its XPage branch,
# so every post of that form skips the CSRF check. Name it id_page.
TM13_MATCHES=""
if [ -d "webapp/WEB-INF/templates/admin" ]; then
    TM13_MATCHES=$(grep -rnE "name *= *['\"]page['\"]" webapp/WEB-INF/templates/admin --include="*.html" 2>/dev/null) || TM13_MATCHES=""
fi
COUNT=0; [ -n "$TM13_MATCHES" ] && COUNT=$(echo "$TM13_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM13" "PASS" "No back-office field named page" 0
else emit "TM13" "FAIL" "Back-office field named page: the CSRF check is skipped on every post of that form (use id_page)" "$COUNT" "$TM13_MATCHES"; fi

# TM02: no theme loads jQuery unless the pom declares library-theme-jquery: without it the calls fail at runtime.
if grep -q 'library-theme-jquery' pom.xml 2>/dev/null; then TM02_SEV=WARN; else TM02_SEV=FAIL; fi
# The plugin's own scripts count too (webapp/js, webapp/themes), not only templates; a vendored library is VL01's.
TM02_MATCHES=$( { grep -rn 'jQuery\|\$(' webapp/WEB-INF/templates/ --include="*.html" --include="*.ftl" --include="*.js" 2>/dev/null;
    find webapp -path webapp/WEB-INF -prune -o -name "*.js" ! -name "*.min.js" ! -path "*/lib/*" ! -path "*/vendor/*" -print 2>/dev/null \
        | grep -viE 'jquery|fileupload|swfupload|plupload|uploadify|swagger-ui|bundle' | xargs -r grep -Hn 'jQuery(\|\$(' 2>/dev/null; } | head -200) || TM02_MATCHES=""
COUNT=0; [ -n "$TM02_MATCHES" ] && COUNT=$(echo "$TM02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM02" "PASS" "No jQuery in the templates and scripts of the plugin" 0
else emit "TM02" "$TM02_SEV" "jQuery -> vanilla JS (no library-theme-jquery: nothing loads it); an upload widget -> plugin-asynchronousupload" "$COUNT" "$TM02_MATCHES"; fi

# TM03: a back-office template calling the front-office upload macros (addFileInput, addUploadedFilesBox): the admin
# side of plugin-asynchronousupload names them addFileBOInput, addBOUploadedFilesBox. Skin templates keep the FO names.
TM03_MATCHES=""
if [ -d "webapp/WEB-INF/templates/admin" ]; then
    TM03_MATCHES=$(grep -rn '<@addFileInput \|<@addUploadedFilesBox\|<@addFileInputAndfilesBox' webapp/WEB-INF/templates/admin/ --include="*.html" 2>/dev/null \
        | grep -v 'addFileBOInput\|addBOUploadedFilesBox\|addFileBOInputAndfilesBox') || TM03_MATCHES=""
fi
COUNT=0; [ -n "$TM03_MATCHES" ] && COUNT=$(echo "$TM03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM03" "PASS" "Upload macros use BO variants" 0
else emit "TM03" "FAIL" "Old upload macros -> BO variants" "$COUNT" "$TM03_MATCHES"; fi

# TM04: Unsafe access to errors/infos/warnings
TM04_MATCHES=""
if [ -d "webapp/WEB-INF/templates/" ]; then
    TM04_MATCHES=$(grep -rn 'errors?size\|errors?has_content\|infos?size\|infos?has_content\|warnings?size\|warnings?has_content' webapp/WEB-INF/templates/ --include="*.html" 2>/dev/null \
        | grep -v '(errors!)\|(infos!)\|(warnings!)' | grep -vE '(errors|infos|warnings)\?\?[[:space:]]*&&[[:space:]]*\1\?') || TM04_MATCHES=""
fi
COUNT=0; [ -n "$TM04_MATCHES" ] && COUNT=$(echo "$TM04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM04" "PASS" "Null-safe errors/infos/warnings access" 0
else emit "TM04" "FAIL" "Unsafe errors/infos/warnings -> use (var!)?size" "$COUNT" "$TM04_MATCHES"; fi

# TM05: Old SuggestPOI
TM05_MATCHES=""
if [ -d "webapp/" ]; then
    TM05_MATCHES=$(grep -rn 'autocomplete-js\.jsp\|createAutocomplete\|\.autocomplete(' webapp/ --include="*.html" --include="*.jsp" 2>/dev/null) || TM05_MATCHES=""
fi
COUNT=0; [ -n "$TM05_MATCHES" ] && COUNT=$(echo "$TM05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM05" "PASS" "No old SuggestPOI autocomplete" 0
else emit "TM05" "FAIL" "Old jQuery SuggestPOI -> LuteceAutoComplete" "$COUNT" "$TM05_MATCHES"; fi

# TM06: @addRequiredJsFiles in admin templates
TM06_MATCHES=""
if [ -d "webapp/WEB-INF/templates/admin/" ]; then
    TM06_MATCHES=$(grep -rn '<@addRequiredJsFiles' webapp/WEB-INF/templates/admin/ --include="*.html" 2>/dev/null \
        | grep -v 'addRequiredBOJsFiles') || TM06_MATCHES=""
fi
COUNT=0; [ -n "$TM06_MATCHES" ] && COUNT=$(echo "$TM06_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM06" "PASS" "Admin templates use @addRequiredBOJsFiles" 0
else emit "TM06" "FAIL" "@addRequiredJsFiles -> @addRequiredBOJsFiles" "$COUNT" "$TM06_MATCHES"; fi
# TM07: MVCMessage ${error} without .message
TM07_MATCHES=""
if [ -d "webapp/WEB-INF/templates/" ]; then
    TM07_MATCHES=$(grep -rn '${error}' webapp/WEB-INF/templates/ --include="*.html" 2>/dev/null | grep -v '${error\.' | grep -v '${error!}') || TM07_MATCHES=""
fi
COUNT=0; [ -n "$TM07_MATCHES" ] && COUNT=$(echo "$TM07_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM07" "PASS" "MVCMessage \${error} uses .message" 0
else emit "TM07" "FAIL" "\${error} without .message (MVCMessage)" "$COUNT" "$TM07_MATCHES"; fi

# TM08: design rules a template already written with macros can still break (scan-template-design.py header lists
# the codes). A check that could not run is never a PASS: the scan exits 2 when the project will not assemble, and
# an empty output would otherwise read as "nothing found".
if [ ! -d "webapp/WEB-INF/templates/" ]; then
    emit "TM08" "PASS" "Template design rules (no templates in this project)" 0
elif ! command -v python3 >/dev/null; then
    emit "TM08" "WARN" "Template design rules NOT EVALUATED: no python3 on PATH" 0
else
    TM08_MATCHES=$(python3 "$SCRIPT_DIR/scan-template-design.py" . --flat --warn-only 2>/dev/null)
    TM08_RC=$?
    if [ "$TM08_RC" -ne 0 ]; then
        emit "TM08" "FAIL" "Template design rules NOT EVALUATED although the project assembled: run scan-template-design.py by hand to see why" 0
    else
        COUNT=0; [ -n "$TM08_MATCHES" ] && COUNT=$(echo "$TM08_MATCHES" | wc -l)
        if [ "$COUNT" -eq 0 ]; then emit "TM08" "PASS" "Template design rules (manageFeature, empty state, switch, raw HTML, macro params, FO macros)" 0
        else emit "TM08" "WARN" "Template design rules broken -> design pass of the Template Migrator (scan-template-design.py)" "$COUNT" "$TM08_MATCHES"; fi
    fi
fi

# TM09: a template FreeMarker cannot parse answers 500 on every request. The parse skips itself when no JDK or no
# freemarker jar is around, which must not read as a green either.
if [ ! -d "webapp/WEB-INF/templates/" ]; then
    emit "TM09" "PASS" "Every template parses with FreeMarker (no templates in this project)" 0
else
    TM09_OUT=$(bash "$SCRIPT_DIR/check-template-parse.sh" . 2>/dev/null)
    TM09_MATCHES=$(echo "$TM09_OUT" | grep '^PARSE_ERROR') || TM09_MATCHES=""
    if echo "$TM09_OUT" | grep -q "^FMPARSE skipped"; then
        echo "$TM09_OUT" | grep '^FMPARSE skipped' >&2
        echo "verify-migration stopped: the templates could not be parsed, so a green report would be a lie." >&2
        exit 2
    else
        COUNT=0; [ -n "$TM09_MATCHES" ] && COUNT=$(echo "$TM09_MATCHES" | wc -l)
        if [ "$COUNT" -eq 0 ]; then emit "TM09" "PASS" "Every template parses with FreeMarker" 0
        else emit "TM09" "FAIL" "Templates FreeMarker cannot parse" "$COUNT" "$TM09_MATCHES"; fi
    fi
fi
echo ""

# ─── Logging ─────────────────────────────────────────────
echo "CATEGORY: Logging"
check_grep "LG01" 'AppLogService\.\(info\|error\|debug\|warn\).*+ ' "src/" "FAIL" "String concat in logging -> parameterized {}"

# LG02: Unnecessary isDebugEnabled checks (harmless but noisy — WARN, not FAIL)
check_grep "LG02" 'isDebugEnabled\|isInfoEnabled' "src/" "WARN" "Unnecessary isDebugEnabled (log4j2 handles this)"
echo ""

# ─── Tests ───────────────────────────────────────────────
echo "CATEGORY: Tests (JUnit 4 -> 5)"
check_grep "TS01" 'import org\.junit\.Test\b' "src/" "FAIL" "JUnit 4 @Test -> jupiter.api.Test"
check_grep "TS02" 'import org\.junit\.Before\b\|import org\.junit\.After\b' "src/" "FAIL" "JUnit 4 @Before/@After -> @BeforeEach/@AfterEach"
check_grep "TS03" 'import org\.junit\.Assert' "src/" "FAIL" "JUnit 4 Assert -> Assertions"
check_grep "TS04" 'MokeHttpServletRequest' "src/" "FAIL" "MokeHttpServletRequest -> MockHttpServletRequest"
check_grep "TS05" 'import org\.junit\.BeforeClass\|import org\.junit\.AfterClass' "src/" "FAIL" "JUnit 4 @BeforeClass/@AfterClass"

# TS06: Test methods without @Test
TS06_MATCHES=""
if [ -d "src/test/" ]; then
    TS06_MATCHES=$(grep -rn 'public void test' src/test/ --include="*.java" 2>/dev/null | while read -r line; do
        FILE=$(echo "$line" | cut -d: -f1)
        LINENUM=$(echo "$line" | cut -d: -f2)
        PREV_LINE=$((LINENUM - 1))
        if ! sed -n "${PREV_LINE}p" "$FILE" 2>/dev/null | grep -q '@Test'; then
            echo "$line"
        fi
    done) || TS06_MATCHES=""
fi
COUNT=0; [ -n "$TS06_MATCHES" ] && COUNT=$(echo "$TS06_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TS06" "PASS" "All test methods have @Test" 0
else emit "TS06" "FAIL" "Test methods without @Test annotation" "$COUNT" "$TS06_MATCHES"; fi

check_grep "TS07" 'SpringContextService\.getBean' "src/test/" "FAIL" "SpringContextService.getBean in tests -> @Inject"
check_grep "TS08" 'org\.springframework\.mock\.web' "src/test/" "FAIL" "Spring mock imports -> fr.paris.lutece.test.mocks"

# TS09: the parent POM sets testFailureIgnore=true, so the test goal prints BUILD SUCCESS whatever the tests did.
# The reports are the only evidence. No report means the tests were never run, which is not a pass.
TS09_MATCHES=""
if [ ! -d "src/test/" ]; then
    if [ -n "$(find src/java src/main/java -name '*.java' 2>/dev/null | head -1)" ]; then
        emit "TS09" "WARN" "No unit test at all: nothing proves the Java of this project outside a bench (a library has no bench)" 1
    else
        emit "TS09" "PASS" "Test results (no Java, no tests)" 0
    fi
elif [ ! -d "target/surefire-reports" ]; then
    emit "TS09" "FAIL" "Test results NOT EVALUATED: no target/surefire-reports (an e2e run.sh build or a mvn clean wipes them: run the tests after the bench). Run mvn lutece:exploded antrun:run -Dlutece-test-hsql test (plain mvn test has no webapp config nor database: every CDI test fails to start); BUILD SUCCESS alone proves nothing, the parent POM sets testFailureIgnore=true" 1
else
    TS09_TALLY=$(grep -h "Tests run" target/surefire-reports/*.txt 2>/dev/null | awk -F'[:,]' '{t+=$2; f+=$4; e+=$6} END {printf "%d %d %d", t, f, e}')
    TS09_RUN=$(echo "$TS09_TALLY" | cut -d' ' -f1)
    TS09_BAD=$(( $(echo "$TS09_TALLY" | cut -d' ' -f2) + $(echo "$TS09_TALLY" | cut -d' ' -f3) ))
    TS09_MATCHES=$(grep -l "FAILURE\|ERROR" target/surefire-reports/*.txt 2>/dev/null | sed 's|target/surefire-reports/||;s|\.txt$||')
    if [ "${TS09_RUN:-0}" -eq 0 ]; then
        emit "TS09" "WARN" "Test results NOT EVALUATED: the reports record no test run" 0
    elif [ "$TS09_BAD" -eq 0 ]; then
        emit "TS09" "PASS" "Test results ($TS09_RUN tests, no failure, no error)" 0
    else
        emit "TS09" "FAIL" "Failing tests ($TS09_RUN run) -- BUILD SUCCESS is meaningless here, the parent POM sets testFailureIgnore=true" "$TS09_BAD" "$TS09_MATCHES"
    fi
fi
echo ""

# ─── Summary ─────────────────────────────────────────────
echo "=========================================="
echo "TOTAL: $TOTAL checks"
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  ${RED}FAIL${NC}: $FAIL"
echo -e "  ${YELLOW}WARN${NC}: $WARN"
echo "=========================================="

if $JSON_MODE; then
    JSON_CHECKS="$JSON_CHECKS]"
    mkdir -p .migration
    cat << ENDJSON > .migration/verify-latest.json
{
  "total": $TOTAL,
  "pass": $PASS,
  "fail": $FAIL,
  "warn": $WARN,
  "checks": $JSON_CHECKS
}
ENDJSON
    echo "JSON output written to .migration/verify-latest.json"
fi

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "RESULT: MIGRATION INCOMPLETE -- $FAIL check(s) failed"
    exit 1
else
    echo ""
    echo "RESULT: ALL CRITICAL CHECKS PASSED"
    [ "$WARN" -gt 0 ] && echo "  ($WARN warning(s) -- recommended to fix)"
    exit 0
fi
