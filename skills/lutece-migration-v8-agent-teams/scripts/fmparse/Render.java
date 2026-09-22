import freemarker.cache.FileTemplateLoader;
import freemarker.cache.MultiTemplateLoader;
import freemarker.cache.TemplateLoader;
import freemarker.template.Configuration;
import freemarker.template.SimpleScalar;
import freemarker.template.Template;
import freemarker.template.TemplateBooleanModel;
import freemarker.template.TemplateCollectionModel;
import freemarker.template.TemplateDirectiveBody;
import freemarker.template.TemplateDirectiveModel;
import freemarker.core.Environment;
import freemarker.template.TemplateExceptionHandler;
import freemarker.template.TemplateHashModelEx;
import freemarker.template.TemplateMethodModelEx;
import freemarker.template.TemplateModel;
import freemarker.template.TemplateModelException;
import freemarker.template.TemplateNumberModel;
import freemarker.template.TemplateScalarModel;
import freemarker.template.TemplateSequenceModel;
import freemarker.template.SimpleCollection;

import java.io.File;
import java.io.StringWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.Set;
import java.util.TreeSet;
import java.util.stream.Stream;

/**
 * Renders plugin templates offline with the real core macros and a lenient model: every variable the template
 * reads and the model does not define is empty (empty string, empty list, false, 0), so the macro calls and the
 * empty branches run without a server. An optional JSON file per template supplies a populated model.
 * Prints one line per template and the warning comments the core macros emit for wrong arguments.
 * Resolves the #i18n keys of the rendered output the way AppTemplateService does, against the bundles of the
 * assembled webapp, and names every key that resolves to nothing: the core swallows the lookup failure and
 * writes an empty string, so a missing key is invisible in the page. A key built from a model variable
 * (#i18n{${...}}) has no shape offline and is left out rather than counted as missing.
 */
public class Render
{
    static final java.util.regex.Pattern MACRO = java.util.regex.Pattern.compile( "<#macro\\s+([A-Za-z_][A-Za-z0-9_]*)" );
    /** A value that is at once an empty string, an empty sequence, an empty hash, false, zero and a directive that renders a marker comment. */
    static class Lenient implements TemplateHashModelEx, TemplateSequenceModel, TemplateScalarModel, TemplateBooleanModel, TemplateNumberModel, TemplateMethodModelEx, TemplateDirectiveModel
    {
        public void execute( Environment env, Map params, TemplateModel[] loopVars, TemplateDirectiveBody body ) throws freemarker.template.TemplateException, java.io.IOException
        {
            env.getOut( ).write( "<!-- render: unresolved macro -->" );
            if ( body != null ) body.render( env.getOut( ) );
        }
        public TemplateModel get( String key ) { return this; }
        public boolean isEmpty( ) { return true; }
        public int size( ) { return 0; }
        public TemplateCollectionModel keys( ) { return new SimpleCollection( new ArrayList<>( ), null ); }
        public TemplateCollectionModel values( ) { return new SimpleCollection( new ArrayList<>( ), null ); }
        public TemplateModel get( int index ) { return this; }
        public String getAsString( ) { return ""; }
        public boolean getAsBoolean( ) { return false; }
        public Number getAsNumber( ) { return 0; }
        public Object exec( List arguments ) { return this; }
    }

    /** Hides the theme overrides (skin/themes/<code>/tpl/**) so that cTpl renders the plugin's own file, as a site without that override would. */
    static class NoThemeOverride implements TemplateLoader
    {
        final TemplateLoader inner;
        NoThemeOverride( TemplateLoader inner ) { this.inner = inner; }
        public Object findTemplateSource( String name ) throws java.io.IOException { return name.matches( ".*skin/themes/[^/]+/tpl/.*" ) ? null : inner.findTemplateSource( name ); }
        public long getLastModified( Object source ) { return inner.getLastModified( source ); }
        public java.io.Reader getReader( Object source, String encoding ) throws java.io.IOException { return inner.getReader( source, encoding ); }
        public void closeTemplateSource( Object source ) throws java.io.IOException { inner.closeTemplateSource( source ); }
    }

    /** The root: values from the JSON model when present, the lenient value otherwise. */
    static class Root implements TemplateHashModelEx
    {
        final Map<String, Object> values;
        final freemarker.template.ObjectWrapper wrapper;
        final Set<String> known;
        Root( Map<String, Object> values, freemarker.template.ObjectWrapper wrapper, Set<String> known ) { this.values = values; this.wrapper = wrapper; this.known = known; }
        // A name the data model does not define is lenient, except a macro a declared macro file defines: the
        // lookup must fall through to the shared variable that stands for it, not to the unresolved marker.
        public TemplateModel get( String key ) throws TemplateModelException
        {
            if ( values.containsKey( key ) ) return wrapper.wrap( values.get( key ) );
            return known.contains( key ) ? null : new Lenient( );
        }
        public boolean isEmpty( ) { return false; }
        public int size( ) { return values.size( ); }
        public TemplateCollectionModel keys( ) { return new SimpleCollection( values.keySet( ), wrapper ); }
        public TemplateCollectionModel values( ) { return new SimpleCollection( values.values( ), wrapper ); }
    }

    /** Entry point: core templates root, plugin templates root, output directory, then template paths relative to the plugin root. */
    public static void main( String[] args ) throws Exception
    {
        String core = args[0], plugin = args[1], out = args[2], autoIncludes = args[3];
        Configuration cfg = new Configuration( Configuration.VERSION_2_3_32 );
        TemplateLoader base = new MultiTemplateLoader( new TemplateLoader[] { new FileTemplateLoader( new File( plugin ) ), new FileTemplateLoader( new File( core ) ) } );
        cfg.setTemplateLoader( new NoThemeOverride( base ) );
        cfg.setNumberFormat( "0.######" );
        cfg.setTemplateExceptionHandler( TemplateExceptionHandler.RETHROW_HANDLER );
        cfg.setLogTemplateExceptions( false );
        cfg.addAutoInclude( "commons_bs5_tabler.html" );
        cfg.addAutoInclude( "skin/themes/global_theme_commons.ftl" );
        // The macro names a declared freemarker-macro-file defines. The application includes those files globally;
        // including them here would run their top-level code against an empty model, so they are only read for
        // their names, and a call to one renders its body instead of the unresolved marker.
        Set<String> known = macroNames( autoIncludes, core, plugin );
        for ( String name : known )
        {
            cfg.setSharedVariable( name, (TemplateDirectiveModel) ( env, params, loopVars, body ) -> { if ( body != null ) body.render( env.getOut( ) ); } );
        }
        cfg.setSharedVariable( "dskey", (TemplateMethodModelEx) a -> new SimpleScalar( "" ) );
        cfg.setSharedVariable( "i18n", (TemplateMethodModelEx) a -> new SimpleScalar( a.isEmpty( ) ? "" : a.get( 0 ).toString( ) ) );
        Files.createDirectories( Path.of( out ) );
        Path webInf = Path.of( core ).getParent( );
        Bundles bundles = new Bundles( webInf == null ? null : webInf.resolve( "classes" ),
                                       webInf == null ? null : webInf.resolve( "lib" ),
                                       sourceBundles( plugin ), sourceBundles( core ) );
        System.out.println( "I18N " + bundles.byName.size( ) + " message bundle(s) read from " + ( bundles.fromAssembly
            ? "the assembled webapp, dependencies included"
            : "the sources at hand: a key owned by a dependency cannot be resolved here, so check the assembly before calling it missing" ) );
        int errors = 0;
        int modelBound = 0;
        int warnings = 0;
        int unresolvedTotal = 0;
        Set<String> missingKeys = new TreeSet<>( );
        for ( int i = 4; i < args.length; i++ )
        {
            String rel = args[i];
            Map<String, Object> model = new HashMap<>( );
            Path json = Path.of( out, rel.replace( '/', '_' ) + ".json" );
            if ( Files.exists( json ) )
            {
                model = Json.parse( Files.readString( json ) );
            }
            try
            {
                Template template = cfg.getTemplate( rel );
                StringWriter writer = new StringWriter( );
                template.process( new Root( model, cfg.getObjectWrapper( ), known ), writer );
                String html = writer.toString( );
                int wrong = count( html, "wrong or deprecated argument" );
                int unresolved = count( html, "render: unresolved macro" );
                Set<String> missing = new TreeSet<>( );
                html = bundles.localize( html, missing );
                missingKeys.addAll( missing );
                Files.writeString( Path.of( out, rel.replace( '/', '_' ) ), html );
                warnings += wrong;
                unresolvedTotal += unresolved;
                System.out.println( ( wrong == 0 && unresolved == 0 && missing.isEmpty( ) ? "OK    " : "WARN  " ) + rel + " -> " + html.length( ) + " bytes" + ( wrong == 0 ? "" : ", " + wrong + " wrong-argument comment(s)" ) + ( unresolved == 0 ? "" : ", " + unresolved + " unresolved macro(s): defined in a template that is not auto-included, or nowhere" ) + ( missing.isEmpty( ) ? "" : ", " + missing.size( ) + " i18n key(s) resolving to nothing: " + String.join( ", ", missing ) ) + ( Files.exists( json ) ? " (json model)" : " (lenient model)" ) );
            }
            catch ( Exception e )
            {
                String first = e.getMessage( ) == null ? "" : e.getMessage( ).split( "\n" )[0];
                if ( first.contains( "Can't convert this string to boolean" ) )
                {
                    modelBound++;
                    System.out.println( "MODEL " + rel + " :: ?boolean needs the exact string \"true\" or \"false\", which an empty model cannot supply: write a JSON model for this template to render it" );
                }
                else
                {
                    errors++;
                    System.out.println( "ERROR " + rel + " :: " + first );
                }
            }
        }
        System.out.println( "RENDER templates=" + ( args.length - 4 ) + " errors=" + errors + " needModel=" + modelBound + " wrongArguments=" + warnings + " unresolvedMacros=" + unresolvedTotal + " i18nBundles=" + bundles.byName.size( ) + " missingI18nKeys=" + missingKeys.size( ) );
        System.exit( errors == 0 ? 0 : 1 );
    }

    /** The macros a declared freemarker-macro-file defines, looked up under the project then under the core. */
    static Set<String> macroNames( String declared, String core, String plugin ) throws java.io.IOException
    {
        Set<String> names = new java.util.TreeSet<>( );
        for ( String rel : declared.split( "," ) )
        {
            if ( rel.isBlank( ) ) continue;
            for ( String base : new String[] { plugin, core } )
            {
                Path file = Path.of( base, rel.trim( ) );
                if ( !Files.isRegularFile( file ) ) continue;
                Matcher macro = MACRO.matcher( new String( Files.readAllBytes( file ), java.nio.charset.StandardCharsets.UTF_8 ) );
                while ( macro.find( ) ) names.add( macro.group( 1 ) );
                break;
            }
        }
        return names;
    }

    /** The src/java of the project a webapp/WEB-INF/templates directory belongs to, where an unassembled checkout keeps its bundles. */
    static Path sourceBundles( String templates )
    {
        Path webapp = Path.of( templates ).getParent( ) == null ? null : Path.of( templates ).getParent( ).getParent( );
        return webapp == null ? null : webapp.resolveSibling( "src/java" );
    }

    /** Occurrences of a marker in a string. */
    static int count( String text, String marker )
    {
        int n = 0;
        for ( int i = text.indexOf( marker ); i >= 0; i = text.indexOf( marker, i + 1 ) ) n++;
        return n;
    }

    /** Minimal JSON reader for the model files: objects, arrays, strings, numbers, booleans, null. */
    static class Json
    {
        final String s;
        int i;
        Json( String s ) { this.s = s; }

        /** Parses a JSON object into a map. */
        @SuppressWarnings( "unchecked" )
        static Map<String, Object> parse( String text ) { return (Map<String, Object>) new Json( text ).value( ); }

        Object value( )
        {
            ws( );
            char c = s.charAt( i );
            if ( c == '{' ) return object( );
            if ( c == '[' ) return array( );
            if ( c == '"' ) return string( );
            if ( s.startsWith( "true", i ) ) { i += 4; return Boolean.TRUE; }
            if ( s.startsWith( "false", i ) ) { i += 5; return Boolean.FALSE; }
            if ( s.startsWith( "null", i ) ) { i += 4; return null; }
            int start = i;
            while ( i < s.length( ) && "+-0123456789.eE".indexOf( s.charAt( i ) ) >= 0 ) i++;
            String num = s.substring( start, i );
            return num.contains( "." ) || num.contains( "e" ) || num.contains( "E" ) ? (Object) Double.parseDouble( num ) : (Object) Long.parseLong( num );
        }

        Map<String, Object> object( )
        {
            Map<String, Object> m = new HashMap<>( );
            i++;
            ws( );
            if ( s.charAt( i ) == '}' ) { i++; return m; }
            while ( true )
            {
                ws( );
                String key = string( );
                ws( );
                i++;
                m.put( key, value( ) );
                ws( );
                if ( s.charAt( i ) == ',' ) { i++; continue; }
                i++;
                return m;
            }
        }

        List<Object> array( )
        {
            List<Object> l = new ArrayList<>( );
            i++;
            ws( );
            if ( s.charAt( i ) == ']' ) { i++; return l; }
            while ( true )
            {
                l.add( value( ) );
                ws( );
                if ( s.charAt( i ) == ',' ) { i++; continue; }
                i++;
                return l;
            }
        }

        String string( )
        {
            StringBuilder b = new StringBuilder( );
            i++;
            while ( s.charAt( i ) != '"' )
            {
                char c = s.charAt( i++ );
                if ( c == '\\' )
                {
                    char e = s.charAt( i++ );
                    if ( e == 'n' ) b.append( '\n' );
                    else if ( e == 't' ) b.append( '\t' );
                    else if ( e == 'u' ) { b.append( (char) Integer.parseInt( s.substring( i, i + 4 ), 16 ) ); i += 4; }
                    else b.append( e );
                }
                else b.append( c );
            }
            i++;
            return b.toString( );
        }

        void ws( ) { while ( i < s.length( ) && Character.isWhitespace( s.charAt( i ) ) ) i++; }
    }
}
