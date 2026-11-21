import freemarker.cache.ConditionalTemplateConfigurationFactory;
import freemarker.cache.FileExtensionMatcher;
import freemarker.cache.FirstMatchTemplateConfigurationFactory;
import freemarker.core.CSSOutputFormat;
import freemarker.core.HTMLOutputFormat;
import freemarker.core.JSONOutputFormat;
import freemarker.core.JavaScriptOutputFormat;
import freemarker.core.OutputFormat;
import freemarker.core.TemplateConfiguration;
import freemarker.template.Configuration;
import freemarker.template.Template;
import java.io.File;
import java.io.FileReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.stream.Stream;

/** Parses every FreeMarker template under the given roots (.html, .ftl and the .js files that live under
 * WEB-INF/templates, which AppTemplateService renders too) and prints one line per syntax error. With --html first, they
 * are read as lutece-core 8.1 reads them: the HTML output format, a .js, .json or .css template in its own. */
public class FmParse
{
    /** A template configuration setting an output format. */
    private static TemplateConfiguration withOutputFormat( OutputFormat format )
    {
        TemplateConfiguration tc = new TemplateConfiguration( );
        tc.setOutputFormat( format );
        return tc;
    }

    /** Entry point: [--html] then roots as arguments, exit code 1 when a template does not parse. */
    public static void main( String[] args ) throws Exception
    {
        Configuration cfg = new Configuration( Configuration.VERSION_2_3_32 );
        cfg.setNumberFormat( "0.######" );
        boolean html = args.length > 0 && args[0].equals( "--html" );
        if ( html )
        {
            cfg.setOutputFormat( HTMLOutputFormat.INSTANCE );
            cfg.setAutoEscapingPolicy( Configuration.ENABLE_IF_DEFAULT_AUTO_ESCAPING_POLICY );
            cfg.setTemplateConfigurations( new FirstMatchTemplateConfigurationFactory(
                    new ConditionalTemplateConfigurationFactory( new FileExtensionMatcher( "js" ), withOutputFormat( JavaScriptOutputFormat.INSTANCE ) ),
                    new ConditionalTemplateConfigurationFactory( new FileExtensionMatcher( "json" ), withOutputFormat( JSONOutputFormat.INSTANCE ) ),
                    new ConditionalTemplateConfigurationFactory( new FileExtensionMatcher( "css" ), withOutputFormat( CSSOutputFormat.INSTANCE ) ) )
                    .allowNoMatch( true ) );
        }
        int errors = 0;
        int files = 0;
        for ( int i = html ? 1 : 0; i < args.length; i++ )
        {
            String root = args[i];
            try ( Stream<Path> stream = Files.walk( Path.of( root ) ) )
            {
                for ( Path p : (Iterable<Path>) stream.filter( q -> q.toString( ).matches( ".*\\.(html|ftl|js|xml|txt|json)$" ) )::iterator )
                {
                    files++;
                    try ( FileReader reader = new FileReader( p.toFile( ) ) )
                    {
                        new Template( p.toString( ), p.toString( ), reader, cfg );
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
