#!/usr/bin/env bash
# Assembles the v7 bench site (target/e2e-site7-* under E2E_SITE7_BUILD, with versions.properties beside it): the
# artefact BEFORE its migration, on a Lutece 7 site, for the database upgrade (lpe2e upgrade). A site target (E2E_TARGET=site) brings its own v7 war (E2E_V7_WAR). The v7 sources are the git ref the clone still carries — HEAD while
# the migration is staged and not committed — checked out in a worktree and
# built with plain mvn (the site pom declares the Lutece repositories), or with E2E_MVN7 when a developer keeps separate settings.
# The local repository is only read: the v7 install and every download go to a repository of the bench (m2 beside the
# worktree), chained in front of it.
set -euo pipefail
. "$(dirname "$0")/python.sh"
BENCH=$(cd "$(dirname "$0")/.." && pwd)
E2E=${E2E_DIR:-$PWD}
# The environment wins over e2e.conf, as in run.sh: a caller that exported E2E_… (E2E_MYLUTECE=0 for one run, for
# instance) must not have its choice overwritten by the file.
_e2e_env=$(export -p | grep -E "^(declare -x |export )E2E_" || true)
. "$E2E/e2e.conf"
eval "$_e2e_env"
SRC=$(cd "$E2E/$E2E_SRC" && pwd)
SITE=${E2E_SITE7_BUILD:?the directory the v7 site is built in}
WT="$SITE/../src7"
mkdir -p "$SITE"
cp "$BENCH/harness/site7/pom.xml.tpl" "$SITE/"
mkdir -p "$SITE/webapp" && cp -a "$BENCH/harness/site7/webapp/." "$SITE/webapp/"
# Plain mvn by default: the site pom declares its repositories. A developer keeping separate v7 settings sets
# E2E_MVN7="mvn -s <path>" in e2e.conf; nothing here depends on one workstation.
MVN7="${E2E_MVN7:-${MVN:-mvn}}"
REF="${E2E_V7_REF:-HEAD}"
SITE_POM="${E2E_V7_SITE_POM:-7.0.8}"
CORE="${E2E_V7_CORE:-7.1.9}"

eval_pom() { $MVN7 -q -f "$1" help:evaluate -Dexpression="$2" -DforceStdout 2>/dev/null; }

case "$E2E_TARGET" in
  plugin) ;;
  site) [ -d "${E2E_V7_WAR:-}/WEB-INF" ] || { echo "gen-site7.sh: a site target takes its v7 before from E2E_V7_WAR, the v7 site assembled by tools/site-assemble.sh without an environment profile" >&2; exit 2; } ;;
  *) echo "gen-site7.sh: only a plugin or a site target has a v7 before; E2E_TARGET=$E2E_TARGET" >&2; exit 2 ;;
esac

if [ "$E2E_TARGET" = plugin ]; then

# -- the v7 sources, in a worktree that never touches the migrated tree ---------------------------------------------
# A worktree left by a bench copied from another clone points at that clone's .git: reusing it fails with "not a git
# repository", or builds the other clone's sources. Keep it only when it belongs to $SRC.
if [ -e "$WT/.git" ] && [ "$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" != "$(git -C "$SRC" rev-parse --path-format=absolute --git-common-dir)" ]; then
  echo ">> $WT is a worktree of another clone: removed and re-added from $SRC"
  rm -rf "$WT"; git -C "$SRC" worktree prune
fi
if [ -d "$WT/.git" ] || [ -f "$WT/.git" ]; then
  # --force: a previous run may have pinned a dependency in this pom, and the worktree is disposable.
  git -C "$WT" checkout -q --force --detach "$(git -C "$SRC" rev-parse "$REF")"
else
  git -C "$SRC" worktree add -q --detach "$WT" "$(git -C "$SRC" rev-parse "$REF")"
fi
# A v7 tree does not always compile against the v7 core the bench runs: an artefact left on an older core keeps a
# call the 7.x line removed (a constructor, a method), and no choice of E2E_V7_CORE fixes it — the code never
# compiled against that core. `harness/src7-overlay` is copied over the disposable worktree, same paths as the
# sources, so the v7 site builds. It holds v7 code, never migrated code, and the
# migrated tree is never touched. Each file deserves a comment saying which core release broke it.
if [ -d "$E2E/harness/src7-overlay" ]; then
  cp -a "$E2E/harness/src7-overlay/." "$WT/"
  echo ">> v7 source overlay applied: $(cd "$E2E/harness/src7-overlay" && find . -type f | sed 's|^\./||' | tr '\n' ' ')"
fi

V7_PARENT=$(grep -A4 '<parent>' "$WT/pom.xml" | grep -oE '<version>[^<]+' | head -1 | sed 's/<version>//')
case "$V7_PARENT" in 7.*|6.*|5.*) ;; *) echo "gen-site7.sh: $REF has parent $V7_PARENT, not a v7 tree (set E2E_V7_REF)" >&2; exit 2 ;; esac

# A v7 pom often declares its dependencies as ranges, and the top of the range has moved on since: the sources
# no longer compile against what Maven resolves today, and the v7 site cannot be built at all. E2E_V7_DEP_PINS
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
    # A Lutece plugin or module comes as a lutece-plugin: declared as a plain jar it would shadow that dependency
    # and the site would lose the plugin's webapp (descriptor, Spring context, templates).
    kind = "\n            <type>lutece-plugin</type>" if re.match(r"(plugin|module)-", a) else ""
    dep = "        <dependency>\n            <groupId>%s</groupId>\n            <artifactId>%s</artifactId>\n            <version>%s</version>%s\n        </dependency>\n" % (g, a, v, kind)
    if "</dependencies>" not in t:
        sys.exit("gen-site7.sh: the v7 pom has no <dependencies> to add %s:%s to" % (g, a))
    t2 = t.replace("</dependencies>", dep + "    </dependencies>", 1)
open(pom, "w", encoding="utf-8").write(t2)
PYPIN
  echo ">> v7 dependency pinned: $PG:$PA -> $PV"
done

# The v7 build reaches the network as the user's Maven does: a bench settings file (E2E_MVN7="mvn -s <file>") gets
# the proxies and mirrors of ~/.m2/settings.xml in a copy beside the worktree, outside git. A repository that does
# not answer stops the run here, in seconds, rather than a Maven waiting on a connection that never opens.
NET_SETTINGS="$HOME/.m2/settings.xml"
read -ra _mvn <<< "$MVN7"
for i in "${!_mvn[@]}"; do
  case "${_mvn[$i]}" in
    -s|--settings)
      j=$((i + 1)); [ -n "${_mvn[$j]:-}" ] || break
      NET_SETTINGS="$(cd "$SITE/.." && pwd)/settings7.xml"
      python3 "$BENCH/tools/maven-net.py" merge "${_mvn[$j]}" "$HOME/.m2/settings.xml" "$NET_SETTINGS"
      echo ">> v7 Maven settings: ${_mvn[$j]}, with the proxies and mirrors of $HOME/.m2/settings.xml ($NET_SETTINGS)"
      _mvn[$j]="$NET_SETTINGS"; MVN7="${_mvn[*]}" ;;
  esac
done
case " $MVN7 " in
  *" -o "*|*" --offline "*) ;;
  *)
    REPOS=$(sed -n 's:.*<url>\(http[^<]*\)</url>.*:\1:p' "$SITE/pom.xml.tpl")
    if ! DOWN=$(python3 "$BENCH/tools/maven-net.py" probe "$NET_SETTINGS" https://repo.maven.apache.org/maven2/ $REPOS); then
      echo "gen-site7.sh: the v7 build cannot reach its Maven repositories (settings $NET_SETTINGS):" >&2
      echo "$DOWN" >&2
      echo "  connect the network they need (VPN, proxy of $HOME/.m2/settings.xml) and run again" >&2
      exit 1
    fi ;;
esac

# The v7 sources carry the same version as an artefact another bench or the developer installed: installed in the
# shared local repository they would replace it, or bring back an older build under its number. Maven reads that
# repository as the tail of a chained one (Maven 3.9) whose head, beside the worktree, takes the install and the
# downloads.
M2_TAIL=$($MVN7 -q -o -N help:evaluate -Dexpression=settings.localRepository -DforceStdout 2>/dev/null </dev/null || true)
[ -d "$M2_TAIL" ] || M2_TAIL="$HOME/.m2/repository"
M2_HEAD="$(cd "$SITE/.." && pwd)/m2"
MVN7="$MVN7 -Dmaven.repo.local=$M2_HEAD -Dmaven.repo.local.tail=$M2_TAIL"
echo ">> v7 Maven repository: $M2_HEAD, reading $M2_TAIL"

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
# site needs the same probe. The probe is the bench's, not the artefact's: it is copied as is.
# The bench's own property overrides belong to both sites: the v8 site gets them from
# harness/site/webapp/WEB-INF/conf/override, and Lutece 7 reads the same directory. Without them the v7 artefact
# calls the real outside systems instead of the bench's stand-ins.
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
    "$BENCH/harness/site/plugins.dat.tpl" > "$SITE/webapp/WEB-INF/plugins/plugins.dat"

echo ">> assemble v7 war"
( cd "$SITE" && $MVN7 -B -q clean package lutece:site-assembly )
FINAL=$(find "$SITE/target" -maxdepth 1 -type d -name "e2e-site7-*" | head -1)
[ -n "$FINAL" ] || { echo "site-assembly produced no exploded directory under $SITE/target" >&2; exit 1; }
else
  # A site is its own v7 before: the war tools/site-assemble.sh exploded, without an environment profile so that no
  # value of a real environment (its database, its identity provider, its search cluster) comes into the bench. The
  # bench's database settings, property overrides and probe pages are laid over it, as for a plugin.
  rm -rf "$SITE/target"; mkdir -p "$SITE/target"
  FINAL="$SITE/target/e2e-site7-site"
  cp -a "$E2E_V7_WAR" "$FINAL"
  cp "$SITE/webapp/WEB-INF/conf/db.properties" "$FINAL/WEB-INF/conf/db.properties"
  if [ -d "$E2E/harness/site/webapp/WEB-INF/conf/override" ]; then
    mkdir -p "$FINAL/WEB-INF/conf/override" && cp -a "$E2E/harness/site/webapp/WEB-INF/conf/override/." "$FINAL/WEB-INF/conf/override/"
  fi
  if [ -d "$E2E/harness/site/webapp/jsp/e2e" ]; then
    mkdir -p "$FINAL/jsp/e2e" && cp -a "$E2E/harness/site/webapp/jsp/e2e/." "$FINAL/jsp/e2e/"
  fi
  CORE=$(find "$FINAL/WEB-INF/lib" -maxdepth 1 -name "lutece-core-*.jar" | head -1 | sed -E 's#.*/lutece-core-(.*)\.jar#\1#')
  echo ">> v7 site: $E2E_V7_WAR, core $CORE, database settings of the bench"
fi
# The v7 core reads its .properties through MicroProfile Config, so the environment reaches them; a literal in a
# Spring context XML reads nothing: the v7 site would call the real outside system. `harness/v7-overlay` is laid over the assembled
# v7 webapp, after assembly so the artefact's own files are already there, for what only a file can change.
if [ -d "$E2E/harness/v7-overlay" ]; then
  cp -a "$E2E/harness/v7-overlay/." "$FINAL/"
  echo ">> v7 overlay applied: $(cd "$E2E/harness/v7-overlay" && find . -type f | sed 's|^\./||' | tr '\n' ' ')"
fi
# Same as the v8 site: a search plugin points at a local engine by default, the bench reaches containers by name.
# Written after the overlay so a bench that ships its own file still wins.
if [ -f "$FINAL/WEB-INF/conf/plugins/search-solr.properties" ] && [ ! -f "$FINAL/WEB-INF/conf/override/plugins/search-solr.properties" ]; then
  mkdir -p "$FINAL/WEB-INF/conf/override/plugins"
  printf '# e2e bench: reach the real Solr container (reference/external-systems.md, Search engines)\nsolr.server.address=http://solr:8983/solr/%s\nsolr.indexer.commit.size=10000\n' \
    "${E2E_SOLR_CORE:-lutece}" > "$FINAL/WEB-INF/conf/override/plugins/search-solr.properties"
  echo ">> solr address overridden on the v7 site: http://solr:8983/solr/${E2E_SOLR_CORE:-lutece}"
fi
# The v7 image runs the Java of E2E_V7_JAVA (11 by default). A version range of the v7 artefact can resolve to a v8
# release built for a newer Java: the site then fails to start on UnsupportedClassVersionError, far from the cause.
# Named here with the pin to add (E2E_V7_DEP_PINS), or the Java the environments run (E2E_V7_JAVA), before any container starts.
V7_JAVA="${E2E_V7_JAVA:-11}"
NEWER=$(python3 - "$FINAL/WEB-INF/lib" "$V7_JAVA" <<'PYJVM'
import glob, os, struct, sys, zipfile
for jar in sorted(glob.glob(os.path.join(sys.argv[1], "*.jar"))):
    try:
        with zipfile.ZipFile(jar) as z:
            names = [n for n in z.namelist() if n.endswith(".class") and not n.startswith("META-INF/") and not n.endswith("module-info.class")]
            heads = [z.read(n)[:8] for n in names[:20]]
            major = max((struct.unpack(">H", h[6:8])[0] for h in heads if len(h) == 8 and h[:4] == b"\xca\xfe\xba\xbe"), default=0)
    except (zipfile.BadZipFile, OSError):
        continue
    if major > 44 + int(sys.argv[2]):
        print("%s (class version %d, Java %d)" % (os.path.basename(jar), major, major - 44))
PYJVM
)
if [ -n "$NEWER" ]; then
  echo "gen-site7.sh: the v7 site carries artefacts built for a newer Java than its Java $V7_JAVA image, it cannot start:" >&2
  echo "$NEWER" | sed 's/^/  /' >&2
  echo "  pin their v7 versions in e2e.conf, E2E_V7_DEP_PINS=groupId:artifactId:version,... (the versions the v7 site of the parent plugin runs)," >&2
  echo "  or set E2E_V7_JAVA=17 when the environments run the v7 site on Java 17" >&2
  exit 1
fi
echo ">> v7 site: $FINAL"
# The component names and versions the v7 site ships, in the form plugin-liquibase records them
# (core.plugins.status.<name>.version), from the plugin descriptors: lpe2e upgrade reports those its v7 start recorded
# no version for.
{ echo "core=$CORE"
  python3 - "$FINAL/WEB-INF/plugins" <<'PYVER'
import glob, os, re, sys
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.xml"))):
    t = open(f, encoding="utf-8", errors="replace").read()
    t = re.sub(r"<!--.*?-->", "", t, flags=re.S)
    n, v = re.search(r"<name>\s*([^<]+?)\s*</name>", t), re.search(r"<version>\s*([^<]+?)\s*</version>", t)
    if n and v and n.group(1) != "core":
        print("%s=%s" % (n.group(1), v.group(1)))
PYVER
} > "$SITE/target/versions.properties"
