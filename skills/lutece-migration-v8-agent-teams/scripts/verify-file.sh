#!/bin/bash
# verify-file.sh — Run migration checks on a single file
# Usage: bash verify-file.sh <file_path>
# Only runs checks relevant to the file type
# Output: JSON to stdout

set -uo pipefail

FILE="$1"

if [ ! -f "$FILE" ]; then
    echo "{\"error\": \"File not found: $FILE\"}"
    exit 1
fi

PASS=0
FAIL=0
WARN=0
DETAILS="["
FIRST=true

check() {
    local id="$1" pattern="$2" severity="$3" description="$4"
    local count
    count=$(grep -c "$pattern" "$FILE" 2>/dev/null) || count=0
    [ -z "$count" ] && count=0

    $FIRST || DETAILS="$DETAILS,"
    FIRST=false

    if [ "$count" -eq 0 ]; then
        DETAILS="$DETAILS{\"id\":\"$id\",\"status\":\"PASS\",\"description\":\"$description\"}"
        PASS=$((PASS + 1))
    else
        DETAILS="$DETAILS{\"id\":\"$id\",\"status\":\"$severity\",\"description\":\"$description\",\"count\":$count}"
        [ "$severity" = "FAIL" ] && FAIL=$((FAIL + 1))
        [ "$severity" = "WARN" ] && WARN=$((WARN + 1))
    fi
}

# ─── Determine file type and apply relevant checks ──────

if echo "$FILE" | grep -q '\.java$'; then
    # Java file checks
    check "JX01" 'javax\.servlet' "FAIL" "javax.servlet"
    check "JX02" 'javax\.validation' "FAIL" "javax.validation"
    check "JX03" 'javax\.annotation\.PostConstruct\|javax\.annotation\.PreDestroy' "FAIL" "javax.annotation lifecycle"
    check "JX04" 'javax\.inject' "FAIL" "javax.inject"
    check "JX05" 'javax\.enterprise' "FAIL" "javax.enterprise"
    check "JX06" 'javax\.ws\.rs' "FAIL" "javax.ws.rs"
    check "JX09" 'javax\.persistence' "FAIL" "javax.persistence"
    check "JP01" 'import org\.hibernate\.[^v]' "FAIL" "Hibernate imports"
    check "JP04" 'IN (:\|IN (?\|IN(:\|IN(?' "FAIL" "Parenthesised collection parameter"
    check "SP01" 'SpringContextService' "FAIL" "SpringContextService"
    check "SP02" 'org\.springframework' "FAIL" "Spring imports"
    check "SP04" '@Autowired' "FAIL" "@Autowired"
    check "CD04" 'org\.apache\.commons\.fileupload' "FAIL" "commons.fileupload"
    check "DA01" 'daoUtil\.free( )' "WARN" "daoUtil.free()"
    check "LG01" 'AppLogService\.\(info\|error\|debug\|warn\).*+ ' "WARN" "String concat in logging"

    # Test-specific checks
    if echo "$FILE" | grep -q 'src/test/'; then
        check "TS01" 'import org\.junit\.Test\b' "FAIL" "JUnit 4 @Test"
        check "TS02" 'import org\.junit\.Before\b\|import org\.junit\.After\b' "FAIL" "JUnit 4 @Before/@After"
        check "TS03" 'import org\.junit\.Assert' "FAIL" "JUnit 4 Assert"
        check "TS04" 'MokeHttpServletRequest' "FAIL" "MokeHttpServletRequest"
        check "TS08" 'org\.springframework\.mock\.web' "FAIL" "Spring mock imports"
    fi

    # JspBean/XPage specific
    if grep -q 'MVCAdminJspBean\|MVCApplication' "$FILE" 2>/dev/null; then
        check "DP03" '\(^\|[^.A-Za-z0-9_]\)getModel( )' "FAIL" "getModel() -> @Inject Models"
        check "MV01" 'new HashMap' "FAIL" "new HashMap -> @Inject Models"
    fi

elif echo "$FILE" | grep -q '\.html$'; then
    # Template checks
    if echo "$FILE" | grep -q 'templates/admin/'; then
        check "TM01" 'class="panel' "WARN" "Old Bootstrap panels"
        check "TM06" '<@addRequiredJsFiles[^B]' "FAIL" "@addRequiredJsFiles -> BO"
    fi
    check "TM02" 'jQuery\|\$(' "WARN" "jQuery usage"
    check "TM04" 'errors?size\|infos?size\|warnings?size' "FAIL" "Unsafe null access"

elif echo "$FILE" | grep -q '\.jsp$'; then
    check "JS01" 'jsp:useBean' "FAIL" "jsp:useBean"
    check "JS02" '<%[^@-]' "WARN" "JSP scriptlets"

elif echo "$FILE" | grep -q '\.xml$'; then
    if echo "$FILE" | grep -q 'plugins/'; then
        check "WB02" '<application-class>' "FAIL" "application-class"
        check "WB04" '<min-core-version>' "WARN" "min-core-version check"
    fi
    if echo "$FILE" | grep -q 'web\.xml'; then
        check "WB01" 'java\.sun\.com/xml/ns/javaee' "FAIL" "Old namespace"
        check "WB03" 'ContextLoaderListener' "FAIL" "Spring ContextLoaderListener"
    fi
fi

DETAILS="$DETAILS]"

cat << ENDJSON
{
  "path": "$FILE",
  "pass": $PASS,
  "fail": $FAIL,
  "warn": $WARN,
  "details": $DETAILS
}
ENDJSON

[ "$FAIL" -gt 0 ] && exit 1
exit 0
