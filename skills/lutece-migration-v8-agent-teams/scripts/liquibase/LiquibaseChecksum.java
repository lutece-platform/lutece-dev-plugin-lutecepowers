import java.nio.file.Path;
import java.nio.file.Paths;

import liquibase.ChecksumVersion;
import liquibase.changelog.ChangeLogParameters;
import liquibase.changelog.ChangeSet;
import liquibase.changelog.DatabaseChangeLog;
import liquibase.parser.core.formattedsql.FormattedSqlChangeLogParser;
import liquibase.resource.DirectoryResourceAccessor;

/**
 * Prints the v8 and v9 Liquibase checksums of every changeset of a formatted SQL file, the values a rewritten
 * changeset declares with validCheckSum so the sites that already ran the old body still start.
 */
public class LiquibaseChecksum
{
    /** Entry point: the formatted SQL file to read. */
    public static void main( String[] args ) throws Exception
    {
        Path file = Paths.get( args[0] ).toAbsolutePath( );
        DirectoryResourceAccessor accessor = new DirectoryResourceAccessor( file.getParent( ) );
        DatabaseChangeLog log = new FormattedSqlChangeLogParser( ).parse( file.getFileName( ).toString( ), new ChangeLogParameters( ), accessor );
        for ( ChangeSet cs : log.getChangeSets( ) )
        {
            System.out.println( cs.getAuthor( ) + ":" + cs.getId( ) + " v8=" + cs.generateCheckSum( ChecksumVersion.V8 ) + " v9=" + cs.generateCheckSum( ChecksumVersion.V9 ) );
        }
    }
}
