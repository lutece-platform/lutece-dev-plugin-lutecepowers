#!/usr/bin/env bash
# Checks ST04, MV01, HM01, HM02, DP01 (java_checks.py, verify-file.sh) and SP03: each fires on its defect and stays silent on sound code.
set -u
. "$(dirname "$0")/../../tools/python.sh"
HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/../../tools"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
check() { if eval "$2"; then :; else echo "FAIL: $1"; fail=1; fi; }

P="$T/plugin"; J="$P/src/java/fr/paris/lutece/plugins/demo"
mkdir -p "$J/service" "$J/web" "$J/business"
echo '<project><packaging>lutece-plugin</packaging></project>' > "$P/pom.xml"
cat > "$J/service/PlainService.java" <<'EOF'
package fr.paris.lutece.plugins.demo.service;

public class PlainService
{
}
EOF
cat > "$J/service/ScopedService.java" <<'EOF'
package fr.paris.lutece.plugins.demo.service;

import jakarta.enterprise.context.ApplicationScoped;

@ApplicationScoped
public class ScopedService implements IScoped
{
}
EOF
cat > "$J/service/IScoped.java" <<'EOF'
package fr.paris.lutece.plugins.demo.service;

public interface IScoped
{
}
EOF
cat > "$J/service/ProducedThing.java" <<'EOF'
package fr.paris.lutece.plugins.demo.service;

public class ProducedThing
{
}
EOF
cat > "$J/service/ThingProducer.java" <<'EOF'
package fr.paris.lutece.plugins.demo.service;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;

@ApplicationScoped
public class ThingProducer
{
    @Produces
    public ProducedThing produce( )
    {
        return new ProducedThing( );
    }
}
EOF
cat > "$J/service/IListener.java" <<'EOF'
package fr.paris.lutece.plugins.demo.service;

public interface IListener
{
}
EOF
cat > "$J/service/NoBeanListener.java" <<'EOF'
package fr.paris.lutece.plugins.demo.service;

public class NoBeanListener implements IListener
{
}
EOF
cat > "$J/business/FileService.java" <<'EOF'
package fr.paris.lutece.plugins.demo.business;

public class FileService
{
}
EOF
cat > "$J/web/UserJspBean.java" <<'EOF'
package fr.paris.lutece.plugins.demo.web;

import fr.paris.lutece.plugins.demo.service.IScoped;
import fr.paris.lutece.plugins.demo.service.PlainService;
import fr.paris.lutece.plugins.demo.service.ProducedThing;
import fr.paris.lutece.plugins.demo.service.IListener;
import fr.paris.lutece.portal.service.file.FileService;
import fr.paris.lutece.portal.util.mvc.admin.MVCAdminJspBean;
import fr.paris.lutece.portal.util.mvc.admin.annotations.Controller;
import jakarta.enterprise.context.RequestScoped;
import jakarta.enterprise.inject.spi.CDI;
import jakarta.inject.Inject;
import java.util.HashMap;
import java.util.Map;

@RequestScoped
@Controller( controllerJsp = "ManageUser.jsp", controllerPath = "jsp/admin/plugins/demo/", right = "DEMO", securityTokenEnabled = true )
public class UserJspBean extends MVCAdminJspBean
{
    @Inject
    private PlainService _plain;
    @Inject
    private IScoped _scoped;
    @Inject
    private ProducedThing _thing;
    @Inject
    private FileService _coreFileService;

    public String getBroken( )
    {
        Map<String, Object> model = new HashMap<>( );
        model.put( "demo", "x" );
        return getPage( "title", "template", model );
    }

    public String getWithToken( )
    {
        Map<String, Object> model = new HashMap<>( );
        model.put( SecurityTokenService.MARK_TOKEN, "t" );
        return getPage( "title", "template", model );
    }

    public String getRedirect( )
    {
        Map<String, String> params = new HashMap<>( );
        params.put( "id", "1" );
        return redirect( null, "view", params );
    }

    public void listeners( )
    {
        CDI.current( ).select( IListener.class ).forEach( l -> { } );
    }
}
EOF
st04=$(python3 "$S/java_checks.py" st04 "$P")
mv01=$(python3 "$S/java_checks.py" mv01 "$P")
check "ST04 fires on an injected class that is no bean" 'echo "$st04" | grep -q "PlainService is resolved by CDI"'
check "ST04 silent on an interface implemented by a bean" '! echo "$st04" | grep -q "IScoped"'
check "ST04 silent on a produced type" '! echo "$st04" | grep -q "ProducedThing"'
check "ST04 silent on an iterated extension point" '! echo "$st04" | grep -q "IListener"'
check "ST04 silent on a same-name class of another package" '! echo "$st04" | grep -q "FileService"'
check "ST04 reports one finding" '[ "$(echo "$st04" | grep -c .)" = 1 ]'
check "MV01 fires on a page map without the token" 'echo "$mv01" | grep -q "UserJspBean.java:.*map model"'
check "MV01 reports only the broken page" '[ "$(echo "$mv01" | grep -c .)" = 1 ]'
vf=$(bash "$S/verify-file.sh" "$J/web/UserJspBean.java" 2>/dev/null)
check "verify-file MV01 counts the precise finding" 'echo "$vf" | grep -q "\"id\":\"MV01\",\"status\":\"FAIL\",[^}]*\"count\":1"'
sed -i 's/, securityTokenEnabled = true//' "$J/web/UserJspBean.java"
check "MV01 silent when the controller does not enable the token" '[ -z "$(python3 "$S/java_checks.py" mv01 "$P")" ]'
sed -i 's#<packaging>lutece-plugin</packaging>#<packaging>jar</packaging>#' "$P/pom.xml"
check "ST04 skips a library" '[ -z "$(python3 "$S/java_checks.py" st04 "$P")" ]'

W="$T/ctx"; mkdir -p "$W/webapp/WEB-INF/conf/plugins"
echo '<beans/>' > "$W/webapp/WEB-INF/conf/plugins/demo_context.xml"
check "SP03 fires on a context file left" '(cd "$W" && bash "$S/verify-migration.sh" . 2>/dev/null) | grep -q "FAIL.*\[SP03\]"'
rm "$W/webapp/WEB-INF/conf/plugins/demo_context.xml"
printf '<beans xmlns="http://www.springframework.org/schema/beans"/>\n' > "$W/webapp/WEB-INF/conf/plugins/context_demo_DAO.xml"
check "SP03 fires on an imported context file left" '(cd "$W" && bash "$S/verify-migration.sh" . 2>/dev/null) | grep -q "FAIL.*\[SP03\]"'
rm "$W/webapp/WEB-INF/conf/plugins/context_demo_DAO.xml"
check "SP03 passes once the file is gone" '(cd "$W" && bash "$S/verify-migration.sh" . 2>/dev/null) | grep -q "PASS.*\[SP03\]"'
Q="$T/portlet"; B="$Q/src/java/fr/paris/lutece/plugins/demo/business"
mkdir -p "$B/portlet"
echo '<project><packaging>lutece-plugin</packaging></project>' > "$Q/pom.xml"
cat > "$B/ThingHome.java" <<'EOF'
package fr.paris.lutece.plugins.demo.business;

public final class ThingHome
{
    private static ThingHome _singleton = new ThingHome( );

    public static ThingHome getInstance( )
    {
        return _singleton;
    }
}
EOF
cat > "$B/OtherHome.java" <<'EOF'
package fr.paris.lutece.plugins.demo.business;

public final class OtherHome
{
    public static void create( )
    {
    }
}
EOF
cat > "$B/portlet/DemoPortletHome.java" <<'EOF'
package fr.paris.lutece.plugins.demo.business.portlet;

import fr.paris.lutece.portal.business.portlet.PortletHome;

public final class DemoPortletHome extends PortletHome
{
    /* This class implements the Singleton design pattern. */
    private static DemoPortletHome _singleton = null;

    /**
     * Constructor
     */
    public DemoPortletHome( )
    {
        if ( _singleton == null )
        {
            _singleton = this;
        }
    }

    /**
     * Returns the instance.
     * @return the instance
     */
    public static PortletHome getInstance( )
    {
        if ( _singleton == null )
        {
            _singleton = new DemoPortletHome( );
        }
        return _singleton;
    }
}
EOF
hm=$(python3 "$S/java_checks.py" hm01 "$Q")
check "HM01 fires on a plain Home with getInstance" 'echo "$hm" | grep -q "ThingHome is a Home"'
check "HM01 leaves a static plain Home alone" '! echo "$hm" | grep -q OtherHome'
check "HM01 passes a hand-made portlet home singleton" '! echo "$hm" | grep -q DemoPortletHome'
check "HM02 reports a hand-made portlet home singleton as the older form" 'python3 "$S/java_checks.py" hm02 "$Q" | grep -q "portlet home DemoPortletHome: not @ApplicationScoped; hand-made singleton (static instance)"'
cat > "$B/portlet/BrokenPortletHome.java" <<'EOF'
package fr.paris.lutece.plugins.demo.business.portlet;

import fr.paris.lutece.portal.business.portlet.PortletHome;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

@ApplicationScoped
public final class BrokenPortletHome extends PortletHome
{
    @Inject
    private IBrokenPortletDAO _dao;

    private BrokenPortletHome( )
    {
    }
}
EOF
hm=$(python3 "$S/java_checks.py" hm01 "$Q")
check "HM01 fires on a portlet home the core cannot create, a final bean and an injected field" 'echo "$hm" | grep -q "portlet home BrokenPortletHome: final (CDI cannot proxy it); @Inject or @PostConstruct (the core creates portlet homes by reflection: never injected nor initialised); no public no-arg constructor"'
rm "$B/portlet/BrokenPortletHome.java"
printf 'package fr.paris.lutece.plugins.demo.business.portlet;\nclass HiddenPortletHome extends PortletHome\n{\n    public HiddenPortletHome( )\n    {\n    }\n}\n' > "$B/portlet/HiddenPortletHome.java"
printf 'package fr.paris.lutece.plugins.demo.business.portlet;\npublic class SetterPortletHome extends PortletHome\n{\n    @Inject\n    public void setDAO( IDemoPortletDAO dao )\n    {\n    }\n}\n' > "$B/portlet/SetterPortletHome.java"
printf 'package fr.paris.lutece.plugins.demo.business.portlet;\npublic class ArgPortletHome extends PortletHome\n{\n    public ArgPortletHome( IDemoPortletDAO dao )\n    {\n    }\n}\n' > "$B/portlet/ArgPortletHome.java"
hm=$(python3 "$S/java_checks.py" hm01 "$Q")
check "HM01 fires on a portlet home class that is not public" 'echo "$hm" | grep -q "portlet home HiddenPortletHome: class not public"'
check "HM01 fires on a portlet home injected through a setter" 'echo "$hm" | grep -q "portlet home SetterPortletHome: @Inject or @PostConstruct"'
check "HM01 fires on a portlet home with only a constructor taking arguments" 'echo "$hm" | grep -q "portlet home ArgPortletHome: no public no-arg constructor"'
rm "$B/portlet/HiddenPortletHome.java" "$B/portlet/SetterPortletHome.java" "$B/portlet/ArgPortletHome.java"
printf 'package fr.paris.lutece.plugins.demo.business.portlet;\n@ApplicationScoped public final class InlinePortletHome extends PortletHome\n{\n}\n' > "$B/portlet/InlinePortletHome.java"
check "HM01 reads a class whose annotation shares its declaration line" 'python3 "$S/java_checks.py" hm01 "$Q" | grep -q "portlet home InlinePortletHome: final (CDI cannot proxy it)"'
rm "$B/portlet/InlinePortletHome.java"
cat > "$B/portlet/DemoPortletHome.java" <<'EOF'
package fr.paris.lutece.plugins.demo.business.portlet;

import fr.paris.lutece.portal.business.portlet.PortletHome;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.spi.CDI;

@ApplicationScoped
public class DemoPortletHome extends PortletHome
{
    /**
     * Returns the instance.
     * @return the instance
     */
    public static PortletHome getInstance( )
    {
        return CDI.current( ).select( DemoPortletHome.class ).get( );
    }
}
EOF
check "HM01 passes a portlet home in the v8 form" '! python3 "$S/java_checks.py" hm01 "$Q" | grep -q DemoPortletHome'
check "HM02 passes a portlet home in the CDI form" '! python3 "$S/java_checks.py" hm02 "$Q" | grep -q DemoPortletHome'
C="$T/csrf"; W2="$C/src/java/x"; mkdir -p "$W2"
printf '<project><packaging>lutece-plugin</packaging></project>\n' > "$C/pom.xml"
printf 'package x;\n@Controller( controllerJsp = "ManageX.jsp", right = "X", securityTokenEnabled = true )\npublic class XJspBean extends MVCAdminJspBean\n{\n    private static final String METHOD_POST = "POST";\n    public String processController( HttpServletRequest request, HttpServletResponse response )\n    {\n        if ( !METHOD_POST.equalsIgnoreCase( request.getMethod( ) ) ) { return null; }\n        return null;\n    }\n}\n' > "$W2/XJspBean.java"
check "CS03 fires on a POST guard in a controller" 'python3 "$S/java_checks.py" cs03 "$C" | grep -q "XJspBean.java:8"'
sed -i '/getMethod/d' "$W2/XJspBean.java"
check "CS03 silent once the guard is gone" '[ -z "$(python3 "$S/java_checks.py" cs03 "$C")" ]'
G="$T/plugin"; W3="$G/src/java/x"; mkdir -p "$W3"
printf 'package x;\n@RequestScoped\n@Controller( controllerJsp = "ManageX.jsp", right = "X", securityTokenEnabled = true )\npublic class YJspBean extends AbstractYJspBean\n{\n    public String getManage( HttpServletRequest request )\n    {\n        return YHome.findAll( getPlugin( ) ).toString( );\n    }\n}\n' > "$W3/YJspBean.java"
printf 'package x;\npublic abstract class AbstractYJspBean extends MVCAdminJspBean\n{\n}\n' > "$W3/AbstractYJspBean.java"
check "WB10 fires on the inherited getPlugin( ) of a @RequestScoped bean, through a local base" 'python3 "$S/java_checks.py" wb10 "$G" | grep -q "YJspBean.java:8"'
printf 'package x;\npublic abstract class AbstractYJspBean extends MVCAdminJspBean\n{\n    @Override\n    public Plugin getPlugin( )\n    {\n        return PluginService.getPlugin( "y" );\n    }\n}\n' > "$W3/AbstractYJspBean.java"
check "WB10 silent once getPlugin( ) is overridden" '[ -z "$(python3 "$S/java_checks.py" wb10 "$G")" ]'
X="$T/xss"; W4="$X/src/java/x"; mkdir -p "$W4"
printf 'package x;\npublic class TagJspBean extends MVCAdminJspBean\n{\n    public String doCreate( HttpServletRequest request )\n    {\n        String strUrl = request.getParameter( "url" );\n        tag.setUrl( strUrl.replaceAll( "&", "&amp;" ) );\n        tag.setName( StringEscapeUtils.escapeHtml4( request.getParameter( "name" ) ) );\n        return null;\n    }\n}\n' > "$W4/TagJspBean.java"
printf 'package x;\npublic class DataServlet extends HttpServlet\n{\n    protected void doGet( HttpServletRequest request, HttpServletResponse response )\n    {\n        String strData = request.getParameter( "data" );\n        write( StringEscapeUtils.escapeHtml4( strData ) );\n    }\n}\n' > "$W4/DataServlet.java"
wb11=$(python3 "$S/java_checks.py" wb11 "$X")
check "WB11 fires on a parameter escaped by hand in a JspBean, through a variable and directly" 'echo "$wb11" | grep -q "TagJspBean.java:7" && echo "$wb11" | grep -q "TagJspBean.java:8"'
check "WB11 leaves a servlet alone (outside the XSS filter)" '! echo "$wb11" | grep -q DataServlet'
D="$T/dao"; W5="$D/src/java/x"; mkdir -p "$W5" "$D/src/sql/plugins/x/plugin"
printf 'CREATE TABLE x_portlet (\n  id_portlet int NOT NULL,\n  id_cloud varchar(255) DEFAULT '"''"' NOT NULL,\n  PRIMARY KEY (id_portlet)\n);\n' > "$D/src/sql/plugins/x/plugin/create_db_x.sql"
printf 'package x;\npublic class XPortletDAO\n{\n    private static final String SQL_QUERY_SELECT = "SELECT id_portlet, id_cloud FROM x_portlet WHERE id_portlet = ?";\n    private static final String SQL_QUERY_INSERT = "INSERT INTO x_portlet ( id_portlet, id_cloud ) VALUES ( ?, ? )";\n    private static final String SQL_QUERY_BY_CLOUD = "SELECT id_portlet FROM x_portlet WHERE id_cloud = ?";\n    public void load( int nId )\n    {\n        try ( DAOUtil daoUtil = new DAOUtil( SQL_QUERY_SELECT ) )\n        {\n            daoUtil.setInt( 1, nId );\n            p.setIdPortlet( daoUtil.getInt( 1 ) );\n            p.setIdCloud( daoUtil.getInt( 2 ) );\n        }\n    }\n    public void insert( int nId, int nCloud )\n    {\n        try ( DAOUtil daoUtil = new DAOUtil( SQL_QUERY_INSERT ) )\n        {\n            daoUtil.setInt( 1, nId );\n            daoUtil.setInt( 2, nCloud );\n        }\n    }\n    public void byCloud( int nCloud )\n    {\n        try ( DAOUtil daoUtil = new DAOUtil( SQL_QUERY_BY_CLOUD ) )\n        {\n            daoUtil.setInt( 1, nCloud );\n        }\n    }\n}\n' > "$W5/XPortletDAO.java"
da03=$(python3 "$S/java_checks.py" da03 "$D")
check "DA03 fires on a getInt and on a where comparison of a varchar column" 'echo "$da03" | grep -q "XPortletDAO.java:13: getInt on id_cloud" && echo "$da03" | grep -q "XPortletDAO.java:28: setInt on id_cloud"'
check "DA03 leaves the int column and the insert of a number alone" '[ "$(echo "$da03" | wc -l)" = 2 ]'
sed -i 's/id_cloud varchar(255) DEFAULT .* NOT NULL/id_cloud int DEFAULT 0 NOT NULL/' "$D/src/sql/plugins/x/plugin/create_db_x.sql"
check "DA03 silent once the column is an int" '[ -z "$(python3 "$S/java_checks.py" da03 "$D")" ]'
R="$T/refs/lutece-core/src/java/fr/paris/lutece/portal/service/captcha"; mkdir -p "$R" "$T/dp/src/java/x"
printf 'package fr.paris.lutece.portal.service.captcha;\n/**\n * Legacy.\n * @deprecated since 8.0 — use CDI injection of the {@code ICaptchaService} bean instead.\n */\n@Deprecated(since = "8.0", forRemoval = true)\npublic class CaptchaSecurityService\n{\n}\n' > "$R/CaptchaSecurityService.java"
printf 'package x;\nimport fr.paris.lutece.portal.service.captcha.CaptchaSecurityService;\nclass A { }\n' > "$T/dp/src/java/x/A.java"
dp04=$(LUTECE_REFERENCES="$T/refs" python3 "$S/java_checks.py" dp04 "$T/dp")
check "DP04 fires on a core type deprecated for removal, with the core's replacement" 'echo "$dp04" | grep -q "A.java:2: CaptchaSecurityService is deprecated for removal in lutece-core: since 8.0 — use CDI injection of the ICaptchaService bean instead."'
PI="$T/pi/src/java/x"; mkdir -p "$PI"
printf 'package x;\npublic class XPlugin extends PluginDefaultImplementation\n{\n    public void init( )\n    {\n        CDI.current( ).select( XService.class ).get( ).init( );\n    }\n}\n' > "$PI/XPlugin.java"
check "PI01 fires on a plugin init( ) that initialises a service" 'python3 "$S/java_checks.py" pi01 "$T/pi" | grep -q "XPlugin.java:4"'
printf 'package x;\npublic class XPlugin extends PluginDefaultImplementation\n{\n    public void init( )\n    {\n        RatingType.newBuilder( X.class ).build( );\n    }\n}\n' > "$PI/XPlugin.java"
check "PI01 leaves another init( ) alone" '[ -z "$(python3 "$S/java_checks.py" pi01 "$T/pi")" ]'
printf 'package x;\npublic class XPlugin extends PluginDefaultImplementation\n{\n    public void init( )\n    {\n        XImageService.getInstance( ).register( );\n    }\n}\n' > "$PI/XPlugin.java"
check "PI01 fires on a plugin init( ) that registers a provider" 'python3 "$S/java_checks.py" pi01 "$T/pi" | grep -q "XPlugin.java:4"'
CD="$T/cd/src/java/x"; mkdir -p "$CD"
printf 'package x;\n@ApplicationScoped\npublic class XService\n{\n    public static XService getInstance( )\n    {\n        return CDI.current( ).select( XService.class ).get( );\n    }\n\n    public void run( String strName )\n    {\n        CDI.current( ).select( IStep.class, NamedLiteral.of( strName ) ).get( );\n        CDI.current( ).getBeanManager( ).getEvent( ).select( XEvent.class ).fire( new XEvent( ) );\n    }\n}\n' > "$CD/XService.java"
printf 'package x;\npublic class XHome\n{\n    public void run( )\n    {\n        CDI.current( ).select( XService.class ).get( );\n    }\n}\n' > "$CD/XHome.java"
cd08=$(python3 "$S/java_checks.py" cd08 "$T/cd")
check "CD08 fires on lookups in a bean's instance method, with the named and event hints" 'echo "$cd08" | grep -q "XService.java:12: .*CdiHelper.resolve" && echo "$cd08" | grep -q "XService.java:13: .*Event<X>"'
check "CD08 leaves a static accessor and a class that is not a bean alone" '[ "$(echo "$cd08" | wc -l)" = 2 ]'
PG="$T/pg"; mkdir -p "$PG/src/java/x" "$PG/webapp/WEB-INF/conf/plugins"
printf 'contactList.itemsPerPage=20\nother.itemsPerPage=5\n' > "$PG/webapp/WEB-INF/conf/plugins/x.properties"
printf 'package x;\nclass A\n{\n    private static final String PROPERTY_ITEMS = "contact.contactList.itemsPerPage";\n    @Inject\n    @Pager( listBookmark = "l", defaultItemsPerPage = PROPERTY_ITEMS )\n    private IPager<X, Void> _pager;\n    @Inject\n    @Pager( listBookmark = "m", defaultItemsPerPage = "other.itemsPerPage" )\n    private IPager<X, Void> _other;\n    @Inject\n    @Pager( listBookmark = "n" )\n    private IPager<X, Void> _plain;\n}\n' > "$PG/src/java/x/A.java"
mv08=$(python3 "$S/java_checks.py" mv08 "$PG")
check "MV08 fires on an undeclared pager key and names the declared one" 'echo "$mv08" | grep -q "A.java:6: .*contact.contactList.itemsPerPage.*declares contactList.itemsPerPage"'
check "MV08 leaves a declared key and the default alone" '[ "$(echo "$mv08" | wc -l)" = 1 ]'
WG="$T/wg/src/java/x"; mkdir -p "$WG"
printf 'package x;\npublic class Item implements AdminWorkgroupResource\n{\n}\n' > "$WG/Item.java"
printf 'package x;\npublic class ItemJspBean extends MVCAdminJspBean\n{\n    public String getManage( HttpServletRequest request )\n    {\n        return AdminWorkgroupService.getAuthorizedCollection( ItemHome.findAll( ), (User) getUser( ) ).toString( );\n    }\n\n    public String getModify( HttpServletRequest request )\n    {\n        Item item = ItemHome.findByPrimaryKey( 1 );\n        return "";\n    }\n\n    public String getRemove( HttpServletRequest request )\n    {\n        Item item = ItemHome.findByPrimaryKey( 1 );\n        check( item );\n        return "";\n    }\n\n    private void check( Item item )\n    {\n        if ( !AdminWorkgroupService.isAuthorized( item, (User) getUser( ) ) ) throw new AccessDeniedException( "" );\n    }\n}\n' > "$WG/ItemJspBean.java"
wg01=$(python3 "$S/java_checks.py" wg01 "$T/wg")
check "WG01 fires on a workgroup resource loaded by id unchecked, not through a checking helper" '[ "$(echo "$wg01" | wc -l)" = 1 ] && echo "$wg01" | grep -q "getModify( ) loads a Item"'
P3="$T/pd3/src/java/x"; mkdir -p "$P3"
printf 'package x;\npublic class EmptyPlugin extends PluginDefaultImplementation\n{\n    public static final String PLUGIN_NAME = "x";\n}\n' > "$P3/EmptyPlugin.java"
printf 'package x;\npublic class BusyPlugin extends PluginDefaultImplementation\n{\n    @Override\n    public void init( )\n    {\n        AppLogService.info( "x" );\n    }\n}\n' > "$P3/BusyPlugin.java"
pd03=$(python3 "$S/java_checks.py" pd03 "$T/pd3")
check "PD03 fires on a plugin class with only constants, not on one that overrides init( )" '[ "$(echo "$pd03" | wc -l)" = 1 ] && echo "$pd03" | grep -q "EmptyPlugin overrides nothing"'
RL="$T/rl/src/java/x"; mkdir -p "$RL"
printf 'package x;\npublic class Entity\n{\n    public static void init( )\n    {\n        CDI.current( ).select( RemovalListenerService.class, NamedLiteral.of( BeanUtils.BEAN_WORKGROUP_REMOVAL_SERVICE ) ).get( ).registerListener( new L( ) );\n    }\n}\n' > "$RL/Entity.java"
check "RL01 fires on a listener registered from a static init( )" 'python3 "$S/java_checks.py" rl01 "$T/rl" | grep -q "Entity.java:6"'
printf 'package x;\n@ApplicationScoped\npublic class Listeners\n{\n    @Inject\n    @Named( BeanUtils.BEAN_WORKGROUP_REMOVAL_SERVICE )\n    private RemovalListenerService _workgroupRemovalService;\n    public void onStartup( @Observes @Initialized( ApplicationScoped.class ) ServletContext context )\n    {\n        _workgroupRemovalService.registerListener( new L( ) );\n    }\n}\n' > "$RL/Entity.java"
check "RL01 leaves a startup observer alone" '[ -z "$(python3 "$S/java_checks.py" rl01 "$T/rl")" ]'
PD="$T/pd"; mkdir -p "$PD/src/java/x" "$PD/webapp/WEB-INF/plugins"
printf '<plug-in><class>fr.paris.lutece.portal.service.plugin.PluginDefaultImplementation</class></plug-in>\n' > "$PD/webapp/WEB-INF/plugins/x.xml"
printf 'package x;\npublic class XPlugin extends PluginDefaultImplementation\n{\n    public void init( )\n    {\n        XService.start( );\n    }\n}\n' > "$PD/src/java/x/XPlugin.java"
check "PD02 fires on a plugin init( ) no descriptor runs" 'python3 "$S/java_checks.py" pd02 "$PD" | grep -q "XPlugin.init( ) never runs"'
printf '<plug-in><class>x.XPlugin</class></plug-in>\n' > "$PD/webapp/WEB-INF/plugins/x.xml"
check "PD02 silent when the descriptor names the class" '[ -z "$(python3 "$S/java_checks.py" pd02 "$PD")" ]'
GI="$T/gi/src/java/x"; mkdir -p "$GI"
printf 'package x;\n@ApplicationScoped\npublic class XService\n{\n    public static XService getInstance( )\n    {\n        return CDI.current( ).select( XService.class ).get( );\n    }\n}\n' > "$GI/XService.java"
printf 'package x;\npublic class XJspBean\n{\n    void f( ) { XService.getInstance( ); }\n}\n' > "$GI/XJspBean.java"
gi=$(python3 "$S/java_checks.py" gi01 "$T/gi")
check "GI01 fires on an undeprecated accessor and on its call" 'echo "$gi" | grep -q "XService.java:5" && echo "$gi" | grep -q "XJspBean.java:4"'
printf 'package x;\n@ApplicationScoped\npublic class XService\n{\n    @Deprecated( since = "8.0", forRemoval = true )\n    public static XService getInstance( )\n    {\n        return CDI.current( ).select( XService.class ).get( );\n    }\n}\n' > "$GI/XService.java"
rm "$GI/XJspBean.java"
check "GI01 accepts an accessor deprecated for removal no project code calls" '[ -z "$(python3 "$S/java_checks.py" gi01 "$T/gi")" ]'
DC="$T/dcore/lutece-core/src/java/fr/paris/lutece/portal/service/workflow"; mkdir -p "$DC"
printf 'package fr.paris.lutece.portal.service.workflow;\npublic class WorkflowService\n{\n    @Deprecated( since = "8.0", forRemoval = true )\n    public static WorkflowService getInstance( )\n    {\n        return null;\n    }\n}\n' > "$DC/WorkflowService.java"
D1="$T/dp1/src/java/x"; mkdir -p "$D1/own" "$D1/test"
printf 'package x;\nimport fr.paris.lutece.portal.service.workflow.WorkflowService;\npublic class A\n{\n    void f( ) { WorkflowService.getInstance( ).run( ); }\n    void g( ) { WorkflowService\n        .getInstance( ); }\n    // WorkflowService.getInstance( );\n    void h( ) { MyWorkflowService.getInstance( ); fr.paris.lutece.portal.service.workflow.WorkflowService.getInstance( ); }\n}\n' > "$D1/A.java"
printf 'package x.own;\nimport fr.paris.lutece.plugins.workflowcore.service.workflow.WorkflowService;\npublic class B\n{\n    void f( ) { WorkflowService.getInstance( ); }\n}\n' > "$D1/own/B.java"
printf 'package x.test;\npublic class C\n{\n    void f( ) { WorkflowService.getInstance( ); }\n}\n' > "$D1/test/C.java"
printf 'package x.test;\npublic class WorkflowService\n{\n}\n' > "$D1/test/WorkflowService.java"
printf 'package x;\nimport fr.paris.lutece.portal.service.workflow.WorkflowService;\r\npublic class E\r\n{\r\n    void f( ) { WorkflowService.getInstance( ); }\r\n}\r\n' > "$D1/E.java"
dp01=$(LUTECE_REFERENCES="$T/dcore" python3 "$S/java_checks.py" dp01 "$T/dp1" | sed 's|^src/java/x/||' | cut -d: -f1,2 | tr '\n' ' ')
check "DP01 fires on the core class, one line or two, qualified, at grep's line, not on a comment, a longer name or a project class of the same name" '[ "$dp01" = "A.java:5 A.java:6 A.java:9 E.java:5 " ]'
R="$T/refs5"; C="$R/lutece-core"
mkdir -p "$C/src/java/fr/paris/lutece/portal/web/admin" "$C/src/java/fr/paris/lutece/portal/service/portal" "$R/lutece-tech-library-core-utils/src/java/fr/paris/lutece/util/string"
( cd "$C" && git init -q && printf '<project><dependencies><dependency><artifactId>library-core-utils</artifactId></dependency></dependencies></project>\n' > pom.xml \
  && for t in portal/web/admin/BreadcrumbItem portal/web/xpages/SiteMapCacheService util/string/StringUtil; do mkdir -p "src/java/fr/paris/lutece/$(dirname $t)"; echo "class $(basename $t) { }" > "src/java/fr/paris/lutece/$t.java"; done \
  && git add -A && git -c user.name=t -c user.email=t@t commit -qm v7 && git branch -q develop7.x && git update-ref refs/remotes/origin/develop7.x develop7.x \
  && git rm -rq src/java && mkdir -p src/java/fr/paris/lutece/portal/service/portal && echo "class SiteMapCacheService { }" > src/java/fr/paris/lutece/portal/service/portal/SiteMapCacheService.java )
echo "class StringUtil { }" > "$R/lutece-tech-library-core-utils/src/java/fr/paris/lutece/util/string/StringUtil.java"
mkdir -p "$T/dp5/src/java/x"
printf 'package x;\nimport fr.paris.lutece.portal.web.admin.BreadcrumbItem;\nimport fr.paris.lutece.portal.web.xpages.SiteMapCacheService;\nimport fr.paris.lutece.util.string.StringUtil;\nclass A { }\n' > "$T/dp5/src/java/x/A.java"
dp05=$(LUTECE_REFERENCES="$R" python3 "$S/java_checks.py" dp05 "$T/dp5")
check "DP05 names a core type removed in v8" 'echo "$dp05" | grep -q "A.java:2: fr.paris.lutece.portal.web.admin.BreadcrumbItem is no longer in lutece-core: removed;"'
check "DP05 gives where a core type moved" 'echo "$dp05" | grep -q "A.java:3: .*SiteMapCacheService is no longer in lutece-core: moved to fr.paris.lutece.portal.service.portal.SiteMapCacheService"'
check "DP05 leaves a type a core library carries now" '! echo "$dp05" | grep -q StringUtil'
R6="$T/refs6"; C6="$R6/lutece-core"; P6=src/java/fr/paris/lutece/portal/business/portlet
mkdir -p "$C6/$P6" "$C6/src/sql"
( cd "$C6" && git init -q && printf 'public abstract class PortletHtmlContent {\n    public String getHtmlContent( ) { return null; }\n}\n' > "$P6/PortletHtmlContent.java" \
  && printf 'CREATE TABLE core_portlet (id int);\n' > src/sql/create_db_lutece_core.sql && git add -A && git -c user.name=t -c user.email=t@t commit -qm r1 && git tag lutece-core-8.0.2-beta-03 \
  && printf 'public abstract class PortletHtmlContent {\n    public String getHtmlContent( ) { return null; }\n    protected String renderTemplate( String s ) { return s; }\n}\n' > "$P6/PortletHtmlContent.java" \
  && printf 'CREATE TABLE core_portlet (id int);\nCREATE TABLE IF NOT EXISTS core_portlet_template (id int);\n' > src/sql/create_db_lutece_core.sql \
  && git -c user.name=t -c user.email=t@t commit -qam dev )
mkdir -p "$T/dp6/src/java/x" "$T/dp6/src/sql/plugins/x/core" "$T/dp6old/src/java/x"
printf 'package x;\nimport fr.paris.lutece.portal.business.portlet.PortletHtmlContent;\nclass A extends PortletHtmlContent { String h( ) { return renderTemplate( "t" ); } }\n' > "$T/dp6/src/java/x/A.java"
printf 'INSERT INTO core_portlet_template VALUES (1);\n' > "$T/dp6/src/sql/plugins/x/core/init_core_x.sql"
printf 'package x;\nimport fr.paris.lutece.portal.business.portlet.PortletHtmlContent;\nclass A extends PortletHtmlContent { String h( ) { return getHtmlContent( ); } }\n' > "$T/dp6old/src/java/x/A.java"
dp06=$(LUTECE_REFERENCES="$R6" python3 "$S/java_checks.py" dp06 "$T/dp6")
check "DP06 names a core method of develop only" 'echo "$dp06" | grep -q "A.java:2: PortletHtmlContent.renderTemplate on the core.s develop, in no published core (last: lutece-core-8.0.2-beta-03)"'
check "DP06 names a core table of develop only" 'echo "$dp06" | grep -q "init_core_x.sql: table core_portlet_template created by the core.s develop only"'
check "DP06 leaves a core method the published core has" '[ -z "$(LUTECE_REFERENCES="$R6" python3 "$S/java_checks.py" dp06 "$T/dp6old")" ]'
R7="$T/refs7"; C7="$R7/lutece-core"
mkdir -p "$C7/$P6" "$C7/src/sql"
( cd "$C7" && git init -q && printf 'public abstract class PortletHtmlContent {\n    public String getHtmlContent( ) { return null; }\n}\n' > "$P6/PortletHtmlContent.java" \
  && printf 'CREATE TABLE core_portlet (id int);\n' > src/sql/create_db_lutece_core.sql && git add -A && git -c user.name=t -c user.email=t@t commit -qm r1 \
  && git tag lutece-core-8.0.2-beta-10 && git tag lutece-core-8.0.1 && git tag lutece-core-8.0.2-beta-04 \
  && git checkout -q --orphan dev && printf 'public abstract class PortletHtmlContent {\n    public String getHtmlContent( ) { return null; }\n    protected String renderTemplate( String s ) { return s; }\n}\n' > "$P6/PortletHtmlContent.java" \
  && git add -A && git -c user.name=t -c user.email=t@t commit -qm dev )
dp06=$(LUTECE_REFERENCES="$R7" python3 "$S/java_checks.py" dp06 "$T/dp6")
check "DP06 reads the highest published tag when it is no ancestor of the clone's head" 'echo "$dp06" | grep -q "renderTemplate on the core.s develop, in no published core (last: lutece-core-8.0.2-beta-10)"'
( cd "$C7" && git tag -d lutece-core-8.0.2-beta-10 lutece-core-8.0.1 lutece-core-8.0.2-beta-04 >/dev/null )
dp06=$(LUTECE_REFERENCES="$R7" python3 "$S/java_checks.py" dp06 "$T/dp6")
check "DP06 says NOT EVALUATED on a clone with no published tag" '[ "$(echo "$dp06" | cut -c1-13)" = "NOT EVALUATED" ] && [ "$(echo "$dp06" | wc -l)" = 1 ]'
if [ $fail = 0 ]; then echo "PASS: ST04, MV01, SP03, HM01, HM02, CS03, WB10, WB11, DA03, DP04, PI01, RL01, PD02, GI01, CD08, MV08, WG01, PD03, DP01, DP05 and DP06 fire on their defect and stay silent on sound code"; else echo "$st04"; echo "$mv01"; echo "$hm"; exit 1; fi
