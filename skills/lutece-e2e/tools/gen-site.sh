#!/usr/bin/env bash
# Materialises harness/site from the templates and e2e.conf, then assembles target/lutece.war.
# The artefact under test (core or plugin) is installed to ~/.m2 first so the site picks the local build.
set -euo pipefail
E2E=$(cd "$(dirname "$0")/.." && pwd)
# The environment wins over e2e.conf, as in run.sh: a caller that exported E2E_… (run.sh compare assembling the
# site without the authentication plugin, for instance) must not have its choice overwritten by the file.
_e2e_env=$(export -p | grep -E "^(declare -x |export )E2E_" || true)
. "$E2E/e2e.conf"
eval "$_e2e_env"
SRC=$(cd "$E2E/$E2E_SRC" && pwd)
SITE="$E2E/harness/site"
MVN=${MVN:-mvn}

eval_pom() { $MVN -q -f "$1" help:evaluate -Dexpression="$2" -DforceStdout 2>/dev/null; }

if [ "${1:-}" != "--no-install" ]; then
  echo ">> mvn install ($E2E_TARGET) $SRC"
  $MVN -B -q -f "$SRC/pom.xml" clean install -Dmaven.test.skip=true
fi

DEPS=""
case "$E2E_TARGET" in
  core)
    CORE_VERSION=$(eval_pom "$SRC/pom.xml" project.version) ;;
  plugin)
    CORE_VERSION=${E2E_CORE_VERSION:-$($MVN -q -B -f "$SRC/pom.xml" dependency:list -DincludeArtifactIds=lutece-core -DoutputFile=/dev/stdout 2>/dev/null | grep -oE 'lutece-core:[^:]+:[^:]+:' | head -1 | awk -F: '{print $3}')}
    [ -n "$CORE_VERSION" ] || { echo "cannot resolve the lutece-core version the plugin depends on; set E2E_CORE_VERSION in e2e.conf" >&2; exit 2; }
    G=$(eval_pom "$SRC/pom.xml" project.groupId); A=$(eval_pom "$SRC/pom.xml" project.artifactId)
    V=$(eval_pom "$SRC/pom.xml" project.version); T=$(eval_pom "$SRC/pom.xml" project.packaging)
    DEPS="        <dependency><groupId>$G</groupId><artifactId>$A</artifactId><version>$V</version><type>$T</type></dependency>"
    # The key in plugins.dat is the descriptor's <name>, which is not always the file name (appointmentfilling.xml
    # declares <name>appointment-filling</name>) nor the artifact id. Enabling the wrong key installs nothing: the
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
# that names another version in E2E_PLUGINS keeps its own. Snapshots by default because the 5.0.0 release still
# writes core_style* at install, tables the v8 core no longer has (its 5.0.0-5.0.1 upgrade deletes those rows):
# on a v8 core the site never turns healthy with it.
if [ "${E2E_MYLUTECE:-1}" != 0 ]; then
  case ",${E2E_PLUGINS:-}," in *plugin-mylutece:*) ;; *) E2E_PLUGINS="${E2E_PLUGINS:+$E2E_PLUGINS,}fr.paris.lutece.plugins:plugin-mylutece:${E2E_MYLUTECE_VERSION:-5.0.1-SNAPSHOT}:lutece-plugin" ;; esac
  case ",${E2E_PLUGINS:-}," in *module-mylutece-database:*) ;; *) E2E_PLUGINS="$E2E_PLUGINS,fr.paris.lutece.plugins:module-mylutece-database:${E2E_MYLUTECE_DATABASE_VERSION:-7.0.1-SNAPSHOT}:lutece-plugin" ;; esac
  for n in mylutece mylutece-database; do case ",${E2E_ENABLE:-}," in *,"$n",*) ;; *) E2E_ENABLE="${E2E_ENABLE:+$E2E_ENABLE,}$n" ;; esac; done
fi
IFS=',' read -ra EXTRA <<< "${E2E_PLUGINS:-}"
for p in "${EXTRA[@]}"; do
  [ -n "$p" ] || continue
  IFS=':' read -r G A V T <<< "$p"
  DEPS="$DEPS
        <dependency><groupId>$G</groupId><artifactId>$A</artifactId><version>$V</version><type>${T:-lutece-plugin}</type></dependency>"
done
echo ">> core $CORE_VERSION ; liquibase ${E2E_LIQUIBASE_VERSION:-2.0.2-SNAPSHOT} ; extra deps: ${E2E_PLUGINS:-none} ; enabled: ${E2E_ENABLE:-none}"

# plugin-liquibase 2.0.0 and 2.0.1 order the SQL files alphabetically and ignore the `--lutece runAfter:<plugin>`
# directive (`-- lutece runAfter:<plugin>`) that a plugin whose init_db depends on another plugin's tables carries;
# under an older plugin-liquibase those inserts run before the tables exist and the install dies at first boot.
# 2.0.2-SNAPSHOT is the first version honouring it. Override with E2E_LIQUIBASE_VERSION in e2e.conf.
LIQUIBASE_VERSION=${E2E_LIQUIBASE_VERSION:-2.0.2-SNAPSHOT}
awk -v core="$CORE_VERSION" -v deps="$DEPS" -v liquibase="$LIQUIBASE_VERSION" '{gsub(/@@CORE_VERSION@@/, core); gsub(/@@LIQUIBASE_VERSION@@/, liquibase); if ($0 ~ /^[[:space:]]*@@DEPENDENCIES@@[[:space:]]*$/) print deps; else print}' \
    "$SITE/pom.xml.tpl" > "$SITE/pom.xml"
ENABLED=$(echo "${E2E_ENABLE:-}" | tr ',' '\n' | sed '/^$/d; s/[[:space:]]//g; s/$/.installed=1/' | sort -u)
awk -v repl="$ENABLED" '{if ($0 ~ /@@PLUGINS_ENABLED@@/) print repl; else print}' \
    "$SITE/plugins.dat.tpl" > "$SITE/webapp/WEB-INF/plugins/plugins.dat"

echo ">> assemble war"
( cd "$SITE" && $MVN -B -q -Pcontainer-runtime clean package lutece:site-assembly )
FINAL=$(find "$SITE/target" -maxdepth 1 -type d -name "e2e-site-*" | head -1)
[ -n "$FINAL" ] || { echo "site-assembly produced no exploded directory under $SITE/target" >&2; exit 1; }
# A search plugin ships a properties file pointing at a local engine (localhost:8983 for solr, localhost:9200 for
# elasticdata). In the bench the engines are containers reached by name, so the site must override the address or
# the indexer writes nowhere and the failure only shows as an empty index, never as an error on screen. Written
# here, after assembly, so no bench can forget it.
if [ -d "$FINAL/WEB-INF/plugins/solr" ] || [ -f "$FINAL/WEB-INF/conf/plugins/search-solr.properties" ]; then
  mkdir -p "$FINAL/WEB-INF/conf/override/plugins"
  if [ ! -f "$E2E/harness/site/webapp/WEB-INF/conf/override/plugins/search-solr.properties" ]; then
    printf '# e2e bench: reach the real Solr container (SKILL.md, Search engines)\nsolr.server.address=http://solr:8983/solr/%s\nsolr.indexer.commit.size=10000\n' \
      "${E2E_SOLR_CORE:-lutece}" > "$FINAL/WEB-INF/conf/override/plugins/search-solr.properties"
    echo ">> solr address overridden: http://solr:8983/solr/${E2E_SOLR_CORE:-lutece}"
  fi
fi
if [ -f "$FINAL/WEB-INF/conf/plugins/elasticdata.properties" ] \
   && [ ! -f "$E2E/harness/site/webapp/WEB-INF/conf/override/plugins/elasticdata.properties" ]; then
  mkdir -p "$FINAL/WEB-INF/conf/override/plugins"
  printf '# e2e bench: reach the real Elasticsearch container (SKILL.md, Search engines)\nelasticdata.elastic_server_url=http://elastic:9200\n' \
    > "$FINAL/WEB-INF/conf/override/plugins/elasticdata.properties"
  echo ">> elasticsearch address overridden: http://elastic:9200"
fi
( cd "$FINAL" && jar -cf ../lutece.war . )
echo ">> $(du -h "$SITE/target/lutece.war" | cut -f1) $SITE/target/lutece.war"
