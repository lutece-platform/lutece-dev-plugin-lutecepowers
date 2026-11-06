#!/usr/bin/env bash
# Checks that check-v8-floor.sh refuses a core below the floor (the latest published lutece-core) and accepts one at
# or above it, pinned or through the open range, on the core itself and on a project that resolves the core through
# Maven (offline, from the local repository), the lowest of its modules; warns (rc 3) on a snapshot older than the
# latest build deployed; is undecidable (rc 2) when it passes a floor the repositories could not confirm; warns (rc 4)
# on a project other than a site that pins its core, refuses one pinned below Lutece 8.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
C="$HERE/../../tools/check-v8-floor.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export MAVEN_ARGS="-Daether.enhancedLocalRepository.trackingFilename=none"
fails=0

# Reports cases not run: a failure on CI, where every case must run.
skip() {
    echo "SKIP: $*"
    [ -z "${CI:-}" ] || fails=$((fails + 1))
}

# Writes a pom that is lutece-core itself at the given version.
core_pom() {
    mkdir -p "$T/$1"
    printf '<project><modelVersion>4.0.0</modelVersion><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><version>%s</version></project>\n' "$2" > "$T/$1/pom.xml"
}

# Writes a pom that depends on lutece-core at the given version or range.
dep_pom() {
    mkdir -p "$T/$1"
    printf '<project><modelVersion>4.0.0</modelVersion><groupId>x</groupId><artifactId>%s</artifactId><version>1.0.0</version><packaging>pom</packaging><repositories><repository><id>lutece</id><url>https://dev.lutece.paris.fr/maven_repository</url></repository><repository><id>luteceSnapshot</id><url>https://dev.lutece.paris.fr/snapshot_repository</url></repository></repositories><dependencies><dependency><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><version>%s</version><exclusions><exclusion><groupId>*</groupId><artifactId>*</artifactId></exclusion></exclusions></dependency></dependencies></project>\n' "${1##*/}" "$2" > "$T/$1/pom.xml"
}

# Writes a site pom (parent lutece-site-pom at the site floor) that pins lutece-core at the given version.
site_pom() {
    mkdir -p "$T/$1"
    printf '<project><modelVersion>4.0.0</modelVersion><parent><groupId>fr.paris.lutece.tools</groupId><artifactId>lutece-site-pom</artifactId><version>%s</version></parent><groupId>x</groupId><artifactId>%s</artifactId><version>1.0.0</version><packaging>lutece-site</packaging><dependencies><dependency><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><version>%s</version><type>lutece-core</type><exclusions><exclusion><groupId>*</groupId><artifactId>*</artifactId></exclusion></exclusions></dependency></dependencies></project>\n' "$V8_FLOOR_SITE_PARENT" "$1" "$2" > "$T/$1/pom.xml"
}

# Writes a site pom (parent lutece-site-pom at the site floor) that imports the given lutece-bom and takes lutece-core
# from it.
site_bom_pom() {
    mkdir -p "$T/$1"
    printf '<project><modelVersion>4.0.0</modelVersion><parent><groupId>fr.paris.lutece.tools</groupId><artifactId>lutece-site-pom</artifactId><version>%s</version></parent><groupId>x</groupId><artifactId>%s</artifactId><version>1.0.0</version><packaging>lutece-site</packaging><dependencyManagement><dependencies><dependency><groupId>fr.paris.lutece.starters</groupId><artifactId>lutece-bom</artifactId><version>%s</version><type>pom</type><scope>import</scope></dependency></dependencies></dependencyManagement><dependencies><dependency><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><type>lutece-core</type><exclusions><exclusion><groupId>*</groupId><artifactId>*</artifactId></exclusion></exclusions></dependency></dependencies></project>\n' "$V8_FLOOR_SITE_PARENT" "$1" "$2" > "$T/$1/pom.xml"
}

# Writes an aggregator whose modules a and b depend on lutece-core at the given versions (b: none when empty).
multi_pom() {
    mkdir -p "$T/$1"
    printf '<project><modelVersion>4.0.0</modelVersion><groupId>x</groupId><artifactId>%s</artifactId><version>1.0.0</version><packaging>pom</packaging><modules><module>a</module><module>b</module></modules></project>\n' "$1" > "$T/$1/pom.xml"
    dep_pom "$1/a" "$2"
    if [ -n "$3" ]; then dep_pom "$1/b" "$3"; else mkdir -p "$T/$1/b"; printf '<project><modelVersion>4.0.0</modelVersion><groupId>x</groupId><artifactId>b</artifactId><version>1.0.0</version><packaging>pom</packaging></project>\n' > "$T/$1/b/pom.xml"; fi
}

# Runs the check on a fixture and compares the exit code with the expected one.
expect() {
    local dir=$1 want=$2 got
    rm -f "$T/$dir/target/.v8-floor"
    bash "$C" "$T/$dir" --offline 2> "$T/$dir.err"; got=$?
    if [ "$got" != "$want" ]; then
        echo "FAIL: $dir expected rc=$want, got rc=$got: $(cat "$T/$dir.err")"; fails=$((fails + 1))
    fi
}

export V8_SNAPSHOT_CORE="" V8_SNAPSHOT_CORE_BUILD=""
for c in 8.0.1:1 8.0.2-beta-03:1 8.0.2-beta-04:0 8.0.2-SNAPSHOT:0 8.0.3:0; do
    v=${c%:*}; core_pom "core-$v" "$v"; V8_FLOOR_CORE=8.0.2-beta-04 expect "core-$v" "${c#*:}"
done
core_pom core-snap-after 8.0.2-SNAPSHOT; V8_FLOOR_CORE=8.0.2 expect core-snap-after 1
. "$HERE/../../tools/v8-floor.conf"
SNAP=$(python3 "$HERE/../../tools/latest-lutece.py" snapshot fr.paris.lutece:lutece-core 2>/dev/null | cut -d: -f3)
M2="$HOME/.m2/repository/fr/paris/lutece/lutece-core"
if [ -n "$SNAP" ] && ls "$M2/8.0.1/"*.jar "$M2/$V8_FLOOR_CORE/"*.jar "$M2/$SNAP/"*.jar "$M2/maven-metadata-lutece.xml" >/dev/null 2>&1; then
    dep_pom dep-801 '[8.0.1,8.0.1]';         expect dep-801 1
    dep_pom dep-open '[8.0.0,)';             expect dep-open 0
    dep_pom dep-floor "[$V8_FLOOR_CORE,$V8_FLOOR_CORE]"; expect dep-floor 0
    dep_pom dep-snap "[$SNAP,$SNAP]";        expect dep-snap 0
    V8_SNAPSHOT_CORE="$SNAP" V8_SNAPSHOT_CORE_BUILD=2099-01-01 expect dep-snap 3
    V8_SNAPSHOT_CORE="$SNAP" V8_SNAPSHOT_CORE_BUILD=2000-01-01 expect dep-snap 0
    dep_pom dep-nope '[0.0.0-nope,0.0.0-nope]'; expect dep-nope 2
    dep_pom dep-touched '[8.0.0,)';          expect dep-touched 0
    dep_pom dep-touched '[8.0.1,8.0.1]'; bash "$C" "$T/dep-touched" --offline 2>/dev/null
    [ $? = 1 ] || { echo "FAIL: a pom changed after the verdict does not invalidate the cache"; fails=$((fails + 1)); }
    multi_pom multi-low 8.0.1 "";           expect multi-low 1
    multi_pom multi-ok "$V8_FLOOR_CORE" "";  expect multi-ok 0
    dep_pom multi-ok/a 8.0.1; touch -d '2000-01-01' "$T/multi-ok/a/pom.xml"
    bash "$C" "$T/multi-ok" --offline 2>/dev/null
    [ $? = 1 ] || { echo "FAIL: a module pom changed after the verdict does not invalidate the cache"; fails=$((fails + 1)); }
    grep -q "lutecepowers supports" "$T/dep-801.err" || { echo "FAIL: the refusal does not name the floor"; fails=$((fails + 1)); }
    grep -q "Declare lutece-core as an open range" "$T/dep-801.err" || { echo "FAIL: the refusal of a plugin does not say to open the range"; fails=$((fails + 1)); }
    site_pom site-801 8.0.1
    bash "$C" "$T/site-801" --offline 2> "$T/site-801.err"; rc=$?
    if [ "$rc" = 2 ]; then
        skip "Maven cannot load a site on lutece-site-pom $V8_FLOOR_SITE_PARENT offline (its parents and the lutece-site extension are not in ~/.m2), the site case is not run"
    elif [ "$rc" != 1 ] || ! grep -q "lutece-bom" "$T/site-801.err" || grep -q "open range" "$T/site-801.err"; then
        echo "FAIL: a site below the floor is not refused with a message pointing at lutece-bom (rc=$rc): $(cat "$T/site-801.err")"; fails=$((fails + 1))
    fi
    IFS=: read -r _ _ BOMV BOMCORE <<< "$(python3 "$HERE/../../tools/latest-lutece.py" bom fr.paris.lutece.starters:lutece-bom 2>/dev/null)"
    if [ "$rc" != 2 ] && [ -n "$BOMV" ] && ls "$HOME/.m2/repository/fr/paris/lutece/starters/lutece-bom/$BOMV/"*.pom "$M2/$BOMCORE/"*.jar >/dev/null 2>&1; then
        site_bom_pom site-bom "$BOMV"; site_pom site-pin "$BOMCORE"; dep_pom dep-pin-lag "[$BOMCORE,$BOMCORE]"
        export V8_FLOOR_BOM="$BOMV" V8_FLOOR_BOM_CORE="$BOMCORE"
        V8_FLOOR_CORE=99.0.0 expect site-bom 0
        V8_FLOOR_CORE=99.0.0 expect site-pin 1
        V8_FLOOR_CORE=99.0.0 expect dep-pin-lag 1
        V8_FLOOR_BOM_CORE=99.0.0 V8_FLOOR_CORE="$BOMCORE" expect site-bom 0
        unset V8_FLOOR_BOM V8_FLOOR_BOM_CORE
    else
        skip "~/.m2 lacks lutece-bom $BOMV or the lutece-core $BOMCORE it manages, the core-before-its-BOM cases are not run"
    fi
else
    skip "~/.m2 lacks the lutece-core 8.0.1, $V8_FLOOR_CORE or $SNAP jars or its version list, the offline Maven cases are not run (mvn dependency:get fetches them, RELEASE the list)"
fi
mkdir -p "$T/nopom";                     expect nopom 2
dep_pom dep-pin 8.0.2-beta-04;           expect dep-pin 4
dep_pom dep-hard '[8.0.2-beta-04]';      expect dep-hard 4
V8_FLOOR_CORE=99.0.0 expect dep-hard 4
grep -q "\[8.0.2-beta-04,)" "$T/dep-hard.err" || { echo "FAIL: a pinned plugin is not told to declare a range from its core"; fails=$((fails + 1)); }
dep_pom dep-v7 7.1.0;                    expect dep-v7 1
V8_FLOOR_UNVERIFIED=x V8_FLOOR_CORE=8.0.2-beta-04 expect core-8.0.3 2
V8_FLOOR_UNVERIFIED=x V8_FLOOR_CORE=8.0.2-beta-04 expect core-8.0.1 1
LUTECE_RELEASE_REPO=http://127.0.0.1:9 LUTECE_LATEST_CACHE="$T/unreachable.json" M2_REPO="$T/m2" V8_FLOOR_CORE= expect core-8.0.3 2
KEY="lutece-core $V8_FLOOR_CORE or later, the latest published; snapshot  "
core_pom core-803 99.0.3
mkdir -p "$T/core-803/target"; printf '1\t\t-|%s|-\tV8FLOOR CACHED\n' "$KEY" > "$T/core-803/target/.v8-floor"
M2_REPO="$T/m2" bash "$C" "$T/core-803" --offline 2> "$T/cached.err"
[ $? = 1 ] && grep -q "V8FLOOR CACHED" "$T/cached.err" || { echo "FAIL: a cache with no jar field is not read"; fails=$((fails + 1)); }
printf 'x' > "$T/core.jar"
printf '1\t%s\t1:1:1|%s\tV8FLOOR STALE\n' "$T/core.jar" "$KEY" > "$T/core-803/target/.v8-floor"
bash "$C" "$T/core-803" --offline 2> "$T/stale.err"
[ $? = 0 ] && ! grep -q "V8FLOOR STALE" "$T/stale.err" || { echo "FAIL: a cache recorded for another jar file is read"; fails=$((fails + 1)); }
printf '1\t\t-|lutece-core 0.0.0 or later, the latest published; snapshot  \tV8FLOOR OLD FLOOR\n' > "$T/core-803/target/.v8-floor"
bash "$C" "$T/core-803" --offline 2> "$T/floor.err"
[ $? = 0 ] && ! grep -q "V8FLOOR OLD FLOOR" "$T/floor.err" || { echo "FAIL: a cache recorded under another floor is read"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] && { echo "PASS: v8 floor"; exit 0; }
exit 1
