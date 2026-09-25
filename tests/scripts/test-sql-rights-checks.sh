#!/usr/bin/env bash
# Checks SQ07, WB09, PM13 and XT03 both ways, then the inventory resolving a constant defined as another constant and
# the error markers of an artefact living in the core namespace.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
V="${VERIFY:-$HERE/../../skills/lutece-migration-v8-agent-teams/scripts/verify-migration.sh}"
INV="$HERE/../../skills/lutece-e2e/tools/inventory.py"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0

# Prints the status of one check on a fixture directory.
status() {
    ( cd "$T/$1" && bash "$V" . 2>/dev/null ) | sed 's/\x1b\[[0-9;]*m//g' | grep -oE "(PASS|FAIL|WARN) \[$2\]" | head -1 | cut -d' ' -f1
}

# Records a failure when a check does not answer the expected status.
expect() {
    local got; got=$(status "$1" "$2")
    [ "$got" = "$3" ] || { echo "FAIL: $2 on $1 expected $3, got ${got:-nothing}"; fails=$((fails + 1)); }
}

for k in prerun upgrade; do mkdir -p "$T/sq-$k/src/sql/plugins/myplugin/plugin"; done
printf -- '-- liquibase formatted sql\n-- changeset myplugin:prerun_db_myplugin.sql\n-- validCheckSum: 9:abc\nSELECT 1;\n' > "$T/sq-prerun/src/sql/plugins/myplugin/plugin/prerun_db_myplugin.sql"
printf -- '-- liquibase formatted sql\n-- changeset myplugin:update_db_myplugin-1.0.0-1.0.1.sql\n-- validCheckSum: 9:abc\nSELECT 1;\n' > "$T/sq-upgrade/src/sql/plugins/myplugin/plugin/update_db_myplugin-1.0.0-1.0.1.sql"
expect sq-prerun SQ07 PASS
expect sq-upgrade SQ07 WARN

for k in own core; do mkdir -p "$T/wb-$k/webapp/WEB-INF/plugins"; done
printf '<plug-in><admin-features><admin-feature><feature-id>MYPLUGIN_MANAGEMENT</feature-id></admin-feature></admin-features></plug-in>\n' > "$T/wb-own/webapp/WEB-INF/plugins/myplugin.xml"
printf '<plug-in><admin-features><admin-feature><feature-id>CORE_STYLES_MANAGEMENT</feature-id></admin-feature></admin-features></plug-in>\n' > "$T/wb-core/webapp/WEB-INF/plugins/myplugin.xml"
expect wb-own WB09 PASS
expect wb-core WB09 WARN

for k in dao web mvc mvcok; do mkdir -p "$T/pm-$k/src/test/java"; printf '<project><dependencies></dependencies></project>\n' > "$T/pm-$k/pom.xml"; done
printf 'public class ThingDAOTest extends LuteceTestCase\n{\n}\n' > "$T/pm-dao/src/test/java/ThingDAOTest.java"
printf 'public class ThingJspBeanTest extends LuteceTestCase\n{\n    private ThingJspBean _bean;\n}\n' > "$T/pm-web/src/test/java/ThingJspBeanTest.java"
printf 'public class ThingJspBeanTest extends LuteceTestCase\n{\n    private ThingJspBean _bean;\n    void t( ) { _bean.processController( r, s ); }\n}\n' > "$T/pm-mvc/src/test/java/ThingJspBeanTest.java"
cp "$T/pm-mvc/src/test/java/ThingJspBeanTest.java" "$T/pm-mvcok/src/test/java/"
printf '<project><dependencies><dependency><artifactId>jaxb-runtime</artifactId></dependency><dependency><artifactId>hibernate-validator</artifactId></dependency><dependency><artifactId>expressly</artifactId></dependency></dependencies></project>\n' > "$T/pm-mvcok/pom.xml"
expect pm-dao PM13 PASS
expect pm-web PM13 WARN
expect pm-mvc PM13 WARN
expect pm-mvcok PM13 PASS

for k in rights table; do mkdir -p "$T/xt-$k/src/sql/plugins/myplugin/upgrade"; done
printf -- "-- liquibase formatted sql\n-- changeset myplugin:update_core_myplugin-1.0.0-1.0.1.sql\nUPDATE core_admin_right SET id_right = 'MY_STYLES' WHERE id_right = 'CORE_STYLES_MANAGEMENT';\n" > "$T/xt-rights/src/sql/plugins/myplugin/upgrade/update_core_myplugin-1.0.0-1.0.1.sql"
printf -- "-- liquibase formatted sql\n-- changeset myplugin:update_core_myplugin-1.0.0-1.0.1.sql\nDELETE FROM core_style WHERE id_style = 9;\n" > "$T/xt-table/src/sql/plugins/myplugin/upgrade/update_core_myplugin-1.0.0-1.0.1.sql"
expect xt-rights XT03 PASS
expect xt-table XT03 FAIL

mkdir -p "$T/inv/src/java/fr/paris/lutece/portal/web/thing" "$T/inv/webapp/jsp/admin/thing"
printf '<project><packaging>lutece-plugin</packaging></project>\n' > "$T/inv/pom.xml"
cat > "$T/inv/src/java/fr/paris/lutece/portal/web/thing/ThingJspBean.java" <<'JAVA'
package fr.paris.lutece.portal.web.thing;
import fr.paris.lutece.portal.util.mvc.commons.annotations.Action;
import fr.paris.lutece.portal.util.mvc.commons.annotations.View;
import fr.paris.lutece.portal.util.mvc.admin.annotations.Controller;
@Controller( controllerJsp = "ManageThings.jsp", controllerPath = "jsp/admin/thing/", right = "THING_MANAGEMENT" )
public class ThingJspBean extends MVCAdminJspBean
{
    private static final String VIEW_CREATE_THING = "createThing";
    private static final String ACTION_CREATE_THING = VIEW_CREATE_THING;
    @View( value = VIEW_CREATE_THING )
    public String getCreateThing( ) { return null; }
    @Action( value = ACTION_CREATE_THING )
    public String doCreateThing( ) { return null; }
}
JAVA
out=$(cd "$T" && python3 "$INV" "$T/inv" 2>/dev/null)
echo "$out" | grep -q 'ManageThings.jsp?action=createThing' || { echo "FAIL: an action defined as a view constant is not resolved to its value"; fails=$((fails + 1)); }
echo "$out" | python3 -c "
import json,sys
m=json.load(sys.stdin)['surface']['markers']
sys.exit(0 if 'fr.paris.lutece.portal.web.thing.ThingJspBean' in m and 'fr.paris.lutece.portal' not in m else 1)" || { echo "FAIL: an artefact in the core namespace is not marked by its own classes"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] && echo "PASS: SQ07, WB09, PM13, XT03 both ways, constant aliases resolved, core-namespace artefact marked by its classes"
exit "$fails"
