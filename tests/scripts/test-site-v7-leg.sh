#!/usr/bin/env bash
# Checks the v7 leg of gen-site7.sh. Site mode: the v7 site of lpe2e upgrade is the site's own v7 war (E2E_V7_WAR),
# with the bench's database settings laid over the site's, and the versions it ships read from its plugin descriptors
# and its core jar. Plugin mode: every Maven run writes to the bench's own repository, the shared one only read.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SKILL="$HERE/../../skills/lutece-e2e"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
B="$T/bench"; E="$T/project/e2e"; S="$T/state/site7"
mkdir -p "$B/tools" "$B/harness/site7" "$E" "$T/v7/WEB-INF/lib" "$T/v7/WEB-INF/plugins" "$T/v7/WEB-INF/conf"
cp "$SKILL/tools/gen-site7.sh" "$B/tools/"
cp "$HERE/../../tools/python.sh" "$B/tools/"
cp -a "$SKILL/harness/site7/." "$B/harness/site7/"
printf 'E2E_TARGET=site\nE2E_SRC=..\nE2E_V7_WAR=%s\n' "$T/v7" > "$E/e2e.conf"
echo "portal.url=jdbc:mysql://production-host:3306/site" > "$T/v7/WEB-INF/conf/db.properties"
echo "<plug-in><name>forms</name><version>3.1.3</version></plug-in>" > "$T/v7/WEB-INF/plugins/forms.xml"
( cd "$T" && mkdir -p j/x && printf '\xca\xfe\xba\xbe\x00\x00\x00\x37' > j/x/A.class && cd j && jar -cf "$T/v7/WEB-INF/lib/lutece-core-7.1.5.jar" x/A.class )
OUT=$(E2E_DIR="$E" E2E_SITE7_BUILD="$S" bash "$B/tools/gen-site7.sh" 2>&1); RC=$?
fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
check "gen-site7.sh accepts a site target with E2E_V7_WAR" "[ $RC -eq 0 ]"
check "the bench database settings replace the site's" "grep -q 'jdbc:mysql://db:3306/lutece' '$S/target/e2e-site7-site/WEB-INF/conf/db.properties' && ! grep -q production-host '$S/target/e2e-site7-site/WEB-INF/conf/db.properties'"
check "versions.properties names the core and the plugins of the v7 war" "grep -qx 'core=7.1.5' '$S/target/versions.properties' && grep -qx 'forms=3.1.3' '$S/target/versions.properties'"
printf 'E2E_TARGET=site\nE2E_SRC=..\n' > "$E/e2e.conf"
OUT2=$(E2E_DIR="$E" E2E_SITE7_BUILD="$S" bash "$B/tools/gen-site7.sh" 2>&1); RC2=$?
check "a site target without E2E_V7_WAR is refused with the reason" "[ $RC2 -eq 2 ] && echo \"\$OUT2\" | grep -q E2E_V7_WAR"

P="$T/plugin"; S7="$T/state7/build7/site7"; SHARED="$T/shared-m2"
mkdir -p "$P/webapp/WEB-INF/plugins" "$P/e2e" "$T/bin" "$SHARED" "$B/harness/site"
cp "$SKILL/harness/site/plugins.dat.tpl" "$B/harness/site/"
printf '<project><parent><artifactId>lutece-global-pom</artifactId>\n<version>7.0.2</version></parent></project>\n' > "$P/pom.xml"
echo "<plug-in><name>x</name><version>1.0.0</version></plug-in>" > "$P/webapp/WEB-INF/plugins/x.xml"
printf 'E2E_TARGET=plugin\nE2E_SRC=..\nE2E_MYLUTECE=0\n' > "$P/e2e/e2e.conf"
git -C "$P" init -q && git -C "$P" add -A && git -C "$P" -c user.name=t -c user.email=t@t commit -qm v7
cat > "$T/bin/mvn" <<MVN
#!/usr/bin/env bash
echo "\$*" >> "$T/mvn.log"
case " \$* " in
  *help:evaluate*) case " \$* " in *settings.localRepository*) printf '%s' "$SHARED" ;; *project.groupId*) printf g ;;
                   *project.artifactId*) printf plugin-x ;; *project.version*) printf 1.0.0 ;; *) printf lutece-plugin ;; esac ;;
  *" install "*) r=\$(printf '%s\\n' "\$@" | sed -n 's/^-Dmaven.repo.local=//p'); mkdir -p "\$r/g/plugin-x/1.0.0" && touch "\$r/g/plugin-x/1.0.0/plugin-x-1.0.0.jar" ;;
  *lutece:site-assembly*) mkdir -p target/e2e-site7-x/WEB-INF/lib target/e2e-site7-x/WEB-INF/plugins ;;
esac
MVN
chmod +x "$T/bin/mvn"
OUT3=$(cd "$T" && PATH="$T/bin:$PATH" E2E_DIR="$P/e2e" E2E_SITE7_BUILD="$S7" bash "$B/tools/gen-site7.sh" 2>&1); RC3=$?
check "gen-site7.sh assembles a plugin's v7 site" "[ $RC3 -eq 0 ]"
check "every v7 Maven run but the probe writes to the bench's repository, the shared one as its tail" "! grep -v settings.localRepository '$T/mvn.log' | grep -qv -- '-Dmaven.repo.local=$T/state7/build7/m2 -Dmaven.repo.local.tail=$SHARED'"
check "the v7 install lands in the bench's repository, never in the shared one" "[ -f '$T/state7/build7/m2/g/plugin-x/1.0.0/plugin-x-1.0.0.jar' ] && [ -z \"\$(ls -A '$SHARED')\" ]"
[ $fail -eq 0 ] || { echo "$OUT"; echo "$OUT3"; cat "$T/mvn.log"; exit 1; }
