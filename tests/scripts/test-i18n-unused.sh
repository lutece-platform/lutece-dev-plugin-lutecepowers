#!/usr/bin/env bash
# Checks i18n_unused.py on a synthetic plugin: every way a Lutece key is used keeps it, only the dead key is reported.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../../skills/lutece-migration-v8-agent-teams/scripts/i18n_unused.py"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
P="$T/plugin-demo"
R="$T/refs"
mkdir -p "$P/src/java/fr/paris/lutece/plugins/demo/resources" "$P/src/java/fr/paris/lutece/plugins/demo/web" \
         "$P/webapp/WEB-INF/templates/admin/plugins/demo" "$P/webapp/WEB-INF/conf/plugins" "$P/webapp/WEB-INF/plugins" \
         "$P/src/sql/plugins/demo/core" "$P/webapp/js/plugins/demo" "$R/plugin-parent/webapp/WEB-INF/templates"
cat > "$P/src/java/fr/paris/lutece/plugins/demo/resources/demo_messages.properties" <<'EOF'
tpl.title=literal in a template
java.title=literal in Java
type.alpha=built from a Java constant
dyn.beta=built in a template
conf.label=named by a configuration file
sql.label=stored by an init SQL
xml.label=named by the plugin descriptor
js.label=named by a script
quoted.key=looked up by its bare key
parent.label=used by another repository
model.entity.demo.attribute.name=read by the validation at runtime
site_property.demo.help=read by the site properties screen
adminFeature.used.name=named by the descriptor
adminFeature.gone.name=a feature no descriptor declares
dead.label=nobody uses it
EOF
cp "$P/src/java/fr/paris/lutece/plugins/demo/resources/demo_messages.properties" "$P/src/java/fr/paris/lutece/plugins/demo/resources/demo_messages_fr.properties"
echo "<h1>#i18n{demo.tpl.title}</h1><p>#i18n{demo.dyn.\${item.code}}</p>" > "$P/webapp/WEB-INF/templates/admin/plugins/demo/manage.html"
cat > "$P/src/java/fr/paris/lutece/plugins/demo/web/DemoJspBean.java" <<'EOF'
class DemoJspBean {
    private static final String TITLE = "demo.java.title";
    private static final String PREFIX_TYPE = "demo.type.";
    private static final String KEY = "quoted.key";
    String label( String type ) { return I18nService.getLocalizedString( PREFIX_TYPE + type, null ); }
}
EOF
echo "demo.list=1,#i18n{demo.conf.label}" > "$P/webapp/WEB-INF/conf/plugins/demo.properties"
echo "INSERT INTO demo_type (label) VALUES ('demo.sql.label');" > "$P/src/sql/plugins/demo/core/init_core_demo.sql"
echo "<plugin><admin-feature><feature-title>demo.adminFeature.used.name</feature-title><feature-description>demo.xml.label</feature-description></admin-feature></plugin>" > "$P/webapp/WEB-INF/plugins/demo.xml"
echo "const k = 'demo.js.label';" > "$P/webapp/js/plugins/demo/demo.js"
echo "#i18n{demo.parent.label}" > "$R/plugin-parent/webapp/WEB-INF/templates/view.html"
OUT=$(python3 "$SCRIPT" "$P" --refs "$R")
RC=$?
fail=0
if [ "$RC" -ne 1 ] || [ "$(echo "$OUT" | wc -l)" -ne 2 ] || ! echo "$OUT" | grep -q ": dead.label$" || ! echo "$OUT" | grep -q ": adminFeature.gone.name$"; then
    echo "FAIL: expected only dead.label and adminFeature.gone.name, rc=1; got rc=$RC:"; echo "$OUT"; fail=1
fi
sed -i '/^dead.label=/d; /^adminFeature.gone.name=/d' "$P/src/java/fr/paris/lutece/plugins/demo/resources/demo_messages.properties"
OUT=$(python3 "$SCRIPT" "$P" --refs "$R"); RC=$?
if [ "$RC" -ne 0 ] || [ -n "$OUT" ]; then echo "FAIL: expected nothing once dead.label is gone; got rc=$RC: $OUT"; fail=1; fi
[ "$fail" -eq 0 ] && echo "PASS: i18n_unused keeps every used key and reports the dead ones, adminFeature keys included"
exit $fail
