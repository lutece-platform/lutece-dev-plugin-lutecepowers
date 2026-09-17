#!/usr/bin/env bash
# Assembles harness/site7/target/lutece.war: the artefact BEFORE its migration, on a Lutece 7 site, for the
# before/after comparison (run.sh compare). The v7 sources are the git ref the clone still carries — HEAD when
# the migration is staged and not committed, which is how the campaign works — checked out in a worktree and
# built with plain mvn (the site pom declares the Lutece repositories), or with E2E_MVN7 when a developer keeps separate settings.
set -euo pipefail
E2E=$(cd "$(dirname "$0")/.." && pwd)
# The environment wins over e2e.conf, as in run.sh: a caller that exported E2E_… (run.sh compare assembling the
# site without the authentication plugin, for instance) must not have its choice overwritten by the file.
_e2e_env=$(export -p | grep -E "^(declare -x |export )E2E_" || true)
. "$E2E/e2e.conf"
eval "$_e2e_env"
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
  # --force: a previous run may have pinned a dependency in this pom, and the worktree is disposable.
  git -C "$WT" checkout -q --force --detach "$(git -C "$SRC" rev-parse "$REF")"
else
  git -C "$SRC" worktree add -q --detach "$WT" "$(git -C "$SRC" rev-parse "$REF")"
fi
# A v7 tree does not always compile against the v7 core the bench runs: an artefact left on an older core keeps a
# call the 7.x line removed (a constructor, a method), and no choice of E2E_V7_CORE fixes it — the code never
# compiled against that core. `harness/src7-overlay` is copied over the disposable worktree, same paths as the
# sources, so the leg builds and the comparison can happen. It holds v7 code, never migrated code, and the
# migrated tree is never touched. Each file deserves a comment saying which core release broke it.
if [ -d "$E2E/harness/src7-overlay" ]; then
  cp -a "$E2E/harness/src7-overlay/." "$WT/"
  echo ">> v7 source overlay applied: $(cd "$E2E/harness/src7-overlay" && find . -type f | sed 's|^\./||' | tr '\n' ' ')"
fi

V7_PARENT=$(grep -A4 '<parent>' "$WT/pom.xml" | grep -oE '<version>[^<]+' | head -1 | sed 's/<version>//')
case "$V7_PARENT" in 7.*|6.*|5.*) ;; *) echo "gen-site7.sh: $REF has parent $V7_PARENT, not a v7 tree (set E2E_V7_REF)" >&2; exit 2 ;; esac

# A v7 pom often declares its dependencies as ranges, and the top of the range has moved on since: the sources
# no longer compile against what Maven resolves today, and the leg cannot be built at all. E2E_V7_DEP_PINS
# ("groupId:artifactId:version,...") replaces those versions in the worktree pom — the worktree is disposable,
# the migrated tree is never touched. The pin belongs to the bench, beside E2E_V7_PLUGINS in e2e.conf.
_PINS="${E2E_V7_DEP_PINS:-}"
for pin in ${_PINS//,/ }; do
  IFS=':' read -r PG PA PV <<< "$pin"
  [ -n "${PV:-}" ] || { echo "gen-site7.sh: E2E_V7_DEP_PINS wants groupId:artifactId:version, got '$pin'" >&2; exit 2; }
  python3 - "$WT/pom.xml" "$PG" "$PA" "$PV" <<'PYPIN'
import re, sys
pom, g, a, v = sys.argv[1:5]
# A plain version is only a soft requirement: another dependency asking for the same artefact through a range
# wins over it, and the pin changes nothing. Written as a one-value range it is a hard requirement, which is
# what pinning means here.
v = v if v.startswith(("[", "(")) else "[%s]" % v
t = open(pom, encoding="utf-8").read()
pat = re.compile(r"(<dependency>(?:(?!</dependency>).)*?<groupId>\s*%s\s*</groupId>(?:(?!</dependency>).)*?<artifactId>\s*%s\s*</artifactId>(?:(?!</dependency>).)*?<version>)([^<]*)(</version>)"
                 % (re.escape(g), re.escape(a)), re.S)
t2, n = pat.subn(lambda m: m.group(1) + v + m.group(3), t)
if not n:
    # Not declared: the version comes through another dependency's range, and the top of that range has moved on.
    # A direct dependency wins over a transitive one, so declaring it here is what pins it.
    dep = "        <dependency>\n            <groupId>%s</groupId>\n            <artifactId>%s</artifactId>\n            <version>%s</version>\n        </dependency>\n" % (g, a, v)
    if "</dependencies>" not in t:
        sys.exit("gen-site7.sh: the v7 pom has no <dependencies> to add %s:%s to" % (g, a))
    t2 = t.replace("</dependencies>", dep + "    </dependencies>", 1)
open(pom, "w", encoding="utf-8").write(t2)
PYPIN
  echo ">> v7 dependency pinned: $PG:$PA -> $PV"
done

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
# A bench whose artefact has no screen proves it through a probe JSP under harness/site/webapp/jsp/e2e. The v7
# site needs the same probe, or every probe scenario fails on the v7 leg and the comparison reads "corrigé"
# where only the v7 site was missing the page. The probe is the bench's, not the artefact's: it is copied as is.
# The bench's own property overrides belong to both legs: the v8 site gets them from
# harness/site/webapp/WEB-INF/conf/override, and Lutece 7 reads the same directory. Without them the v7 artefact
# calls the real outside systems instead of the bench's stand-ins, and every such scenario reads as "corrigé".
if [ -d "$E2E/harness/site/webapp/WEB-INF/conf/override" ]; then
  mkdir -p "$SITE/webapp/WEB-INF/conf/override"
  cp -a "$E2E/harness/site/webapp/WEB-INF/conf/override/." "$SITE/webapp/WEB-INF/conf/override/"
  echo ">> property overrides copied to the v7 site"
fi
if [ -d "$E2E/harness/site/webapp/jsp/e2e" ]; then
  mkdir -p "$SITE/webapp/jsp/e2e" && cp -a "$E2E/harness/site/webapp/jsp/e2e/." "$SITE/webapp/jsp/e2e/"
  echo ">> probe pages copied to the v7 site ($(ls "$SITE/webapp/jsp/e2e" | tr '\n' ' '))"
fi
ENABLED=$(echo "$ENABLE" | tr ',' '\n' | sed '/^$/d; s/[[:space:]]//g; s/$/.installed=1/' | sort -u)
awk -v repl="$ENABLED" '{if ($0 ~ /@@PLUGINS_ENABLED@@/) print repl; else print}' \
    "$E2E/harness/site/plugins.dat.tpl" > "$SITE/webapp/WEB-INF/plugins/plugins.dat"

echo ">> assemble v7 war"
( cd "$SITE" && $MVN7 -B -q clean package lutece:site-assembly )
FINAL=$(find "$SITE/target" -maxdepth 1 -type d -name "e2e-site7-*" | head -1)
[ -n "$FINAL" ] || { echo "site-assembly produced no exploded directory under $SITE/target" >&2; exit 1; }
# v7 configuration is not reachable from the environment: an endpoint often sits as a literal in a Spring context
# XML, or in a .properties the artefact ships, and neither reads the variables the v8 leg is configured with. The
# v7 leg then calls the real outside system while the v8 leg calls the stand-in, and the comparison reads the
# difference as "corrigé". `harness/v7-overlay` is laid over the assembled v7 webapp, after assembly so the
# artefact's own files are already there: same paths, same purpose as app.env on the v8 leg.
if [ -d "$E2E/harness/v7-overlay" ]; then
  cp -a "$E2E/harness/v7-overlay/." "$FINAL/"
  echo ">> v7 overlay applied: $(cd "$E2E/harness/v7-overlay" && find . -type f | sed 's|^\./||' | tr '\n' ' ')"
fi
# Same as the v8 leg: a search plugin points at a local engine by default, the bench reaches containers by name.
# Written after the overlay so a bench that ships its own file still wins.
if [ -f "$FINAL/WEB-INF/conf/plugins/search-solr.properties" ] && [ ! -f "$FINAL/WEB-INF/conf/override/plugins/search-solr.properties" ]; then
  mkdir -p "$FINAL/WEB-INF/conf/override/plugins"
  printf '# e2e bench: reach the real Solr container (SKILL.md, Search engines)\nsolr.server.address=http://solr:8983/solr/%s\nsolr.indexer.commit.size=10000\n' \
    "${E2E_SOLR_CORE:-lutece}" > "$FINAL/WEB-INF/conf/override/plugins/search-solr.properties"
  echo ">> solr address overridden on the v7 leg: http://solr:8983/solr/${E2E_SOLR_CORE:-lutece}"
fi
( cd "$FINAL" && jar -cf ../lutece.war . )
echo ">> $(du -h "$SITE/target/lutece.war" | cut -f1) $SITE/target/lutece.war"
# What run.sh compare needs to hand the v7 database to the v8 site: the component names and versions the v7 site
# ran with, in the form plugin-liquibase records them (core.plugins.status.<name>.version).
{ echo "core=$CORE"; echo "$AUTO_PLUGIN=$V"
  for p in "${EXTRA[@]}"; do [ -n "$p" ] || continue; IFS=':' read -r XG XA XV XT <<< "$p"; echo "$(echo "$XA" | sed 's/^\(plugin\|module\|library\)-//')=$XV"; done
} > "$SITE/target/versions.properties"
