#!/bin/bash
# verify-migration.sh — Run all migration verification checks (70+ checks)
# Usage: bash verify-migration.sh [project_root] [--json]
# Exit code: 0 if all PASS, 1 if any FAIL
# --json flag: output JSON instead of colored text (writes to .migration/verify-latest.json)

set -uo pipefail

PROJECT_ROOT="${1:-.}"
JSON_MODE=false
[ "${2:-}" = "--json" ] && JSON_MODE=true

cd "$PROJECT_ROOT"

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
check_pom "PM05" 'net\.sf\.json-lib' "WARN" "json-lib in pom.xml (use Jackson)"
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

# CA04: AbstractCacheableService without isCacheAvailable guard
CA04_MATCHES=""
if [ -d "src/" ]; then
    CA04_MATCHES=$(grep -rln 'extends AbstractCacheableService' src/ --include="*.java" 2>/dev/null | while read -r f; do
        if ! grep -q 'isCacheAvailable' "$f" 2>/dev/null; then
            echo "$f: extends AbstractCacheableService without isCacheAvailable guard"
        fi
    done) || CA04_MATCHES=""
fi
COUNT=0; [ -n "$CA04_MATCHES" ] && COUNT=$(echo "$CA04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then
    emit "CA04" "PASS" "CacheService missing isCacheAvailable guard" 0
else
    emit "CA04" "WARN" "CacheService missing isCacheAvailable guard" "$COUNT" "$CA04_MATCHES"
fi
echo ""

# ─── Deprecated API ──────────────────────────────────────
echo "CATEGORY: Deprecated API"
check_grep "DP01" 'AccessControlService\.getInstance\|AccessLogService\.getInstance\|AdminDashboardService\.getInstance\|AttributeFieldService\.getInstance\|AttributeService\.getInstance\|AttributeTypeService\.getInstance\|DashboardService\.getInstance\|EditorBbcodeService\.getInstance\|ExtendableResourceActionHit\.getInstance\|FileImagePublicService\.getInstance\|FileImageService\.getInstance\|FileService\.getInstance\|FilterService\.getInstance\|LuteceUserCacheService\.getInstance\|PortalMenuService\.getInstance\|PortletService\.getInstance\|ProgressManagerService\.getInstance\|QueryListenersService\.getInstance\|RegularExpressionService\.getInstance\|RSAKeyPairUtil\.getInstance\|SecurityTokenService\.getInstance\|ServletService\.getInstance\|WorkflowService\.getInstance' "src/" "FAIL" "Deprecated core getInstance() calls (23 @Deprecated(since=8.0) in lutece-core; SecurityService/AdminAuthenticationService are not deprecated)"
check_grep "DP02" 'FileImagePublicService\.init\|FileImageService\.init' "src/" "FAIL" "Deprecated init() calls (auto-registered in v8)"
check_grep "DP03" '\(^\|[^.A-Za-z0-9_]\)getModel( )' "src/" "FAIL" "MANDATORY: getModel() -> @Inject Models (excludes DTO getters like request.getModel())"
echo ""

# ─── DAO ─────────────────────────────────────────────────
echo "CATEGORY: DAO"
check_grep "DA01" 'daoUtil\.free( )' "src/" "WARN" "daoUtil.free() -> try-with-resources"
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
else emit "CD01" "WARN" "Static _instance/_singleton on CDI-managed classes" "$COUNT" "$CD01_MATCHES"; fi

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

check_grep "MV02" 'AbstractPaginatorJspBean' "src/" "WARN" "AbstractPaginatorJspBean -> @Pager IPager"
check_grep "MV03" 'SecurityTokenService\.MARK_TOKEN\|getSecurityTokenService( )\.\(getToken\|validate\)\|_securityTokenService\.\(getToken\|validate\)\|securityTokenEnabled\s*=\s*false' "src/" "WARN" "Manual CSRF token or securityTokenEnabled=false (policy: @Controller securityTokenEnabled = true, no MARK_TOKEN/getToken/validate; manual token only in non-MVC beans)"

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

check_file_exists "ST01" "src/main/resources/META-INF/beans.xml" "FAIL" "beans.xml exists"
echo ""

# ─── Structure ───────────────────────────────────────────
echo "CATEGORY: Structure"

# ST02: final on CDI-managed classes
ST02_MATCHES=""
if [ -d "src/" ]; then
    ST02_MATCHES=$(grep -rn 'public final class' src/ --include="*.java" 2>/dev/null | while read -r line; do
        FILE=$(echo "$line" | cut -d: -f1)
        if grep -q '@ApplicationScoped\|@RequestScoped\|@SessionScoped\|@Dependent' "$FILE" 2>/dev/null; then
            echo "$line"
        fi
    done) || ST02_MATCHES=""
fi
COUNT=0; [ -n "$ST02_MATCHES" ] && COUNT=$(echo "$ST02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "ST02" "PASS" "No final keyword on CDI-managed classes" 0
else emit "ST02" "WARN" "final keyword on CDI-managed classes" "$COUNT" "$ST02_MATCHES"; fi

# ST03: DAO classes without @ApplicationScoped
ST03_MATCHES=""
if [ -d "src/" ]; then
    ST03_MATCHES=$(grep -rln 'class.*DAO\b' src/ --include="*.java" 2>/dev/null | while read -r f; do
        grep -q 'public interface\|protected interface' "$f" 2>/dev/null && continue
        if ! grep -q '@ApplicationScoped\|@RequestScoped\|@SessionScoped\|@Dependent' "$f" 2>/dev/null; then
            echo "$f: DAO class without CDI scope annotation"
        fi
    done) || ST03_MATCHES=""
fi
COUNT=0; [ -n "$ST03_MATCHES" ] && COUNT=$(echo "$ST03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "ST03" "PASS" "DAO classes have CDI scope" 0
else emit "ST03" "WARN" "DAO classes without @ApplicationScoped" "$COUNT" "$ST03_MATCHES"; fi

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
else emit "ST04" "WARN" "Service classes without CDI scope" "$COUNT" "$ST04_MATCHES"; fi
echo ""

# ─── JSP ─────────────────────────────────────────────────
echo "CATEGORY: JSP"
check_grep "JS01" 'jsp:useBean' "webapp/" "FAIL" "jsp:useBean -> CDI-managed beans"

JS02_MATCHES=""
if [ -d "webapp/" ]; then
    JS02_MATCHES=$(grep -rn '<%[^@-]' webapp/ --include="*.jsp" 2>/dev/null) || JS02_MATCHES=""
fi
COUNT=0; [ -n "$JS02_MATCHES" ] && COUNT=$(echo "$JS02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JS02" "PASS" "No JSP scriptlets" 0
else emit "JS02" "WARN" "Old JSP scriptlets -> EL expressions" "$COUNT" "$JS02_MATCHES"; fi
echo ""

# ─── Templates ───────────────────────────────────────────
echo "CATEGORY: Templates"
check_grep "TM01" 'class="panel' "webapp/WEB-INF/templates/admin/" "WARN" "Old Bootstrap panels -> v8 macros"
check_grep "TM02" 'jQuery\|\$(' "webapp/WEB-INF/templates/" "WARN" "jQuery -> vanilla JS"

# TM03: Old upload macro names
TM03_MATCHES=""
if [ -d "webapp/WEB-INF/templates/" ]; then
    TM03_MATCHES=$(grep -rn '<@addFileInput \|<@addUploadedFilesBox\|<@addFileInputAndfilesBox' webapp/WEB-INF/templates/ --include="*.html" 2>/dev/null \
        | grep -v 'addFileBOInput\|addBOUploadedFilesBox\|addFileBOInputAndfilesBox') || TM03_MATCHES=""
fi
COUNT=0; [ -n "$TM03_MATCHES" ] && COUNT=$(echo "$TM03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM03" "PASS" "Upload macros use BO variants" 0
else emit "TM03" "WARN" "Old upload macros -> BO variants" "$COUNT" "$TM03_MATCHES"; fi

# TM04: Unsafe access to errors/infos/warnings
TM04_MATCHES=""
if [ -d "webapp/WEB-INF/templates/" ]; then
    TM04_MATCHES=$(grep -rn 'errors?size\|errors?has_content\|infos?size\|infos?has_content\|warnings?size\|warnings?has_content' webapp/WEB-INF/templates/ --include="*.html" 2>/dev/null \
        | grep -v '(errors!)\|(infos!)\|(warnings!)') || TM04_MATCHES=""
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
