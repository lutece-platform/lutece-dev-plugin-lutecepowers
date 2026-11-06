#!/usr/bin/env bash
# Materialises the bench site project from the bench templates and e2e.conf, then assembles it (target/e2e-site-*).
# The artefact under test (core or plugin) is installed to ~/.m2 first so the site picks the local build.
#   gen-site.sh [--no-install | --pom-only]
# --pom-only writes the site pom and plugins.dat and stops: their content is the key of the assembled-site cache.
# E2E_DIR is the project's e2e folder (configuration), E2E_SITE_BUILD the directory the site is built in.
set -euo pipefail
BENCH=$(cd "$(dirname "$0")/.." && pwd)
E2E=${E2E_DIR:-$PWD}
# The environment wins over e2e.conf, as in run.sh: a caller that exported E2E_… (E2E_MYLUTECE=0 for one run, for
# instance) must not have its choice overwritten by the file.
_e2e_env=$(export -p | grep -E "^(declare -x |export )E2E_" || true)
. "$E2E/e2e.conf"
eval "$_e2e_env"
SRC=$(cd "$E2E/$E2E_SRC" && pwd)
SITE=${E2E_SITE_BUILD:-$E2E/harness/site}
MVN=${MVN:-mvn}
mkdir -p "$SITE"
cp "$BENCH/harness/site/pom.xml.tpl" "$BENCH/harness/site/plugins.dat.tpl" "$SITE/"
mkdir -p "$SITE/webapp" && cp -a "$BENCH/harness/site/webapp/." "$SITE/webapp/"

# What Maven resolves from the project's pom (inherited groupId, the lutece-core version), asked once per content of
# that pom: five Maven starts cost seconds on every build otherwise.
POMKEY=$(sha1sum "$SRC/pom.xml" | cut -c1-12)
POMINFO="$SITE/.pominfo-$POMKEY"
eval_pom() {
  local k; k=$(echo "$2" | tr . _)
  grep -sq "^$k=" "$POMINFO" || echo "$k=$($MVN -q -f "$1" help:evaluate -Dexpression="$2" -DforceStdout 2>/dev/null)" >> "$POMINFO"
  sed -n "s/^$k=//p" "$POMINFO" | head -1
}

# Every Lutece version of the site is the latest Lutece 8 one the repositories carry (tools/latest-lutece.py), unless
# e2e.conf pins one: the bench tests against what is available now, never against a version written down once.
LATEST="$BENCH/tools/latest-lutece.py"; [ -f "$LATEST" ] || LATEST="$BENCH/../../tools/latest-lutece.py"
BUILDS="$SITE/.builds"; : > "$BUILDS"
latest() {
  local line; line=$(python3 "$LATEST" snapshot "$1") || [ $? -eq 3 ] || return 1
  echo "$line" >> "$BUILDS"
  echo "$line" | cut -d: -f3
}
need() { [ -n "$2" ] || { echo "no Lutece 8 snapshot of $1 found (repositories and local Maven repository); pin one in e2e.conf" >&2; exit 2; }; }

if [ "${1:-}" != "--no-install" ] && [ "${1:-}" != "--pom-only" ]; then
  echo ">> mvn install ($E2E_TARGET) $SRC"
  $MVN -B -q -f "$SRC/pom.xml" clean install -Dmaven.test.skip=true
fi

DEPS=""
case "$E2E_TARGET" in
  core)
    CORE_VERSION=$(eval_pom "$SRC/pom.xml" project.version) ;;
  plugin)
    CORE_VERSION=${E2E_CORE_VERSION:-$(latest fr.paris.lutece:lutece-core)}; need lutece-core "$CORE_VERSION"
    [ -n "$CORE_VERSION" ] || { echo "cannot resolve the lutece-core version the plugin depends on; set E2E_CORE_VERSION in e2e.conf" >&2; exit 2; }
    G=$(eval_pom "$SRC/pom.xml" project.groupId); A=$(eval_pom "$SRC/pom.xml" project.artifactId)
    V=$(eval_pom "$SRC/pom.xml" project.version); T=$(eval_pom "$SRC/pom.xml" project.packaging)
    DEPS="        <dependency><groupId>$G</groupId><artifactId>$A</artifactId><version>$V</version><type>$T</type></dependency>"
    # The key in plugins.dat is the descriptor's <name>, which is not always the file name (myplugin.xml may
    # declare <name>my-plugin</name>) nor the artifact id. Enabling the wrong key installs nothing: the
    # site boots, the plugin's screens answer "this page does not exist" and nothing says why.
    PLUGIN_XML=$(find "$SRC/webapp/WEB-INF/plugins" -maxdepth 1 -name "*.xml" | head -1)
    AUTO_PLUGIN=$(sed -n 's:.*<name>\([^<]*\)</name>.*:\1:p' "$PLUGIN_XML" 2>/dev/null | head -1)
    [ -n "$AUTO_PLUGIN" ] || AUTO_PLUGIN=$(basename "$PLUGIN_XML" .xml)
    [ -n "$E2E_ENABLE" ] || E2E_ENABLE="$AUTO_PLUGIN"
    # The plugin under test is always enabled, even when E2E_ENABLE lists other plugins.
    case ",$E2E_ENABLE," in *,"$AUTO_PLUGIN",*) ;; *) E2E_ENABLE="$E2E_ENABLE,$AUTO_PLUGIN" ;; esac ;;
  *) echo "E2E_TARGET=$E2E_TARGET: only core and plugin are generated; a site builds with its own pom" >&2; exit 2 ;;
esac
# Front-office authentication comes with the bench: plugin-mylutece and its database module, enabled, with the
# account harness/db/post-init-mylutece.sql seeds (test / testtest). E2E_MYLUTECE=0 leaves them out; a bench
# that names them in E2E_PLUGINS keeps its own entry. Default: the latest Lutece 8 snapshots.
if [ "${E2E_MYLUTECE:-1}" != 0 ]; then
  case ",${E2E_PLUGINS:-}," in *plugin-mylutece:*) ;; *) E2E_PLUGINS="${E2E_PLUGINS:+$E2E_PLUGINS,}fr.paris.lutece.plugins:plugin-mylutece:${E2E_MYLUTECE_VERSION:-}:lutece-plugin" ;; esac
  case ",${E2E_PLUGINS:-}," in *module-mylutece-database:*) ;; *) E2E_PLUGINS="$E2E_PLUGINS,fr.paris.lutece.plugins:module-mylutece-database:${E2E_MYLUTECE_DATABASE_VERSION:-}:lutece-plugin" ;; esac
  for n in mylutece mylutece-database; do case ",${E2E_ENABLE:-}," in *,"$n",*) ;; *) E2E_ENABLE="${E2E_ENABLE:+$E2E_ENABLE,}$n" ;; esac; done
fi
IFS=',' read -ra EXTRA <<< "${E2E_PLUGINS:-}"
for p in "${EXTRA[@]}"; do
  [ -n "$p" ] || continue
  IFS=':' read -r G A V T <<< "$p"
  case "$V" in ""|latest|LATEST) V=$(latest "$G:$A"); need "$A" "$V" ;; esac
  DEPS="$DEPS
        <dependency><groupId>$G</groupId><artifactId>$A</artifactId><version>$V</version><type>${T:-lutece-plugin}</type></dependency>"
done
LIQUIBASE_VERSION=${E2E_LIQUIBASE_VERSION:-$(latest fr.paris.lutece.plugins:plugin-liquibase)}; need plugin-liquibase "$LIQUIBASE_VERSION"
SITE_POM_VERSION=${E2E_SITE_POM_VERSION:-$(python3 "$LATEST" release fr.paris.lutece.tools:lutece-site-pom | cut -d: -f3 || true)}; need lutece-site-pom "$SITE_POM_VERSION"
echo ">> site pom $SITE_POM_VERSION ; core $CORE_VERSION ; liquibase $LIQUIBASE_VERSION ; extra deps: ${E2E_PLUGINS:-none} ; enabled: ${E2E_ENABLE:-none}"
awk -v core="$CORE_VERSION" -v deps="$DEPS" -v liquibase="$LIQUIBASE_VERSION" -v sitepom="$SITE_POM_VERSION" '{gsub(/@@CORE_VERSION@@/, core); gsub(/@@LIQUIBASE_VERSION@@/, liquibase); gsub(/@@SITE_POM_VERSION@@/, sitepom); if ($0 ~ /^[[:space:]]*@@DEPENDENCIES@@[[:space:]]*$/) print deps; else print}' \
    "$SITE/pom.xml.tpl" > "$SITE/pom.xml"
# The snapshot builds the site was resolved against: a new build published since changes the pom, so the cached
# assembled site is not reused and the assembly below fetches it (-U).
echo "<!-- lutece snapshot builds: $(sort -u "$BUILDS" | tr '\n' ' ')-->" >> "$SITE/pom.xml"
mkdir -p "$SITE/webapp/WEB-INF/plugins"
ENABLED=$(echo "${E2E_ENABLE:-}" | tr ',' '\n' | sed '/^$/d; s/[[:space:]]//g; s/$/.installed=1/' | sort -u)
awk -v repl="$ENABLED" '{if ($0 ~ /@@PLUGINS_ENABLED@@/) print repl; else print}' \
    "$SITE/plugins.dat.tpl" > "$SITE/webapp/WEB-INF/plugins/plugins.dat"
[ "${1:-}" = "--pom-only" ] && exit 0

echo ">> assemble the site"
( cd "$SITE" && $MVN -B -q -U -Pcontainer-runtime clean package lutece:site-assembly )
FINAL=$(find "$SITE/target" -maxdepth 1 -type d -name "e2e-site-*" | head -1)
[ -n "$FINAL" ] || { echo "site-assembly produced no exploded directory under $SITE/target" >&2; exit 1; }
# A search plugin ships a properties file pointing at a local engine (localhost:8983 for solr, localhost:9200 for
# elasticdata). In the bench the engines are containers reached by name, so the site must override the address or
# the indexer writes nowhere and the failure only shows as an empty index, never as an error on screen. Written
# here, after assembly, so no bench can forget it.
if [ -d "$FINAL/WEB-INF/plugins/solr" ] || [ -f "$FINAL/WEB-INF/conf/plugins/search-solr.properties" ]; then
  mkdir -p "$FINAL/WEB-INF/conf/override/plugins"
  if [ ! -f "$E2E/harness/site/webapp/WEB-INF/conf/override/plugins/search-solr.properties" ]; then
    printf '# e2e bench: reach the real Solr container (reference/external-systems.md, Search engines)\nsolr.server.address=http://solr:8983/solr/%s\nsolr.indexer.commit.size=10000\n' \
      "${E2E_SOLR_CORE:-lutece}" > "$FINAL/WEB-INF/conf/override/plugins/search-solr.properties"
    echo ">> solr address overridden: http://solr:8983/solr/${E2E_SOLR_CORE:-lutece}"
  fi
fi
if [ -f "$FINAL/WEB-INF/conf/plugins/elasticdata.properties" ] \
   && [ ! -f "$E2E/harness/site/webapp/WEB-INF/conf/override/plugins/elasticdata.properties" ]; then
  mkdir -p "$FINAL/WEB-INF/conf/override/plugins"
  printf '# e2e bench: reach the real Elasticsearch container (reference/external-systems.md, Search engines)\nelasticdata.elastic_server.url=http://elastic:9200\n' \
    > "$FINAL/WEB-INF/conf/override/plugins/elasticdata.properties"
  echo ">> elasticsearch address overridden: http://elastic:9200"
fi
echo ">> site assembled: $FINAL"
