#!/bin/bash
# verify-migration.sh — Run all migration verification checks
# Usage: bash verify-migration.sh [project_root] [--json]
# Exit code: 0 if all PASS, 1 if any FAIL
# --json flag: output JSON instead of colored text (writes to .migration/verify-latest.json)

set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/python.sh"
. "$(dirname "${BASH_SOURCE[0]}")/portable.sh"
lp_require_gnu
if [ -z "$LP_PYTHON" ]; then python3 2>&1 | sed "s/^/verify-migration stopped: /" >&2; exit 2; fi

PROJECT_ROOT="${1:-.}"
JSON_MODE=false
[ "${2:-}" = "--json" ] && JSON_MODE=true
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$PROJECT_ROOT" || { echo "verify-migration: no such directory: $PROJECT_ROOT" >&2; exit 2; }

# No finding stops the verification: a core below the floor is PM14, a project that does not assemble leaves TM08 and
# TM09 NOT EVALUATED, and every other check still runs. LP_ANY_CORE lets the template tools assemble whatever the core.
FLOOR_RC=0; FLOOR_OUT=""
[ -f pom.xml ] && { FLOOR_OUT=$(bash "$SCRIPT_DIR/check-v8-floor.sh" . 2>&1 >/dev/null); FLOOR_RC=$?; }
export LP_ANY_CORE=1
EXPLODED_RC=0; EXPLODED_OUT=""
if [ -d "webapp/WEB-INF/templates" ]; then
    EXPLODED_OUT=$(bash "$SCRIPT_DIR/ensure-exploded.sh" . 2>&1) || EXPLODED_RC=$?
fi

# The slowest checks are functions started in the background here, each writing its output, errors and status to
# files the check reads at its turn (fetched); the report keeps its order.
BG_DIR=$(mktemp -d)
PF_PIDS=()
trap 'kill "${PF_PIDS[@]}" 2>/dev/null; rm -rf "$BG_DIR"' EXIT

# A check whose Python dies on an exception has not run. Its error is kept in LP_CRASH_FILE and the next result
# reported (emit) turns into a FAIL naming it; a Python that feeds several results keeps it for each (CRASH_HOLD).
LP_CRASH_FILE="$BG_DIR/crash"
python3() {
    local err rc
    err=$(mktemp "$BG_DIR/py.XXXXXX")
    command "$LP_PYTHON" "$@" 2> "$err"; rc=$?
    cat "$err" >&2
    if [ "$rc" -ne 0 ] && grep -q "^Traceback (most recent call last):" "$err"; then
        grep -v "^[[:space:]]" "$err" | tail -1 >> "$LP_CRASH_FILE"
    fi
    rm -f "$err"
    return "$rc"
}
export -fn python3

# Starts a function in the background under a name.
prefetch() {
    { LP_CRASH_FILE="$BG_DIR/$1.crash"; "$2" > "$BG_DIR/$1.out" 2> "$BG_DIR/$1.err"; echo $? > "$BG_DIR/$1.part"; mv "$BG_DIR/$1.part" "$BG_DIR/$1.rc"; } &
    PF_PIDS+=("$!")
    printf -v "PF_$1" '%s' "$!"
}

# Prints what a prefetched function printed and returns its status, or runs the function when it was not started.
fetched() {
    local pid_var="PF_$1"
    local pid="${!pid_var:-}"
    while [ ! -f "$BG_DIR/$1.rc" ] && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; do sleep 0.02; done
    if [ -f "$BG_DIR/$1.rc" ]; then
        cat "$BG_DIR/$1.out"
        cat "$BG_DIR/$1.err" >&2
        [ -f "$BG_DIR/$1.crash" ] && cat "$BG_DIR/$1.crash" >> "$LP_CRASH_FILE"
        return "$(cat "$BG_DIR/$1.rc")"
    fi
    "$2"
}

# Prints the I18N02 findings. A module's keys are module.<plugin>.<module>.*: I18nService reads them from
# plugins/<plugin>/modules/<module>/resources. Its bare <module>.* keys belong to the plugin of that name, whose bundle
# this project does not carry.
i18n02_scan() {
    BUNDLE=$(find src/java -name "*_messages.properties" 2>/dev/null | head -1)
    PLUGIN=$(basename "${BUNDLE:-}" 2>/dev/null | sed 's/_messages.properties//')
    if [[ "${BUNDLE:-}" =~ /plugins/([a-z0-9]+)/modules/([a-z0-9]+)/resources/ ]]; then
        PLUGIN="module\.${BASH_REMATCH[1]}\.${BASH_REMATCH[2]}"
    fi
    if [ -n "$PLUGIN" ] && [ -n "$BUNDLE" ]; then
        DECLARED=$(mktemp); ASKED=$(mktemp)
        SCRIPT_DIR="$SCRIPT_DIR" python3 -c 'import glob, os, sys; sys.path.insert(0, os.environ["SCRIPT_DIR"]); from bundles import keys; print("\n".join(k for f in glob.glob("src/java/**/*_messages*.properties", recursive=True) for k in keys(f)))' | LC_ALL=C sort -u > "$DECLARED"
        grep -arhoE "#i18n\{$PLUGIN\.[A-Za-z0-9_.-]+\}" webapp src 2>/dev/null | sed -E "s/^#i18n\{$PLUGIN\.//; s/\}$//" >> "$ASKED"
        grep -arhoE "[A-Z0-9_]*(MESSAGE|INFO|ERROR|WARNING|TITLE|PROPERTY_PAGE_TITLE)_[A-Z0-9_]+ *= *\"$PLUGIN\.[A-Za-z0-9_.-]+\"" src/java --include="*.java" 2>/dev/null \
            | grep -vE "^[A-Z0-9_]*(DS_KEY|DSKEY|DATASTORE)" | grep -oE "\"$PLUGIN\.[A-Za-z0-9_.-]+\"" | tr -d '"' | sed -E "s/^$PLUGIN\.//" >> "$ASKED"
        grep -arhoE "(pageTitleI18nKey|pagePathI18nKey) *= *\"$PLUGIN\.[A-Za-z0-9_.-]+\"" src/java --include="*.java" 2>/dev/null \
            | grep -oE "\"$PLUGIN\.[A-Za-z0-9_.-]+\"" | tr -d '"' | sed -E "s/^$PLUGIN\.//" >> "$ASKED"
        grep -ahoE "<(description|feature-title|feature-description|portlet-type-name|daemon-name|daemon-description|insert-service-label)>$PLUGIN\.[A-Za-z0-9_.-]+<" webapp/WEB-INF/plugins/*.xml 2>/dev/null \
            | sed -E "s/^<[a-z-]+>$PLUGIN\.//; s/<$//" >> "$ASKED"
        grep -rahiE "INSERT +INTO +core_(portlet_type|admin_right)\b" src/sql --include="*.sql" 2>/dev/null \
            | grep -oE "'$PLUGIN\.[A-Za-z0-9_.-]+'" | tr -d "'" | sed -E "s/^$PLUGIN\.//" >> "$ASKED"
        NOTKEYS=$(mktemp)
        { find webapp/WEB-INF/conf -name "*.properties" -exec grep -ahoE "^[[:space:]]*$PLUGIN\.[^=:[:space:]]+" {} + 2>/dev/null
          grep -rahoiE "core_datastore[^;]*" src/sql --include="*.sql" 2>/dev/null | grep -oE "'$PLUGIN\.[A-Za-z0-9_.-]+'" | tr -d "'"; } \
            | sed -E "s/^[[:space:]]*$PLUGIN\.//" | LC_ALL=C sort -u > "$NOTKEYS"
        sort -u "$ASKED" | while read -r k; do
            [ -n "$k" ] || continue
            grep -qxF "$k" "$NOTKEYS" && continue
            grep -qxF "$k" "$DECLARED" || echo "${PLUGIN//\\/}.$k: asked for by a template, a message constant, the plugin descriptor or a right/portlet type row, declared in no bundle"
        done
        rm -f "$DECLARED" "$ASKED" "$NOTKEYS"
    fi
}

# Prints the I18N03 findings between the default bundle and _fr.
i18n03_scan() {
    SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'PY'
import glob, os, sys
sys.path.insert(0, os.environ["SCRIPT_DIR"])
from bundles import keys
from i18n_unused import unused
dead = {(os.path.normpath(b), k) for b, _, k in unused(".", os.path.expanduser("~/.lutece-references"))}
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
            if (os.path.normpath(base), k) not in dead:
                print("%s: %s missing (present in %s)" % (fr, k, os.path.basename(base)))
PY
}

# Prints the I18N08 findings.
i18n08_scan() {
    python3 "$SCRIPT_DIR/i18n_unused.py" . 2>/dev/null
}

# Prints the TS06 findings.
ts06_scan() {
    [ -d "src/test/" ] || return 0
    grep -rn 'public void test' src/test/ --include="*.java" 2>/dev/null | while read -r line; do
        FILE=$(echo "$line" | cut -d: -f1)
        LINENUM=$(echo "$line" | cut -d: -f2)
        if ! head -n $((LINENUM - 1)) "$FILE" 2>/dev/null | lp_reverse | awk '/^[[:space:]]*(@|$)/ { print; next } { exit }' \
                | grep -qE '@(Test|ParameterizedTest|RepeatedTest|TestFactory|TestTemplate)\b'; then
            echo "$line"
        fi
    done
}

# Prints the TM08 findings; exits as scan-template-design.py does.
tm08_scan() {
    python3 "$SCRIPT_DIR/scan-template-design.py" . --flat --warn-only 2>/dev/null
}

# Prints the template parse report of TM09.
tm09_scan() {
    bash "$SCRIPT_DIR/check-template-parse.sh" . 2>/dev/null
}

# Prints the ST02 findings.
st02_scan() {
    grep -rn 'public final class' src/ --include="*.java" 2>/dev/null | while read -r line; do
        FILE=$(echo "$line" | cut -d: -f1)
        grep -q '@ApplicationScoped\|@RequestScoped\|@SessionScoped' "$FILE" 2>/dev/null || continue
        CLS=$(echo "$line" | sed 's/.*public final class \([A-Za-z0-9_]*\).*/\1/')
        [ -z "$CLS" ] && continue
        if grep -rqE "select\( *${CLS}\.class|Instance< *${CLS} *>" src/ --include="*.java" 2>/dev/null \
           || python3 - "$CLS" <<'PY'
import glob, re, sys
cls = sys.argv[1]
for f in glob.glob("src/**/*.java", recursive=True):
    t = re.sub(r"/\*.*?\*/|//[^\n]*", "", open(f, encoding="utf-8", errors="replace").read(), flags=re.S)
    if re.search(r"@Inject\b[^;{]*?[\s>]%s\s+[_a-zA-Z]\w*\s*;|@Inject\b[^;{]*?\([^)]*[\s(,>]%s\s+\w+\s*[,)]" % (re.escape(cls), re.escape(cls)), t):
        sys.exit(0)
sys.exit(1)
PY
        then
            echo "$line -> resolved by concrete type, not proxyable"
        fi
    done
}

# Prints the JS04 findings.
js04_scan() {
    bash "$SCRIPT_DIR/legacy-admin-jsp.sh" . | awk -F '\t' '$4 == "direct" { print $1 ": calls the @Controller " $2 " outside processController: make that method a @View (the defaultView for the menu entry) and the JSP a processController one"; next } { print $1 ": calls " $2 ", a JspBean without @Controller: port it to MVCAdminJspBean, one JSP with processController" }'
}

# Prints the static scripts JS07 parses.
js07_files() {
    find webapp -path webapp/WEB-INF -prune -o -name "*.js" ! -name "*.min.js" ! -path "*/lib/*" ! -path "*/vendor/*" -print 2>/dev/null
}

# Prints the JS07 findings.
js07_scan() {
    js07_files | while read -r js; do
        out=$(node --check "$js" 2>&1) || echo "$js: $(printf '%s\n' "$out" | grep -m1 -E 'SyntaxError')"
    done
}

JC_PIDS=()
for checks in "wg01 cd08 cd05" "dp01 dp04 dp05 dp06 pi01 rl01 pd02 gi01 mv08 pd03 mv01 st04 cs03 wb10 wb11 da03 hm01 hm02"; do
    "$LP_PYTHON" "$SCRIPT_DIR/java_checks.py" --into "$BG_DIR" . $checks >/dev/null 2>&1 &
    JC_PIDS+=("$!")
done
PF_PIDS+=("${JC_PIDS[@]}")
if [ -d "src/java" ]; then
    prefetch i18n02 i18n02_scan
    prefetch i18n03 i18n03_scan
    prefetch i18n08 i18n08_scan
fi
[ -d "src/test/" ] && prefetch ts06 ts06_scan
if [ -d "webapp/WEB-INF/templates/" ] && [ "$EXPLODED_RC" -eq 0 ]; then
    prefetch tm08 tm08_scan
    prefetch tm09 tm09_scan
fi
[ -d "src/" ] && prefetch st02 st02_scan
prefetch js04 js04_scan
[ -d "webapp" ] && [ -n "$(js07_files)" ] && command -v node >/dev/null 2>&1 && prefetch js07 js07_scan

# Tells whether a java_checks.py process is still running.
jc_running() {
    local pid
    for pid in "${JC_PIDS[@]}"; do kill -0 "$pid" 2>/dev/null && return 0; done
    return 1
}

# Prints the findings of a java_checks.py check: its file once written, else the check run on its own.
jc() {
    while [ ! -f "$BG_DIR/$1" ] && jc_running; do sleep 0.02; done
    if [ -f "$BG_DIR/$1" ]; then cat "$BG_DIR/$1"; else python3 "$SCRIPT_DIR/java_checks.py" "$1" . 2>/dev/null; fi
}

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
    if [ -s "$LP_CRASH_FILE" ]; then
        status=FAIL; count=1; matches=""
        description="NOT EVALUATED, the check crashed: $(tail -1 "$LP_CRASH_FILE")"
        ${CRASH_HOLD:-false} || : > "$LP_CRASH_FILE"
    fi

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

# check_grep: a grep check; a match inside a comment (a line opening with *, //, /*, <!--, <#--, or a <!-- --> or /* */
# span within the line) or the declaration of a method named like
# a deprecated core one (getModel, putInCache, getFromCache, removeKey) is not a use.
check_grep() {
    local id="$1" pattern="$2" path="$3" severity="$4" description="$5" includes="${6:---include=*.java --include=*.xml --include=*.html --include=*.jsp}"

    if [ ! -d "$path" ]; then
        emit "$id" "PASS" "$description" 0
        return
    fi

    local matches count=0
    matches=$(eval "grep -rn '$pattern' '$path' $includes 2>/dev/null" \
        | sed -E 's#<!--([^-]|-[^-])*-->##g; s#<\#--([^-]|-[^-])*-->##g; s#/\*([^*]|\*[^/])*\*/##g' | eval "grep '$pattern'" \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(\*|//|/\*|<!--|<#--)' \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(public|protected|private)[^=;(]*[[:space:]](getModel|putInCache|getFromCache|removeKey)[[:space:]]*\(') || true
    [ -n "$matches" ] && count=$(echo "$matches" | wc -l)

    if [ "$count" -eq 0 ]; then
        emit "$id" "PASS" "$description" 0
    else
        emit "$id" "$severity" "$description" "$count" "$matches"
    fi
}

# Prints pom.xml with its comments blanked, and with the <scope>test</scope> dependencies blanked when $1 is "runtime".
masked_pom() {
    python3 - "$1" <<'PY'
import re, sys
t = open("pom.xml", encoding="latin-1").read()
blank = lambda m: re.sub(r"[^\n]", " ", m.group())
t = re.sub(r"<!--.*?-->", blank, t, flags=re.S)
if sys.argv[1] == "runtime":
    t = re.sub(r"<dependency>(?:(?!</dependency>).)*<scope>\s*test\s*</scope>(?:(?!</dependency>).)*</dependency>", blank, t, flags=re.S)
sys.stdout.write(t)
PY
}

# Reports the lines of pom.xml matching a pattern outside comments; "runtime" as $5 also leaves out test-scoped dependencies.
check_pom() {
    local id="$1" pattern="$2" severity="$3" description="$4" mode="${5:-all}"

    if [ ! -f "pom.xml" ]; then
        emit "$id" "PASS" "$description" 0
        return
    fi

    local matches count=0
    matches=$(masked_pom "$mode" | grep -n "$pattern" 2>/dev/null) || true
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
    matches=$({ grep -rl 'createNativeQuery' src/ --include="*.java" 2>/dev/null || true; } | { xargs grep -n '"[^"]*[=(, ]:[a-zA-Z_][a-zA-Z0-9_]*' 2>/dev/null || true; } | grep -v '::\|://\|createQuery(\|\.class\|\(FROM\|UPDATE\|JOIN\) [A-Z][a-zA-Z]* ' || true)
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
    if python3 -c 'import re, sys; t = re.sub(r"<!--.*?-->", "", open(sys.argv[1], encoding="utf-8", errors="replace").read(), flags=re.S); sys.exit(0 if re.search(r"<shared-cache-mode>", t) or any(re.search(r"name\s*=\s*[\"\x27]eclipselink\.cache\.shared\.default[\"\x27]", p) and re.search(r"value\s*=\s*[\"\x27]false[\"\x27]", p) for p in re.findall(r"<property\b[^>]*>", t)) else 1)' "$px"; then
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
check_pom "PM02" 'net\.sf\.ehcache' "FAIL" "EhCache dependencies in pom.xml" runtime
check_pom "PM03" 'com\.sun\.mail' "FAIL" "javax.mail dependency in pom.xml" runtime
check_pom "PM04" 'org\.glassfish\.jersey' "FAIL" "Jersey dependencies in pom.xml (Liberty provides JAX-RS; test scope allowed)" runtime
check_pom "PM05" 'net\.sf\.json-lib' "FAIL" "json-lib in pom.xml (use Jackson)" runtime
check_pom "PM07" '<springVersion>' "WARN" "springVersion property in pom.xml (read by nothing, remove)"
check_pom "PM08" '<jiraProjectName>\|<jiraComponentId>' "WARN" "Jira properties in pom.xml (remove)"

# PM09: bounded version ranges [X,Y) should be open [X,)
if [ -f "pom.xml" ]; then
    PM09_MATCHES=$(masked_pom all | grep -n ',[0-9].*)</version>')
    BOUNDED=0; [ -n "$PM09_MATCHES" ] && BOUNDED=$(echo "$PM09_MATCHES" | wc -l)
    if [ "$BOUNDED" -gt 0 ]; then
        emit "PM09" "WARN" "Bounded version range(s) found — convert to open [X,)" "$BOUNDED" "$PM09_MATCHES"
    else
        emit "PM09" "PASS" "No bounded version ranges" 0
    fi
else
    emit "PM09" "PASS" "No bounded version ranges (no pom.xml)" 0
fi

# PM06: the parent is at or above the lowest Lutece 8 parent lutecepowers supports (v8-floor.conf).
if [ -f "pom.xml" ]; then
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/v8-floor.conf"
    PARENT_VER=$(masked_pom all | python3 -c 'import re, sys; m = re.search(r"<parent>(.*?)</parent>", sys.stdin.read(), re.S); v = m and re.search(r"<version>\s*([^<]*?)\s*</version>", m.group(1)); print(v.group(1) if v else "")')
    PARENT_AID=$(masked_pom all | python3 -c 'import re, sys; m = re.search(r"<parent>(.*?)</parent>", sys.stdin.read(), re.S); a = m and re.search(r"<artifactId>\s*([^<]*?)\s*</artifactId>", m.group(1)); print(a.group(1) if a else "")')
    PARENT_FLOOR=$V8_FLOOR_PARENT
    [ "$PARENT_AID" = "lutece-site-pom" ] && PARENT_FLOOR=$V8_FLOOR_SITE_PARENT
    if [[ "$PARENT_VER" == 8.* ]] && [ "$(printf '%s\n%s\n' "$PARENT_FLOOR" "${PARENT_VER%%-*}" | lp_version_sort | head -1)" = "$PARENT_FLOOR" ] && [[ "$PARENT_VER" != "$PARENT_FLOOR"-* ]]; then
        emit "PM06" "PASS" "Parent version is $PARENT_VER" 0
    else
        emit "PM06" "FAIL" "Parent version is '$PARENT_VER' (must be $PARENT_FLOOR or later: the latest released ${PARENT_AID:-lutece-global-pom} 8.x)" 1
    fi
else
    emit "PM06" "PASS" "Parent version check (no pom.xml)" 0
fi

# PM14: the lutece-core the project resolves is at or above the Lutece 8 level lutecepowers supports (check-v8-floor.sh).
# Below it, the other checks still run, judged against that level.
case "$FLOOR_RC" in
    0) emit "PM14" "PASS" "lutece-core at or above the supported Lutece 8 level" 0 ;;
    1) emit "PM14" "FAIL" "lutece-core below the Lutece 8 level lutecepowers supports: the other checks judge the project against that level" 1 "$FLOOR_OUT" ;;
    *) emit "PM14" "WARN" "lutece-core level NOT EVALUATED" 1 "$FLOOR_OUT" ;;
esac

# PM10: EL implementation is org.glassfish.expressly:expressly, the one the parent manages (org.glassfish:jakarta.el
#   stopped at 5.0.0-M1 and has no managed version).
# PM11: explicit <version> on a dependency the parent manages
# PM12: Jakarta EE 11 artifact on the EE 10 baseline
# Only <dependency> blocks outside <dependencyManagement> are inspected.
MANAGED='fr\.paris\.lutece\.plugins:library-lutece-unit-testing|org\.hibernate\.validator:hibernate-validator|org\.glassfish\.expressly:expressly|org\.glassfish\.jaxb:jaxb-runtime|commons-logging:commons-logging|org\.jboss\.logging:jboss-logging|jakarta\.el:jakarta\.el-api|jakarta\.annotation:jakarta\.annotation-api|org\.slf4j:slf4j-api|org\.apache\.commons:commons-lang3|org\.apache\.commons:commons-collections4|commons-codec:commons-codec|commons-io:commons-io|commons-beanutils:commons-beanutils|com\.fasterxml\.jackson(\.[a-z.]+)?:.+|org\.junit(\.[a-z.]+)?:.+|org\.apache\.logging\.log4j:.+'
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
    ' < <(masked_pom all) 2>/dev/null | sed 's|<exclusions>.*</exclusions>||')

    while IFS= read -r blk; do
        [ -z "$blk" ] && continue
        GID=$(printf '%s' "$blk" | sed -n 's/.*<groupId>\([^<]*\)<\/groupId>.*/\1/p' | head -1)
        AID=$(printf '%s' "$blk" | sed -n 's/.*<artifactId>\([^<]*\)<\/artifactId>.*/\1/p' | head -1)
        VER=$(printf '%s' "$blk" | sed -n 's/.*<version>\([^<]*\)<\/version>.*/\1/p' | head -1)

        case "$GID:$AID" in
            org.glassfish:jakarta.el)
                PM10_COUNT=$((PM10_COUNT + 1)); PM10_MATCHES="${PM10_MATCHES}org.glassfish:jakarta.el is not managed by the parent, use org.glassfish.expressly:expressly"$'\n' ;;
        esac

        if [ -n "$VER" ] && printf '%s' "$GID:$AID" | grep -qE "^($MANAGED)$" \
            && ! { [[ "$VER" == '${'*'}' ]] && ! grep -q "<${VER:2:${#VER}-3}>" pom.xml; }; then
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
    emit "PM10" "PASS" "EL implementation is org.glassfish.expressly:expressly" 0
else
    emit "PM10" "FAIL" "org.glassfish:jakarta.el declared: use org.glassfish.expressly:expressly, the EL implementation the parent manages" "$PM10_COUNT" "$PM10_MATCHES"
fi

if [ "$PM11_COUNT" -eq 0 ]; then
    emit "PM11" "PASS" "No explicit version on a parent-managed dependency" 0
else
    emit "PM11" "WARN" "Explicit version on a parent-managed dependency (remove it)" "$PM11_COUNT" "$PM11_MATCHES"
fi

# PM13: web-layer tests need test-scoped implementations the core does not pass on, and only them. A test that renders
# a JspBean or XPage page needs jaxb-runtime: without it the cache manager cannot read its XML configuration and AppInit
# stops before AppTemplateService.initMacros, so the page fails on a missing macro (@pageContainer...). A test that
# calls an MVC action through processController also needs hibernate-validator and expressly (bean validation).
# Business-only tests (DAO, Home) need none of them.
PM13_MATCHES=""
if [ -f pom.xml ] && [ -d src/test ]; then
    NEEDED=""
    grep -rqlE "extends +LuteceTestCase" src/test 2>/dev/null && grep -rqlE "\b[A-Za-z]+(JspBean|XPage)\b" src/test --include="*.java" 2>/dev/null && NEEDED="jaxb-runtime"
    grep -rqlE "processController *\(" src/test --include="*.java" 2>/dev/null && NEEDED="$NEEDED hibernate-validator expressly"
    for dep in $NEEDED; do
        grep -q "<artifactId>$dep</artifactId>" pom.xml || PM13_MATCHES="${PM13_MATCHES}${PM13_MATCHES:+$'\n'}pom.xml: no test dependency $dep"
    done
fi
COUNT=0; [ -n "$PM13_MATCHES" ] && COUNT=$(echo "$PM13_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "PM13" "PASS" "Web-layer tests have the test implementations they need" 0
else emit "PM13" "WARN" "Test dependency missing: a JspBean/XPage test needs jaxb-runtime (else the test startup stops before the macros load, pages fail on @pageContainer), a processController test also needs hibernate-validator and expressly (lutece-update-plugin steps/4-tests.md)" "$COUNT" "$PM13_MATCHES"; fi

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

# JX10: a JAX-RS resource handing the container an object whose class carries Jackson annotations. v7 sites wrote
# JSON with Jackson; the v8 server (restfulWS + jsonb) writes it with JSON-B, which ignores @JsonProperty/@JsonFormat/
# @JsonIgnore: field names and date formats of the api change, a non-public nested class fails with a 500.
JX10_MATCHES=""
if [ -d src/java ]; then
    JX10_MATCHES=$(python3 - <<'PY'
import glob, re
files = {f: open(f, encoding="utf-8", errors="replace").read() for f in glob.glob("src/java/**/*.java", recursive=True)}
if any(re.search(r"JacksonJsonProvider|JacksonFeature|ContextResolver\s*<\s*ObjectMapper", t) for t in files.values()):
    raise SystemExit
jackson = set()
for t in files.values():
    if "com.fasterxml.jackson.annotation" in t:
        jackson.update(re.findall(r"\b(?:class|record|enum)\s+(\w+)", t))
if not jackson:
    raise SystemExit
names = r"\b(?:%s)\b" % "|".join(sorted(jackson))
for f, t in files.items():
    if not re.search(r"import jakarta\.ws\.rs\.", t) or not re.search(r"^\s*@Path\b", t, re.M):
        continue
    for m in re.finditer(r"@(?:GET|POST|PUT|DELETE|PATCH)\b[^{;]*?\bpublic\s+([\w<>\[\], ?]+?)\s+\w+\s*\(", t, re.S):
        if re.search(names, m.group(1)):
            print("%s:%d: returns %s" % (f, t[:m.start(1)].count("\n") + 1, m.group(1).strip()))
    for m in re.finditer(r"(?:Response\s*\.\s*ok|\.\s*entity)\s*\(\s*(\w+)\s*\)", t):
        decl = re.search(r"([\w<>\[\], ?]+?)\s+%s\s*[;=]" % re.escape(m.group(1)), t)
        if decl and re.search(names, decl.group(1)):
            print("%s:%d: entity %s of type %s" % (f, t[:m.start()].count("\n") + 1, m.group(1), decl.group(1).strip()))
PY
)
fi
COUNT=0; [ -n "$JX10_MATCHES" ] && COUNT=$(echo "$JX10_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JX10" "PASS" "No REST answer relies on Jackson annotations the server ignores" 0
else emit "JX10" "WARN" "REST resource hands the server a Jackson-annotated object: JSON-B writes it, the annotations are ignored (write it with an ObjectMapper)" "$COUNT" "$JX10_MATCHES"; fi
echo ""

# ─── Spring Residues ─────────────────────────────────────
echo "CATEGORY: Spring residues"
check_grep "SP01" 'SpringContextService' "src/" "FAIL" "SpringContextService -> CDI"
check_grep "SP02" 'org\.springframework' "src/" "FAIL" "Spring imports"
# SP03: a Spring context file left under webapp/ is dead in v8, nothing reads it, whether named *_context.xml or
# imported by one; a file naming one is dead too.
SP03_MATCHES=$( { [ -d webapp ] && find webapp -name '*_context.xml' | sed 's/$/: Spring context file, delete it/'; \
    grep -rl --include='*.xml' 'springframework.org/schema/beans' webapp/WEB-INF/conf 2>/dev/null | grep -v '_context\.xml$' | sed 's/$/: Spring context file (imported by another), delete it/'; \
    grep -rln --include='*.xml' '_context\.xml' webapp/ 2>/dev/null | sed 's/$/: names a Spring context file/'; } | sort -u )
COUNT=0; [ -n "$SP03_MATCHES" ] && COUNT=$(echo "$SP03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SP03" "PASS" "No Spring context XML file" 0
else emit "SP03" "FAIL" "Spring context XML file left: v8 never reads it (delete it once its beans are CDI)" "$COUNT" "$SP03_MATCHES"; fi
check_grep "SP04" '@Autowired' "src/" "FAIL" "@Autowired -> @Inject"
check_grep "SP05" 'implements.*InitializingBean' "src/" "FAIL" "InitializingBean -> @PostConstruct"
check_grep "SP06" '@Component(' "src/" "FAIL" "@Component(name) -> @ApplicationScoped @Named(name)"
check_grep "SP07" '@Service(' "src/" "FAIL" "@Service(name) -> @ApplicationScoped @Named(name)"
check_grep "SP08" '@Repository(' "src/" "FAIL" "@Repository(name) -> @ApplicationScoped @Named(name)"
echo ""

# ─── Deprecated Libraries ────────────────────────────────
echo "CATEGORY: Deprecated libraries"
check_grep "DL01" 'net\.sf\.json' "src/" "FAIL" "net.sf.json -> com.fasterxml.jackson"
# DL02: opencsv 2.x (packages au.com.bytecode.opencsv) came with the v7 core; the v8 core ships com.opencsv 5. A plugin
# that imports the old packages without declaring net.sf.opencsv itself no longer compiles.
DL02_MATCHES=""
if [ -d src ] && ! { [ -f pom.xml ] && masked_pom all | grep -q "<groupId>net\.sf\.opencsv</groupId>"; }; then
    DL02_MATCHES=$(grep -rn --include=*.java "^import au\.com\.bytecode\.opencsv" src/ 2>/dev/null)
fi
COUNT=0; [ -n "$DL02_MATCHES" ] && COUNT=$(echo "$DL02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "DL02" "PASS" "No opencsv 2 import left to the core" 0
else emit "DL02" "FAIL" "au.com.bytecode.opencsv came with the v7 core, the v8 core ships com.opencsv: move to com.opencsv (CSVReader/CSVWriter builders) or declare net.sf.opencsv" "$COUNT" "$DL02_MATCHES"; fi
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
check_grep "CA03" 'extends AbstractCacheableService\($\|[[:space:]]*[^<[:space:]]\)' "src/" "FAIL" "Raw AbstractCacheableService (needs type params)"

echo ""

# ─── Deprecated API ──────────────────────────────────────
echo "CATEGORY: Deprecated API"
# DP01: a call to a lutece-core getInstance( ) deprecated for removal, the class resolved through the imports (java_checks.py dp01).
DP01_MATCHES=$(jc dp01)
COUNT=0; [ -n "$DP01_MATCHES" ] && COUNT=$(echo "$DP01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "DP01" "PASS" "No deprecated core getInstance( ) call" 0
else emit "DP01" "FAIL" "Deprecated core getInstance() calls (@Deprecated forRemoval in lutece-core; SecurityService/AdminAuthenticationService are not deprecated)" "$COUNT" "$DP01_MATCHES"; fi
check_grep "DP02" '[^A-Za-z]FileImageService\.init' "src/" "FAIL" "FileImageService.init( ): the core registers FileImageService at startup (AppInit), a second call registers the provider twice"
check_grep "DP03" '\(^\|[^.A-Za-z0-9_]\)getModel([[:space:]]*)' "src/" "FAIL" "MANDATORY: getModel() -> Models parameter (excludes DTO getters like request.getModel())"
# DP04: an import of a lutece-core type deprecated for removal, read in the core of ~/.lutece-references (java_checks.py dp04).
DP04_MATCHES=$(jc dp04)
COUNT=0; [ -n "$DP04_MATCHES" ] && COUNT=$(echo "$DP04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "DP04" "PASS" "No lutece-core type deprecated for removal" 0
else emit "DP04" "FAIL" "lutece-core type deprecated for removal: use the replacement the core gives" "$COUNT" "$DP04_MATCHES"; fi
# DP05: an import of a lutece-core type the v7 core had and the v8 core does not (java_checks.py dp05): removed with no
# deprecation first, nothing points at a replacement; the compiler says the symbol is missing, not where it went.
DP05_MATCHES=$(jc dp05)
COUNT=0; [ -n "$DP05_MATCHES" ] && COUNT=$(echo "$DP05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "DP05" "PASS" "No lutece-core type the v8 core no longer has" 0
else emit "DP05" "FAIL" "lutece-core type gone in v8 (moved, or removed with nothing pointing at a replacement)" "$COUNT" "$DP05_MATCHES"; fi
# DP06: core API or core_* table on the core's develop and in no published core (java_checks.py dp06): the build passes
# on the latest snapshot, a site on the published core fails. A signal, not a bound to raise: no release carries it yet.
DP06_MATCHES=$(jc dp06)
COUNT=0; [ -n "$DP06_MATCHES" ] && COUNT=$(echo "$DP06_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "DP06" "PASS" "No core API or table of an unpublished core" 0
else emit "DP06" "WARN" "Needs a core not published yet: say it in the hand-over, raise the lutece-core lower bound to the first release that carries it once there is one" "$COUNT" "$DP06_MATCHES"; fi
# PI01: a plugin init( ) that initialises a service; in v8 the service observes the startup itself (java_checks.py pi01).
PI01_MATCHES=$(jc pi01)
COUNT=0; [ -n "$PI01_MATCHES" ] && COUNT=$(echo "$PI01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "PI01" "PASS" "No plugin init( ) initialising a service" 0
else emit "PI01" "FAIL" "Plugin init( ) initialising a service: the service observes the startup itself (@Observes @Initialized( ApplicationScoped.class )), its dependencies injected" "$COUNT" "$PI01_MATCHES"; fi
# RL01: a removal listener registered outside a startup observer, a producer or an @Inject method (java_checks.py rl01).
RL01_MATCHES=$(jc rl01)
COUNT=0; [ -n "$RL01_MATCHES" ] && COUNT=$(echo "$RL01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "RL01" "PASS" "Removal listeners register at startup on the injected removal services" 0
else emit "RL01" "FAIL" "Removal listener registered from an init( ): register it in a @Observes @Initialized( ApplicationScoped.class ) method, on the core's removal service injected by name" "$COUNT" "$RL01_MATCHES"; fi
# PD02: a plugin class whose init( ) works while no descriptor names it: the core never runs that init( ) (java_checks.py pd02).
PD02_MATCHES=$(jc pd02)
COUNT=0; [ -n "$PD02_MATCHES" ] && COUNT=$(echo "$PD02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "PD02" "PASS" "Every plugin init( ) belongs to a class a descriptor names" 0
else emit "PD02" "FAIL" "Plugin init( ) that never runs: no descriptor names its class; move what it does into a startup observer, then delete the class" "$COUNT" "$PD02_MATCHES"; fi
# GI01: a static getInstance( ) on a CDI bean of the project, called inside it or left undeprecated (java_checks.py gi01).
GI01_MATCHES=$(jc gi01)
COUNT=0; [ -n "$GI01_MATCHES" ] && COUNT=$(echo "$GI01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "GI01" "PASS" "No static getInstance( ) used or left open on a CDI bean" 0
else emit "GI01" "FAIL" "Static getInstance( ) on a CDI bean: inject the bean; the accessor goes, or stays @Deprecated( forRemoval = true ) for the artefacts that call it" "$COUNT" "$GI01_MATCHES"; fi
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
')
fi
COUNT=0; [ -n "$DA02_MATCHES" ] && COUNT=$(echo "$DA02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "DA02" "PASS" "Every DAOUtil lives in a try-with-resources" 0
else emit "DA02" "FAIL" "DAOUtil outside try-with-resources: the connection leaks on an exception" "$COUNT" "$DA02_MATCHES"; fi

# SQ05: a value glued into a SQL literal in a DAO ("… LIKE '%" + str + "%'", "col = '" + value + "'"): an injection
# point, and a quote in the value breaks the query. Bind it with daoUtil.setString. A constant of the class glued the
# same way is a compile-time literal, not a value.
SQ05_MATCHES=""
if [ -d "src/" ]; then
    SQ05_MATCHES=$(grep -rnE "'[%_]*\"[[:space:]]*\+[[:space:]]*[A-Za-z_]" src/ --include="*DAO.java" 2>/dev/null \
        | grep -vE "'[%_]*\"[[:space:]]*\+[[:space:]]*[A-Z][A-Z0-9_]*[[:space:]]*(\+|;|$)")
fi
COUNT=0; [ -n "$SQ05_MATCHES" ] && COUNT=$(echo "$SQ05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ05" "PASS" "No value concatenated into a SQL literal" 0
else emit "SQ05" "FAIL" "Value concatenated into a SQL literal: bind it (setString), it is an injection point" "$COUNT" "$SQ05_MATCHES"; fi
echo ""

# SQ06: a Liquibase-headed SQL file of the project that never reaches WEB-INF/classes/sql of the assembled webapp. The
# lutece-maven-plugin copies a file there only when it can parse its name (update_db_<plugin>-<from>-<to>.sql, versions
# in digits and dots) or when it is a prerun_db_* script; plugin-liquibase reads nothing else, so the script is
# dropped without a log line.
SQ06_MATCHES=""
SQ06_CLASSES=""
for d in target/lutece target/*; do [ -d "$d/WEB-INF/classes/sql" ] && [ -d "$d/WEB-INF/templates" ] && { SQ06_CLASSES="$d/WEB-INF/classes/sql"; break; }; done
if [ -d "src/sql" ] && [ -n "$SQ06_CLASSES" ]; then
    SQ06_MATCHES=$(find src/sql -name "*.sql" 2>/dev/null | sort | while read -r f; do
        head -1 "$f" | grep -q "liquibase formatted sql" || continue
        rel=${f#src/sql/}
        [ -f "$SQ06_CLASSES/$rel" ] || echo "$f: not copied to WEB-INF/classes/sql, Liquibase never runs it: an upgrade is plugins/<plugin>/upgrade/update_db_<plugin>-<from>-<to>.sql (versions in digits and dots), an install script plugins/<plugin>/plugin/create_db_ or init_db_, or core/init_core_, a pre-execution script prerun_db_<plugin>.sql"
    done)
fi
COUNT=0; [ -n "$SQ06_MATCHES" ] && COUNT=$(echo "$SQ06_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ06" "PASS" "Every Liquibase SQL file reaches the classpath of the assembled webapp" 0
else emit "SQ06" "FAIL" "SQL file Liquibase never sees: its name is not parsed" "$COUNT" "$SQ06_MATCHES"; fi
echo ""

# ─── JPA ─────────────────────────────────────────────────
echo "CATEGORY: JPA (persistence-patterns.md)"
check_grep "JP01" 'import org\.hibernate\.[^v]' "src/" "FAIL" "Hibernate imports -> jakarta.persistence API only (EclipseLink of the container)"
check_pom "JP02" 'hibernate-core\|hibernate-entitymanager\|module-jpa-hibernate\|spring-orm\|spring-data-jpa' "FAIL" "JPA provider in pom.xml (the container provides EclipseLink)"
check_grep "JP03" 'hibernate\.\|HibernatePersistenceProvider' "src/main/resources/META-INF/" "FAIL" "Hibernate settings in persistence.xml" "--include=persistence.xml"
# JP04: a JPQL collection parameter in parentheses; JDBC's "IN ( ?, ?" built for DAOUtil is left alone.
JP04_MATCHES=""
if [ -d src ]; then
    JP04_MATCHES=$(grep -rlE "import (jakarta|javax)\.persistence\.|createQuery|@NamedQuery|@Query" src --include="*.java" 2>/dev/null | xargs -r grep -nH 'IN (:\|IN (?\|IN(:\|IN(?' 2>/dev/null)
fi
COUNT=0; [ -n "$JP04_MATCHES" ] && COUNT=$(echo "$JP04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JP04" "PASS" "No parenthesised JPQL collection parameter" 0
else emit "JP04" "FAIL" "Parenthesised JPQL collection parameter -> IN :param" "$COUNT" "$JP04_MATCHES"; fi
check_named_native_params
check_persistence_xml
check_grep "JP07" 'persistenceContainer-3\.1' "src/main/liberty/" "WARN" "persistenceContainer-3.1 in server.xml (norm: persistence-3.1)" "--include=server.xml"
echo ""

# ─── CDI Patterns ────────────────────────────────────────
echo "CATEGORY: CDI patterns"

# CD01: static _instance/_singleton on CDI-managed classes
CD01_MATCHES=""
if [ -d "src/" ]; then
    CD01_MATCHES=$(grep -rnE '^[[:space:]]*((private|protected|public|final|volatile)[[:space:]]+)*static[[:space:]][^=;(]*[[:space:]]_(instance|singleton)[[:space:]]*[=;]' src/ --include="*.java" 2>/dev/null | while read -r line; do
        FILE=$(echo "$line" | cut -d: -f1)
        if grep -q '@ApplicationScoped\|@RequestScoped\|@SessionScoped\|@Dependent\|@Singleton' "$FILE" 2>/dev/null; then
            echo "$line"
        fi
    done)
fi
COUNT=0; [ -n "$CD01_MATCHES" ] && COUNT=$(echo "$CD01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "CD01" "PASS" "Static _instance/_singleton on CDI-managed classes" 0
else emit "CD01" "FAIL" "Static _instance/_singleton on CDI-managed classes" "$COUNT" "$CD01_MATCHES"; fi

check_grep "CD02" 'new CaptchaSecurityService()' "src/" "FAIL" "new CaptchaSecurityService() -> @Inject"
check_grep "CD09" '"jcaptcha"' "src/" "FAIL" "Captcha tested through the jcaptcha plugin: v8 has none (plugin-captcha is named captcha), isPluginEnable( \"jcaptcha\" ) is always false and the captcha never shows -> test the injected Instance<ICaptchaService> (BeanUtils.BEAN_CAPTCHA_SERVICE) with isResolvable( ) alone"
check_grep "CD03" 'CompletableFuture\.runAsync( ( ) ->[^,]*$\|CompletableFuture\.runAsync( [^,]*$' "src/" "WARN" "CompletableFuture.runAsync without explicit executor -> use a managed ExecutorService or @Asynchronous"
check_grep "CD04" 'org\.apache\.commons\.fileupload' "src/" "FAIL" "commons.fileupload -> MultipartItem (MemoryFileItem from library-httpaccess for in-memory cases)"

# CD05: a CDI bean registering itself in its constructor or @PostConstruct with no startup observer (java_checks.py cd05).
CD05_MATCHES=$(jc cd05)
COUNT=0; [ -n "$CD05_MATCHES" ] && COUNT=$(echo "$CD05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "CD05" "PASS" "No lazy bean self-registration trap" 0
else emit "CD05" "WARN" "CDI bean registering itself in its constructor or @PostConstruct, created on first use only: register from an @Observes @Initialized method" "$COUNT" "$CD05_MATCHES"; fi

# CD08: a CDI.current( ) lookup inside an instance method of a CDI bean: the bean injects it (java_checks.py cd08).
CD08_MATCHES=$(jc cd08)
COUNT=0; [ -n "$CD08_MATCHES" ] && COUNT=$(echo "$CD08_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "CD08" "PASS" "No CDI.current( ) lookup inside a CDI bean" 0
else emit "CD08" "WARN" "CDI.current( ) inside a CDI bean: inject it (@Inject, @Inject @Any Instance<X>, @Inject Event<X>)" "$COUNT" "$CD08_MATCHES"; fi

# MV08: an @Pager defaultItemsPerPage naming a property no properties file declares (java_checks.py mv08).
MV08_MATCHES=$(jc mv08)
COUNT=0; [ -n "$MV08_MATCHES" ] && COUNT=$(echo "$MV08_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "MV08" "PASS" "Every @Pager items-per-page property is declared" 0
else emit "MV08" "WARN" "@Pager defaultItemsPerPage names an undeclared property: the pager shows 50 items whatever is configured" "$COUNT" "$MV08_MATCHES"; fi

# WG01: an admin method loading a workgroup resource by its id without the workgroup check (java_checks.py wg01).
WG01_MATCHES=$(jc wg01)
COUNT=0; [ -n "$WG01_MATCHES" ] && COUNT=$(echo "$WG01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WG01" "PASS" "Every workgroup resource loaded by its id is checked against the user's workgroups" 0
else emit "WG01" "WARN" "Workgroup resource loaded by its id without AdminWorkgroupService.isAuthorized( ): the listing hides it, the url opens it" "$COUNT" "$WG01_MATCHES"; fi

# PD03: a plugin class that overrides nothing; the descriptor can name PluginDefaultImplementation (java_checks.py pd03).
PD03_MATCHES=$(jc pd03)
COUNT=0; [ -n "$PD03_MATCHES" ] && COUNT=$(echo "$PD03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "PD03" "PASS" "Every plugin class overrides something" 0
else emit "PD03" "WARN" "Plugin class with nothing but constants: name PluginDefaultImplementation in the descriptor, move the constants to the service" "$COUNT" "$PD03_MATCHES"; fi

# CD06: an event fired only with fireAsync() reaches @ObservesAsync observers only: a plain @Observes observer of it is
# never called and nothing fails (a search index never updated, a listener silent). The firing sites are read in this
# project and in the reference clones, where the plugins publishing the events live.
CD06_MATCHES=""
if [ -d "src/java" ]; then
    CD06_MATCHES=$(REFS="${LUTECE_REFERENCES:-$HOME/.lutece-references}" python3 - <<'PY'
import glob, os, re
fired = {}
roots = ["src/java"] + glob.glob(os.path.join(os.environ["REFS"], "*", "src", "java"))
for root in roots:
    for path in glob.glob(os.path.join(root, "**", "*.java"), recursive=True):
        text = open(path, encoding="utf-8", errors="replace").read()
        if ".fire" not in text:
            continue
        for m in re.finditer(r"select\(\s*(\w+)\.class[^;]*?\.(fireAsync|fire)\s*\(", text, flags=re.S):
            fired.setdefault(m.group(1), set()).add(m.group(2))
        for field in re.finditer(r"\bEvent\s*<\s*(\w+)\s*>\s+(\w+)\s*;", text):
            for m in re.finditer(r"\b%s\s*\.(?:select\([^;]*?\)\s*\.)?(fireAsync|fire)\s*\(" % re.escape(field.group(2)), text, flags=re.S):
                fired.setdefault(field.group(1), set()).add(m.group(1))
for path in glob.glob("src/java/**/*.java", recursive=True):
    text = open(path, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"@Observes\s+(?:@\w+(?:\([^)]*\))?\s+)*(\w+)\s+\w+\s*\)", text):
        kinds = fired.get(m.group(1))
        if kinds == {"fireAsync"}:
            line = text.count("\n", 0, m.start()) + 1
            print("%s:%d: @Observes %s, which is only fired with fireAsync(): the observer is never called, use @ObservesAsync" % (path, line, m.group(1)))
PY
)
fi
COUNT=0; [ -n "$CD06_MATCHES" ] && COUNT=$(echo "$CD06_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "CD06" "PASS" "No synchronous observer of an event only fired asynchronously" 0
else emit "CD06" "FAIL" "@Observes on an event only fired with fireAsync(): never called (use @ObservesAsync)" "$COUNT" "$CD06_MATCHES"; fi

# CD07: an @Inject of a library interface whose only implementation lives in a plugin the pom does not bring. v7
# looked the bean up by name when used; v8 resolves every injection point at deployment, so a site without that
# plugin does not start at all (WELD-001408 Unsatisfied dependencies).
CD07_MATCHES=""
if [ -d src/java ] && [ -f pom.xml ]; then
    CD07_MATCHES=$(python3 - <<'PY'
import glob, re
PROVIDERS = {"fr.paris.lutece.plugins.workflowcore.service.": ("plugin-workflow", r"<artifactId>(plugin-workflow|module-workflow-[\w-]+)</artifactId>")}
pom = open("pom.xml", encoding="utf-8", errors="replace").read()
own = (re.search(r"</parent>.*?<artifactId>([^<]+)</artifactId>", pom, re.S) or re.search(r"<artifactId>([^<]+)</artifactId>", pom)).group(1)
for f in sorted(glob.glob("src/java/**/*.java", recursive=True)):
    t = open(f, encoding="utf-8", errors="replace").read()
    for package, (plugin, brought) in PROVIDERS.items():
        if own == plugin or re.search(brought, pom) or glob.glob("src/java/" + package.rsplit(".service.", 1)[0].replace(".", "/") + "/**/*.java", recursive=True):
            continue
        for m in re.finditer(r"^import\s+(%s[\w.]*\.([A-Z]\w*))\s*;" % re.escape(package), t, re.M):
            simple = m.group(2)
            use = re.search(r"@Inject\b(?:\s+@\w+(?:\([^)]*\))?)*\s+(?:(?:private|protected|public|final)\s+)*%s\s+\w+" % simple, t)
            if use:
                print("%s:%d: @Inject %s, implemented by %s, which the pom does not declare" % (f, t[:use.start()].count("\n") + 1, simple, plugin))
PY
)
fi
COUNT=0; [ -n "$CD07_MATCHES" ] && COUNT=$(echo "$CD07_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "CD07" "PASS" "Every injected library service comes with the plugin that implements it" 0
else emit "CD07" "FAIL" "@Inject of a service only a plugin absent from the pom implements: without it the site does not deploy (declare the plugin, or Instance<>)" "$COUNT" "$CD07_MATCHES"; fi
echo ""

# ─── MVC / New Patterns (v2 additions) ──────────────────
echo "CATEGORY: MVC / New patterns"

# MV01: an admin page rendered from a new HashMap misses the security token its controller enables (java_checks.py).
MV01_MATCHES=$(jc mv01)
COUNT=0; [ -n "$MV01_MATCHES" ] && COUNT=$(echo "$MV01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "MV01" "PASS" "Admin pages carry the security token their controller enables" 0
else emit "MV01" "FAIL" "Admin page rendered from a new HashMap without the enabled security token: its forms are refused (fill Models, call getPage( title, template ))" "$COUNT" "$MV01_MATCHES"; fi

check_grep "MV02" 'AbstractPaginatorJspBean' "src/" "FAIL" "AbstractPaginatorJspBean -> @Pager IPager"
# MV05: a @View that calls a do* @Action method of its bean runs that action on a GET, which the token filter never
# checks (it only reads the action named in the request): a link followed by a crawler, a prefetch or an <img> then
# writes. The view asks for a confirmation whose form posts the action instead (AdminMessage TYPE_CONFIRMATION).
# MV06: addError( ... ) then a redirect from a @View of an admin bean: the message only travels from an @Action, the
# next page shows no error (web-bean.md, "Errors from a view"). The view answers an AdminMessage TYPE_STOP instead.
MV05_MATCHES=""; MV06_MATCHES=""
if [ -d "src/java" ]; then
    MV_VIEWS=$({ grep -rlE '@View' src/java --include="*.java" 2>/dev/null || true; } | python3 -c '
import re, sys
SIG = r"(?:\s*@\w+(?:\([^)]*\))?)*\s*(?:public|protected|private)\s+[\w<>\[\], ]+\s+(\w+)\s*\("
for path in sys.stdin.read().split():
    text = open(path, encoding="utf-8", errors="replace").read()
    actions = {a for a in re.findall(r"@Action\s*\([^)]*\)" + SIG, text) if a.startswith("do")}
    admin = "MVCAdminJspBean" in text
    for m in re.finditer(r"@View\s*\([^)]*\)" + SIG, text):
        start = text.find("{", m.end())
        depth, i = 0, start
        while i < len(text):
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            if depth == 0:
                break
            i += 1
        body = text[start:i]
        if actions:
            for call in re.finditer(r"\b(%s)\s*\(" % "|".join(map(re.escape, sorted(actions))), body):
                line = text.count("\n", 0, start + call.start()) + 1
                print("MV05\t%s:%d: @View %s calls @Action %s: the action runs on a GET, unchecked by the token filter" % (path, line, m.group(1), call.group(1)))
        if admin:
            for err in re.finditer(r"\baddError\s*\(", body):
                if re.search(r"\bredirect(View)?\s*\(", body[err.end():]):
                    line = text.count("\n", 0, start + err.start()) + 1
                    print("MV06\t%s:%d: @View %s adds an error then redirects: the message is lost, answer an AdminMessage TYPE_STOP" % (path, line, m.group(1)))
')
    MV05_MATCHES=$(echo "$MV_VIEWS" | grep "^MV05" | cut -f2-)
    MV06_MATCHES=$(echo "$MV_VIEWS" | grep "^MV06" | cut -f2-)
fi
COUNT=0; [ -n "$MV05_MATCHES" ] && COUNT=$(echo "$MV05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "MV05" "PASS" "No @View runs an @Action of its bean" 0
else emit "MV05" "WARN" "@View calling an @Action: the write runs on a GET without token (confirm, then post the action)" "$COUNT" "$MV05_MATCHES"; fi
COUNT=0; [ -n "$MV06_MATCHES" ] && COUNT=$(echo "$MV06_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "MV06" "PASS" "No admin @View loses an error on a redirect" 0
else emit "MV06" "WARN" "addError then redirect from an admin @View: the next page shows no error (answer an AdminMessage TYPE_STOP)" "$COUNT" "$MV06_MATCHES"; fi
# MV07: the core joins controllerPath and controllerJsp without a separator (view and action urls, the CSRF action
# registry of SecurityTokenHandler): a path without its trailing slash names a JSP that does not exist.
MV07_MATCHES=""
[ -d "src/java" ] && MV07_MATCHES=$(python3 - <<'PY'
import glob, re
files = {p: open(p, encoding="utf-8", errors="replace").read() for p in glob.glob("src/java/**/*.java", recursive=True)}
consts = {}
for text in files.values():
    for m in re.finditer(r"\bString\s+(\w+)\s*=\s*\"([^\"]*)\"", text):
        consts.setdefault(m.group(1), m.group(2))
for path, text in files.items():
    for m in re.finditer(r"controllerPath\s*=\s*(\"[^\"]*\"|[\w.]+)", text):
        raw = m.group(1)
        value = raw[1:-1] if raw.startswith('"') else consts.get(raw.split(".")[-1])
        if value is not None and value and not value.endswith("/"):
            print('%s:%d: controllerPath "%s" must end with "/"' % (path, text.count("\n", 0, m.start()) + 1, value))
PY
)
COUNT=0; [ -n "$MV07_MATCHES" ] && COUNT=$(echo "$MV07_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "MV07" "PASS" "Every @Controller path ends with a slash" 0
else emit "MV07" "FAIL" "@Controller controllerPath without its trailing slash: urls and CSRF registry name a missing JSP" "$COUNT" "$MV07_MATCHES"; fi
# MV03: an MVC bean gets its CSRF token from the framework; carrying it by hand there means the framework's own
# token is off or duplicated. A bean that is not MVC (a portlet admin bean, a servlet) has no framework token and
# must carry it by hand: that is the pattern, not a finding. A disabled or unset securityTokenEnabled is always one.
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
    MV03_UNSET=$({ grep -rlE 'annotations\.Controller\b' src/ --include="*.java" 2>/dev/null || true; } | python3 -c '
import re, sys
for f in sys.stdin.read().split():
    s = open(f, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"^[ \t]*@Controller[ \t]*\(", s, re.M):
        i, depth = m.end(), 1
        while i < len(s) and depth:
            depth += {"(": 1, ")": -1}.get(s[i], 0)
            i += 1
        if not re.search(r"securityTokenEnabled\s*=", s[m.end():i]):
            print("%s:%d: @Controller without securityTokenEnabled (the token is off by default)" % (f, s.count("\n", 0, m.start()) + 1))
')
    [ -n "$MV03_UNSET" ] && MV03_MATCHES="$MV03_MATCHES${MV03_MATCHES:+$'\n'}$MV03_UNSET"
    MV03_GET=""
    if [ -n "$MV03_MATCHES" ] && [ -d webapp/WEB-INF/templates ]; then
        MV03_GET=$(SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'PY'
import os, re, sys
sys.path.insert(0, os.environ["SCRIPT_DIR"])
from template_rules import MACRO_LIBRARY, blank_comments, line_of
LINK = re.compile(r"[?&](?:amp;)?token=\$\{\s*token\b[^'\"\s>]*")
MUTATION = re.compile(r"[?&](?:amp;)?action=|/Do[A-Z]\w*\.jsp")
SCRIPT = re.compile(r"<script\b[^>]*>(.*?)</script>", re.S | re.I)
for dirpath, _, files in os.walk("webapp/WEB-INF/templates"):
    for n in sorted(files):
        path = os.path.join(dirpath, n)
        if not n.endswith((".html", ".ftl")) or MACRO_LIBRARY.search(path.replace(os.sep, "/")):
            continue
        text = blank_comments(open(path, encoding="utf-8", errors="replace").read())
        lines = set()
        for i, line in enumerate(text.split("\n"), 1):
            for m in LINK.finditer(line):
                start = max(line.rfind(q, 0, m.start()) for q in ("'", '"', "`"))
                if MUTATION.search(line[start:m.end()]):
                    lines.add(i)
        for block in SCRIPT.finditer(text):
            for m in re.finditer(r"\$\{\s*token\b", block.group(1)):
                lines.add(line_of(text, block.start(1) + m.start()))
        for i in sorted(lines):
            print("%s:%d: the token rides a GET link to an action or a script: move that mutation to a POST form first (TD71), never drop the manual check while the action is reachable by GET: the core runs an @Action on GET without its token" % (path, i))
PY
)
    fi
    [ -n "$MV03_GET" ] && MV03_MATCHES="$MV03_GET"$'\n'"$MV03_MATCHES"
fi
COUNT=0; [ -n "$MV03_MATCHES" ] && COUNT=$(echo "$MV03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "MV03" "PASS" "CSRF token left to the framework in the MVC beans" 0
elif [ -n "$MV03_GET" ]; then emit "MV03" "WARN" "Manual CSRF token that also protects GET links or scripts: keep it until those mutations are POST forms (TD71), then leave the token to the framework" "$COUNT" "$MV03_MATCHES"
else emit "MV03" "WARN" "Manual CSRF token in an MVC bean, or securityTokenEnabled false or unset (the framework owns the token there)" "$COUNT" "$MV03_MATCHES"; fi

echo ""

# ─── Web / Config ────────────────────────────────────────
echo "CATEGORY: Web / Config"
check_grep "WB01" 'java\.sun\.com/xml/ns/javaee' "webapp/" "FAIL" "Old Java EE namespace -> Jakarta EE"
check_grep "WB02" '<application-class>' "webapp/WEB-INF/plugins/" "FAIL" "application-class -> CDI auto-discovery"
check_grep "WB03" 'ContextLoaderListener' "webapp/" "FAIL" "Spring ContextLoaderListener in web.xml"

# WB04: min-core-version below the declared Lutece 8 core (digits only: the core cuts the value at '-')
. "$SCRIPT_DIR/v8-floor.conf"
WB04_FLOOR="$V8_DECLARED_CORE"
WB04_MATCHES=""
if [ -d "webapp/WEB-INF/plugins/" ]; then
    WB04_MATCHES=$(grep -rn '<min-core-version>' webapp/WEB-INF/plugins/ --include="*.xml" 2>/dev/null | while IFS= read -r l; do
        v=$(printf '%s' "$l" | sed -n 's/.*<min-core-version>\([^<]*\)<\/min-core-version>.*/\1/p' | tr -d ' ')
        { [[ ! "$v" =~ ^[0-9]+(\.[0-9]+)*$ ]] || [ "$(printf '%s\n%s\n' "$WB04_FLOOR" "$v" | lp_version_sort | head -1)" != "$WB04_FLOOR" ]; } && echo "$l"
    done)
fi
COUNT=0; [ -n "$WB04_MATCHES" ] && COUNT=$(echo "$WB04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB04" "PASS" "min-core-version at $WB04_FLOOR or later" 0
else emit "WB04" "WARN" "min-core-version below $WB04_FLOOR, or not plain digits: set <min-core-version>$WB04_FLOOR</min-core-version>" "$COUNT" "$WB04_MATCHES"; fi

# WB05: a descriptor filter mapped under the JAX-RS application path never fires in v8.
# MainFilter.matchMapping compares the url-pattern to request.getServletPath( ), which is "/rest" for every call
# routed to the application mounted by @ApplicationPath( "/rest/" ). A pattern deeper than that can never match,
# so the filter is registered at startup and silently never runs.
# Replace it with a @NameBinding ContainerRequestFilter on the resource (patterns/rest-patterns.md 3 and 6).
WB05_MATCHES=""
if [ -d "webapp/WEB-INF/plugins/" ]; then
    WB05_MATCHES=$(for f in webapp/WEB-INF/plugins/*.xml; do [ -f "$f" ] && python3 -c 'import re, sys; t = re.sub(r"<!--.*?-->", lambda m: re.sub(r"[^\n]", " ", m.group()), open(sys.argv[1], encoding="utf-8", errors="replace").read(), flags=re.S); [print("%s:%d:%s" % (sys.argv[1], n, l.strip())) for n, l in enumerate(t.split("\n"), 1) if re.search(r"<url-pattern>/rest/.+</url-pattern>", l) and "<url-pattern>/rest/*</url-pattern>" not in l]' "$f"; done)
fi
COUNT=0; [ -n "$WB05_MATCHES" ] && COUNT=$(echo "$WB05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB05" "PASS" "no descriptor filter mapped under the JAX-RS application path" 0
else emit "WB05" "FAIL" "descriptor filter under /rest/ never fires: remove it and protect the resource with a @NameBinding ContainerRequestFilter carrying the same parameters (rest-patterns.md 3 and 6)" "$COUNT" "$WB05_MATCHES"; fi

# ST01: a project that declares CDI beans ships src/main/resources/META-INF/beans.xml; one with no CDI bean (a site, a
# library of static helpers) needs none.
if grep -rqE '@(ApplicationScoped|RequestScoped|SessionScoped|Dependent|Singleton|Named|Inject|Produces|Observes|ObservesAsync|Decorator|Interceptor)\b' src/ --include="*.java" 2>/dev/null; then
    check_file_exists "ST01" "src/main/resources/META-INF/beans.xml" "FAIL" "beans.xml exists"
else
    emit "ST01" "PASS" "No CDI bean in the project: no beans.xml needed" 0
fi
echo ""

# ─── Structure ───────────────────────────────────────────
echo "CATEGORY: Structure"

# ST02: final on a normal-scoped CDI class resolved by its concrete type (a @Dependent bean gets no proxy)
# final is legal when the bean is only resolved through its interface (cdi-patterns.md §1):
# core DAOs are @ApplicationScoped public final class. Only flag a class the code injects
# or selects by its concrete type, which is the case that cannot be proxied.
ST02_MATCHES=""
if [ -d "src/" ]; then
    ST02_MATCHES=$(fetched st02 st02_scan)
fi
COUNT=0; [ -n "$ST02_MATCHES" ] && COUNT=$(echo "$ST02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "ST02" "PASS" "No final keyword on a CDI class resolved by its concrete type" 0
else emit "ST02" "FAIL" "final keyword on a CDI class resolved by its concrete type" "$COUNT" "$ST02_MATCHES"; fi

# ST03: DAO classes without @ApplicationScoped
ST03_MATCHES=""
if [ -d "src/" ]; then
    # Only a file that DECLARES a DAO class: a line naming a DAO after the word class, such as
    # `select( IMyEntityDAO.class, … )` in a Home, is not one, and a Home facade is static by design with no scope.
    # An abstract DAO base is never a bean itself: its subclasses carry (or inherit) the scope. A test DAO (src/test)
    # is the test's own business.
    ST03_MATCHES=$(grep -rlE '^[[:space:]]*(public|final|public final)[[:space:]]+class[[:space:]]+[A-Za-z0-9_]*DAO\b' src/ --include="*.java" --exclude-dir=test 2>/dev/null | while read -r f; do
        grep -q 'public interface\|protected interface' "$f" 2>/dev/null && continue
        if ! grep -q '@ApplicationScoped\|@RequestScoped\|@SessionScoped\|@Dependent' "$f" 2>/dev/null; then
            echo "$f: DAO class without CDI scope annotation"
        fi
    done)
fi
COUNT=0; [ -n "$ST03_MATCHES" ] && COUNT=$(echo "$ST03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "ST03" "PASS" "DAO classes have CDI scope" 0
else emit "ST03" "FAIL" "DAO classes without @ApplicationScoped" "$COUNT" "$ST03_MATCHES"; fi

# ST04: a project type CDI must resolve while no class of the project assignable to it is a bean (java_checks.py).
ST04_MATCHES=$(jc st04)
COUNT=0; [ -n "$ST04_MATCHES" ] && COUNT=$(echo "$ST04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "ST04" "PASS" "Every project type CDI resolves has a bean" 0
else emit "ST04" "FAIL" "Project type resolved by CDI with no bean: the lookup is unsatisfied at deployment (give it a scope or a producer)" "$COUNT" "$ST04_MATCHES"; fi

# CS03: a @Controller comparing the request method with POST works around the core defect that runs an @Action on GET
# without its token; the core owns the fix, the e2e scenario carries core_defect (java_checks.py).
CS03_MATCHES=$(jc cs03)
COUNT=0; [ -n "$CS03_MATCHES" ] && COUNT=$(echo "$CS03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "CS03" "PASS" "No plugin guard around the core GET token defect" 0
else emit "CS03" "WARN" "Request method guard in a @Controller: the core runs an @Action on GET without its token, a core defect to report, not to work around; remove the guard, keep the e2e scenario with core_defect" "$COUNT" "$CS03_MATCHES"; fi

# WB10: PluginAdminPageJspBean.init sets the plugin from the plugin_name parameter only; a @RequestScoped bean is new on
# every request, so its inherited getPlugin( ) is null on each request that does not carry it (java_checks.py wb10).
WB10_MATCHES=$(jc wb10)
COUNT=0; [ -n "$WB10_MATCHES" ] && COUNT=$(echo "$WB10_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB10" "PASS" "No @RequestScoped bean relying on the inherited getPlugin( )" 0
else emit "WB10" "FAIL" "Inherited getPlugin( ) in a @RequestScoped bean: null on a request without plugin_name; override it with PluginService.getPlugin( PLUGIN_NAME )" "$COUNT" "$WB10_MATCHES"; fi

# WB11: the core XSS filter (sanitizeFilterMode) escapes every parameter under /jsp/admin and /jsp/site; a JspBean or an
# XPage escaping one again stores it escaped twice (java_checks.py wb11).
WB11_MATCHES=$(jc wb11)
COUNT=0; [ -n "$WB11_MATCHES" ] && COUNT=$(echo "$WB11_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB11" "PASS" "No request parameter escaped on top of the core XSS filter" 0
else emit "WB11" "WARN" "Request parameter HTML-escaped by hand: the core XSS filter already escapes it, the value is stored escaped twice; drop the escaping" "$COUNT" "$WB11_MATCHES"; fi

# DA03: a DAO reading or binding as a number a column its create scripts declare as text (java_checks.py da03).
DA03_MATCHES=$(jc da03)
COUNT=0; [ -n "$DA03_MATCHES" ] && COUNT=$(echo "$DA03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "DA03" "PASS" "DAO numeric reads and binds match the column types" 0
else emit "DA03" "WARN" "Number read or bound on a text column: align the column type with an upgrade script, or use get/setString" "$COUNT" "$DA03_MATCHES"; fi

# HM01: Homes in the v8 form: a plain Home is static, a portlet home is one the core can create by reflection (java_checks.py).
HM01_MATCHES=$(jc hm01)
COUNT=0; [ -n "$HM01_MATCHES" ] && COUNT=$(echo "$HM01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "HM01" "PASS" "Homes in the v8 form" 0
else emit "HM01" "FAIL" "Home not in the v8 form: plain Home static without getInstance( ); portlet home the core can create by reflection (public no-arg constructor, no @Inject field, a CDI bean not final)" "$COUNT" "$HM01_MATCHES"; fi

# HM02: a portlet home in the older form (hand-made singleton): it works, the modern form is a CDI bean (java_checks.py).
HM02_MATCHES=$(jc hm02)
COUNT=0; [ -n "$HM02_MATCHES" ] && COUNT=$(echo "$HM02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "HM02" "PASS" "Portlet homes in the modern form" 0
else emit "HM02" "WARN" "Portlet home in the older form: make it @ApplicationScoped, getInstance( ) returning CDI.current( ).select( X.class ).get( ) (rules/dao-patterns.md)" "$COUNT" "$HM02_MATCHES"; fi

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
# as converted when the work tree disagrees on carriage returns with HEAD and with what a checkout of HEAD writes
# (core.autocrlf=true turns LF into CRLF), whatever else changed in it: the files
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
        out_le=$(git cat-file --filters "HEAD:$f" 2>/dev/null | head -c 20000 | line_endings)
        work_le=$(head -c 20000 "$f" | line_endings)
        [ "$head_le" = "$work_le" ] || [ "$out_le" = "$work_le" ] || [ "$head_le" = "CR" ] || [ "$head_le" = "mixed" ] || [ "$head_le" = "none" ] || [ "$work_le" = "none" ] || echo "$f: $head_le in HEAD, $work_le now"
    done)
fi
COUNT=0; [ -n "$LE01_MATCHES" ] && COUNT=$(echo "$LE01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "LE01" "PASS" "No file had its line endings converted" 0
else emit "LE01" "FAIL" "Line endings converted: run $SCRIPT_DIR/restore-line-endings.sh . (it puts back each file's endings), the diff must show the migration, not the whole file" "$COUNT" "$LE01_MATCHES"; fi

# PT01: the core registers a plugin's portlet types only when an admin installs the plugin from the UI; a site
# whose database is created by the SQL scripts never has them, and the portlet cannot be created.
PT01_MATCHES=""
for f in $(find webapp/WEB-INF/plugins -maxdepth 1 -name '*.xml' 2>/dev/null); do
    for id in $(sed -n 's:.*<portlet-type-id>[[:space:]]*\([^<[:space:]]*\)[[:space:]]*</portlet-type-id>.*:\1:p' "$f"); do
        find src/sql -name '*.sql' -not -path '*/upgrade/*' 2>/dev/null | xargs grep -il "core_portlet_type" 2>/dev/null | xargs grep -l "'$id'" >/dev/null 2>&1 || PT01_MATCHES="$PT01_MATCHES$f: portlet type $id is not inserted into core_portlet_type by an install script
"
    done
done
PT01_MATCHES=$(printf '%s' "$PT01_MATCHES" | sed '/^$/d')
COUNT=$(printf '%s' "$PT01_MATCHES" | grep -c . || true)
if [ "$COUNT" -eq 0 ]; then emit "PT01" "PASS" "Every portlet type of plugin.xml is inserted by an install script" 0
else emit "PT01" "FAIL" "Portlet type missing from the install SQL: INSERT INTO core_portlet_type in src/sql/plugins/<plugin>/core (the core registers it only on a UI install), and in an upgrade script" "$COUNT" "$PT01_MATCHES"; fi

# XT01: the XSL machinery is not in the v8 core: XmlTransformerService and the core_style* tables live in
# plugin-xmltransformer. Code or SQL that still uses them needs that dependency declared — or, for a portlet, the
# port to HTML (XS01).
XT01_MATCHES=""
if ! grep -q '<artifactId>plugin-xmltransformer</artifactId>' pom.xml 2>/dev/null; then
    XT01_MATCHES=$({ grep -rnE '\b(XmlTransformerService|XslExportService)\b' src/ --include="*.java" 2>/dev/null || true; } | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(\*|//|/\*)' | cut -d: -f1 | sort -u | sed 's/$/: uses the XSL services that moved to plugin-xmltransformer, undeclared/')
    # Statements only: a leftover `-- Dumping data for table core_style` comment writes nothing. An upgrade statement
    # sitting in a changeset guarded by a precondition on those tables is a legacy step kept for the sites that have
    # them (XT03 checks the guard): it needs no dependency and is not counted here.
    SQL_XT=$({ python3 "$SCRIPT_DIR/sql_paths.py" . 2>/dev/null | sort | while read -r f; do
        awk 'BEGIN{IGNORECASE=1; g=0; found=0} /^--[[:space:]]*changeset/ {g=0} /^--[[:space:]]*precondition-sql-check/ {g=1}
             /^[[:space:]]*(INSERT[[:space:]]+INTO|UPDATE|DELETE[[:space:]]+FROM|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE)[[:space:]]+core_style/ && !g {found=1} END{exit !found}' "$f" && echo "$f"
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
    XT02_MATCHES=$(SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'PY'
import glob, re
owners = {}
import subprocess, os
run = subprocess.run(["python3", os.path.join(os.environ["SCRIPT_DIR"], "sql_paths.py"), "."], capture_output=True, encoding="utf-8", errors="replace").stdout.split()
for f in sorted(run):
    m = re.search(r"sql/plugins/([^/]+)(/modules/[^/]+)?/", f.replace("\\", "/"))
    if m:
        owners.setdefault(m.group(1) + (m.group(2) or ""), []).append(f)
def directive(f):
    for n, line in enumerate(open(f, encoding="utf-8", errors="replace")):
        s = line.strip().lstrip("\ufeff")
        if n >= 20 or (s and not s.startswith("--")):
            return False
        if re.search(r"^--\s*lutece\b.*\brunAfter:xmltransformer\b", s):
            return True
    return False
for owner, files in owners.items():
    writers = [f for f in files if "/upgrade/" not in f and re.search(r"(?mi)^[ \t]*(INSERT[ \t]+INTO|UPDATE|DELETE[ \t]+FROM)[ \t]+`?core_style", open(f, encoding="utf-8", errors="replace").read())]
    if writers and not any(directive(f) for f in files):
        print("%s: writes core_style* and no script of %s declares '-- lutece runAfter:xmltransformer' in its leading comments" % (writers[0], owner))
PY
)
fi
COUNT=0; [ -n "$XT02_MATCHES" ] && COUNT=$(echo "$XT02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "XT02" "PASS" "Install scripts writing core_style* run after xmltransformer" 0
else emit "XT02" "FAIL" "Install scripts write core_style* without runAfter:xmltransformer (rules/sql-liquibase.md)" "$COUNT" "$XT02_MATCHES"; fi

# XT03: an upgrade script that writes to core_style* runs on every site that migrates, including the ones where
# those tables are gone. Unguarded, its first statement stops the whole Liquibase update, the core's own upgrade
# included. The statement must sit in a changeset opened by a precondition on the presence of the tables.
XT03_MATCHES=""
if [ -d src/sql ]; then
    XT03_MATCHES=$(find src/sql -path '*/upgrade/*' -name '*.sql' | sort | while read -r f; do
        awk -v F="$f" 'BEGIN{IGNORECASE=1; guarded=0}
            /^--[[:space:]]*changeset/ {guarded=0}
            /^--[[:space:]]*precondition-sql-check/ {guarded=1}
            /^[[:space:]]*(INSERT[[:space:]]+INTO|UPDATE|DELETE[[:space:]]+FROM|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE)[[:space:]]+core_style/ && !guarded {print F": "NR": statement on core_style* in a changeset without precondition-sql-check"}' "$f"
    done)
fi
COUNT=0; [ -n "$XT03_MATCHES" ] && COUNT=$(echo "$XT03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "XT03" "PASS" "Upgrade statements on core_style* are guarded by a precondition" 0
else emit "XT03" "FAIL" "Upgrade statements on core_style* without a precondition on the tables (rules/sql-liquibase.md)" "$COUNT" "$XT03_MATCHES"; fi

# SQ03: adding AUTO_INCREMENT to a column whose rows include a 0 makes MariaDB and MySQL renumber that 0 into 1
# and fail on the duplicate key. Reference rows shipped with id 0 are common in older init scripts. The ALTER needs
# `SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO'` in the same changeset, restricted to dbms:mariadb,mysql.
SQ03_MATCHES=""; SQ03_ZERO=0
if [ -d src/sql ]; then
    SQ03_MATCHES=$(python3 - <<'PY'
import glob, re
STRING = r"'(?:[^']|'')*'"
def code(text):
    return re.sub(r"%s|--[^\n]*|/\*.*?\*/" % STRING, lambda m: m.group() if m.group().startswith("'") else re.sub(r"[^\n]", " ", m.group()), text, flags=re.S)
def split(values):
    return [v.strip() for v in re.split(r",(?=(?:[^']*'[^']*')*[^']*$)", values)]
install = code(" ".join(open(f, encoding="utf-8", errors="replace").read() for f in glob.glob("src/sql/**/*.sql", recursive=True) if "/upgrade/" not in f))
def created(table):
    m = re.search(r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?`?%s`?\s*\(" % table, install, re.I)
    if not m:
        return []
    depth, i = 1, m.end()
    while depth and i < len(install):
        depth += {"(": 1, ")": -1}.get(install[i], 0)
        i += 1
    cols = re.split(r",(?![^()]*\))", install[m.end():i - 1])
    return [c.split()[0].strip("`").lower() for c in cols if c.strip() and not re.match(r"\s*(PRIMARY|KEY|CONSTRAINT|UNIQUE|INDEX|FOREIGN)\b", c, re.I)]
def zero(table, column):
    for ins in re.finditer(r"INSERT\s+INTO\s+`?%s`?\s*(\(([^)]*)\))?\s*VALUES\s*((?:%s|[^;'])*)" % (table, STRING), install, re.S | re.I):
        cols = [c.strip().strip("`").lower() for c in ins.group(2).split(",")] if ins.group(2) else created(table)
        if column not in cols:
            continue
        for row in re.findall(r"\(((?:%s|[^()'])*)\)" % STRING, ins.group(3)):
            vals = split(row)
            if len(vals) == len(cols) and vals[cols.index(column)].strip("'") == "0":
                return True
    return False
for f in sorted(glob.glob("src/sql/**/upgrade/**/*.sql", recursive=True)):
    raw = open(f, encoding="utf-8", errors="replace").read()
    bounds = [0] + [m.start() for m in re.finditer(r"(?mi)^--\s*changeset\b", raw)] + [len(raw)]
    for start, end in zip(bounds, bounds[1:]):
        body = code(raw[start:end])
        if re.search(r"SET\s+(?:SESSION\s+)?sql_mode\s*=[^;]*NO_AUTO_VALUE_ON_ZERO", body, re.I):
            continue
        for m in re.finditer(r"ALTER\s+TABLE\s+`?(\w+)`?\s+(?:MODIFY(?:\s+COLUMN)?\s+`?(\w+)`?|CHANGE(?:\s+COLUMN)?\s+`?\w+`?\s+`?(\w+)`?)[^;]*AUTO_INCREMENT", body, re.I):
            table, column = m.group(1).lower(), (m.group(2) or m.group(3)).lower()
            line = raw[:start + m.start()].count("\n") + 1
            print("%s: %d: AUTO_INCREMENT added to %s without NO_AUTO_VALUE_ON_ZERO in the changeset" % (f, line, table))
            if zero(table, column):
                print("ZERO %s.%s: the install data ships a row with %s 0 — this upgrade fails on every site installed with it" % (table, column, column))
PY
)
    if printf '%s' "$SQ03_MATCHES" | grep -q '^ZERO '; then SQ03_ZERO=1; SQ03_MATCHES=$(printf '%s' "$SQ03_MATCHES" | sed 's/^ZERO //'); fi
fi
COUNT=0; [ -n "$SQ03_MATCHES" ] && COUNT=$(echo "$SQ03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ03" "PASS" "No AUTO_INCREMENT added without NO_AUTO_VALUE_ON_ZERO" 0
elif [ "$SQ03_ZERO" -eq 1 ]; then emit "SQ03" "FAIL" "AUTO_INCREMENT added to a table shipped with an id 0, without NO_AUTO_VALUE_ON_ZERO (rules/sql-liquibase.md)" "$COUNT" "$SQ03_MATCHES"
else emit "SQ03" "WARN" "AUTO_INCREMENT added without NO_AUTO_VALUE_ON_ZERO: fails on a site whose older data holds an id 0 (rules/sql-liquibase.md)" "$COUNT" "$SQ03_MATCHES"; fi

# CS02: ContentService no longer extends AbstractCacheableService in v8: initCache/getFromCache/putInCache on a
# content service do not compile. The cache, if still wanted, is a service of its own (lutece-cache skill).
CS02_MATCHES=""
if [ -d "src/" ]; then
    CS02_MATCHES=$({ grep -rl 'extends ContentService\b' src/ --include="*.java" 2>/dev/null || true; } | while read -r f; do
        python3 - "$f" <<'PY'
import re, sys
f = sys.argv[1]
t = re.sub(r"/\*.*?\*/|//[^\n]*", lambda m: re.sub(r"[^\n]", " ", m.group()), open(f, encoding="utf-8", errors="replace").read(), flags=re.S)
own = set(re.findall(r"(?m)^\s*(?:public|protected|private)[^=;(]*\s(initCache|getFromCache|putInCache)\s*\(", t))
calls = [m for m in re.finditer(r"(?:^|[^.\w]|super\.)(?:this\.)?(initCache|getFromCache|putInCache)\s*\(", t, re.M)
         if m.group(1) not in own or m.group(0).startswith("super.")]
calls = [m for m in calls if not re.match(r"(?m)^\s*(?:public|protected|private)[^=;(]*$", t[t.rfind("\n", 0, m.start()) + 1:m.start()])]
if calls:
    print("%s:%d: content service using the cache methods v8 removed from ContentService" % (f, t[:calls[0].start()].count("\n") + 1))
PY
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
# stub, and the back office cannot create an XSL portlet whose type is not
# DOCUMENT* (MANDATORY_FIELDS, whatever is installed). Port per mvc-patterns.md §10:
# extend PortletHtmlContent, implement getHtmlContent(), delete the XSL and the core_style rows.
# lutece-core is left out: it owns the portlet base classes, PortletHtmlContent included.
XS01_MATCHES=""
if [ -d "src/" ] && ! grep -q "<packaging>lutece-core</packaging>" pom.xml 2>/dev/null; then
    XS01_MATCHES=$({ grep -rln --exclude-dir=test 'getXmlDocument\|public String getXml(' src/ --include="*.java" 2>/dev/null || true; } | while read -r f; do
        grep -q 'extends PortletHtmlContent' "$f" 2>/dev/null && continue
        grep -q 'class .*Portlet\b' "$f" 2>/dev/null || continue
        if grep -q '<artifactId>plugin-xmltransformer</artifactId>' pom.xml 2>/dev/null; then
            CLS=$(basename "$f" .java)
            cat webapp/WEB-INF/plugins/*.xml 2>/dev/null | tr -d '\n\r\t' | grep -oE "<portlet-class>[^<]*\.${CLS}Home *</portlet-class> *<portlet-type-id>DOCUMENT[A-Z_]*</portlet-type-id>" | grep -q . && continue
        fi
        echo "$f: portlet still rendered by XSL, port it to PortletHtmlContent"
    done)
fi
COUNT=0; [ -n "$XS01_MATCHES" ] && COUNT=$(echo "$XS01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "XS01" "PASS" "No portlet left on XSL rendering" 0
else emit "XS01" "FAIL" "Portlet still rendered by XSL (port to HTML, mvc-patterns.md 10)" "$COUNT" "$XS01_MATCHES"; fi

# SQ01: every SQL file of the folders Liquibase reads (sql_paths.py --folders) must start with the Liquibase header.
# v7 installed through Ant and ran headerless files; v8 installs through plugin-liquibase only, which drops them
# without a log line (rules/sql-liquibase.md). An archive outside those folders is never run and needs none.
SQ01_MATCHES=""
if [ -d "src/sql" ]; then
    SQ01_MATCHES=$(python3 "$SCRIPT_DIR/sql_paths.py" . --folders | while read -r f; do
        grep -m1 -v '^[[:space:]]*$' "$f" | grep -q 'liquibase formatted sql' || echo "$f: no '-- liquibase formatted sql' first line"
    done)
fi
COUNT=0; [ -n "$SQ01_MATCHES" ] && COUNT=$(echo "$SQ01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ01" "PASS" "Every SQL file carries the Liquibase header" 0
else emit "SQ01" "FAIL" "SQL files Liquibase will ignore (rules/sql-liquibase.md)" "$COUNT" "$SQ01_MATCHES"; fi

# SQ02: what the creation script gained since the last commit, an existing site never gets. A column or a table
# added to create_db_*.sql is green on every fresh bench and breaks the first migrated site (a v8 DAO writing a
# column the v7 base does not have). Each addition needs an
# upgrade script under src/sql/**/upgrade/ that creates it, with a real precondition (rules/sql-liquibase.md).
SQ02_MATCHES=""
if [ -d "src/sql" ] && git rev-parse -q --verify HEAD >/dev/null 2>&1; then
    columns() { awk 'BEGIN{IGNORECASE=1} /CREATE TABLE/{t=$0; sub(/.*CREATE TABLE[[:space:]]+(IF NOT EXISTS[[:space:]]+)?/,"",t); sub(/[[:space:]]*\(.*/,"",t); gsub(/`/,"",t); in_t=1; next}
        in_t && /^[[:space:]]*\)/{in_t=0} in_t && /^[[:space:]]*--/{next} in_t{c=$1; gsub(/[`,]/,"",c); if (c!="" && c !~ /^(PRIMARY|KEY|CONSTRAINT|UNIQUE|INDEX|FOREIGN|\)|\()$/) print tolower(t)"."tolower(c)}' "$@" 2>/dev/null | LC_ALL=C sort -u; }
    SQ02_MATCHES=$(find src/sql -path '*/plugin/*' -name 'create_db_*.sql' | sort | while read -r f; do
        git cat-file -e "HEAD:$f" 2>/dev/null || continue
        LC_ALL=C comm -13 <(columns <(git show "HEAD:$f")) <(columns "$f") | while IFS=. read -r table col; do
            # Covered when an upgrade script adds the column, or (re)creates the table WITH it — an older
            # upgrade that created the table without the column proves nothing.
            if python3 -c 'import glob, re, sys; t, c = sys.argv[1:3]; sys.exit(0 if any(re.search(r"ALTER\s+TABLE\s+`?%s`?\s(?:[^;]*?,)?\s*ADD\s+(?:COLUMN\s+)?(?:IF\s+NOT\s+EXISTS\s+)?`?%s`?\b" % (re.escape(t), re.escape(c)), re.sub(r"--[^\n]*", "", open(f, encoding="utf-8", errors="replace").read()), re.I) for f in glob.glob("src/sql/**/update_db_*.sql", recursive=True)) else 1)' "$table" "$col"; then continue; fi
            if grep -rliE "CREATE TABLE (IF NOT EXISTS )?\`?$table\`?\b" src/sql --include='update_db_*.sql' 2>/dev/null | { xargs cat 2>/dev/null || true; } | columns | grep -qx "$table.$col"; then continue; fi
            echo "$f: $table.$col is new here and no upgrade script under src/sql/**/upgrade/ adds it"
        done
    done)
fi
COUNT=0; [ -n "$SQ02_MATCHES" ] && COUNT=$(echo "$SQ02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ02" "PASS" "Every column or table the creation script gained has its upgrade script" 0
else emit "SQ02" "FAIL" "Schema gained by create_db without an upgrade script for existing sites (rules/sql-liquibase.md)" "$COUNT" "$SQ02_MATCHES"; fi

# TL01: ThreadLocal must be cleared with remove() in a finally block, never reassigned.
# Reassigning keeps one entry per pooled thread for the whole application lifetime.
TL01_MATCHES=""
if [ -d "src/" ]; then
    TL01_MATCHES=$({ grep -rlnE '\bThreadLocal\b' src/ --include="*.java" 2>/dev/null || true; } | while read -r f; do
        grep -q '\.remove( *)' "$f" 2>/dev/null && continue
        echo "$f: ThreadLocal never cleared with remove()"
    done)
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
    CS01_MATCHES=$(python3 - <<'PY'
import glob, re
def body(text, start):
    depth, i = 1, start
    while depth and i < len(text):
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        i += 1
    return text[start:i]
files = {}
for f in sorted(glob.glob("src/**/*.java", recursive=True)):
    if "/test/" in f:
        continue
    files[f] = re.sub(r"/\*.*?\*/|//[^\n]*", lambda m: re.sub(r"[^\n]", " ", m.group()), open(f, encoding="utf-8", errors="replace").read(), flags=re.S)
parent = {}
for f, text in files.items():
    m = re.search(r"\bclass\s+(\w+)\s+extends\s+(\w+)", text)
    if m:
        parent[m.group(1)] = (m.group(2), f)
def portlet_bean(cls, seen=()):
    up = parent.get(cls, (None,))[0]
    return up == "PortletJspBean" or (up in parent and up not in seen and portlet_bean(up, seen + (cls,)))
for cls, (up, f) in sorted(parent.items(), key=lambda x: x[1][1]):
    if not portlet_bean(cls):
        continue
    text = files[f]
    methods = {m.group(1): body(text, m.end()) for m in re.finditer(r"\b(\w+)\s*\([^)]*\)[^{;]*\{", text) if m.group(1) not in ("if", "for", "while", "switch", "catch", "synchronized")}
    guards = {n for n, b in methods.items() if re.search(r"\.validate\s*\(\s*request", b)}
    for m in re.finditer(r"public\s+String\s+(do\w+)\s*\([^)]*\)[^{]*\{", text):
        b = body(text, m.end())
        if not re.search(r"\.validate\s*\(\s*request", b) and not any(re.search(r"\b%s\s*\(" % g, b) for g in guards):
            print("%s:%d: %s() is public and validates no token (reachable or not, a public do* is a mutation entry)" % (f, text[:m.start()].count("\n") + 1, m.group(1)))
PY
)
fi
COUNT=0; [ -n "$CS01_MATCHES" ] && COUNT=$(echo "$CS01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "CS01" "PASS" "Portlet JspBean mutations carry a CSRF token" 0
else emit "CS01" "FAIL" "Portlet JspBean without CSRF token (mvc-patterns.md 11)" "$COUNT" "$CS01_MATCHES"; fi

# I18N01: a key of <plugin>_messages.properties is relative to the bundle, so it never repeats the plugin name.
# Writing <plugin>.message.x in <plugin>_messages.properties resolves as <plugin>.<plugin>.message.x and
# the message renders as an empty label (and a WARN in the log). The same grep catches a key appended without a newline, glued to
# the value of the line above, which corrupts both entries at once. A key whose full form (<plugin>.<plugin>.x) the code
# asks for is a sub-namespace named like the plugin (an entity called contact in plugin contact), not the mistake; a
# key nothing asks for in either form is dead, reported by I18N08, not renamed.
I18N01_MATCHES=""
if [ -d "src/java" ]; then
    I18N01_MATCHES=$(find src/java -name "*_messages*.properties" 2>/dev/null | while read -r f; do
        PLUGIN=$(basename "$f" | sed 's/_messages.*//')
        [ -n "$PLUGIN" ] || continue
        # The plugin name must be followed by a key and an '=': without that, a value ending with a sentence
        # such as "CSS style to apply to the links." is flagged as a key, which it is not.
        grep -nE "(^|[^A-Za-z0-9_.])$PLUGIN\.[A-Za-z0-9_.]*[A-Za-z0-9_] *=" "$f" 2>/dev/null | while read -r line; do
            key=$(printf '%s' "${line#*:}" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*=.*//')
            grep -rqF --include="*.html" --include="*.ftl" --include="*.java" --include="*.jsp" --include="*.xml" --include="*.sql" --include="*.js" "$PLUGIN.$key" webapp src 2>/dev/null && continue
            if printf '%s' "${line#*:}" | grep -qE "^[[:space:]]*$PLUGIN\."; then
                grep -rqE --include="*.html" --include="*.ftl" --include="*.java" --include="*.jsp" --include="*.xml" --include="*.sql" --include="*.js" "(^|[^A-Za-z0-9_.]|module\.[A-Za-z0-9_]+\.)$(printf '%s' "$key" | sed 's/\./\\./g')([^A-Za-z0-9_.]|\$)" webapp src 2>/dev/null || continue
            fi
            echo "$f:$line"
        done
    done)
fi
COUNT=0; [ -n "$I18N01_MATCHES" ] && COUNT=$(echo "$I18N01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N01" "PASS" "No i18n key repeating the plugin prefix" 0
else emit "I18N01" "FAIL" "i18n key repeats the plugin prefix (or glued to the line above): it never resolves (fix-i18n-bundles.py)" "$COUNT" "$I18N01_MATCHES"; fi
echo ""

# I18N02: a key a template or a message constant asks for, that no bundle of this plugin declares. Lutece then
# renders an empty label (and a WARN in the log) and nothing fails at build time. Unambiguous sources only: `#i18n{}` in the
# templates, the Java constants whose name says they hold a message key (MESSAGE_, INFO_, ERROR_, WARNING_, TITLE_,
# PROPERTY_PAGE_TITLE_), the page title and path keys of an XPage @Controller, the label tags of the plugin descriptor (feature, portlet type, daemon, description) and the
# name/description of the core_admin_right and core_portlet_type rows the SQL inserts. Bean names and CSRF action names are strings too, and are not keys,
# nor is a key the plugin's conf properties or its core_datastore rows declare (a property or a datastore key).
# Every grep here is `-a`: a bundle written in ISO-8859 counts as binary for grep, which then reports nothing and
# the check would silently pass — the same trap applies to any manual search in these files.
I18N02_MATCHES=""
[ -d "src/java" ] && I18N02_MATCHES=$(fetched i18n02 i18n02_scan)
COUNT=0; [ -n "$I18N02_MATCHES" ] && COUNT=$(echo "$I18N02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N02" "PASS" "Every i18n key the plugin asks for is declared" 0
else emit "I18N02" "WARN" "i18n key asked for but declared nowhere: an empty label on screen (and a WARN in the log)" "$COUNT" "$I18N02_MATCHES"; fi
echo ""

# ─── JSP ─────────────────────────────────────────────────
# SQ04: an INSERT into a core table without its column list. The core adds columns: a positional VALUES list then fails with "Column count doesn't match value count", Liquibase
# stops and the site never starts. Name the columns. An upgrade script already committed is released: it is left as it is.
SQ04_MATCHES=""
if [ -d "src/sql" ]; then
    SQ04_MATCHES=$(grep -rniE "INSERT +INTO +core_[a-z0-9_]+ +VALUES" src/sql --include="*.sql" 2>/dev/null | while IFS= read -r line; do
        f=${line%%:*}
        if echo "$f" | grep -qE "/upgrades?/" && git cat-file -e "HEAD:$f" 2>/dev/null; then continue; fi
        echo "$line"
    done)
fi
COUNT=0; [ -n "$SQ04_MATCHES" ] && COUNT=$(echo "$SQ04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ04" "PASS" "INSERTs into core tables name their columns" 0
else emit "SQ04" "FAIL" "INSERT into a core table without column list: breaks when the core adds a column. Name the columns in create_/init_ scripts (fresh installs only); a released update_ script is left as it is (rules/sql-liquibase.md: roll forward, no validCheckSum)" "$COUNT" "$SQ04_MATCHES"; fi
echo ""
SQ07_MATCHES=""
if [ -d src/sql ]; then
    SQ07_MATCHES=$(grep -rniE "^--[[:space:]]*validCheckSum" src/sql --include="*.sql" 2>/dev/null | grep -v "/prerun_db_[^/]*\.sql:")
fi
COUNT=0; [ -n "$SQ07_MATCHES" ] && COUNT=$(echo "$SQ07_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ07" "PASS" "No validCheckSum outside prerun_db_* scripts" 0
else emit "SQ07" "WARN" "validCheckSum outside a prerun_db_* script: a shipped changeset body was edited. Keep the directive (a site that replays the file fails without it); change the script by appending a changeset (rules/sql-liquibase.md)" "$COUNT" "$SQ07_MATCHES"; fi
echo ""
# SQ08: an install script shipped in the war without the Liquibase header. The lutece-maven-plugin reports every
# plugins/<p>/(plugin|core)/(create|init)_*.sql of WEB-INF/sql that is not a changeset; plugin-liquibase then refuses
# to start with safeRun=true. src/sql is SQ01's; this looks at webapp/WEB-INF/sql, copied into the war as it is.
SQ08_MATCHES=""
if [ -d webapp/WEB-INF/sql ]; then
    SQ08_MATCHES=$(find webapp/WEB-INF/sql -type f -name "*.sql" 2>/dev/null | grep -E "/plugins/[^/]+/(modules/[^/]+/)?(plugin|core)/(create|init)_[^/]*\.sql$" | sort | while read -r f; do
        grep -m1 -v '^[[:space:]]*$' "$f" | grep -q "liquibase formatted sql" || echo "$f"
    done)
fi
COUNT=0; [ -n "$SQ08_MATCHES" ] && COUNT=$(echo "$SQ08_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ08" "PASS" "No untagged install script under webapp/WEB-INF/sql" 0
else emit "SQ08" "FAIL" "Install script in webapp/WEB-INF/sql without the Liquibase header: plugin-liquibase refuses to start in safeRun (add the header, move it to src/sql, or remove it)" "$COUNT" "$SQ08_MATCHES"; fi

# SQ09: a SQL directory named after no component of the project. plugin-liquibase reads sql/plugins/<plugin>/ and
# sql/plugins/<plugin>/modules/<module>/ as the scripts of the component <plugin> or <plugin>-<module>; a name no
# descriptor of the project declares is a packaging fault (LUT-33232): the scripts are versioned as that other
# component's, and startup aborts with safeRun=true on a site that does not carry it. LuteceRunAfterComparator orders a
# component's scripts after another's with -- lutece runAfter:<plugin>, from its own directory.
SQ09_MATCHES=""
if [ -d src/sql/plugins ] && ls webapp/WEB-INF/plugins/*.xml >/dev/null 2>&1; then
    SQ09_NAMES=$(sed -n 's:.*<name>[[:space:]]*\([^<[:space:]]*\)[[:space:]]*</name>.*:\1:p' webapp/WEB-INF/plugins/*.xml 2>/dev/null | sort -u)
    SQ09_MATCHES=$(find src/sql/plugins -type f -name "*.sql" 2>/dev/null | sed -n 's:^src/sql/plugins/\([^/]*\)/modules/\([^/]*\)/.*:\1-\2:p; t; s:^src/sql/plugins/\([^/]*\)/.*:\1:p' | sort -u | while read -r c; do
        printf '%s\n' "$SQ09_NAMES" | grep -qxF "$c" || echo "src/sql/plugins: '$c' is the name of no <name> in webapp/WEB-INF/plugins/*.xml"
    done)
fi
COUNT=0; [ -n "$SQ09_MATCHES" ] && COUNT=$(echo "$SQ09_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ09" "PASS" "Every SQL directory is named after a component of the project" 0
else emit "SQ09" "FAIL" "SQL directory named after no plugin of the project: plugin-liquibase versions its scripts as that other component's (LUT-33232), and aborts the startup in safeRun on a site that does not carry it. Put them in the project's own directory (<plugin>, a module as <plugin>/modules/<module>); to run after another plugin's scripts, write -- lutece runAfter:<plugin> in the leading comments" "$COUNT" "$SQ09_MATCHES"; fi

# SQ10: a changeset without any SQL statement. Liquibase validates the whole changelog before running it: an empty
# formatted-sql changeset fails with "'sql' is required" and no changeset of the site runs, whatever failOnError.
SQ10_MATCHES=""
if [ -d src/sql ]; then
    SQ10_MATCHES=$(find src/sql -type f -name "*.sql" 2>/dev/null | sort | while read -r f; do
        head -1 "$f" | grep -q "liquibase formatted sql" || continue
        awk -v f="$f" '
            /^--[[:space:]]*changeset[[:space:]]/ { if (cs != "" && !body) print f ": " cs; cs = $0; body = 0; next }
            /^[[:space:]]*--/ || /^[[:space:]]*$/ { next }
            { body = 1 }
            END { if (cs != "" && !body) print f ": " cs }' "$f"
    done)
fi
COUNT=0; [ -n "$SQ10_MATCHES" ] && COUNT=$(echo "$SQ10_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ10" "PASS" "Every changeset carries SQL" 0
else emit "SQ10" "FAIL" "Changeset without SQL: Liquibase validation fails and no changeset of the site runs (remove the changeset or give it its statements)" "$COUNT" "$SQ10_MATCHES"; fi
echo ""

# SQ11-SQ12: a changeset identity reused in an upgrade script. Liquibase tracks (author:id, file): the same identity
# twice in one file fails the validation (SQ11). A body changed under an identity the last tag or the last commit
# carries (a rebase that took the id of another changeset, an edited release) never reaches the bases that ran it, and
# fails with ValidationFailedException where the file is replayed (SQ12); the rules allow it only for damage that
# cannot be undone afterwards, said in the changeset comment.
SQ11_MATCHES=""; SQ12_MATCHES=""
if [ -d src/sql ]; then
    SQ1X=$(python3 - <<'PY'
import glob, re, subprocess
def changesets(text):
    out, cur = [], None
    for line in text.splitlines():
        m = re.match(r"--\s*changeset\s+(\S+)", line)
        if m:
            cur = [m.group(1), []]
            out.append(cur)
        elif cur and line.strip() and not line.lstrip().startswith("--"):
            cur[1].append(" ".join(line.split()))
    return [(i, "\n".join(b)) for i, b in out]
def git(*args):
    r = subprocess.run(["git", *args], capture_output=True, encoding="utf-8", errors="replace")
    return r.stdout if r.returncode == 0 else None
tag = (git("describe", "--tags", "--abbrev=0") or "").strip()
for f in sorted(glob.glob("src/sql/**/update_*.sql", recursive=True)):
    text = open(f, encoding="utf-8", errors="replace").read()
    if "liquibase formatted sql" not in text.split("\n", 1)[0]:
        continue
    now = changesets(text)
    seen = {}
    for ident, body in now:
        if ident in seen:
            print("SQ11 %s: changeset %s declared twice" % (f, ident))
        seen.setdefault(ident, body)
    told = set()
    for ref in (tag, "HEAD"):
        old = git("show", "%s:%s" % (ref, f)) if ref else None
        for ident, body in dict(changesets(old or "")).items():
            if ident in seen and seen[ident] != body and ident not in told:
                told.add(ident)
                print("SQ12 %s: changeset %s has another body than in %s" % (f, ident, ref))
PY
)
    SQ11_MATCHES=$(echo "$SQ1X" | sed -n 's/^SQ11 //p')
    SQ12_MATCHES=$(echo "$SQ1X" | sed -n 's/^SQ12 //p')
fi
COUNT=0; [ -n "$SQ11_MATCHES" ] && COUNT=$(echo "$SQ11_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then CRASH_HOLD=true emit "SQ11" "PASS" "No changeset identity reused in the upgrade scripts" 0
else CRASH_HOLD=true emit "SQ11" "FAIL" "Changeset identity declared twice in one file: Liquibase refuses the changelog; give the second one a new id" "$COUNT" "$SQ11_MATCHES"; fi
COUNT=0; [ -n "$SQ12_MATCHES" ] && COUNT=$(echo "$SQ12_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "SQ12" "PASS" "No released or committed changeset of the upgrade scripts rewritten" 0
else emit "SQ12" "WARN" "Released or committed changeset with another body (an id taken over in a rebase?): a base that ran it never gets the new body; add a new changeset, or say in its comment why the edit cannot wait (rules/sql-liquibase.md)" "$COUNT" "$SQ12_MATCHES"; fi
echo ""

# I18N03: a key the default bundle carries and _fr does not, or the reverse (the two languages the core ships): the
# missing language falls back, a French user reads the English text, nothing logs it. A key nothing uses is I18N08's:
# removing it is the fix, not translating it. I18N04: the other languages.
I18N03_MATCHES=""
if [ -d "src/java" ]; then
    I18N03_MATCHES=$(fetched i18n03 i18n03_scan)
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
)
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
)
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
    done)
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
)
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
)
fi
COUNT=0; [ -n "$I18N07_MATCHES" ] && COUNT=$(echo "$I18N07_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N07" "PASS" "No common spelling error in French values" 0
else emit "I18N07" "WARN" "French value with a spelling error (Êtes-vous, sûr) or a leftover class name" "$COUNT" "$I18N07_MATCHES"; fi

# I18N08: a key of the default bundle nothing uses (generator leftovers the translators keep paying for).
# i18n_unused.py has the exact rules: runtime-read families, stems built in Java or templates, other repositories.
I18N08_MATCHES=""
[ -d "src/java" ] && { I18N08_MATCHES=$(fetched i18n08 i18n08_scan) || true; }
COUNT=0; [ -n "$I18N08_MATCHES" ] && COUNT=$(echo "$I18N08_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "I18N08" "PASS" "Every bundle key is used" 0
else emit "I18N08" "WARN" "Bundle key no file names: remove it in every language (fix-i18n-bundles.py --drop <keys file>), unless built at runtime" "$COUNT" "$I18N08_MATCHES"; fi
echo ""

# WB06: an <admin-feature> whose <feature-group> is not the group its install SQL gives it. Reinstalling the plugin from
# the Plugins screen rebuilds its rights from the descriptor (Plugin.install -> registerRights), so the feature moves
# (CONTENT -> NULL, then shown in the last menu group). A NULL group in both is consistent.
WB06_MATCHES=""
if [ -d "webapp/WEB-INF/plugins" ]; then
    WB06_MATCHES=$(python3 - <<'PY'
import glob, re
STRING = r"'(?:[^']|'')*'"
def uncommented(text):
    return re.sub(r"%s|--[^\n]*|/\*.*?\*/" % STRING, lambda m: m.group() if m.group().startswith("'") else " ", text, flags=re.S)
sql = " ".join(uncommented(open(f, encoding="utf-8", errors="replace").read()) for f in glob.glob("src/sql/**/*.sql", recursive=True) if "/upgrade/" not in f)
def tuples(values):
    return re.findall(r"\(((?:%s|[^()'])*)\)" % STRING, values)
def sql_group(fid):
    for ins in re.finditer(r"INSERT\s+INTO\s+core_admin_right\s*\(([^)]*)\)\s*VALUES\s*((?:%s|[^;'])*);" % STRING, sql, re.S | re.I):
        cols = [c.strip().strip("`").lower() for c in ins.group(1).split(",")]
        for row in tuples(ins.group(2)):
            vals = [v.strip().strip("'") for v in re.split(r",(?=(?:[^']*'[^']*')*[^']*$)", row)]
            if vals and vals[cols.index("id_right") if "id_right" in cols else 0] == fid and "id_feature_group" in cols and len(vals) == len(cols):
                g = vals[cols.index("id_feature_group")]
                return None if g.upper() == "NULL" else g
    return None
for f in sorted(glob.glob("webapp/WEB-INF/plugins/*.xml")):
    text = re.sub(r"<!--.*?-->", "", open(f, encoding="utf-8", errors="replace").read(), flags=re.S)
    for m in re.finditer(r"<admin-feature>(.*?)</admin-feature>", text, re.S):
        fid = re.search(r"<feature-id>\s*([^<\s]+)", m.group(1))
        fid = fid.group(1) if fid else "?"
        xml = re.search(r"<feature-group>\s*([^<\s]+)", m.group(1))
        want = sql_group(fid)
        if want and (not xml or xml.group(1) != want):
            print("%s: admin-feature %s: the install SQL puts it in %s, the descriptor says %s: a reinstall rebuilds it from the descriptor" % (f, fid, want, xml.group(1) if xml else "nothing"))
PY
)
fi
WB07_MATCHES=""
if [ -d "webapp/WEB-INF/plugins" ]; then
    WB07_MATCHES=$(python3 - <<'PY'
import glob, re
for f in sorted(glob.glob("webapp/WEB-INF/plugins/*.xml")):
    text = open(f, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"<admin-feature>(.*?)</admin-feature>", text, re.S):
        if re.search(r"<feature-icon-url>\s*[^<\s]", m.group(1)) and "<icon-url>" not in m.group(1):
            fid = re.search(r"<feature-id>\s*([^<\s]+)", m.group(1))
            print("%s: admin-feature %s carries its icon in <feature-icon-url>, which the core digester ignores (it reads <icon-url>): a reinstall resets icon_url to NULL" % (f, fid.group(1) if fid else "?"))
PY
)
fi
# WB08: an <icon-url> of the descriptor naming an image no webapp carries (the project, the assembled site, the core)
# while the project ships an image of that name elsewhere: a mistyped path, the plugin shows the generic icon. An icon
# no webapp carries at all (a v7 default) is left alone: the core falls back to apps.svg.
WB08_MATCHES=""
if [ -d "webapp/WEB-INF/plugins" ]; then
    WB08_MATCHES=$(python3 - <<'PY'
import glob, os, re
roots = ["webapp"] + [d for d in glob.glob("target/*/") if os.path.isdir(os.path.join(d, "WEB-INF"))]
roots.append(os.path.expanduser("~/.lutece-references/lutece-core/webapp"))
for f in sorted(glob.glob("webapp/WEB-INF/plugins/*.xml")):
    text = open(f, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"<(?:feature-)?icon-url>\s*([^<\s]+)\s*</", text):
        path = m.group(1)
        if "/" not in path or not re.search(r"\.(png|svg|gif|jpe?g|ico|webp)$", path, re.I):
            continue
        if not any(os.path.isfile(os.path.join(r, path.lstrip("/"))) for r in roots):
            shipped = [os.path.relpath(p, "webapp") for p in glob.glob("webapp/**/" + os.path.basename(path), recursive=True)]
            if shipped:
                print("SHIPPED %s:%d: icon %s is carried by no webapp: the project ships it at %s" % (f, text[:m.start()].count("\n") + 1, path, shipped[0]))
PY
)
fi
COUNT=0; [ -n "$WB06_MATCHES" ] && COUNT=$(echo "$WB06_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB06" "PASS" "Every admin feature declares its menu group" 0
else emit "WB06" "FAIL" "admin-feature whose descriptor group differs from its install SQL: a reinstall moves it" "$COUNT" "$WB06_MATCHES"; fi
COUNT=0; [ -n "$WB07_MATCHES" ] && COUNT=$(echo "$WB07_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB07" "PASS" "Admin feature icons survive a reinstall" 0
else emit "WB07" "WARN" "Icon in <feature-icon-url>: the core digester reads <icon-url>" "$COUNT" "$WB07_MATCHES"; fi
WB08_WARN=$(echo "$WB08_MATCHES" | sed -n 's/^SHIPPED //p')
COUNT=0; [ -n "$WB08_WARN" ] && COUNT=$(echo "$WB08_WARN" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB08" "PASS" "Every descriptor icon the project ships is named by its path" 0
else emit "WB08" "WARN" "Descriptor icon path the project does not ship while it ships that image elsewhere (a typo): the plugin shows the generic icon" "$COUNT" "$WB08_WARN"; fi

# WB09: a plugin declaring an admin right with the core's CORE_ prefix shares that id with the core: a core upgrade that
# removes its own right removes the plugin's too.
WB09_MATCHES=""
if [ -d webapp/WEB-INF/plugins ] && ! grep -q "<packaging>lutece-core</packaging>" pom.xml 2>/dev/null; then
    WB09_MATCHES=$(grep -HnoE "<feature-id>CORE_[A-Z0-9_]+</feature-id>" webapp/WEB-INF/plugins/*.xml 2>/dev/null | sed 's#<feature-id>\(.*\)</feature-id>#\1: a plugin right named like a core one (use the plugin prefix, rename existing rows with an UPDATE changeset)#')
fi
COUNT=0; [ -n "$WB09_MATCHES" ] && COUNT=$(echo "$WB09_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB09" "PASS" "No plugin right reuses the core CORE_ prefix" 0
else emit "WB09" "WARN" "Plugin right with the CORE_ prefix: a core upgrade removing its own right removes this one" "$COUNT" "$WB09_MATCHES"; fi
echo ""

# WB12: the admin menu links a feature as `url?plugin_name=…` (core adminHeader.ftl, since 2007: a feature url is a bare
# JSP, and plugin_name is how PluginAdminPageJspBean.init loads the plugin). A feature url that carries a query string
# gets a second `?` and loses its parameters (the view of an MVC controller: "No method found to process view").
# Read in the descriptor and in the core_admin_right rows.
WB12_MATCHES=""
if [ -d webapp/WEB-INF/plugins ] || [ -d src/sql ]; then
    WB12_MATCHES=$({ grep -HnoE "<feature-url>[^<]*\?[^<]*</feature-url>" webapp/WEB-INF/plugins/*.xml 2>/dev/null | sed 's#$#: the admin menu appends ?plugin_name=, the url gets two ?#'
        python3 - <<'EOF2'
import glob, re
for f in sorted(glob.glob("src/sql/**/*.sql", recursive=True)):
    text = open(f, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"(?is)insert\s+into\s+core_admin_right\s*\(([^)]*)\)\s*values\s*(.*?);", text):
        cols = [c.strip().lower() for c in m.group(1).split(",")]
        if "admin_url" not in cols:
            continue
        for row in re.findall(r"\(((?:'(?:[^']|'')*'|[^()'])*)\)", m.group(2)):
            vals = [v.strip() for v in re.findall(r"'(?:[^']|'')*'|[^,]+", row) if v.strip()]
            i = cols.index("admin_url")
            if i < len(vals) and "?" in vals[i]:
                print("%s:%d: admin_url %s: the admin menu appends ?plugin_name=, the url gets two ?" % (f, text[:m.start()].count("\n") + 1, vals[i]))
EOF2
    } 2>/dev/null)
fi
COUNT=0; [ -n "$WB12_MATCHES" ] && COUNT=$(echo "$WB12_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB12" "PASS" "Admin feature urls carry no query string" 0
else emit "WB12" "FAIL" "Admin feature url with a query string: the menu appends ?plugin_name= and the url gets two ?; point the feature at the bare JSP and make that view the defaultView" "$COUNT" "$WB12_MATCHES"; fi
echo ""

# WB13: the install SQL and the descriptor give an admin feature a different url or icon: a fresh install shows the
# SQL row, a reinstall from the Plugins screen rebuilds the row from the descriptor (Plugin.install -> registerRights).
# WB14: an icon written as Tabler classes (ti ti-x) that tabler-icons.min.css of the core does not define: an empty glyph.
WB13_MATCHES=""; WB14_MATCHES=""
if [ -d webapp/WEB-INF/plugins ] || [ -d src/sql ]; then
    WB1314=$(SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'EOF2'
import glob, os, re, sys
sys.path.insert(0, os.environ["SCRIPT_DIR"])
from admin_rights import uncommented, updates
rows = {}
for f in sorted(glob.glob("src/sql/**/*.sql", recursive=True)):
    if re.search(r"/upgrades?/", f):
        continue
    text = uncommented(open(f, encoding="utf-8", errors="replace").read())
    steps = []
    for m in re.finditer(r"(?is)insert\s+into\s+core_admin_right\s*\(([^)]*)\)\s*values\s*(.*?);", text):
        cols = [c.strip().lower() for c in m.group(1).split(",")]
        for row in re.findall(r"\(((?:'(?:[^']|'')*'|[^()'])*)\)", m.group(2)):
            vals = [v.strip().strip("'") for v in re.findall(r"'(?:[^']|'')*'|[^,]+", row) if v.strip()]
            if len(vals) == len(cols) and "id_right" in cols:
                steps.append((m.start(), vals[cols.index("id_right")], dict(zip(cols, vals)), None))
    steps += [(offset, fid, None, sets) for offset, fid, sets in updates(text)]
    for offset, fid, row, sets in sorted(steps, key=lambda s: s[0]):
        line = text[:offset].count("\n") + 1
        if row is not None:
            rows[fid] = (f, line, row)
        elif fid in rows:
            row = rows.pop(fid)[2]
            row.update({k: v for k, v in sets.items() if k != "id_right"})
            rows[sets.get("id_right", fid)] = (f, line, row)
css = os.path.expanduser(os.environ.get("LUTECE_REFERENCES", "~/.lutece-references")) + "/lutece-core/webapp/themes/shared/css/tabler-icons.min.css"
icons = set(re.findall(r"\.ti-([a-z0-9-]+):before", open(css, encoding="utf-8", errors="replace").read())) if os.path.isfile(css) else set()
def unknown(value):
    m = re.fullmatch(r"\s*ti\s+ti-([a-z0-9-]+)\s*", value or "")
    return icons and m and m.group(1) not in icons
for fid, (f, line, row) in sorted(rows.items()):
    if unknown(row.get("icon_url")):
        print("WB14 %s:%d: %s icon_url %s: no such Tabler icon (tabler-icons.min.css of the core)" % (f, line, fid, row["icon_url"]))
for f in sorted(glob.glob("webapp/WEB-INF/plugins/*.xml")):
    text = open(f, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"<admin-feature>(.*?)</admin-feature>", text, re.S):
        line = text[:m.start()].count("\n") + 1
        get = lambda tag: (re.search(r"<%s>\s*([^<]*?)\s*</%s>" % (tag, tag), m.group(1)) or [None, None])[1]
        fid, url, icon = get("feature-id"), get("feature-url"), get("icon-url")
        if unknown(icon):
            print("WB14 %s:%d: %s icon-url %s: no such Tabler icon (tabler-icons.min.css of the core)" % (f, line, fid, icon))
        if fid not in rows:
            continue
        sf, sl, row = rows[fid]
        for col, val, tag in (("admin_url", url, "feature-url"), ("icon_url", icon, "icon-url")):
            if col in row and val is not None and row[col].upper() != "NULL" and row[col] != val:
                print("WB13 %s:%d: %s %s %s, the descriptor %s %s (%s:%d): a reinstall rebuilds the right from the descriptor" % (sf, sl, fid, col, row[col], tag, val, f, line))
EOF2
    )
    WB13_MATCHES=$(echo "$WB1314" | sed -n 's/^WB13 //p'); WB14_MATCHES=$(echo "$WB1314" | sed -n 's/^WB14 //p')
fi
COUNT=0; [ -n "$WB13_MATCHES" ] && COUNT=$(echo "$WB13_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then CRASH_HOLD=true emit "WB13" "PASS" "Install SQL and descriptor agree on every admin feature url and icon" 0
else CRASH_HOLD=true emit "WB13" "FAIL" "Admin feature url or icon differs between the install SQL and the descriptor: align both (and give upgraded sites an UPDATE)" "$COUNT" "$WB13_MATCHES"; fi
COUNT=0; [ -n "$WB14_MATCHES" ] && COUNT=$(echo "$WB14_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "WB14" "PASS" "Every Tabler icon of the admin rights exists" 0
else emit "WB14" "FAIL" "Admin feature icon that Tabler does not define: the menu shows an empty glyph" "$COUNT" "$WB14_MATCHES"; fi
echo ""

# ST07: a production class whose name matches the surefire test patterns (Test*, *Test, *Tests, *TestCase).
# `lutece:exploded … test` puts it in WEB-INF/classes, surefire collects it as a test and the fork fails
# ("wrong name", "There was an error in the forked process").
ST07_MATCHES=""
if [ -d "src/java" ]; then
    ST07_MATCHES=$(find src/java -name "*.java" 2>/dev/null | grep -E "/(Test[^/]*|[^/]*Test|[^/]*Tests|[^/]*TestCase)\.java$")
fi
COUNT=0; [ -n "$ST07_MATCHES" ] && COUNT=$(echo "$ST07_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "ST07" "PASS" "No production class named like a test" 0
else emit "ST07" "FAIL" "Production class named like a test: surefire collects it from WEB-INF/classes and the test run breaks" "$COUNT" "$ST07_MATCHES"; fi
echo ""

# ST08: a src/site/*.xml maven-site-plugin cannot read: an unclosed tag, or an HTML entity such as &egrave; inside the
# root <project ...> tag (its parser knows the HTML entities everywhere else). It fails the site build, and with it the
# "Generating reports" step of the release. Blank lines before the XML declaration are read fine.
ST08_MATCHES=""
if [ -d "src/site" ]; then
    ST08_MATCHES=$(find src/site -maxdepth 1 -name "*.xml" 2>/dev/null | sort | python3 -c '
import re, sys, xml.etree.ElementTree as ET
HTML = re.compile(r"&(?!(?:amp|lt|gt|quot|apos|#[0-9]+|#x[0-9a-fA-F]+);)[A-Za-z][A-Za-z0-9]*;")
for f in sys.stdin.read().split():
    text = open(f, encoding="utf-8", errors="replace").read().lstrip()
    root = re.search(r"<(?![?!])[^>]*>", text)
    if root and HTML.search(root.group(0)):
        print("%s: HTML entity in the root tag: %s" % (f, HTML.search(root.group(0)).group(0)))
        continue
    try:
        ET.fromstring(HTML.sub("x", text))
    except ET.ParseError as e:
        print("%s: %s" % (f, e))
')
fi
COUNT=0; [ -n "$ST08_MATCHES" ] && COUNT=$(echo "$ST08_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "ST08" "PASS" "src/site descriptors are well-formed XML" 0
else emit "ST08" "FAIL" "src/site descriptor maven-site-plugin cannot read (HTML entity in <project>, unclosed tag): the site build fails; write the character itself" "$COUNT" "$ST08_MATCHES"; fi
echo ""

# PV01: the pom and the plugin descriptor disagree on the version: the plugin screen, the upgrade scripts (Liquibase
# compares the installed version with the scripts' target) and the release read different ones.
# PV02: the v8 version is not above the last released tag while upgrade scripts changed since: a site already on that
# release is "up to date", so those scripts are silently NOT included (2.0.0-SNAPSHOT after a 2.1.x release).
# PV03: the same version without upgrade script since: nothing is lost yet, the next script would be. Below a release,
# or equal to a final one, it warns (the version was not raised after a release); equal to the numbers of a
# pre-release (2.0.1-SNAPSHOT after 2.0.1-beta-01, the beta cycle) it passes with the reminder: raising the version
# then would only make a release number nobody asked for.
PV_MATCHES=$(python3 - <<'PY'
import glob, os, re, subprocess
def version(v):
    return tuple(int(x) for x in re.findall(r"\d+", v.split("-")[0])[:3])
pom = re.sub(r"<!--.*?-->", "", open("pom.xml", encoding="utf-8", errors="replace").read(), flags=re.S) if __import__("os").path.isfile("pom.xml") else ""
own = re.sub(r"<(parent|dependencies|dependencyManagement|build|profiles|reporting|pluginRepositories|repositories|distributionManagement)\b.*?</\1>", "", pom, flags=re.S)
m = re.search(r"<version>([^<]+)</version>", own)
if not m:
    raise SystemExit
pv = m.group(1).strip()
for x in glob.glob("webapp/WEB-INF/plugins/*.xml"):
    xv = re.search(r"<version>([^<]+)</version>", re.sub(r"<!--.*?-->", "", open(x, encoding="utf-8", errors="replace").read(), flags=re.S))
    if xv and "${" not in xv.group(1) and xv.group(1).strip() != pv:
        print("PV01 %s: <version>%s</version>, the pom says %s" % (x, xv.group(1).strip(), pv))
try:
    inside = subprocess.run(["git", "rev-parse", "--is-shallow-repository"], capture_output=True, encoding="utf-8", errors="replace")
    tags = subprocess.run(["git", "tag"], capture_output=True, encoding="utf-8", errors="replace").stdout.split()
except OSError:
    inside, tags = None, []
if inside is None or inside.returncode:
    print("PV02NE not a git checkout: the release tags cannot be read")
elif inside.stdout.strip() == "true" and not tags:
    print("PV02NE shallow clone without tags: fetch them (git fetch --unshallow --tags) to compare with the last release")
released = [(version(re.findall(r"\d+\.\d+(?:\.\d+)*", t)[-1]), t) for t in tags if re.search(r"\d+\.\d+", t)]
released = [(v, t) for v, t in released if v]
if released:
    last = max(released)
    if version(pv) <= last[0]:
        why = " (plugin-liquibase compares the numbers only, PluginVersion of library-sql-utils: a qualifier such as -beta-03 or -SNAPSHOT does not count)" if re.search(r"\d-[A-Za-z]", last[1] + " " + pv) else ""
        since = subprocess.run(["git", "diff", "--name-only", last[1], "HEAD", "--", "src/sql"], capture_output=True, encoding="utf-8", errors="replace").stdout.split()
        upgrades = [f for f in since if re.search(r"/upgrades?/[^/]+\.sql$", f)]
        if upgrades:
            print("PV02 pom.xml: version %s is not above the last release %s, and %d upgrade script(s) changed since (%s): a site on that release never runs them (a script ending at the installed version runs only with liquibase.accept.unstable.versions or accept.snapshot.versions and an upgrade as the last run, never after a fresh install): put the changes in a script ending above the release, and raise the version to it%s" % (pv, last[1], len(upgrades), ", ".join(os.path.basename(f) for f in upgrades[:3]), why))
        elif version(pv) == last[0] and re.search(r"\d-[A-Za-z]", last[1]):
            print("PV03N version %s carries the numbers of the pre-release %s and no upgrade script was added since: nothing is lost; a new upgrade script needs a version above it (PV02)" % (pv, last[1]))
        else:
            print("PV03 pom.xml: version %s is not above the last release %s: raise it before adding an upgrade script, or a site on that release never runs it%s" % (pv, last[1], why))
PY
)
PV01_MATCHES=$(echo "$PV_MATCHES" | grep "^PV01 " | sed 's/^PV01 //'); PV02_MATCHES=$(echo "$PV_MATCHES" | grep "^PV02 " | sed 's/^PV02 //')
PV02_UNJUDGED=$(echo "$PV_MATCHES" | grep "^PV02NE " | sed 's/^PV02NE //'); PV03_MATCHES=$(echo "$PV_MATCHES" | grep "^PV03 " | sed 's/^PV03 //')
PV03_NOTE=$(echo "$PV_MATCHES" | sed -n 's/^PV03N //p')
COUNT=0; [ -n "$PV01_MATCHES" ] && COUNT=$(echo "$PV01_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then CRASH_HOLD=true emit "PV01" "PASS" "pom and plugin descriptor carry the same version" 0
else CRASH_HOLD=true emit "PV01" "FAIL" "pom and plugin descriptor versions differ" "$COUNT" "$PV01_MATCHES"; fi
COUNT=0; [ -n "$PV02_MATCHES" ] && COUNT=$(echo "$PV02_MATCHES" | wc -l)
if [ -n "$PV02_UNJUDGED" ]; then CRASH_HOLD=true emit "PV02" "WARN" "Version NOT EVALUATED against the last release" 1 "$PV02_UNJUDGED"
elif [ "$COUNT" -eq 0 ]; then CRASH_HOLD=true emit "PV02" "PASS" "The version is above the last release" 0
else CRASH_HOLD=true emit "PV02" "FAIL" "Version not above the last release while upgrade scripts changed since: upgraded sites skip them" "$COUNT" "$PV02_MATCHES"; fi
COUNT=0; [ -n "$PV03_MATCHES" ] && COUNT=$(echo "$PV03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ] && [ -n "$PV03_NOTE" ]; then emit "PV03" "PASS" "The $PV03_NOTE" 0
elif [ "$COUNT" -eq 0 ]; then emit "PV03" "PASS" "The version is above the last release, or nothing to judge" 0
else emit "PV03" "WARN" "Version not above the last release: raise it before the next upgrade script" "$COUNT" "$PV03_MATCHES"; fi
echo ""

echo "CATEGORY: JSP"
check_grep "JS01" 'jsp:useBean' "webapp/" "FAIL" "jsp:useBean -> CDI-managed beans"

JS02_MATCHES=""
if [ -d "webapp/" ]; then
    JS02_MATCHES=$(grep -rnE '<%([^@-]|$)' webapp/ --include="*.jsp" 2>/dev/null)
fi
COUNT=0; [ -n "$JS02_MATCHES" ] && COUNT=$(echo "$JS02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JS02" "PASS" "No JSP scriptlets" 0
else emit "JS02" "FAIL" "Old JSP scriptlets -> EL expressions; a JSP writing its own <head> gets the base href from AdminHeader.jsp, not from a scriptlet" "$COUNT" "$JS02_MATCHES"; fi

# JS03: an EL call written with the class name resolves only static methods (StaticFieldELResolver), so an
# instance method fails at runtime with MethodNotFoundException while everything compiled. A JspBean called
# from a JSP is @Named and called by its bean name, the decapitalized class name.
JS03_MATCHES=""
if [ -d "webapp/" ]; then
    JS03_MATCHES=$(grep -rnE '\$\{[^}]*\b[A-Z][A-Za-z0-9_]*(JspBean|Bean)\.[a-z][A-Za-z0-9_]*\(' webapp/ --include="*.jsp" 2>/dev/null)
fi
COUNT=0; [ -n "$JS03_MATCHES" ] && COUNT=$(echo "$JS03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JS03" "PASS" "EL calls a bean by its CDI name" 0
else emit "JS03" "FAIL" "EL call by class name resolves only static methods (use the bean name)" "$COUNT" "$JS03_MATCHES"; fi

# JS05: an admin JSP writing its own HTML. A v8 admin JSP is an entry point (errorPage, header, processController,
# footer); the screen is a template the bean renders, where the macros, the i18n, the token and the scanner apply.
# Markup written in a JSP escapes all of them (labels pointing at missing ids, v5 classes, no token).
JS05_MATCHES=""
if [ -d "webapp/jsp/admin" ]; then
    JS05_MATCHES=$(python3 - <<'PY' | awk -F: '!seen[$1]++ {print $1": writes its own HTML (line "$2"): move the markup to a template rendered by a @View"}'
import glob, re
for f in sorted(glob.glob("webapp/jsp/admin/**/*.jsp", recursive=True)):
    text = re.sub(r"<%--.*?--%>", lambda m: re.sub(r"[^\n]", " ", m.group()), open(f, encoding="utf-8", errors="replace").read(), flags=re.S)
    for n, line in enumerate(text.split("\n"), 1):
        if re.search(r"<(form|table|div|input|select|textarea|html|body|button|label|ul|p|h[1-6])([ >\t\r]|$)", line):
            print("%s:%d:%s" % (f, n, line))
PY
)
fi
COUNT=0; [ -n "$JS05_MATCHES" ] && COUNT=$(echo "$JS05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JS05" "PASS" "Admin JSPs are entry points, the markup lives in templates" 0
else emit "JS05" "FAIL" "Admin JSP writing its own HTML: move it to a template rendered by the bean" "$COUNT" "$JS05_MATCHES"; fi

# JS06: a JSP that streams a file (download, export) and leaves template text. The bean writes the bytes through
# getOutputStream(); at the end of the page the JSP flushes its own text through getWriter() and the container throws
# "OutputStream already obtained" on every download. Only directives, JSP comments and the EL call may remain: a
# newline between them is template text too, and trimDirectiveWhitespaces="true" does not remove it on Liberty.
JS06_MATCHES=""
if [ -d "webapp/jsp" ]; then
    JS06_MATCHES=$(python3 - <<'PY'
import glob, re
for f in sorted(glob.glob("webapp/jsp/**/*.jsp", recursive=True)):
    text = open(f, encoding="utf-8", errors="replace").read()
    if not re.search(r"\.\s*(?:(?:do)?[Dd]ownload\w*|(?:do)?[Ee]xport\w*|getFile|getBlob)\s*\(", text):
        continue
    rest = re.sub(r"<%--.*?--%>|<%@.*?%>|<%[^@=-].*?%>|\$\{.*?\}", "", text, flags=re.S)
    if rest.strip():
        print("%s: streams a file and leaves template text (%r)" % (f, rest.strip()[:40]))
    elif rest:
        print("%s: streams a file and leaves %d whitespace character(s) outside its directives: glue them (<%%@ … %%><%%-- newline --%%>${ … }, no final newline); trimDirectiveWhitespaces does not remove them on Liberty" % (f, len(rest)))
PY
)
fi
COUNT=0; [ -n "$JS06_MATCHES" ] && COUNT=$(echo "$JS06_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JS06" "PASS" "Download JSPs write nothing after the stream" 0
else emit "JS06" "FAIL" "Download JSP leaving template text: 'OutputStream already obtained' on every download" "$COUNT" "$JS06_MATCHES"; fi

# JS04: an admin JSP driving a bean that is not a @Controller. v8 dispatches views and actions through
# processController() on one JSP per controller, and the automatic CSRF filter only covers those actions: a legacy
# DoXxx.jsp calling bean.doXxx( request ) accepts a forged call unless the bean validates a token itself. Portlet
# JspBeans are the one legacy path the platform keeps (CS01 covers their token).
JS04_MATCHES=$(fetched js04 js04_scan)
COUNT=0; [ -n "$JS04_MATCHES" ] && COUNT=$(echo "$JS04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "JS04" "PASS" "Admin JSPs dispatch through a @Controller" 0
else emit "JS04" "FAIL" "Admin JSP outside the MVC dispatch (a non-MVC bean, or a @Controller called directly): no v8 dispatch, no automatic CSRF (rules/jsp-admin.md)" "$COUNT" "$JS04_MATCHES"; fi
echo ""

# JS07: a static script of the plugin that does not parse. The browser drops the whole file on the first syntax error
# (an extra brace, a truncated line), so every function it declares is missing on the page and nothing fails in the
# build. Checked with node --check, NOT EVALUATED without node; FreeMarker templates under WEB-INF and minified vendor
# files are left out.
JS07_MATCHES=""; JS07_FILES=""
[ -d "webapp" ] && JS07_FILES=$(js07_files)
if [ -n "$JS07_FILES" ] && command -v node >/dev/null 2>&1; then
    JS07_MATCHES=$(fetched js07 js07_scan)
fi
COUNT=0; [ -n "$JS07_MATCHES" ] && COUNT=$(echo "$JS07_MATCHES" | wc -l)
if [ -n "$JS07_FILES" ] && ! command -v node >/dev/null 2>&1; then emit "JS07" "WARN" "Static scripts NOT EVALUATED: node is not installed" 0
elif [ "$COUNT" -eq 0 ]; then emit "JS07" "PASS" "Static scripts parse" 0
else emit "JS07" "FAIL" "Script that does not parse: the browser drops the whole file" "$COUNT" "$JS07_MATCHES"; fi
echo ""

# ─── Templates ───────────────────────────────────────────
echo "CATEGORY: Templates"
check_grep "TM01" 'class="panel' "webapp/WEB-INF/templates/admin/" "FAIL" "Old Bootstrap panels -> v8 macros"
# VL01: a copy of jQuery or of a jQuery-era upload widget shipped under webapp/: nothing updates it (jQuery before 3.5
# carries known XSS flaws) and v8 has the component the widget stood for (plugin-asynchronousupload).
VL01_MATCHES=""
if [ -d "webapp/" ]; then
    VL01_MATCHES=$(find webapp -path webapp/WEB-INF -prune -o \( -iname 'jquery.js' -o -iname 'jquery.min.js' -o -iname 'jquery-[0-9]*.js' -o -iname 'jquery.slim*.js' -o -iname '*jquery*file*upload*' -o -iname '*swfupload*' -o -iname '*plupload*' -o -iname '*uploadify*' \) -print 2>/dev/null | grep -v '^webapp/WEB-INF$'; grep -rlE '(\$|jQuery)\.fn\.([A-Za-z_$][A-Za-z0-9_$]* *=|extend\()' webapp --include='*.js' 2>/dev/null | grep -v '^webapp/WEB-INF/' | grep -viE 'jquery[-.]?[0-9]|jquery(\.slim)?(\.min)?\.js$|file[-.]?upload|swfupload|plupload|uploadify')
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
TM10_MATCHES=$(template_rules offcanvas 2>/dev/null)
COUNT=0; [ -n "$TM10_MATCHES" ] && COUNT=$(echo "$TM10_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM10" "PASS" "No offcanvas" 0
else emit "TM10" "FAIL" "Offcanvas: content of the page -> @modal / @cModal, another page -> a plain link to it" "$COUNT" "$TM10_MATCHES"; fi
TM11_MATCHES=$(template_rules fo-forms 2>/dev/null)
COUNT=0; [ -n "$TM11_MATCHES" ] && COUNT=$(echo "$TM11_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM11" "PASS" "Front-office forms are @cForm with the core form validation" 0
else emit "TM11" "FAIL" "Front-office form without the core form validation: use @cForm, never foValidation=false" "$COUNT" "$TM11_MATCHES"; fi
TM12_MATCHES=$(template_rules inline-forms 2>/dev/null)
COUNT=0; [ -n "$TM12_MATCHES" ] && COUNT=$(echo "$TM12_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM12" "PASS" "No inline form" 0
else emit "TM12" "FAIL" "Inline form (fields side by side): one field per row, the standard form layout" "$COUNT" "$TM12_MATCHES"; fi

# TM02 to TM07: template rules read with FreeMarker, HTML, JSP and script comments blanked (template_rules.py).
# TM02: no theme loads jQuery unless the pom declares library-theme-jquery: without it the calls fail at runtime.
if grep -q 'library-theme-jquery' pom.xml 2>/dev/null; then TM02_SEV=WARN; else TM02_SEV=FAIL; fi
# The plugin's own scripts count too (webapp/js, webapp/themes), not only templates; a vendored library is VL01's.
TM02_MATCHES=$( { template_rules jquery 2>/dev/null;
    find webapp -path webapp/WEB-INF -prune -o -name "*.js" ! -name "*.min.js" ! -name "*.umd.js" ! -path "*/lib/*" ! -path "*/vendor/*" -print 2>/dev/null \
        | { grep -viE 'jquery|fileupload|swfupload|plupload|uploadify|swagger-ui|bundle' || true; } | { xargs grep -Hn 'jQuery(\|\$(' 2>/dev/null || true; }; } | head -200)
COUNT=0; [ -n "$TM02_MATCHES" ] && COUNT=$(echo "$TM02_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM02" "PASS" "No jQuery in the templates and scripts of the plugin" 0
else emit "TM02" "$TM02_SEV" "jQuery -> vanilla JS (no library-theme-jquery: nothing loads it); an upload widget -> plugin-asynchronousupload" "$COUNT" "$TM02_MATCHES"; fi

# TM03: a back-office template calling the front-office upload macros (addFileInput, addUploadedFilesBox): the admin
# side of plugin-asynchronousupload names them addFileBOInput, addBOUploadedFilesBox. Skin templates keep the FO names.
TM03_MATCHES=$(template_rules fo-upload 2>/dev/null)
COUNT=0; [ -n "$TM03_MATCHES" ] && COUNT=$(echo "$TM03_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM03" "PASS" "Upload macros use BO variants" 0
else emit "TM03" "FAIL" "Old upload macros -> BO variants" "$COUNT" "$TM03_MATCHES"; fi

# TM04: errors/infos/warnings read without a default: the MVC model holds them only when there is one.
TM04_MATCHES=$(template_rules unsafe-messages 2>/dev/null)
COUNT=0; [ -n "$TM04_MATCHES" ] && COUNT=$(echo "$TM04_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM04" "PASS" "Null-safe errors/infos/warnings access" 0
else emit "TM04" "FAIL" "Unsafe errors/infos/warnings -> use (var!)?size" "$COUNT" "$TM04_MATCHES"; fi

# TM05: the old jQuery SuggestPOI autocomplete.
TM05_MATCHES=$(template_rules suggestpoi 2>/dev/null)
COUNT=0; [ -n "$TM05_MATCHES" ] && COUNT=$(echo "$TM05_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM05" "PASS" "No old SuggestPOI autocomplete" 0
else emit "TM05" "FAIL" "Old jQuery autocomplete (SuggestPOI, autocomplete-js.jsp) -> LuteceAutoComplete" "$COUNT" "$TM05_MATCHES"; fi

# TM06: @addRequiredJsFiles in admin templates.
TM06_MATCHES=$(template_rules fo-required-js 2>/dev/null)
COUNT=0; [ -n "$TM06_MATCHES" ] && COUNT=$(echo "$TM06_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM06" "PASS" "Admin templates use @addRequiredBOJsFiles" 0
else emit "TM06" "FAIL" "@addRequiredJsFiles -> @addRequiredBOJsFiles" "$COUNT" "$TM06_MATCHES"; fi
# TM07: errors are MVCMessage objects printed through .message; infos and warnings are strings, .message throws.
TM07_MATCHES=$(template_rules mvc-message 2>/dev/null)
COUNT=0; [ -n "$TM07_MATCHES" ] && COUNT=$(echo "$TM07_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM07" "PASS" "Errors print .message, infos and warnings print the string" 0
else emit "TM07" "FAIL" "\${error} -> \${error.message} (MVCMessage); \${info.message} / \${warning.message} -> \${info} (a string: the page throws)" "$COUNT" "$TM07_MATCHES"; fi
# TM13: infos or warnings the project fills with MVCMessage objects itself: they work, the core's addInfo / addWarning is the modern form.
TM13_MATCHES=$(template_rules own-messages 2>/dev/null)
COUNT=0; [ -n "$TM13_MATCHES" ] && COUNT=$(echo "$TM13_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TM13" "PASS" "Infos and warnings come from the core's addInfo / addWarning" 0
else emit "TM13" "WARN" "Infos or warnings kept as the project's own MVCMessage list: use the core's addInfo( ) / addWarning( ) and print \${info}" "$COUNT" "$TM13_MATCHES"; fi

# TM08: design rules a template already written with macros can still break (scan-template-design.py header lists
# the codes). A check that could not run is never a PASS: the scan exits 2 when the project will not assemble, and
# an empty output would otherwise read as "nothing found".
if [ ! -d "webapp/WEB-INF/templates/" ]; then
    emit "TM08" "PASS" "Template design rules (no templates in this project)" 0
elif [ "$EXPLODED_RC" -ne 0 ]; then
    emit "TM08" "FAIL" "Template design rules NOT EVALUATED: the project does not assemble, fix the build first" 1 "$(echo "$EXPLODED_OUT" | tail -5)"
elif ! command -v python3 >/dev/null; then
    emit "TM08" "WARN" "Template design rules NOT EVALUATED: no python3 on PATH" 0
else
    TM08_MATCHES=$(fetched tm08 tm08_scan)
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
elif [ "$EXPLODED_RC" -ne 0 ]; then
    emit "TM09" "FAIL" "Template parse NOT EVALUATED: the project does not assemble, fix the build first" 1
else
    TM09_OUT=$(fetched tm09 tm09_scan)
    TM09_MATCHES=$(echo "$TM09_OUT" | grep '^PARSE_ERROR')
    if echo "$TM09_OUT" | grep -q "^FMPARSE skipped"; then
        emit "TM09" "FAIL" "Template parse NOT EVALUATED: the templates could not be parsed" 1 "$(echo "$TM09_OUT" | grep '^FMPARSE skipped')"
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

# TS06: Test methods without @Test (or another JUnit 5 test annotation) in the annotation block above them
TS06_MATCHES=""
[ -d "src/test/" ] && TS06_MATCHES=$(fetched ts06 ts06_scan)
COUNT=0; [ -n "$TS06_MATCHES" ] && COUNT=$(echo "$TS06_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TS06" "PASS" "All test methods have @Test" 0
else emit "TS06" "FAIL" "Test methods without @Test annotation" "$COUNT" "$TS06_MATCHES"; fi

check_grep "TS07" 'SpringContextService\.getBean' "src/test/" "FAIL" "SpringContextService.getBean in tests -> @Inject"
check_grep "TS08" 'org\.springframework\.mock\.web' "src/test/" "FAIL" "Spring mock imports -> fr.paris.lutece.test.mocks"

# TS10: tests that never name a class of the project (assertTrue( true ), a placeholder): they pass and prove nothing.
TS10_MATCHES=""
if [ -d src/test ]; then
    TS10_MATCHES=$(python3 - <<'PY'
import glob, os, re
main = {os.path.basename(f)[:-5] for d in ("src/java", "src/main/java") for f in glob.glob(d + "/**/*.java", recursive=True)}
tests = sorted(glob.glob("src/test/**/*.java", recursive=True))
if main and tests:
    names = re.compile(r"\b(%s)\b" % "|".join(map(re.escape, sorted(main))))
    if not any(names.search(re.sub(r"//[^\n]*|/\*.*?\*/", "", open(f, encoding="utf-8", errors="replace").read(), flags=re.S)) for f in tests):
        print("\n".join(tests))
PY
)
fi
COUNT=0; [ -n "$TS10_MATCHES" ] && COUNT=$(echo "$TS10_MATCHES" | wc -l)
if [ "$COUNT" -eq 0 ]; then emit "TS10" "PASS" "The tests exercise classes of the project" 0
else emit "TS10" "WARN" "No test names a class of the project (a placeholder such as assertTrue( true )): the tests pass and prove nothing" "$COUNT" "$TS10_MATCHES"; fi
echo ""

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
        TS09_SQL=$(grep -ao "Failed to execute: [^&<]\{0,160\}" target/surefire-reports/antrun_report.xml 2>/dev/null | head -3)
        [ -n "$TS09_SQL" ] && TS09_MATCHES=$(printf '%s\n%s' "the test database was built with SQL errors (antrun_report.xml), every test on those tables fails: a script declaring '-- lutece runAfter:' runs in alphabetical order under build-config, before the plugin it waits for" "$TS09_SQL"; [ -n "$TS09_MATCHES" ] && printf '\n%s' "$TS09_MATCHES")
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
