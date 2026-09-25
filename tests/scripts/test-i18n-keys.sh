#!/usr/bin/env bash
# Checks that check-i18n-keys.sh rebuilds a key glued with '+' from the constants of the file, reports it when the
# bundle lacks it, skips a key read from a configuration properties file, and still reports a missing literal key.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
C="$HERE/../../skills/lutece-migration-v8-agent-teams/scripts/check-i18n-keys.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/p/src/java/fr/paris/lutece/plugins/myplugin/resources" "$T/p/src/java/fr/paris/lutece/plugins/myplugin/web" \
         "$T/p/webapp/WEB-INF/conf/plugins" "$T/core/admin/themes/tabler" "$T/core/skin/themes/macros"
printf 'menu.home=Home\nlabel.title=Title\n' > "$T/p/src/java/fr/paris/lutece/plugins/myplugin/resources/myplugin_messages.properties"
printf 'myplugin.error.MES01=Select an item\n' > "$T/p/webapp/WEB-INF/conf/plugins/myplugin.properties"
cat > "$T/p/src/java/fr/paris/lutece/plugins/myplugin/web/MyJspBean.java" <<'EOF'
public class MyJspBean
{
    private static final String PREFIX_MENU = "myplugin.menu.";
    private static final String MENU_HOME = "home";
    private static final String MENU_GONE = "gone";
    public void render( )
    {
        I18nService.getLocalizedString( PREFIX_MENU + MENU_HOME, locale );
        I18nService.getLocalizedString( PREFIX_MENU + MENU_GONE, locale );
        I18nService.getLocalizedString( "myplugin.label.missing", locale );
        form.addError( request, "myplugin.error.MES01" );
    }
}
EOF
OUT=$(LUTECE_CORE_TEMPLATES="$T/core" bash "$C" "$T/p" 2>&1)
fails=0
echo "$OUT" | grep -q "myplugin.menu.gone" || { echo "FAIL: a missing key glued with + is not reported"; fails=1; }
echo "$OUT" | grep -q "myplugin.menu.home" && { echo "FAIL: an existing key glued with + is reported"; fails=1; }
echo "$OUT" | grep -q "myplugin.menu\. " && { echo "FAIL: the bare prefix of a glued key is reported as a key"; fails=1; }
echo "$OUT" | grep -q "MES01" && { echo "FAIL: a key of a configuration properties file is reported"; fails=1; }
echo "$OUT" | grep -q "myplugin.label.missing" || { echo "FAIL: a missing literal key is not reported"; fails=1; }
[ "$fails" -eq 0 ] && { echo "PASS: i18n keys glued with + are rebuilt, configuration keys are skipped, missing keys still reported"; exit 0; }
echo "$OUT"; exit 1
