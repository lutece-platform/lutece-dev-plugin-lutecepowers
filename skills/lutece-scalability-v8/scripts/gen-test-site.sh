#!/usr/bin/env bash
# Generate a DISPOSABLE Docker environment to test a Lutece v8 plugin's scalability
# in a 3-instance cluster (Liberty + MariaDB + nginx + Hazelcast).
#
# Usage:
#   gen-test-site.sh --local <plugin-path> --enable <name[,name...]> [--out <dir>] [--no-build]
#   gen-test-site.sh --plugin <groupId:artifactId:version> [--type lutece-plugin] --enable <name[,name...]> [--out <dir>] [--no-build]
#
# Produces in <dir> (default ./e2e/.scalability-test): pom.xml, plugins.dat, docker-compose.yml,
# Dockerfile, Liberty/Hazelcast/nginx config, and the assembled war -> ready for `docker compose up -d`.
set -euo pipefail
HARNESS="$(cd "$(dirname "$0")/../harness" && pwd)"
FLOOR="$(cd "$(dirname "$0")/../../lutece-migration-v8-agent-teams/scripts" && pwd)/check-v8-floor.sh"
HZ_VERSION="5.5.0"
OUT="./e2e/.scalability-test"; LOCAL=""; PLUGIN=""; PTYPE="lutece-plugin"; ENABLE=""; BUILD=1

while [ $# -gt 0 ]; do case "$1" in
  --local)  LOCAL="$2"; shift 2;;
  --plugin) PLUGIN="$2"; shift 2;;
  --type)   PTYPE="$2"; shift 2;;
  --enable) ENABLE="$2"; shift 2;;
  --out)    OUT="$2"; shift 2;;
  --no-build) BUILD=0; shift;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; done

# --- Resolve the plugin-under-test coordinates ---
if [ -n "$LOCAL" ]; then
  echo ">> install local plugin: $LOCAL"
  mvn -B -f "$LOCAL/pom.xml" install -DskipTests -Dmaven.test.skip=true >/dev/null
  G=$(mvn -q -f "$LOCAL/pom.xml" help:evaluate -Dexpression=project.groupId -DforceStdout 2>/dev/null)
  A=$(mvn -q -f "$LOCAL/pom.xml" help:evaluate -Dexpression=project.artifactId -DforceStdout 2>/dev/null)
  V=$(mvn -q -f "$LOCAL/pom.xml" help:evaluate -Dexpression=project.version -DforceStdout 2>/dev/null)
  PTYPE=$(mvn -q -f "$LOCAL/pom.xml" help:evaluate -Dexpression=project.packaging -DforceStdout 2>/dev/null)
  # auto-derive --enable if not given: the <name> of the plugin descriptor webapp/WEB-INF/plugins/*.xml
  if [ -z "$ENABLE" ]; then
    DESC=$(find "$LOCAL/webapp/WEB-INF/plugins" -maxdepth 1 -name "*.xml" 2>/dev/null | head -1)
    [ -n "$DESC" ] && ENABLE=$(sed -n 's:.*<name>[[:space:]]*\([^<[:space:]]*\)[[:space:]]*</name>.*:\1:p' "$DESC" | head -1)
  fi
elif [ -n "$PLUGIN" ]; then
  IFS=':' read -r G A V <<< "$PLUGIN"
else
  echo "ERROR: --local <path> or --plugin <g:a:v> is required" >&2; exit 2
fi
[ -n "${G:-}" ] && [ -n "${A:-}" ] && [ -n "${V:-}" ] || { echo "ERROR: incomplete plugin coordinates ($G:$A:$V)" >&2; exit 2; }
[ -n "$ENABLE" ] || { echo "ERROR: --enable <plugin names to activate> is required (e.g. myplugin,genericattributes)" >&2; exit 2; }
echo ">> plugin under test: $G:$A:$V ($PTYPE) ; plugins enabled: $ENABLE"

# --- Materialise the test site ---
rm -rf "$OUT"; mkdir -p "$OUT"
cp -a "$HARNESS/." "$OUT/"
rm -f "$OUT/pom.xml.tpl" "$OUT/webapp/WEB-INF/plugins/plugins.dat.tpl"

sed -e "s#@@PUT_GROUPID@@#$G#" -e "s#@@PUT_ARTIFACTID@@#$A#" \
    -e "s#@@PUT_VERSION@@#$V#" -e "s#@@PUT_TYPE@@#$PTYPE#" \
    "$HARNESS/pom.xml.tpl" > "$OUT/pom.xml"

ENABLED_LINES=$(echo "$ENABLE" | tr ',' '\n' | sed 's/[[:space:]]//g; s/$/.installed=1/' | sort -u)
awk -v repl="$ENABLED_LINES" '{gsub(/@@PUT_PLUGINS_ENABLED@@/, repl)}1' \
    "$HARNESS/webapp/WEB-INF/plugins/plugins.dat.tpl" > "$OUT/webapp/WEB-INF/plugins/plugins.dat"

# --- Refuse a plugin below the supported Lutece 8 level (exit 2 = undecidable, let the build decide) ---
bash "$FLOOR" "$OUT" || [ $? -eq 2 ] || { echo "ERROR: the site resolves a lutece-core below the Lutece 8 level lutecepowers supports" >&2; exit 1; }

# --- Hazelcast jar (server-level, for Liberty sessionCache) ---
echo ">> fetch hazelcast $HZ_VERSION"
mvn -B dependency:get -Dartifact="com.hazelcast:hazelcast:$HZ_VERSION" >/dev/null
cp "$HOME/.m2/repository/com/hazelcast/hazelcast/$HZ_VERSION/hazelcast-$HZ_VERSION.jar" "$OUT/hazelcast-$HZ_VERSION.jar"

# --- Build the war ---
if [ "$BUILD" = "1" ]; then
  echo ">> build war (mvn -Pcontainer-runtime lutece:site-assembly)"
  ( cd "$OUT" && mvn -B -Pcontainer-runtime clean package lutece:site-assembly >/dev/null )
  FINAL=$(find "$OUT/target" -maxdepth 1 -type d -name "scalability-test-site-*" | head -1)
  ( cd "$FINAL" && jar -cf ../lutece.war . )
  echo ">> war: $(du -h "$OUT/target/lutece.war" | cut -f1)"
fi

echo ""
echo "OK. Test environment generated in: $OUT"
echo "Start the cluster:  ( cd $OUT && docker compose up -d )"
echo "Verify:             bash $(cd "$(dirname "$0")" && pwd)/cluster-verify.sh $OUT"
echo "Stop:               ( cd $OUT && docker compose down -v )"
