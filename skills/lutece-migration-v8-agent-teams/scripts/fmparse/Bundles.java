import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;
import java.util.Properties;
import java.util.Set;
import java.util.jar.JarFile;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

/** The message bundles of the assembled webapp, indexed the way I18nService names them. */
class Bundles
{
    static final Pattern KEY = Pattern.compile( "#i18n\\{(.*?)\\}" );
    final Map<String, Properties> byName = new HashMap<>( );

    final boolean fromAssembly;

    private final java.util.Set<String> fromSources = new java.util.HashSet<>( );

    Bundles( Path classes, Path lib, Path... sources )
    {
        fromAssembly = classes != null && Files.isDirectory( classes );
        for ( Path source : sources ) index( source );
        fromSources.addAll( byName.keySet( ) );
        index( classes );
        if ( lib != null && Files.isDirectory( lib ) )
        {
            try ( Stream<Path> jars = Files.list( lib ) )
            {
                for ( Path jar : jars.filter( f -> f.toString( ).endsWith( ".jar" ) ).toList( ) ) indexJar( jar );
            }
            catch ( Exception e )
            {
                // a jar we cannot open simply contributes no bundle
            }
        }
    }

    private void index( Path root )
    {
        if ( root == null || !Files.isDirectory( root ) ) return;
        try ( Stream<Path> files = Files.walk( root ) )
        {
            for ( Path f : files.filter( f -> f.getFileName( ).toString( ).endsWith( ".properties" ) ).toList( ) )
            {
                Properties props = new Properties( );
                try ( var in = Files.newInputStream( f ) ) { props.load( in ); }
                String bundle = name( root.relativize( f ).toString( ) );
                if ( !fromSources.contains( bundle ) ) byName.merge( bundle, props, Bundles::keepFirst );
            }
        }
        catch ( Exception e )
        {
            // an unreadable tree simply contributes no bundle
        }
    }

    private void indexJar( Path jar )
    {
        try ( JarFile file = new JarFile( jar.toFile( ) ) )
        {
            for ( var entry : file.stream( ).filter( e -> e.getName( ).endsWith( ".properties" ) ).toList( ) )
            {
                Properties props = new Properties( );
                try ( var in = file.getInputStream( entry ) ) { props.load( in ); }
                String bundle = name( entry.getName( ) );
                if ( !fromSources.contains( bundle ) ) byName.merge( bundle, props, Bundles::keepFirst );
            }
        }
        catch ( Exception e )
        {
            // a jar we cannot open simply contributes no bundle
        }
    }

    private static Properties keepFirst( Properties first, Properties second )
    {
        Properties merged = new Properties( );
        merged.putAll( second );
        merged.putAll( first );
        return merged;
    }

    /** Bundle name of a resource path: fr/paris/lutece/portal/resources/site_messages_fr.properties -> ...site_messages#fr */
    private static String name( String path )
    {
        String dotted = path.replace( File.separatorChar, '/' ).replace( '/', '.' ).replaceAll( "\\.properties$", "" );
        int under = dotted.lastIndexOf( '_' );
        String locale = under > 0 && dotted.length( ) - under == 3 ? dotted.substring( under + 1 ) : "";
        return ( locale.isEmpty( ) ? dotted : dotted.substring( 0, under ) ) + "#" + locale;
    }

    /** The bundle I18nService reads for a key, or null when the key is not of a known shape. */
    private String bundleOf( String key )
    {
        int dot = key.indexOf( '.' );
        if ( dot < 0 ) return null;
        String head = key.substring( 0, dot ), rest = key.substring( dot + 1 );
        if ( head.equals( "portal" ) )
        {
            int next = rest.indexOf( '.' );
            return next < 0 ? null : "fr.paris.lutece.portal.resources." + rest.substring( 0, next ) + "_messages";
        }
        if ( head.equals( "module" ) )
        {
            String[] parts = rest.split( "\\.", 3 );
            return parts.length < 3 ? null : "fr.paris.lutece.plugins." + parts[0] + ".modules." + parts[1] + ".resources." + parts[1] + "_messages";
        }
        return "fr.paris.lutece.plugins." + head + ".resources." + head + "_messages";
    }

    /** The key inside its bundle: what I18nService strips off the front. */
    private static String insideBundle( String key )
    {
        String[] parts = key.split( "\\." );
        if ( parts[0].equals( "portal" ) ) return key.substring( parts[0].length( ) + parts[1].length( ) + 2 );
        if ( parts[0].equals( "module" ) ) return key.substring( parts[0].length( ) + parts[1].length( ) + parts[2].length( ) + 3 );
        return key.substring( parts[0].length( ) + 1 );
    }

    /** The closest key of the same bundle when one is within a typo's distance, as a suffix to show the caller. */
    private String nearest( String bundle, String key )
    {
        String best = null;
        int bestDistance = Integer.MAX_VALUE;
        for ( String locale : new String[] { "fr", "" } )
        {
            Properties props = byName.get( bundle + "#" + locale );
            if ( props == null ) continue;
            for ( String candidate : props.stringPropertyNames( ) )
            {
                int d = distance( key, candidate );
                if ( d < bestDistance ) { bestDistance = d; best = candidate; }
            }
        }
        return best != null && bestDistance <= Math.max( 2, key.length( ) / 8 ) ? " (nearest key by spelling: '" + best + "', check it means the same before using it)" : "";
    }

    /** Levenshtein distance, to tell a typo from an absent key. */
    private static int distance( String a, String b )
    {
        int[] previous = new int[b.length( ) + 1];
        for ( int j = 0; j <= b.length( ); j++ ) previous[j] = j;
        for ( int i = 1; i <= a.length( ); i++ )
        {
            int[] current = new int[b.length( ) + 1];
            current[0] = i;
            for ( int j = 1; j <= b.length( ); j++ )
            {
                int cost = a.charAt( i - 1 ) == b.charAt( j - 1 ) ? 0 : 1;
                current[j] = Math.min( Math.min( current[j - 1] + 1, previous[j] + 1 ), previous[j - 1] + cost );
            }
            previous = current;
        }
        return previous[b.length( )];
    }

    /** The French value of a key, the default one when there is no French, null when no bundle answers. */
    String value( String key )
    {
        String bundle = bundleOf( key );
        if ( bundle == null ) return null;
        for ( String locale : new String[] { "fr", "" } )
        {
            Properties props = byName.get( bundle + "#" + locale );
            if ( props != null && props.getProperty( insideBundle( key ) ) != null ) return props.getProperty( insideBundle( key ) );
        }
        return null;
    }

    /** The prefix of the loaded bundle that holds this key as it is written, when the call forgot that prefix; else null. */
    String ownerOfRelativeKey( String key )
    {
        for ( Map.Entry<String, Properties> bundle : byName.entrySet( ) )
        {
            if ( bundle.getValue( ).containsKey( key ) ) return prefixOf( bundle.getKey( ).replaceFirst( "#.*$", "" ) );
        }
        return null;
    }

    /** The i18n prefix a template writes for a bundle: plugin, module.plugin.module or portal.element. */
    static String prefixOf( String bundle )
    {
        java.util.regex.Matcher m = java.util.regex.Pattern.compile( "fr\\.paris\\.lutece\\.plugins\\.(\\w+)\\.modules\\.(\\w+)\\.resources\\.\\w+_messages" ).matcher( bundle );
        if ( m.matches( ) ) return "module." + m.group( 1 ) + "." + m.group( 2 );
        m = java.util.regex.Pattern.compile( "fr\\.paris\\.lutece\\.plugins\\.(\\w+)\\.resources\\.\\w+_messages" ).matcher( bundle );
        if ( m.matches( ) ) return m.group( 1 );
        m = java.util.regex.Pattern.compile( "fr\\.paris\\.lutece\\.portal\\.resources\\.(\\w+)_messages" ).matcher( bundle );
        if ( m.matches( ) ) return "portal." + m.group( 1 );
        return bundle;
    }

    /** Whether a bundle of that name was loaded: in Java, where a key is guessed from an argument, this tells a key from a URL. */
    boolean hasBundle( String key )
    {
        String bundle = bundleOf( key );
        return bundle != null && ( byName.containsKey( bundle + "#fr" ) || byName.containsKey( bundle + "#" ) );
    }

    /** Whether any key of any bundle starts with a prefix: what a key built as "literal" + variable can be checked against. */
    boolean anyKeyStartsWith( String prefix )
    {
        int dot = prefix.indexOf( '.' );
        if ( dot < 0 ) return true;
        String bundle = bundleOf( prefix );
        if ( bundle == null ) return true;
        String inside = insideBundle( prefix );
        for ( String locale : new String[] { "fr", "" } )
        {
            Properties props = byName.get( bundle + "#" + locale );
            if ( props != null && props.stringPropertyNames( ).stream( ).anyMatch( k -> k.startsWith( inside ) ) ) return true;
        }
        return false;
    }

    /** Empty when the key resolves or has no shape offline, otherwise the key and the closest one that exists. */
    String unresolved( String key )
    {
        String bundle = bundleOf( key );
        if ( bundle == null || value( key ) != null ) return "";
        return key + nearest( bundle, insideBundle( key ) );
    }

    /** Replaces every #i18n key the way the core does, in French, and records those that resolve to nothing. */
    String localize( String html, Set<String> missing )
    {
        Matcher matcher = KEY.matcher( html );
        StringBuilder sb = new StringBuilder( );
        while ( matcher.find( ) )
        {
            String key = matcher.group( 1 );
            String value = value( key );
            String problem = unresolved( key );
            if ( !problem.isEmpty( ) ) missing.add( problem );
            matcher.appendReplacement( sb, Matcher.quoteReplacement( value == null ? "" : value ) );
        }
        matcher.appendTail( sb );
        return sb.toString( );
    }
}
