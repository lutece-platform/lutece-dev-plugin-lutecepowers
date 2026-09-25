import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

/**
 * Checks every #i18n key of a project against the message bundles of the assembled webapp, whatever file it sits in
 * and whether or not that file ever renders. A key no bundle answers is not an error at runtime: the core catches
 * the lookup failure and writes an empty string, so the label is simply absent from the page.
 * Three shapes are handled. A literal key is resolved. A key built as a literal prefix plus an expression is checked
 * on its prefix: no key of the bundle starting with it means the whole family is missing. A key that is only an
 * expression cannot be resolved here and is listed apart, not counted as missing. A key whose bundle was never
 * loaded belongs to a plugin this webapp does not carry and is listed apart too.
 * In Java, the key usually arrives through a constant of the same file: the constant is followed to its literal, and
 * only a value whose bundle exists is taken for a key, because the same call also carries URLs and JSP names. A key
 * glued with '+' is rebuilt from its literals and constants. A key defined in a configuration properties file of the
 * project is a value read through AppPropertiesService, not a bundle key.
 * Reports path:line, the key and the closest key that does exist when one is within a typo's distance.
 */
public class I18nKeys
{
    static final List<String> SUFFIXES = List.of( ".html", ".ftl", ".js", ".java", ".xml", ".sql" );
    static final Pattern COMMENT = Pattern.compile( "<#--.*?-->", Pattern.DOTALL );
    static final Pattern PREFIX = Pattern.compile( "\\$\\{\\s*\"([^\"]+)\"\\s*\\+" );
    static final Pattern CONSTANT = Pattern.compile( "final\\s+String\\s+([A-Z][A-Z_0-9]*)\\s*=\\s*\"([^\"]*)\"" );
    static final Pattern I18N_CALL = Pattern.compile( "(?:getLocalizedString|getLocalizedMessage|getMessageUrl|localize|setPageTitleProperty|getPage|addError|addInfo|addWarning)\\s*\\(([^;)]*)\\)|(?:pageTitleI18nKey|pagePathI18nKey)\\s*=\\s*([^,)]+)" );
    static final Pattern WORD = Pattern.compile( "\"([^\"]+)\"|([A-Z][A-Z_0-9]{2,})" );

    public static void main( String[] args ) throws Exception
    {
        Path core = Path.of( args[0] ), root = Path.of( args[1] );
        Path webInf = core.getParent( );
        Bundles bundles = new Bundles( webInf == null ? null : webInf.resolve( "classes" ),
                                       webInf == null ? null : webInf.resolve( "lib" ),
                                       sources( root ), sources( core ) );
        int keys = 0, missing = 0, files = 0, dynamic = 0, foreign = 0;
        java.util.Set<String> configuration = configurationKeys( root );
        StringBuilder later = new StringBuilder( );
        try ( Stream<Path> tree = Files.walk( root ) )
        {
            for ( Path file : tree.filter( I18nKeys::readable ).sorted( ).toList( ) )
            {
                String text = blankComments( new String( Files.readAllBytes( file ), java.nio.charset.StandardCharsets.UTF_8 ) );
                boolean counted = false;
                for ( Map.Entry<Integer, String> found : keysOf( text, file.toString( ).endsWith( ".java" ), bundles ).entrySet( ) )
                {
                    String key = found.getValue( );
                    keys++;
                    if ( !counted ) { files++; counted = true; }
                    String where = root.relativize( file ) + ":" + line( text, found.getKey( ) ) + " ";
                    if ( configuration.contains( key ) ) continue;
                    if ( key.startsWith( "?" ) )
                    {
                        dynamic++;
                        later.append( where ).append( key.substring( 1 ) ).append( " -- built from a variable, not checkable here\n" );
                    }
                    else if ( key.endsWith( "*" ) )
                    {
                        if ( !bundles.anyKeyStartsWith( key.substring( 0, key.length( ) - 1 ) ) )
                        {
                            missing++;
                            System.out.println( where + key + " -- no key of that bundle starts with this prefix" );
                        }
                    }
                    else if ( !bundles.hasBundle( key ) && bundles.ownerOfRelativeKey( key ) != null )
                    {
                        missing++;
                        String owner = bundles.ownerOfRelativeKey( key );
                        System.out.println( where + key + " -- no bundle answers it; the bundle '" + owner + "' holds it as written: the prefix is missing, write " + owner + "." + key );
                    }
                    else if ( !bundles.hasBundle( key ) )
                    {
                        foreign++;
                        later.append( where ).append( key ).append( " -- its bundle was not loaded, the plugin that owns it is not part of this webapp\n" );
                    }
                    else
                    {
                        String problem = bundles.unresolved( key );
                        if ( !problem.isEmpty( ) ) { missing++; System.out.println( where + problem ); }
                    }
                }
            }
        }
        System.out.print( later );
        System.out.println( "I18NKEYS files=" + files + " keys=" + keys + " unresolved=" + missing + " dynamic=" + dynamic + " foreignBundle=" + foreign
            + " bundles=" + bundles.byName.size( ) + ( bundles.fromAssembly ? " (assembled webapp, dependencies included)"
            : " (sources at hand: a key owned by a dependency cannot be resolved here, assemble the project first)" ) );
        System.exit( missing == 0 ? 0 : 1 );
    }

    /**
     * Every key a file references, by offset. A key is returned plain when literal, suffixed with '*' when only its
     * prefix is known, prefixed with '?' when it is an expression this tool cannot evaluate.
     */
    static Map<Integer, String> keysOf( String text, boolean java, Bundles bundles )
    {
        Map<Integer, String> found = new java.util.TreeMap<>( );
        Matcher matcher = Bundles.KEY.matcher( text );
        while ( matcher.find( ) )
        {
            String key = matcher.group( 1 );
            if ( key.isEmpty( ) ) continue;
            if ( !key.contains( "$" ) ) { found.put( matcher.start( ), key ); continue; }
            String whole = balanced( text, matcher.start( ) + "#i18n{".length( ) );
            Matcher prefix = PREFIX.matcher( whole );
            found.put( matcher.start( ), prefix.find( ) ? prefix.group( 1 ) + "*" : "?#i18n{" + whole + "}" );
        }
        if ( java ) found.putAll( javaKeys( text, bundles ) );
        return found;
    }

    /** The keys a Java file hands to I18nService, following the constant of the same file to its literal. */
    static Map<Integer, String> javaKeys( String text, Bundles bundles )
    {
        Map<String, String> constants = new HashMap<>( );
        Matcher declaration = CONSTANT.matcher( text );
        while ( declaration.find( ) ) constants.put( declaration.group( 1 ), declaration.group( 2 ) );
        Map<Integer, String> found = new java.util.TreeMap<>( );
        Matcher call = I18N_CALL.matcher( text );
        while ( call.find( ) )
        {
            for ( String argument : ( call.group( 1 ) != null ? call.group( 1 ) : call.group( 2 ) ).split( "," ) )
            {
                if ( argument.contains( "+" ) )
                {
                    String key = concatenated( argument, constants );
                    String bare = key.endsWith( "*" ) ? key.substring( 0, key.length( ) - 1 ) : key;
                    if ( isKey( bare ) && bundles.hasBundle( bare ) ) found.put( call.start( ), key );
                    continue;
                }
                Matcher word = WORD.matcher( argument );
                while ( word.find( ) )
                {
                    String key = word.group( 1 ) != null ? word.group( 1 ) : constants.get( word.group( 2 ) );
                    if ( key != null && isKey( key ) && bundles.hasBundle( key ) ) found.put( call.start( ), key );
                }
            }
        }
        return found;
    }

    /**
     * The key an argument glued with '+' spells, its literals and the constants of the file joined in order; when a
     * piece is not a literal nor a known constant, the part before it followed by '*', a prefix to check.
     */
    static String concatenated( String argument, Map<String, String> constants )
    {
        StringBuilder key = new StringBuilder( );
        for ( String piece : argument.split( "\\+" ) )
        {
            String value = valueOf( piece.trim( ), constants );
            if ( value == null ) return key + "*";
            key.append( value );
        }
        return key.toString( );
    }

    /** The value of a string literal or of a constant of the file, null for anything else. */
    static String valueOf( String piece, Map<String, String> constants )
    {
        if ( piece.length( ) >= 2 && piece.startsWith( "\"" ) && piece.endsWith( "\"" ) ) return piece.substring( 1, piece.length( ) - 1 );
        return constants.get( piece );
    }

    /** A value shaped like a bundle key, not a URL, a path or a sentence. */
    static boolean isKey( String value )
    {
        return value.contains( "." ) && !value.contains( " " ) && !value.contains( "/" );
    }

    /** The keys of every configuration properties file of the project: a value read through AppPropertiesService. */
    static java.util.Set<String> configurationKeys( Path root ) throws java.io.IOException
    {
        java.util.Set<String> keys = new java.util.HashSet<>( );
        Path conf = root.resolve( "webapp/WEB-INF/conf" );
        if ( !Files.isDirectory( conf ) ) return keys;
        try ( Stream<Path> tree = Files.walk( conf ) )
        {
            for ( Path file : tree.filter( f -> f.toString( ).endsWith( ".properties" ) ).toList( ) )
            {
                java.util.Properties properties = new java.util.Properties( );
                try ( java.io.Reader reader = Files.newBufferedReader( file, java.nio.charset.StandardCharsets.ISO_8859_1 ) ) { properties.load( reader ); }
                keys.addAll( properties.stringPropertyNames( ) );
            }
        }
        return keys;
    }

    /** The text between an opening brace and the one that closes it, so an interpolated key is shown whole. */
    static String balanced( String text, int from )
    {
        int depth = 1;
        for ( int i = from; i < text.length( ); i++ )
        {
            if ( text.charAt( i ) == '{' ) depth++;
            else if ( text.charAt( i ) == '}' && --depth == 0 ) return text.substring( from, i );
        }
        return text.substring( from, Math.min( text.length( ), from + 80 ) );
    }

    /** The same text with every FreeMarker comment blanked, offsets kept: a macro documents itself with example keys. */
    static String blankComments( String text )
    {
        Matcher matcher = COMMENT.matcher( text );
        StringBuilder sb = new StringBuilder( text );
        while ( matcher.find( ) )
        {
            for ( int i = matcher.start( ); i < matcher.end( ); i++ ) if ( sb.charAt( i ) != '\n' ) sb.setCharAt( i, ' ' );
        }
        return sb.toString( );
    }

    /** A source file worth scanning, outside the build output. */
    static boolean readable( Path file )
    {
        String path = file.toString( );
        if ( !Files.isRegularFile( file ) || path.contains( "/target/" ) || path.contains( "/.git/" ) || path.contains( "/e2e/" ) ) return false;
        return SUFFIXES.stream( ).anyMatch( path::endsWith );
    }

    /** The src/java of the project a directory belongs to, where an unassembled checkout keeps its bundles. */
    static Path sources( Path anywhere )
    {
        Path here = anywhere;
        while ( here != null && !Files.isDirectory( here.resolve( "src/java" ) ) ) here = here.getParent( );
        return here == null ? null : here.resolve( "src/java" );
    }

    /** One-based line of an offset. */
    static int line( String text, int offset )
    {
        int n = 1;
        for ( int i = 0; i < offset; i++ ) if ( text.charAt( i ) == '\n' ) n++;
        return n;
    }
}
