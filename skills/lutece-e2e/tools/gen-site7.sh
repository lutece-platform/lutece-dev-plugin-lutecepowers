#!/usr/bin/env bash
# Assembles harness/site7/target/lutece.war: the artefact BEFORE its migration, on a Lutece 7 site, for the
# before/after comparison (run.sh compare). The v7 sources are the git ref the clone still carries — HEAD when
# the migration is staged and not committed, which is how the campaign works — checked out in a worktree and
# built with plain mvn (the site pom declares the Lutece repositories), or with E2E_MVN7 when a developer keeps separate settings.
set -euo pipefail
E2E=$(cd "$(dirname "$0")/.." && pwd)
. "$E2E/e2e.conf"
SRC=$(cd "$E2E/$E2E_SRC" && pwd)
SITE="$E2E/harness/site7"
WT="$E2E/harness/src7"
# Plain mvn by default: the site pom declares its repositories. A developer keeping separate v7 settings sets
# E2E_MVN7="mvn -s <path>" in e2e.conf; nothing here depends on one workstation.
MVN7="${E2E_MVN7:-${MVN:-mvn}}"
REF="${E2E_V7_REF:-HEAD}"
SITE_POM="${E2E_V7_SITE_POM:-7.0.8}"
CORE="${E2E_V7_CORE:-7.1.9}"

eval_pom() { $MVN7 -q -f "$1" help:evaluate -Dexpression="$2" -DforceStdout 2>/dev/null; }

[ "$E2E_TARGET" = plugin ] || { echo "gen-site7.sh: only a plugin target has a v7 before; E2E_TARGET=$E2E_TARGET" >&2; exit 2; }

# -- the v7 sources, in a worktree that never touches the migrated tree ---------------------------------------------
if [ -d "$WT/.git" ] || [ -f "$WT/.git" ]; then
  git -C "$WT" checkout -q --detach "$(git -C "$SRC" rev-parse "$REF")"
else
  git -C "$SRC" worktree add -q --detach "$WT" "$(git -C "$SRC" rev-parse "$REF")"
fi
V7_PARENT=$(grep -A4 '<parent>' "$WT/pom.xml" | grep -oE '<version>[^<]+' | head -1 | sed 's/<version>//')
case "$V7_PARENT" in 7.*|6.*|5.*) ;; *) echo "gen-site7.sh: $REF has parent $V7_PARENT, not a v7 tree (set E2E_V7_REF)" >&2; exit 2 ;; esac

if [ "${1:-}" != "--no-install" ]; then
  echo ">> mvn install (v7, ref $REF, parent $V7_PARENT) $WT"
  $MVN7 -B -q -f "$WT/pom.xml" clean install -Dmaven.test.skip=true
fi
G=$(eval_pom "$WT/pom.xml" project.groupId); A=$(eval_pom "$WT/pom.xml" project.artifactId)
V=$(eval_pom "$WT/pom.xml" project.version); T=$(eval_pom "$WT/pom.xml" project.packaging)
DEPS="        <dependency><groupId>$G</groupId><artifactId>$A</artifactId><version>$V</version><type>$T</type></dependency>"
# Extra artefacts at their v7 versions: the v8 list (E2E_PLUGINS) names v8 versions and does not apply here.
# Front-office authentication travels with the bench on this side too (tools/gen-site.sh): the last v7 releases.
V7_PLUGINS="${E2E_V7_PLUGINS:-}"
if [ "${E2E_MYLUTECE:-1}" != 0 ]; then
  case ",$V7_PLUGINS," in *plugin-mylutece:*) ;; *) V7_PLUGINS="${V7_PLUGINS:+$V7_PLUGINS,}fr.paris.lutece.plugins:plugin-mylutece:${E2E_V7_MYLUTECE_VERSION:-4.0.8}:lutece-plugin" ;; esac
  case ",$V7_PLUGINS," in *module-mylutece-database:*) ;; *) V7_PLUGINS="$V7_PLUGINS,fr.paris.lutece.plugins:module-mylutece-database:${E2E_V7_MYLUTECE_DATABASE_VERSION:-6.0.5}:lutece-plugin" ;; esac
fi
IFS=',' read -ra EXTRA <<< "$V7_PLUGINS"
for p in "${EXTRA[@]}"; do
  [ -n "$p" ] || continue
  IFS=':' read -r XG XA XV XT <<< "$p"
  DEPS="$DEPS
        <dependency><groupId>$XG</groupId><artifactId>$XA</artifactId><version>$XV</version><type>${XT:-lutece-plugin}</type></dependency>"
done
PLUGIN_XML=$(find "$WT/webapp/WEB-INF/plugins" -maxdepth 1 -name "*.xml" | head -1)
AUTO_PLUGIN=$(sed -n 's:.*<name>\([^<]*\)</name>.*:\1:p' "$PLUGIN_XML" 2>/dev/null | head -1)
[ -n "$AUTO_PLUGIN" ] || AUTO_PLUGIN=$(basename "$PLUGIN_XML" .xml)
ENABLE="${E2E_ENABLE:-}"
case ",$ENABLE," in *,"$AUTO_PLUGIN",*) ;; *) ENABLE="${ENABLE:+$ENABLE,}$AUTO_PLUGIN" ;; esac
if [ "${E2E_MYLUTECE:-1}" != 0 ]; then
  for n in mylutece mylutece-database; do case ",$ENABLE," in *,"$n",*) ;; *) ENABLE="$ENABLE,$n" ;; esac; done
fi
echo ">> v7 site: lutece-site-pom $SITE_POM, core $CORE, $A $V ; extra: ${V7_PLUGINS:-none} ; enabled: $ENABLE"

awk -v core="$CORE" -v sp="$SITE_POM" -v deps="$DEPS" '{gsub(/@@CORE_VERSION@@/, core); gsub(/@@SITE_POM_VERSION@@/, sp); if ($0 ~ /^[[:space:]]*@@DEPENDENCIES@@[[:space:]]*$/) print deps; else print}' \
    "$SITE/pom.xml.tpl" > "$SITE/pom.xml"
mkdir -p "$SITE/webapp/WEB-INF/plugins"
ENABLED=$(echo "$ENABLE" | tr ',' '\n' | sed '/^$/d; s/[[:space:]]//g; s/$/.installed=1/' | sort -u)
awk -v repl="$ENABLED" '{if ($0 ~ /@@PLUGINS_ENABLED@@/) print repl; else print}' \
    "$E2E/harness/site/plugins.dat.tpl" > "$SITE/webapp/WEB-INF/plugins/plugins.dat"

echo ">> assemble v7 war"
( cd "$SITE" && $MVN7 -B -q clean package lutece:site-assembly )
FINAL=$(find "$SITE/target" -maxdepth 1 -type d -name "e2e-site7-*" | head -1)
[ -n "$FINAL" ] || { echo "site-assembly produced no exploded directory under $SITE/target" >&2; exit 1; }
( cd "$FINAL" && jar -cf ../lutece.war . )
echo ">> $(du -h "$SITE/target/lutece.war" | cut -f1) $SITE/target/lutece.war"
# What run.sh compare needs to hand the v7 database to the v8 site: the component names and versions the v7 site
# ran with, in the form plugin-liquibase records them (core.plugins.status.<name>.version).
{ echo "core=$CORE"; echo "$AUTO_PLUGIN=$V"
  for p in "${EXTRA[@]}"; do [ -n "$p" ] || continue; IFS=':' read -r XG XA XV XT <<< "$p"; echo "$(echo "$XA" | sed 's/^\(plugin\|module\|library\)-//')=$XV"; done
} > "$SITE/target/versions.properties"
