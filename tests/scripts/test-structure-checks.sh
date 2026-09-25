#!/usr/bin/env bash
# Checks TS06, ST01, WB04, WB07, ST03, JS04, SQ06 and MV03 both ways, each on a passing and a failing fixture.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
V="${VERIFY:-$HERE/../../skills/lutece-migration-v8-agent-teams/scripts/verify-migration.sh}"
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

mkdir -p "$T/ts-ok/src/test/java" "$T/ts-bad/src/test/java"
printf 'class ATest\n{\n    @Test\n    @DisplayName( "x" )\n    public void testX( ) { }\n}\n' > "$T/ts-ok/src/test/java/ATest.java"
printf 'class ATest\n{\n    @DisplayName( "x" )\n    public void testX( ) { }\n}\n' > "$T/ts-bad/src/test/java/ATest.java"
expect ts-ok TS06 PASS
expect ts-bad TS06 FAIL

mkdir -p "$T/st-none/src/java" "$T/st-cdi/src/java"
printf 'public final class MyUtil\n{\n    public static String x( ) { return ""; }\n}\n' > "$T/st-none/src/java/MyUtil.java"
printf '@ApplicationScoped\npublic class MyService { }\n' > "$T/st-cdi/src/java/MyService.java"
expect st-none ST01 PASS
expect st-cdi ST01 FAIL

mkdir -p "$T/wb-empty/webapp/WEB-INF/plugins" "$T/wb-value/webapp/WEB-INF/plugins"
printf '<plug-in><admin-features><admin-feature><feature-id>MY_FEATURE</feature-id><feature-icon-url></feature-icon-url></admin-feature></admin-features></plug-in>\n' > "$T/wb-empty/webapp/WEB-INF/plugins/myplugin.xml"
printf '<plug-in><admin-features><admin-feature><feature-id>MY_FEATURE</feature-id><feature-icon-url>ti ti-list</feature-icon-url></admin-feature></admin-features></plug-in>\n' > "$T/wb-value/webapp/WEB-INF/plugins/myplugin.xml"
expect wb-empty WB07 PASS
expect wb-value WB07 WARN

mkdir -p "$T/dao-abstract/src/java" "$T/dao-bare/src/java"
printf 'public abstract class MyGenericDAO\n{\n}\n' > "$T/dao-abstract/src/java/MyGenericDAO.java"
printf 'public class MyEntityDAO\n{\n}\n' > "$T/dao-bare/src/java/MyEntityDAO.java"
expect dao-abstract ST03 PASS
expect dao-bare ST03 FAIL

for k in comment real; do
    mkdir -p "$T/js-$k/src/java" "$T/js-$k/webapp/jsp/admin/plugins/myplugin"
    printf '<%%@ page errorPage="../../ErrorPage.jsp" %%>\n${ myEntityJspBean.doRemove( pageContext.request ) }\n' > "$T/js-$k/webapp/jsp/admin/plugins/myplugin/DoRemove.jsp"
    printf 'public class MyEntityJspBean extends MyBaseJspBean\n{\n}\n' > "$T/js-$k/src/java/MyEntityJspBean.java"
done
printf '/**\n * Base of the beans; the converted ones carry @Controller.\n */\npublic abstract class MyBaseJspBean\n{\n}\n' > "$T/js-comment/src/java/MyBaseJspBean.java"
printf '@Controller( controllerJsp = "ManageMyEntities.jsp", controllerPath = "jsp/admin/plugins/myplugin/", right = "MY_RIGHT" )\npublic abstract class MyBaseJspBean\n{\n}\n' > "$T/js-real/src/java/MyBaseJspBean.java"
expect js-comment JS04 FAIL
expect js-real JS04 PASS

for k in seen unseen; do
    mkdir -p "$T/sq-$k/src/sql/plugins/myplugin/plugin" "$T/sq-$k/target/lutece/WEB-INF/templates" "$T/sq-$k/target/lutece/WEB-INF/classes/sql/plugins/myplugin/plugin"
    printf -- '-- liquibase formatted sql\n-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql\nSELECT 1;\n' > "$T/sq-$k/src/sql/plugins/myplugin/plugin/update_db_myplugin-1.0.0-2.0.0.sql"
done
cp "$T/sq-seen/src/sql/plugins/myplugin/plugin/update_db_myplugin-1.0.0-2.0.0.sql" "$T/sq-seen/target/lutece/WEB-INF/classes/sql/plugins/myplugin/plugin/"
expect sq-seen SQ06 PASS
expect sq-unseen SQ06 FAIL

for k in on unset; do
    mkdir -p "$T/mv-$k/src/java"
done
printf 'import fr.paris.lutece.portal.util.mvc.xpage.annotations.Controller;\n@Controller( xpageName = "tasks",\n    securityTokenEnabled = true )\npublic class TasksXPage extends MVCApplication\n{\n}\n' > "$T/mv-on/src/java/TasksXPage.java"
printf 'import fr.paris.lutece.portal.util.mvc.xpage.annotations.Controller;\n@Controller( xpageName = "tasks" )\npublic class TasksXPage extends MVCApplication\n{\n}\n' > "$T/mv-unset/src/java/TasksXPage.java"
expect mv-on MV03 PASS
expect mv-unset MV03 WARN

for k in v800 v700; do
    mkdir -p "$T/wb4-$k/webapp/WEB-INF/plugins"
done
printf '<plug-in><min-core-version>8.0.0</min-core-version></plug-in>\n' > "$T/wb4-v800/webapp/WEB-INF/plugins/myplugin.xml"
printf '<plug-in><min-core-version>7.0.0</min-core-version></plug-in>\n' > "$T/wb4-v700/webapp/WEB-INF/plugins/myplugin.xml"
expect wb4-v800 WB04 PASS
expect wb4-v700 WB04 WARN

[ "$fails" -eq 0 ] && { echo "PASS: TS06 reads the annotation block, ST01 needs CDI beans, WB07 ignores an empty feature-icon-url, ST03 skips abstract DAO bases, JS04 ignores @Controller in comments, SQ06 finds SQL Liquibase never sees, MV03 flags a @Controller without securityTokenEnabled, WB04 accepts min-core-version 8.0.0"; exit 0; }
exit 1
