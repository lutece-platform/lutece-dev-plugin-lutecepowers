#!/usr/bin/env bash
# Checks that check-v8-floor.sh refuses a core below the floor (the latest published lutece-core) and accepts one at
# or above it, pinned or through the open range, on the core itself and on a project that resolves the core through
# Maven (offline, from the local repository); warns (rc 3) on a snapshot older than the latest build deployed.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
C="$HERE/../../tools/check-v8-floor.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export MAVEN_ARGS="-Daether.enhancedLocalRepository.trackingFilename=none"
fails=0

# Writes a pom that is lutece-core itself at the given version.
core_pom() {
    mkdir -p "$T/$1"
    printf '<project><modelVersion>4.0.0</modelVersion><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><version>%s</version></project>\n' "$2" > "$T/$1/pom.xml"
}

# Writes a pom that depends on lutece-core at the given version or range.
dep_pom() {
    mkdir -p "$T/$1"
    printf '<project><modelVersion>4.0.0</modelVersion><groupId>x</groupId><artifactId>%s</artifactId><version>1.0.0</version><packaging>pom</packaging><repositories><repository><id>lutece</id><url>https://dev.lutece.paris.fr/maven_repository</url></repository><repository><id>luteceSnapshot</id><url>https://dev.lutece.paris.fr/snapshot_repository</url></repository></repositories><dependencies><dependency><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><version>%s</version><exclusions><exclusion><groupId>*</groupId><artifactId>*</artifactId></exclusion></exclusions></dependency></dependencies></project>\n' "$1" "$2" > "$T/$1/pom.xml"
}

# Writes a site pom (parent lutece-site-pom at the site floor) that pins lutece-core at the given version.
site_pom() {
    mkdir -p "$T/$1"
    printf '<project><modelVersion>4.0.0</modelVersion><parent><groupId>fr.paris.lutece.tools</groupId><artifactId>lutece-site-pom</artifactId><version>%s</version></parent><groupId>x</groupId><artifactId>%s</artifactId><version>1.0.0</version><packaging>lutece-site</packaging><dependencies><dependency><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><version>%s</version><type>lutece-core</type><exclusions><exclusion><groupId>*</groupId><artifactId>*</artifactId></exclusion></exclusions></dependency></dependencies></project>\n' "$V8_FLOOR_SITE_PARENT" "$1" "$2" > "$T/$1/pom.xml"
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
    dep_pom dep-801 8.0.1;                   expect dep-801 1
    dep_pom dep-open '[8.0.0,)';             expect dep-open 0
    dep_pom dep-pin "$V8_FLOOR_CORE";        expect dep-pin 0
    dep_pom dep-hard "[$V8_FLOOR_CORE]";     expect dep-hard 0
    dep_pom dep-snap "$SNAP";                expect dep-snap 0
    V8_SNAPSHOT_CORE="$SNAP" V8_SNAPSHOT_CORE_BUILD=2099-01-01 expect dep-snap 3
    V8_SNAPSHOT_CORE="$SNAP" V8_SNAPSHOT_CORE_BUILD=2000-01-01 expect dep-snap 0
    grep -q "lutecepowers supports" "$T/dep-801.err" || { echo "FAIL: the refusal does not name the floor"; fails=$((fails + 1)); }
    grep -q "Pin lutece-core at $V8_FLOOR_CORE" "$T/dep-801.err" || { echo "FAIL: the refusal of a plugin does not say to pin or open the range"; fails=$((fails + 1)); }
    site_pom site-801 8.0.1
    bash "$C" "$T/site-801" --offline 2> "$T/site-801.err"; rc=$?
    if [ "$rc" = 2 ]; then
        echo "SKIP: Maven cannot load a site on lutece-site-pom $V8_FLOOR_SITE_PARENT offline (its parents and the lutece-site extension are not in ~/.m2), the site case is not run"
    elif [ "$rc" != 1 ] || ! grep -q "lutece-bom" "$T/site-801.err" || grep -q "open range" "$T/site-801.err"; then
        echo "FAIL: a site below the floor is not refused with a message pointing at lutece-bom (rc=$rc): $(cat "$T/site-801.err")"; fails=$((fails + 1))
    fi
else
    echo "SKIP: ~/.m2 lacks the lutece-core 8.0.1, $V8_FLOOR_CORE or $SNAP jars or its version list, the offline Maven cases are not run (mvn dependency:get fetches them, RELEASE the list)"
fi
mkdir -p "$T/nopom";                     expect nopom 2
KEY="lutece-core $V8_FLOOR_CORE or later; snapshot  "
core_pom core-803 8.0.3
mkdir -p "$T/core-803/target"; printf '1\t\t-|%s\tV8FLOOR CACHED\n' "$KEY" > "$T/core-803/target/.v8-floor"
bash "$C" "$T/core-803" --offline 2> "$T/cached.err"
[ $? = 1 ] && grep -q "V8FLOOR CACHED" "$T/cached.err" || { echo "FAIL: a cache with no jar field is not read"; fails=$((fails + 1)); }
printf 'x' > "$T/core.jar"
printf '1\t%s\t1:1:1|%s\tV8FLOOR STALE\n' "$T/core.jar" "$KEY" > "$T/core-803/target/.v8-floor"
bash "$C" "$T/core-803" --offline 2> "$T/stale.err"
[ $? = 0 ] && ! grep -q "V8FLOOR STALE" "$T/stale.err" || { echo "FAIL: a cache recorded for another jar file is read"; fails=$((fails + 1)); }
printf '1\t\t-|lutece-core 0.0.0 or later; snapshot  \tV8FLOOR OLD FLOOR\n' > "$T/core-803/target/.v8-floor"
bash "$C" "$T/core-803" --offline 2> "$T/floor.err"
[ $? = 0 ] && ! grep -q "V8FLOOR OLD FLOOR" "$T/floor.err" || { echo "FAIL: a cache recorded under another floor is read"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] && { echo "PASS: v8 floor refuses below the latest published core with a message per packaging, accepts it pinned, hard-pinned, through the open range or as a later snapshot, warns on an old snapshot build, reads a cache with no jar, refuses one recorded for another jar file or another floor"; exit 0; }
exit 1
