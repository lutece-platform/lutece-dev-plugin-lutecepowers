import freemarker.template.Configuration;
import freemarker.template.Template;
import java.io.File;
import java.io.FileReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.stream.Stream;

/** Parses every FreeMarker template under the given roots (.html, .ftl and the .js files that live under
 * WEB-INF/templates, which AppTemplateService renders too) and prints one line per syntax error. */
public class FmParse
{
    /** Entry point: roots as arguments, exit code 1 when a template does not parse. */
    public static void main( String[] args ) throws Exception
    {
        Configuration cfg = new Configuration( Configuration.VERSION_2_3_32 );
        cfg.setNumberFormat( "0.######" );
        int errors = 0;
        int files = 0;
        for ( String root : args )
        {
            try ( Stream<Path> stream = Files.walk( Path.of( root ) ) )
            {
                for ( Path p : (Iterable<Path>) stream.filter( q -> q.toString( ).matches( ".*\\.(html|ftl|js|xml|txt|json)$" ) )::iterator )
                {
                    files++;
                    try ( FileReader reader = new FileReader( p.toFile( ) ) )
                    {
                        new Template( p.toString( ), reader, cfg );
                    }
                    catch ( Exception e )
                    {
                        errors++;
                        System.out.println( "PARSE_ERROR " + p + " :: " + e.getMessage( ).split( "\n" )[0] );
                    }
                }
            }
        }
        System.out.println( "FMPARSE files=" + files + " errors=" + errors );
        System.exit( errors == 0 ? 0 : 1 );
    }
}
