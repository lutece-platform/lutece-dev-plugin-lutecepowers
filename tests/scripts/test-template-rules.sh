#!/usr/bin/env bash
# Checks the house template rules (template_rules.py, scanner TD55/TD56) and verify-migration's DA02 and I18N07 on
# small synthetic inputs: each rule must flag its bad case and leave its good case alone.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/../../skills/lutece-migration-v8-agent-teams/scripts"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
expect() {
    local what=$1 want=$2 got=$3
    if [ "$want" = "$got" ]; then echo "  ok   $what"; else echo "  FAIL $what (expected $want, got $got)"; fail=1; fi
}
rule() { python3 "$S/template_rules.py" "$1" "$2" >/dev/null; echo $?; }

A="$T/admin.html"
printf "<@tform action='x'><@row><@columns md=4><@input name='a' /></@columns><@columns md=4><@input name='b' /></@columns><@columns md=4><@input name='c' /></@columns></@row></@tform>\n" > "$A"
expect "inline-forms: three field columns in a row" 1 "$(rule inline-forms "$A")"
printf "<@tform action='x'><@row><@columns md=6><@input name='a' /></@columns><@columns md=6><@input name='b' /></@columns></@row></@tform>\n" > "$A"
expect "inline-forms: two field columns are fine" 0 "$(rule inline-forms "$A")"
printf "<@tform action='x'><@row><@columns md=6><@input name='a' /></@columns><@columns md=6><@input name='b' /></@columns><@columns md=6><@input name='c' /></@columns><@columns md=6><@input name='d' /></@columns></@row></@tform>\n" > "$A"
expect "inline-forms: four md=6 columns wrap two per line" 0 "$(rule inline-forms "$A")"
printf "<@tform action='x'><@row><@columns md=6><@row><@columns md=6><@input name='a' /></@columns><@columns md=6><@input name='b' /></@columns></@row></@columns><@columns md=6><@input name='c' /></@columns></@row></@tform>\n" > "$A"
expect "inline-forms: a nested row is not counted in the outer one" 0 "$(rule inline-forms "$A")"
printf "<@tform action='x'><@row><@columns md=4><@input name='a' /></@columns><@columns md=4><@input name='b' /></@columns><@columns md=4><@input name='c' /></@columns></@row></@tform>\n" > "$A"
expect "inline-forms: three md=4 field columns" 1 "$(rule inline-forms "$A")"
printf "<@tform action='x'><@row><@columns md=4><@checkBox name='a' /></@columns><@columns md=4><@checkBox name='b' /></@columns><@columns md=4><@checkBox name='c' /></@columns></@row></@tform>\n" > "$A"
expect "inline-forms: a grid of switches is fine" 0 "$(rule inline-forms "$A")"
printf "<@tform action='x' class='d-flex flex-column'><@input name='a' /><@input name='b' /><@input name='c' /></@tform>\n" > "$A"
expect "inline-forms: d-flex flex-column stacks the fields" 0 "$(rule inline-forms "$A")"
printf "<@tform type='inline' action='x'><@input name='a' /><@input name='b' /><@input name='c' /></@tform>\n" > "$A"
expect "inline-forms: type inline with three fields" 1 "$(rule inline-forms "$A")"
printf "<@tform type='inline' action='x'><@input type='hidden' name='id' /><@button type='submit' title='Export' /></@tform>\n" > "$A"
expect "inline-forms: hidden form with one submit" 0 "$(rule inline-forms "$A")"
printf "<@offcanvas id='x' title='t'>body</@offcanvas>\n" > "$A"
expect "offcanvas: flagged" 1 "$(rule offcanvas "$A")"

W="$T/proj"
J="$T/java"
mkdir -p "$W/webapp/WEB-INF/templates/admin/plugins/x" "$J/src/java/x/business" "$J/src/java/x/resources"
td() { (cd "$W" && python3 "$S/scan-template-design.py" . --flat --no-exploded 2>/dev/null | grep -c " $1 "); }
printf "<@pageContainer><@aButton href='jsp/admin/plugins/x/ManageX.jsp' title='#i18n{portal.util.labelCancel}' /></@pageContainer>\n" > "$W/webapp/WEB-INF/templates/admin/plugins/x/a.html"
expect "TD56: cancel without colour" 1 "$(td TD56)"
printf "<@pageContainer><@aButton href='jsp/admin/plugins/x/ManageX.jsp' title='#i18n{portal.util.labelCancel}' color='light' /></@pageContainer>\n" > "$W/webapp/WEB-INF/templates/admin/plugins/x/a.html"
expect "TD56: cancel in light" 0 "$(td TD56)"
printf "<@pageContainer><#if l?has_content>x<#else><@empty title='a' /></#if></@pageContainer>\n" > "$W/webapp/WEB-INF/templates/admin/plugins/x/a.html"
expect "TD55: empty state without subtitle, no create action" 1 "$(td TD55)"
printf "<@pageContainer><@aButton href='jsp/admin/plugins/x/ManageX.jsp?view=createX' buttonIcon='plus' title='a' /><@empty /></@pageContainer>\n" > "$W/webapp/WEB-INF/templates/admin/plugins/x/a.html"
expect "TD55: page with a create action" 0 "$(td TD55)"

printf "<@tform action='x'><@box><@boxBody>a</@boxBody><@boxFooter><@button type='submit' title='ok' /></@boxFooter></@box><@box><@boxBody>b</@boxBody></@box></@tform>\n" > "$W/webapp/WEB-INF/templates/admin/plugins/x/a.html"
expect "TD58: submit in one box footer of a two-box form" 1 "$(td TD58)"
printf "<@tform action='x'><@box><@boxBody>a</@boxBody></@box><@box><@boxBody>b</@boxBody></@box><@row><@button type='submit' title='ok' /></@row></@tform>\n" > "$W/webapp/WEB-INF/templates/admin/plugins/x/a.html"
expect "TD58: actions below the boxes" 0 "$(td TD58)"

mkdir -p "$W/webapp/WEB-INF/plugins" "$W/webapp/themes/admin/x/css"
echo "<plug-in><admin-css-stylesheets><admin-css-stylesheet>themes/admin/x/css/x.css</admin-css-stylesheet></admin-css-stylesheets></plug-in>" > "$W/webapp/WEB-INF/plugins/x.xml"
printf "#id_form { max-width: 32rem; }\n" > "$W/webapp/themes/admin/x/css/x.css"
expect "TD57: generic id in a stylesheet loaded on every page" 1 "$(td TD57)"
printf ".x-plugin #id_form { max-width: 32rem; }\n#x-chart-list { margin: 0; }\n" > "$W/webapp/themes/admin/x/css/x.css"
expect "TD57: rules scoped to the plugin" 0 "$(td TD57)"

printf "<@button type='submit' title='#i18n{portal.util.labelValidate}' />\n<@aButton href='x' title='#i18n{portal.util.labelBack}' color='secondary' />\n<@aButton href='x' title='#i18n{portal.util.labelCancel}' />\n<@button cancel=true title='#i18n{portal.util.labelCancel}' />\n" > "$W/webapp/WEB-INF/templates/admin/plugins/x/a.html"
expect "TD56 before fix-button-colours" 1 "$(td TD56)"
python3 "$S/fix-button-colours.py" "$W" > /dev/null
expect "TD51 secondary and cancel=true made light" 2 "$(grep -cE "color='secondary'|cancel=true title='#i18n\{portal.util.labelCancel\}' color='light'|labelBack\}' color='light'" "$W/webapp/WEB-INF/templates/admin/plugins/x/a.html")"
expect "TD56 after fix-button-colours" 0 "$(td TD56)"
expect "submit button left as it is" 1 "$(grep -c "type='submit' title='#i18n{portal.util.labelValidate}' />" "$W/webapp/WEB-INF/templates/admin/plugins/x/a.html")"
expect "fix-button-colours is idempotent" 0 "$(python3 "$S/fix-button-colours.py" "$W" | wc -l)"

vm() { (cd "$J" && bash "$S/verify-migration.sh" . 2>/dev/null | grep "\[$1\]" | grep -c "$2"); }
printf 'class XDAO {\n    public void f( Plugin plugin )\n    {\n        DAOUtil daoUtil = new DAOUtil( SQL, plugin );\n        daoUtil.executeUpdate( );\n    }\n}\n' > "$J/src/java/x/business/XDAO.java"
expect "DA02: DAOUtil outside try-with-resources" 1 "$(vm DA02 FAIL)"
printf 'class XDAO {\n    private DAOUtil build( Plugin plugin )\n    {\n        DAOUtil daoUtil = new DAOUtil( SQL, plugin );\n        daoUtil.setInt( 1, 2 );\n        return daoUtil;\n    }\n}\n' > "$J/src/java/x/business/XDAO.java"
expect "DA02: factory returning its DAOUtil" 1 "$(vm DA02 PASS)"
printf 'message.confirm=Etes vous sur de vouloir supprimer ce PollFormQuestion ?\n' > "$J/src/java/x/resources/x_messages_fr.properties"
expect "I18N07: French spelling error" 1 "$(vm I18N07 WARN)"
printf 'message.confirm=\\u00cates-vous s\\u00fbr de vouloir supprimer ce graphique ?\n' > "$J/src/java/x/resources/x_messages_fr.properties"
expect "I18N07: correct French" 1 "$(vm I18N07 PASS)"

mkdir -p "$J/webapp/jsp/admin/plugins/x" "$J/src/java/x/web"
printf '${ xPortletJspBean.init( pageContext.request, "R" ) }\n' > "$J/webapp/jsp/admin/plugins/x/CreatePortletX.jsp"
printf 'public abstract class AbstractXPortletJspBean extends PortletJspBean\n{\n}\n' > "$J/src/java/x/web/AbstractXPortletJspBean.java"
printf 'public class XPortletJspBean extends AbstractXPortletJspBean\n{\n}\n' > "$J/src/java/x/web/XPortletJspBean.java"
expect "JS04: portlet bean through a local base class" 1 "$(vm JS04 PASS)"
printf 'public abstract class AbstractXPortletJspBean extends AdminFeaturesPageJspBean\n{\n}\n' > "$J/src/java/x/web/AbstractXPortletJspBean.java"
expect "JS04: legacy bean through a local base class" 1 "$(vm JS04 FAIL)"

mkdir -p "$J/webapp/js/plugins/x"
printf 'function a(v) {\n\tif (v) {\n\t\treturn 1;\n\t} else {\t{\n\t\treturn 2;\n\t}\n}\n' > "$J/webapp/js/plugins/x/x.js"
expect "JS07: script with an extra brace" 1 "$(vm JS07 FAIL)"
printf 'function a(v) {\n\treturn v ? 1 : 2;\n}\n' > "$J/webapp/js/plugins/x/x.js"
expect "JS07: script that parses" 1 "$(vm JS07 PASS)"

[ "$fail" -eq 0 ] && echo "PASS: template rules, TD55, TD56, TD57, TD58, DA02, I18N07, JS04, JS07, fix-button-colours"
exit $fail
