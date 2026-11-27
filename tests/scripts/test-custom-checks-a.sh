#!/usr/bin/env bash
# Checks CD01, CD05, CS01, CS02, ST02, ST05, ST07 and ST08 both ways: the defect fires, the v8 form, a longer name or a legit
# shape from the reference plugins does not; each false positive or negative the fleet replay found has its case.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
V="${VERIFY:-$HERE/../../tools/verify-migration.sh}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0

# Writes one file of a fixture project: $1 name, $2 relative file, $3 content.
fixture() {
    mkdir -p "$T/$1/$(dirname "$2")"
    printf '%s\n' "$3" > "$T/$1/$2"
}

# Records a failure when a check does not answer the expected status on a fixture.
expect() {
    local got
    [ -f "$T/$1.out" ] || ( cd "$T/$1" && bash "$V" . 2>/dev/null ) | sed 's/\x1b\[[0-9;]*m//g' > "$T/$1.out"
    got=$(grep -oE "(PASS|FAIL|WARN) \[$2\]" "$T/$1.out" | head -1 | cut -d' ' -f1)
    [ "$got" = "$3" ] || { echo "FAIL: $2 on $1 expected $3, got ${got:-nothing}"; fails=$((fails + 1)); }
}

J=src/java/fr/paris/lutece/plugins/demo

fixture cd01-bad "$J/service/MyService.java" '@ApplicationScoped
public class MyService
{
    private static MyService _instance;
}'
fixture cd01-legacy "$J/service/TagService.java" 'public class TagService
{
    private static TagService _singleton = new TagService( );
}'
fixture cd01-v8 "$J/service/MyService.java" '@ApplicationScoped
public class MyService
{
    private static final String PROPERTY_INSTANCE_NAME = "demo.instance";

    public static MyService getInstance( )
    {
        return CDI.current( ).select( MyService.class ).get( );
    }
}'
expect cd01-bad CD01 FAIL
expect cd01-legacy CD01 PASS
expect cd01-v8 CD01 PASS
fixture cd01-comment "$J/service/MyService.java" '@ApplicationScoped
public class MyService
{
    // private static MyService _instance;
}'
fixture cd01-counter "$J/service/MyService.java" '@ApplicationScoped
public class MyService
{
    private static final AtomicInteger _instanceCount = new AtomicInteger( );
}'
fixture cd01-package "$J/service/MyService.java" '@ApplicationScoped
public class MyService
{
    static MyService _instance;
}'
fixture cd01-singleton "$J/service/MyService.java" '@Singleton
public class MyService
{
    private static MyService _instance = new MyService( );
}'
expect cd01-comment CD01 PASS
expect cd01-counter CD01 PASS
expect cd01-package CD01 FAIL
expect cd01-singleton CD01 FAIL

fixture cd05-bad "$J/service/CategoryService.java" '@ApplicationScoped
public class CategoryService implements ImageResourceProvider
{
    @PostConstruct
    void init( )
    {
        ImageResourceManager.registerProvider( this );
    }
}'
fixture cd05-eager "$J/service/MyCacheService.java" '@ApplicationScoped
public class MyCacheService extends AbstractCacheableService<String, String>
{
    @PostConstruct
    void init( )
    {
        CacheService.registerCacheableService( this );
    }

    public void initializedService( @Observes @Initialized( ApplicationScoped.class ) ServletContext context )
    {
    }
}'
expect cd05-bad CD05 WARN
expect cd05-eager CD05 PASS
fixture cd05-plugin "$J/service/DemoPlugin.java" 'public class DemoPlugin extends PluginDefaultImplementation
{
    @Override
    public void init( )
    {
        ImageResourceManager.registerProvider( new DemoImageResourceProvider( ) );
    }
}'
fixture cd05-decl "$J/service/DemoRegistry.java" '@ApplicationScoped
public class DemoRegistry
{
    public static void registerProvider( ImageResourceProvider provider )
    {
    }
}'
fixture cd05-unregister "$J/service/DemoIndexer.java" '@ApplicationScoped
public class DemoIndexer
{
    DemoIndexer( )
    {
        IndexationService.unregisterIndexer( this );
    }
}'
fixture cd05-plain "$J/web/DemoContentTypeCache.java" 'public class DemoContentTypeCache extends AbstractCacheableService
{
    public DemoContentTypeCache( )
    {
        CacheService.registerCacheableService( this );
    }
}'
fixture cd05-otherobs "$J/service/DemoImageService.java" '@ApplicationScoped
public class DemoImageService implements ImageResourceProvider
{
    DemoImageService( )
    {
        ImageResourceManager.registerProvider( this );
    }

    void onEvent( @Observes ResourceEvent event )
    {
    }
}'
expect cd05-plugin CD05 PASS
expect cd05-decl CD05 PASS
expect cd05-unregister CD05 PASS
expect cd05-plain CD05 PASS
expect cd05-otherobs CD05 WARN

PJ='public class MyPortletJspBean extends PortletJspBean
{
    private static final String ACTION = "createDemoPortlet";'
OK_CREATE='    public String doCreate( HttpServletRequest request ) throws AccessDeniedException
    {
        if ( !getSecurityTokenService( ).validate( request, ACTION ) )
        {
            throw new AccessDeniedException( "Invalid security token" );
        }
        return "";
    }'
fixture cs01-ok "$J/web/portlet/MyPortletJspBean.java" "$PJ
    public String getCreate( HttpServletRequest request )
    {
        Map<String, Object> model = new HashMap<>( );
        model.put( SecurityTokenService.MARK_TOKEN, getSecurityTokenService( ).getToken( request, ACTION ) );
        return getCreateTemplate( \"0\", \"0\", model ).getHtml( );
    }
$OK_CREATE
    public String doModify( HttpServletRequest request ) throws AccessDeniedException
    {
        if ( request.getParameter( \"x\" ) == null )
        {
            return \"\";
        }
        if ( !getSecurityTokenService( ).validate( request, ACTION ) )
        {
            throw new AccessDeniedException( \"Invalid security token\" );
        }
        return \"\";
    }
}"
fixture cs01-bad "$J/web/portlet/MyPortletJspBean.java" "$PJ
$OK_CREATE
    public String doModify( HttpServletRequest request )
    {
        if ( request.getParameter( \"x\" ) == null )
        {
            return \"\";
        }
        return \"\";
    }
}"
expect cs01-ok CS01 PASS
expect cs01-bad CS01 FAIL
fixture cs01-parent "$J/web/portlet/AbstractDemoPortletJspBean.java" 'public abstract class AbstractDemoPortletJspBean extends PortletJspBean
{
}'
fixture cs01-parent "$J/web/portlet/MyPortletJspBean.java" 'public class MyPortletJspBean extends AbstractDemoPortletJspBean
{
    public String doCreate( HttpServletRequest request )
    {
        return "";
    }
}'
fixture cs01-helper "$J/web/portlet/MyPortletJspBean.java" 'public class MyPortletJspBean extends PortletJspBean
{
    public String doCreate( HttpServletRequest request ) throws AccessDeniedException
    {
        checkToken( request );
        return "";
    }

    private void checkToken( HttpServletRequest request ) throws AccessDeniedException
    {
        if ( !getSecurityTokenService( ).validate( request, "createDemoPortlet" ) )
        {
            throw new AccessDeniedException( "Invalid security token" );
        }
    }
}'
fixture cs01-commented "$J/web/portlet/MyPortletJspBean.java" 'public class MyPortletJspBean extends PortletJspBean
{
    public String doCreate( HttpServletRequest request )
    {
        // getSecurityTokenService( ).validate( request, "createDemoPortlet" )
        return "";
    }
}'
expect cs01-parent CS01 FAIL
expect cs01-helper CS01 PASS
expect cs01-commented CS01 FAIL

fixture cs02-bad "$J/service/MyContentService.java" 'public class MyContentService extends ContentService
{
    public String getPage( HttpServletRequest request, int nMode )
    {
        String strPage = "";
        putInCache( "key", strPage );
        return strPage;
    }
}'
fixture cs02-v8 "$J/service/MyContentService.java" 'public class MyContentService extends ContentService
{
    private Lutece107Cache<String, String> _cache;

    public String getPage( HttpServletRequest request, int nMode )
    {
        String strPage = _cache.get( "key" );
        _cache.put( "key", strPage );
        _portletCache.putInCache( "key", strPage );
        return strPage;
    }
}'
fixture cs02-longer "$J/service/MyContentService.java" 'public class MyContentService extends ContentServiceBase
{
    public String getPage( HttpServletRequest request, int nMode )
    {
        putInCache( "key", "" );
        return "";
    }
}'
expect cs02-bad CS02 FAIL
expect cs02-v8 CS02 PASS
expect cs02-longer CS02 PASS
fixture cs02-own "$J/service/MyContentService.java" 'public class MyContentService extends ContentService
{
    private String getFromCache( String strKey )
    {
        return _cache.get( strKey );
    }

    public String getPage( HttpServletRequest request, int nMode )
    {
        return getFromCache( "key" );
    }
}'
fixture cs02-ownother "$J/service/MyContentService.java" 'public class MyContentService extends ContentService
{
    private String getFromCache( String strKey )
    {
        return _cache.get( strKey );
    }

    public String getPage( HttpServletRequest request, int nMode )
    {
        putInCache( "key", "" );
        return getFromCache( "key" );
    }
}'
fixture cs02-comment "$J/service/MyContentService.java" 'public class MyContentService extends ContentService
{
    // putInCache( strKey, strPage ) left ContentService in v8
}'
fixture cs02-super "$J/service/MyContentService.java" 'public class MyContentService extends ContentService
{
    String read( )
    {
        return (String) super.getFromCache( "key" );
    }
}'
expect cs02-own CS02 PASS
expect cs02-ownother CS02 FAIL
expect cs02-comment CS02 PASS
expect cs02-super CS02 FAIL

for k in inject select dao; do
    fixture "st02-$k" "$J/business/MyDAO.java" '@ApplicationScoped
public final class MyDAO implements IMyDAO
{
}'
done
fixture st02-inject "$J/service/MyService.java" '@ApplicationScoped
public class MyService
{
    @Inject
    private MyDAO _dao;
}'
fixture st02-select "$J/business/MyHome.java" 'public final class MyHome
{
    private static IMyDAO _dao = CDI.current( ).select( MyDAO.class ).get( );
}'
fixture st02-dao "$J/business/MyHome.java" 'public final class MyHome
{
    private static IMyDAO _dao = CDI.current( ).select( IMyDAO.class ).get( );
}'
fixture st02-dao "$J/service/MyService.java" '@ApplicationScoped
public class MyService
{
    @Inject
    private IMyDAO _dao;
}'
fixture st02-ctor "$J/business/MyDAO.java" '@ApplicationScoped
public final class MyDAO implements IMyDAO
{
}'
fixture st02-ctor "$J/service/MyService.java" '@ApplicationScoped
public class MyService
{
    @Inject
    public MyService( MyDAO dao )
    {
    }
}'
expect st02-ctor ST02 FAIL
expect st02-inject ST02 FAIL
expect st02-select ST02 FAIL
expect st02-dao ST02 PASS
fixture st02-dependent "$J/service/MyHelper.java" '@Dependent
public final class MyHelper
{
}'
for k in instance far; do
    fixture "st02-$k" "$J/service/MyHelper.java" '@ApplicationScoped
public final class MyHelper
{
}'
done
fixture st02-dependent "$J/service/MyService.java" '@ApplicationScoped
public class MyService
{
    @Inject
    private MyHelper _helper;
}'
fixture st02-instance "$J/service/MyService.java" '@ApplicationScoped
public class MyService
{
    @Inject
    private Instance<MyHelper> _helper;
}'
fixture st02-far "$J/service/MyService.java" '@ApplicationScoped
public class MyService
{
    @Inject
    @Named( "demo.helper" )
    @ConfigProperty( name = "demo.helper" )
    private MyHelper _helper;
}'
expect st02-dependent ST02 PASS
expect st02-instance ST02 FAIL
expect st02-far ST02 FAIL

for k in ignored negated clean props; do
    mkdir -p "$T/st05-$k"
    git -C "$T/st05-$k" init -q
    fixture "st05-$k" src/main/resources/META-INF/beans.xml '<beans xmlns="https://jakarta.ee/xml/ns/jakartaee" bean-discovery-mode="annotated" version="4.0"/>'
done
fixture st05-ignored .gitignore 'target/
src/main/resources/META-INF/'
fixture st05-negated .gitignore '*.xml
!beans.xml'
fixture st05-clean .gitignore 'target/
beans.xml.bak'
fixture st05-props .gitignore '*.properties'
fixture st05-props src/test/resources/META-INF/microprofile-config.properties 'demo.key=1'
fixture st05-nogit src/main/resources/META-INF/beans.xml '<beans/>'
fixture st05-nogit .gitignore 'src/'
expect st05-ignored ST05 FAIL
expect st05-props ST05 FAIL
expect st05-negated ST05 PASS
expect st05-clean ST05 PASS
expect st05-nogit ST05 PASS

fixture st07-suffix "$J/service/MyServiceTest.java" 'public class MyServiceTest { }'
fixture st07-prefix "$J/util/TestUtils.java" 'public class TestUtils { }'
fixture st07-ok "$J/service/ContestService.java" 'public class ContestService { }'
fixture st07-ok "$J/service/MyTestUtils.java" 'public class MyTestUtils { }'
fixture st07-ok "$J/service/Contest.java" 'public class Contest { }'
fixture st07-ok src/test/java/fr/paris/lutece/plugins/demo/service/MyServiceTest.java 'public class MyServiceTest { }'
expect st07-suffix ST07 FAIL
expect st07-prefix ST07 FAIL
expect st07-ok ST07 PASS
fixture st08-entity src/site/site_fr.xml '<project name="Lut&egrave;ce"><body><menu name="Pr&eacute;sentation"/></body></project>'
fixture st08-unclosed src/site/site.xml '<project><body><menu name="Intro"><item name="a" href="a.html"></menu></body></project>'
fixture st08-ok src/site/site_fr.xml '<project><body><menu name="Présentation &amp; aide"/></body></project>'
fixture st08-inner src/site/site_fr.xml '<project name="Lutèce"><body><menu name="Pr&eacute;sentation"/></body></project>'
fixture st08-leading src/site/site.xml $'\n<?xml version="1.0" encoding="UTF-8"?>\n<project><body/></project>'
expect st08-entity ST08 FAIL
expect st08-unclosed ST08 FAIL
expect st08-ok ST08 PASS
expect st08-inner ST08 PASS
expect st08-leading ST08 PASS

[ "$fails" -eq 0 ] && { echo "PASS: CD01 flags a static singleton on a CDI or @Singleton bean only, outside comments, CD05 a lazy bean registering itself in its constructor or @PostConstruct without @Observes @Initialized, never Plugin.init, a declaration or an unregister, CS01 each portlet do* without its token, through a project parent and a validating helper, CS02 unqualified or super. cache calls on a ContentService, not its own methods or comments, ST02 a final normal-scoped bean resolved by its concrete type (field or Instance), not through its interface nor @Dependent, ST05 a beans.xml or test config git ignores, ST07 a production class surefire takes for a test, ST08 a src/site descriptor maven-site-plugin cannot read (HTML entity in the root tag, unclosed tag), not an entity elsewhere nor blank lines before the declaration"; exit 0; }
exit 1
