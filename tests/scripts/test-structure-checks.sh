#!/usr/bin/env bash
# Checks TS06, ST01, WB04, WB07, ST03, JS04, SQ06, SQ08, SQ09, SQ10, SQ11, SQ12, DL02, TS10 and MV03 both ways, each on a passing and a failing fixture,
# and that a check whose Python crashes fails instead of passing.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
V="${VERIFY:-$HERE/../../tools/verify-migration.sh}"
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
mkdir -p "$T/js-direct/src/java" "$T/js-direct/webapp/jsp/admin/plugins/myplugin"
cp -r "$T/js-real/src" "$T/js-real/webapp" "$T/js-direct/"
printf '<%%@ page errorPage="../../ErrorPage.jsp" %%>\n${ myEntityJspBean.processController( pageContext.request, pageContext.response ) }\n' > "$T/js-real/webapp/jsp/admin/plugins/myplugin/DoRemove.jsp"
expect js-comment JS04 FAIL
expect js-real JS04 PASS
expect js-direct JS04 FAIL
for k in jdbc jpa; do mkdir -p "$T/jp-$k/src/java"; done
printf 'class ADAO { static final String Q = "SELECT a FROM t WHERE id IN (?"; }\n' > "$T/jp-jdbc/src/java/ADAO.java"
printf 'import jakarta.persistence.Query;\nclass ADAO { static final String Q = "SELECT a FROM T a WHERE a.id IN (:ids)"; }\n' > "$T/jp-jpa/src/java/ADAO.java"
expect jp-jdbc JP04 PASS
expect jp-jpa JP04 FAIL
for k in jcap cap; do mkdir -p "$T/cd9-$k/src/java"; done
printf 'class A { static final String JCAPTCHA_PLUGIN = "jcaptcha"; boolean on( ) { return PluginService.isPluginEnable( JCAPTCHA_PLUGIN ); } }\n' > "$T/cd9-jcap/src/java/A.java"
printf 'class A { boolean on( ) { return _captchaService.isResolvable( ); } }\n' > "$T/cd9-cap/src/java/A.java"
expect cd9-jcap CD09 FAIL
expect cd9-cap CD09 PASS
for k in jxdoc jxcode wbcomment dtomodel; do mkdir -p "$T/g-$k/src/java" "$T/g-$k/webapp/WEB-INF/plugins"; done
printf '/**\n * Reads the {@link javax.servlet.http.HttpServletRequest} of v7.\n */\nclass A { }\n' > "$T/g-jxdoc/src/java/A.java"
printf 'import javax.servlet.http.HttpServletRequest;\nclass A { }\n' > "$T/g-jxcode/src/java/A.java"
printf '<plug-in><applications><application><!--<application-class>x.App</application-class>--></application></applications></plug-in>\n' > "$T/g-wbcomment/webapp/WEB-INF/plugins/x.xml"
printf 'class Dto\n{\n    public String getModel( )\n    {\n        return "";\n    }\n}\n' > "$T/g-dtomodel/src/java/Dto.java"
expect g-jxdoc JX01 PASS
expect g-jxcode JX01 FAIL
expect g-wbcomment WB02 PASS
expect g-dtomodel DP03 PASS
mkdir -p "$T/ts-sql/src/test/java" "$T/ts-sql/src/java" "$T/ts-sql/target/surefire-reports"
printf 'Tests run: 3, Failures: 1, Errors: 0, Skipped: 0 FAILURE\n' > "$T/ts-sql/target/surefire-reports/x.XTest.txt"
printf '<failure>Failed to execute:  INSERT INTO genatt_entry_type (id_type) VALUES (1)</failure>' > "$T/ts-sql/target/surefire-reports/antrun_report.xml"
( cd "$T/ts-sql" && bash "$V" . 2>/dev/null ) | sed 's/\x1b\[[0-9;]*m//g' | grep -A2 "\[TS09\]" | grep -q "test database was built with SQL errors" || { echo "FAIL: TS09 does not name the SQL errors of the test database"; fails=$((fails + 1)); }
mkdir -p "$T/js-usebean/src/java" "$T/js-usebean/webapp/jsp/admin/plugins/myplugin"
printf '<jsp:useBean id="tag" scope="session" class="fr.paris.lutece.plugins.myplugin.web.MyEntityJspBean" />\n<%%\n    response.sendRedirect( tag.doRemove( request ) );\n%%>\n' > "$T/js-usebean/webapp/jsp/admin/plugins/myplugin/DoRemove.jsp"
printf 'public class MyEntityJspBean extends PluginAdminPageJspBean\n{\n}\n' > "$T/js-usebean/src/java/MyEntityJspBean.java"
expect js-usebean JS04 FAIL
mkdir -p "$T/wb-query/webapp/WEB-INF/plugins" "$T/wb-query/src/sql/plugins/demo/plugin" "$T/wb-bare/webapp/WEB-INF/plugins"
printf '<plug-in><name>demo</name><admin-features><admin-feature><feature-id>DEMO_MANAGEMENT</feature-id><feature-url>jsp/admin/plugins/demo/ManageDemo.jsp</feature-url></admin-feature></admin-features></plug-in>\n' > "$T/wb-query/webapp/WEB-INF/plugins/demo.xml"
cp "$T/wb-query/webapp/WEB-INF/plugins/demo.xml" "$T/wb-bare/webapp/WEB-INF/plugins/demo.xml"
printf "INSERT INTO core_admin_right (id_right,name,level_right,admin_url,description) VALUES ('DEMO_MANAGEMENT','demo.adminFeature.name',3,'jsp/admin/plugins/demo/ManageDemo.jsp?view=home','demo.adminFeature.description');\n" > "$T/wb-query/src/sql/plugins/demo/plugin/init_core_demo.sql"
expect wb-query WB12 FAIL
expect wb-bare WB12 PASS
mkdir -p "$T/wb-diff/webapp/WEB-INF/plugins" "$T/wb-diff/src/sql/plugins/demo/plugin" "$T/wb-same/webapp/WEB-INF/plugins" "$T/wb-same/src/sql/plugins/demo/plugin"
printf '<plug-in><name>demo</name><admin-features><admin-feature><feature-id>DEMO_MANAGEMENT</feature-id><feature-url>jsp/admin/plugins/demo/ManageDemoHome.jsp</feature-url><icon-url>ti ti-no-such-glyph</icon-url></admin-feature></admin-features></plug-in>\n' > "$T/wb-diff/webapp/WEB-INF/plugins/demo.xml"
printf "INSERT INTO core_admin_right (id_right,name,level_right,admin_url,description,icon_url) VALUES ('DEMO_MANAGEMENT','demo.adminFeature.name',3,'jsp/admin/plugins/demo/ManageDemo.jsp','demo.adminFeature.description','ti ti-no-such-glyph');\n" > "$T/wb-diff/src/sql/plugins/demo/plugin/init_core_demo.sql"
printf '<plug-in><name>demo</name><admin-features><admin-feature><feature-id>DEMO_MANAGEMENT</feature-id><feature-url>jsp/admin/plugins/demo/ManageDemo.jsp</feature-url><icon-url>ti ti-address-book</icon-url></admin-feature></admin-features></plug-in>\n' > "$T/wb-same/webapp/WEB-INF/plugins/demo.xml"
printf "INSERT INTO core_admin_right (id_right,name,level_right,admin_url,description,icon_url) VALUES ('DEMO_MANAGEMENT','demo.adminFeature.name',3,'jsp/admin/plugins/demo/ManageDemo.jsp','demo.adminFeature.description','ti ti-address-book');\n" > "$T/wb-same/src/sql/plugins/demo/plugin/init_core_demo.sql"
expect wb-diff WB13 FAIL
expect wb-diff WB14 FAIL
expect wb-same WB13 PASS
expect wb-same WB14 PASS
mkdir -p "$T/wb-fixed/webapp/WEB-INF/plugins" "$T/wb-fixed/src/sql/plugins/demo/plugin" "$T/wb-bulk/webapp/WEB-INF/plugins" "$T/wb-bulk/src/sql/plugins/demo/plugin"
cp "$T/wb-same/webapp/WEB-INF/plugins/demo.xml" "$T/wb-fixed/webapp/WEB-INF/plugins/"; cp "$T/wb-same/webapp/WEB-INF/plugins/demo.xml" "$T/wb-bulk/webapp/WEB-INF/plugins/"
printf "INSERT INTO core_admin_right (id_right,name,level_right,admin_url,description,icon_url) VALUES ('DEMO_MANAGEMENT','demo.adminFeature.name',3,'jsp/admin/plugins/demo/ManageDemo.jsp','demo.adminFeature.description','images/admin/skin/plugins/demo/demo.png');\n-- changeset demo:init_core_demo-rev1.sql\nUPDATE core_admin_right SET icon_url = 'ti ti-address-book' WHERE id_right = 'DEMO_MANAGEMENT';\n" > "$T/wb-fixed/src/sql/plugins/demo/plugin/init_core_demo.sql"
printf "INSERT INTO core_admin_right (id_right,name,level_right,admin_url,description,icon_url) VALUES ('DEMO_MANAGEMENT','demo.adminFeature.name',3,'jsp/admin/plugins/demo/ManageDemo.jsp','demo.adminFeature.description','images/admin/skin/plugins/demo/demo.png');\nUPDATE core_admin_right SET icon_url = 'ti ti-address-book' WHERE plugin_name = 'demo';\n" > "$T/wb-bulk/src/sql/plugins/demo/plugin/init_core_demo.sql"
expect wb-fixed WB13 PASS
expect wb-fixed TM08 PASS
expect wb-bulk WB13 FAIL
mkdir -p "$T/wb-commented/webapp/WEB-INF/plugins" "$T/wb-commented/src/sql/plugins/demo/plugin"
cp "$T/wb-same/webapp/WEB-INF/plugins/demo.xml" "$T/wb-commented/webapp/WEB-INF/plugins/"
printf "INSERT INTO core_admin_right (id_right,name,level_right,admin_url,description,icon_url) VALUES ('DEMO_MANAGEMENT','demo.adminFeature.name',3,'jsp/admin/plugins/demo/ManageDemo.jsp','demo.adminFeature.description','ti ti-address-book');\n--INSERT INTO core_admin_right (id_right,name,level_right,admin_url,description,icon_url) VALUES ('DEMO_MANAGEMENT','x',3,'jsp/admin/plugins/demo/Old.jsp','x','images/admin/skin/plugins/demo/demo.png');\n" > "$T/wb-commented/src/sql/plugins/demo/plugin/init_core_demo.sql"
expect wb-commented WB13 PASS
expect wb-commented TM08 PASS
for k in sub bad dead; do mkdir -p "$T/i18n-$k/src/java/x/resources"; printf 'x.actionDelete=Delete\n' > "$T/i18n-$k/src/java/x/resources/x_messages.properties"; done
printf 'class A { static final String MESSAGE_DELETE = "x.x.actionDelete"; }\n' > "$T/i18n-sub/src/java/x/A.java"
printf 'class A { static final String MESSAGE_DELETE = "x.actionDelete"; }\n' > "$T/i18n-bad/src/java/x/A.java"
expect i18n-sub I18N01 PASS
expect i18n-bad I18N01 FAIL
printf 'class A { static final String MESSAGE_DELETE = "y.actionDelete"; }\n' > "$T/i18n-dead/src/java/x/A.java"
expect i18n-dead I18N01 PASS

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
for k in get view; do
    mkdir -p "$T/mv-$k/src/java" "$T/mv-$k/webapp/WEB-INF/templates/admin/themes/tabler" "$T/mv-$k/webapp/WEB-INF/templates/skin/themes/macros" "$T/mv-$k/webapp/WEB-INF/templates/admin/plugins/x"
    printf '@Controller( controllerJsp = "ManageX.jsp", controllerPath = "jsp/admin/plugins/x/", right = "X", securityTokenEnabled = true )\npublic class XJspBean extends MVCAdminJspBean\n{\n    public String getManage( HttpServletRequest request )\n    {\n        model.put( SecurityTokenService.MARK_TOKEN, _securityTokenService.getToken( request, "x" ) );\n        return "";\n    }\n}\n' > "$T/mv-$k/src/java/XJspBean.java"
done
printf '%s\n' "<@aButton href='jsp/admin/plugins/x/ManageX.jsp?action=doRemove&id=1&token=\${token}' />" "<script>const t = '\${token}';</script>" > "$T/mv-get/webapp/WEB-INF/templates/admin/plugins/x/manage.html"
printf '%s\n' "<@link href='jsp/admin/plugins/x/ManageX.jsp?view=modify&id=1&token=\${token}' />" "<@input type='hidden' name='token' value='\${token}' />" "<#-- <a href='x?action=doRemove&token=\${token}'> -->" > "$T/mv-view/webapp/WEB-INF/templates/admin/plugins/x/manage.html"
expect mv-get MV03 WARN
expect mv-view MV03 WARN
mvget=$( ( cd "$T/mv-get" && bash "$V" . 2>/dev/null ) | grep -c 'rides a GET link to an action or a script' )
[ "$mvget" = 2 ] || { echo "FAIL: MV03 names the action link and the script carrying the token (got $mvget)"; fails=$((fails + 1)); }
mvview=$( ( cd "$T/mv-view" && bash "$V" . 2>/dev/null ) | grep -c 'rides a GET link' )
[ "$mvview" = 0 ] || { echo "FAIL: MV03 leaves a view link, a hidden field and a comment alone (got $mvview)"; fails=$((fails + 1)); }

for k in v800 v700; do
    mkdir -p "$T/wb4-$k/webapp/WEB-INF/plugins"
done
printf '<plug-in><min-core-version>8.0.0</min-core-version></plug-in>\n' > "$T/wb4-v800/webapp/WEB-INF/plugins/myplugin.xml"
printf '<plug-in><min-core-version>7.0.0</min-core-version></plug-in>\n' > "$T/wb4-v700/webapp/WEB-INF/plugins/myplugin.xml"
expect wb4-v800 WB04 PASS
expect wb4-v700 WB04 WARN

for k in sq8-ok sq8-bad; do mkdir -p "$T/$k/webapp/WEB-INF/sql/plugins/old/plugin"; done
printf -- '-- liquibase formatted sql\n-- changeset old:init_db_old.sql\nSELECT 1;\n' > "$T/sq8-ok/webapp/WEB-INF/sql/plugins/old/plugin/init_db_old.sql"
printf 'INSERT INTO old_code VALUES (1);\n' > "$T/sq8-bad/webapp/WEB-INF/sql/plugins/old/plugin/init_db_old.sql"
expect sq8-ok SQ08 PASS
expect sq8-bad SQ08 FAIL

for k in sq9-ok sq9-bad; do
    mkdir -p "$T/$k/webapp/WEB-INF/plugins" "$T/$k/src/sql/plugins/myplugin/plugin"
    printf '<plug-in><name>myplugin</name></plug-in>\n' > "$T/$k/webapp/WEB-INF/plugins/myplugin.xml"
    printf -- '-- liquibase formatted sql\n-- changeset myplugin:create_db_myplugin.sql\nSELECT 1;\n' > "$T/$k/src/sql/plugins/myplugin/plugin/create_db_myplugin.sql"
done
mkdir -p "$T/sq9-bad/src/sql/plugins/other/plugin"
cp "$T/sq9-bad/src/sql/plugins/myplugin/plugin/create_db_myplugin.sql" "$T/sq9-bad/src/sql/plugins/other/plugin/create_db_other.sql"
expect sq9-ok SQ09 PASS
expect sq9-bad SQ09 FAIL

for k in sq10-ok sq10-bad; do mkdir -p "$T/$k/src/sql/plugins/myplugin/plugin"; done
printf -- '-- liquibase formatted sql\n-- changeset myplugin:a\nSELECT 1;\n-- changeset myplugin:b\n-- comment b\nSELECT 2;\n' > "$T/sq10-ok/src/sql/plugins/myplugin/plugin/init_db_myplugin.sql"
printf -- '-- liquibase formatted sql\n-- changeset myplugin:a\nSELECT 1;\n-- changeset myplugin:b\n-- comment b\n\n' > "$T/sq10-bad/src/sql/plugins/myplugin/plugin/init_db_myplugin.sql"
expect sq10-ok SQ10 PASS
expect sq10-bad SQ10 FAIL

U=src/sql/plugins/myplugin/upgrade/update_db_myplugin-1.0.0-1.1.0.sql
for k in sq11-dup sq12-ok sq12-rebase sq12-release; do mkdir -p "$T/$k/$(dirname "$U")"; done
printf -- '-- liquibase formatted sql\n-- changeset myplugin:rev1\nSELECT 1;\n-- changeset myplugin:rev1\nSELECT 2;\n' > "$T/sq11-dup/$U"
for k in sq12-ok sq12-rebase sq12-release; do
    printf -- '-- liquibase formatted sql\n-- changeset myplugin:rev1\nINSERT INTO t VALUES (1);\n' > "$T/$k/$U"
    ( cd "$T/$k" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm one ) >/dev/null
done
( cd "$T/sq12-release" && git tag v1 && printf -- '-- liquibase formatted sql\n-- changeset myplugin:rev1\nINSERT INTO t VALUES (9);\n' > "$U" \
    && git -c user.name=t -c user.email=t@t commit -qam two )
printf -- '-- liquibase formatted sql\n-- changeset myplugin:rev1\n-- preconditions onFail:MARK_RAN onError:WARN\nINSERT  INTO t VALUES (1);\n-- changeset myplugin:rev2\nSELECT 2;\n' > "$T/sq12-ok/$U"
printf -- '-- liquibase formatted sql\n-- changeset myplugin:rev1\nALTER TABLE t ADD c INT;\n' > "$T/sq12-rebase/$U"
expect sq11-dup SQ11 FAIL
expect sq12-ok SQ11 PASS
expect sq12-ok SQ12 PASS
expect sq12-rebase SQ12 WARN
expect sq12-release SQ12 WARN
mkdir -p "$T/sq12-latin1/$(dirname "$U")"
printf -- '-- liquibase formatted sql\n-- changeset myplugin:rev1\nINSERT INTO t VALUES (\x27r\xe9sum\xe9\x27);\n' > "$T/sq12-latin1/$U"
( cd "$T/sq12-latin1" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm one ) >/dev/null
printf -- '-- liquibase formatted sql\n-- changeset myplugin:rev1\nINSERT INTO t VALUES (\x27d\xe9j\xe0\x27);\n' > "$T/sq12-latin1/$U"
expect sq12-latin1 SQ12 WARN
printf '#!/usr/bin/env bash\nif [ "${1:-}" = - ]; then s=$(cat); case "$s" in *"def changesets"*) s="raise RuntimeError(\x27boom\x27)"$\x27\\n\x27"$s" ;; esac; exec %s "$@" <<< "$s"; fi\nexec %s "$@"\n' "$(command -v python3)" "$(command -v python3)" > "$T/crashpy"
chmod +x "$T/crashpy"
CRASH=$( cd "$T/sq12-ok" && LP_PYTHON="$T/crashpy" bash "$V" . 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' )
for id in SQ11 SQ12; do
    echo "$CRASH" | grep -q "FAIL \[$id\] NOT EVALUATED, the check crashed: RuntimeError: boom" || { echo "FAIL: a crashed $id must fail, not pass"; fails=$((fails + 1)); }
done
[ "$(echo "$CRASH" | grep -c "crashed")" -eq 2 ] || { echo "FAIL: the crash must not reach the results of other checks"; fails=$((fails + 1)); }

for k in dl2-bad dl2-declared dl2-v8; do mkdir -p "$T/$k/src/java/x"; printf '<project></project>\n' > "$T/$k/pom.xml"; done
printf 'import au.com.bytecode.opencsv.CSVReader;\nclass A { }\n' | tee "$T/dl2-bad/src/java/x/A.java" > "$T/dl2-declared/src/java/x/A.java"
printf '<project><dependencies><dependency><groupId>net.sf.opencsv</groupId><artifactId>opencsv</artifactId><version>1.8</version></dependency></dependencies></project>\n' > "$T/dl2-declared/pom.xml"
printf 'import com.opencsv.CSVReader;\nclass A { }\n' > "$T/dl2-v8/src/java/x/A.java"
expect dl2-bad DL02 FAIL
expect dl2-declared DL02 PASS
expect dl2-v8 DL02 PASS

for k in ts10-empty ts10-real; do mkdir -p "$T/$k/src/java/x" "$T/$k/src/test/java/x"; printf 'class Task { }\n' > "$T/$k/src/java/x/Task.java"; done
printf 'class ATest { void t( ) { assertTrue( true ); } // Task\n}\n' > "$T/ts10-empty/src/test/java/x/ATest.java"
printf 'class TaskTest { void t( ) { new Task( ); } }\n' > "$T/ts10-real/src/test/java/x/TaskTest.java"
expect ts10-empty TS10 WARN
expect ts10-real TS10 PASS

[ "$fails" -eq 0 ] && { echo "PASS: TS06 reads the annotation block, ST01 needs CDI beans, WB07 ignores an empty feature-icon-url, ST03 skips abstract DAO bases, JS04 ignores @Controller in comments, reads jsp:useBean and flags a @Controller called outside processController, WB12 reads admin_url, WB13 compares the install SQL with the descriptor (an appended update of one right counts, a bulk update does not), TD08 accepts an icon an appended update fixes, both skip a commented-out INSERT, WB14 knows the Tabler icons, I18N01 accepts a sub-namespace named like the plugin and leaves a dead key to I18N08, SQ06 finds SQL Liquibase never sees, MV03 flags a @Controller without securityTokenEnabled and names a token riding a GET action link or a script, not a view link, WB04 accepts min-core-version 8.0.0, SQ08 finds an untagged install script in the war, SQ09 a SQL directory no plugin owns, SQ10 an empty changeset, SQ11 a changeset id twice in a file, SQ12 a committed or released changeset with another body but not a new changeset, a precondition or spacing, in an ISO-8859-1 script too, a crashed check fails, DL02 an opencsv 2 import nothing declares, TS10 tests naming no class of the project (a comment does not count), JP04 JPA only, TS09 names a broken test database, CD09 the dead jcaptcha test, grep checks skip comments and declarations"; exit 0; }
exit 1
