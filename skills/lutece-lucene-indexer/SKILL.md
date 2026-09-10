---
name: lutece-lucene-indexer
description: "Use when adding plugin-internal Lucene search to a Lutece 8 plugin: custom index, indexing daemon, CDI events, batch processing. Triggers on 'Lucene', 'full-text search inside the plugin', 'indexer'."
---

# Lutece 8 Search Indexer

> Before implementing a search indexer, consult `~/.lutece-references/lutece-form-plugin-forms/src/java/fr/paris/lutece/plugins/forms/service/search/` — the reference implementation.

## Architecture Overview

```
IMyPluginSearchIndexer (interface)
    ↑ implements
LuceneMyPluginSearchIndexer (@ApplicationScoped, owns its Lucene index)
    ↓ triggered by
MyPluginSearchDaemon (declared in plugin.xml)
    ↓ fed by
EventListener (@ObservesAsync domain events → queues IndexerAction)
```

A plugin manages its own Lucene index independently from the core. This allows custom fields, sorting, filtering and dedicated search UI in the back-office.

## Step 1 — Indexer Interface

```java
public interface IEntitySearchIndexer
{
    /**
     * Index a single document (queues an action for the daemon)
     */
    void indexDocument( int nIdEntity, int nIdTask, Plugin plugin );

    /**
     * Add an indexer action to the queue
     */
    void addIndexerAction( int nIdEntity, int nIdTask, Plugin plugin );

    /**
     * Process queued actions (called by daemon)
     */
    String incrementalIndexing( );

    /**
     * Rebuild the entire index (called by daemon on flag)
     */
    String fullIndexing( );

    /**
     * Check if index is ready
     */
    boolean isIndexerInitialized( );
}
```

## Step 2 — Lucene Indexer Implementation

```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import org.apache.lucene.document.Document;
import org.apache.lucene.document.Field;
import org.apache.lucene.document.IntPoint;
import org.apache.lucene.document.LongPoint;
import org.apache.lucene.document.NumericDocValuesField;
import org.apache.lucene.document.SortedDocValuesField;
import org.apache.lucene.document.StringField;
import org.apache.lucene.document.TextField;
import org.apache.lucene.index.IndexWriter;
import org.apache.lucene.util.BytesRef;

import fr.paris.lutece.portal.service.search.SearchItem;

@ApplicationScoped
public class LuceneEntitySearchIndexer implements IEntitySearchIndexer
{
    private static final int BATCH_SIZE = 100;

    @Inject
    private LuceneEntitySearchFactory _factory;

    // --- Full reindex ---

    @Override
    public String fullIndexing( )
    {
        // 1. Create temp index
        IndexWriter writer = _factory.getIndexWriter( true ); // temp = true

        try
        {
            List<Integer> listIds = EntityHome.findAllIds( );

            // 2. Batch process
            for ( int i = 0; i < listIds.size( ); i += BATCH_SIZE )
            {
                List<Integer> batch = listIds.subList( i,
                        Math.min( i + BATCH_SIZE, listIds.size( ) ) );

                List<Entity> listEntities = EntityHome.findByPrimaryKeyList( batch );

                for ( Entity entity : listEntities )
                {
                    Document doc = buildDocument( entity );
                    writer.addDocument( doc );
                }

                writer.commit( );
            }
        }
        finally
        {
            _factory.closeWriter( );
        }

        // 3. Swap temp → main index
        _factory.swapIndex( );

        return "Full indexing completed: " + listIds.size( ) + " documents";
    }

    // --- Incremental ---

    @Override
    public String incrementalIndexing( )
    {
        List<IndexerAction> listActions = IndexerActionHome.selectAll( );

        if ( listActions.isEmpty( ) )
        {
            return "No actions to process";
        }

        IndexWriter writer = _factory.getIndexWriter( false ); // main index

        try
        {
            for ( IndexerAction action : listActions )
            {
                switch ( action.getIdTask( ) )
                {
                    case IndexerAction.TASK_CREATE:
                    case IndexerAction.TASK_MODIFY:
                        Entity entity = EntityHome.findByPrimaryKey( action.getIdDocument( ) );
                        if ( entity != null )
                        {
                            // Delete existing then re-add
                            writer.deleteDocuments( IntPoint.newExactQuery(
                                    FIELD_ID_ENTITY, entity.getId( ) ) );
                            writer.addDocument( buildDocument( entity ) );
                        }
                        break;

                    case IndexerAction.TASK_DELETE:
                        writer.deleteDocuments( IntPoint.newExactQuery(
                                FIELD_ID_ENTITY, action.getIdDocument( ) ) );
                        break;
                }
            }

            writer.commit( );

            // Clear processed actions
            IndexerActionHome.deleteAll( );
        }
        finally
        {
            _factory.closeWriter( );
        }

        return "Incremental indexing: " + listActions.size( ) + " actions processed";
    }

    // --- Queue ---

    @Override
    public void indexDocument( int nIdEntity, int nIdTask, Plugin plugin )
    {
        addIndexerAction( nIdEntity, nIdTask, plugin );
    }

    @Override
    public void addIndexerAction( int nIdEntity, int nIdTask, Plugin plugin )
    {
        IndexerAction action = new IndexerAction( );
        action.setIdDocument( nIdEntity );
        action.setIdTask( nIdTask );
        IndexerActionHome.create( action );
    }

    @Override
    public boolean isIndexerInitialized( )
    {
        return _factory.isIndexExists( );
    }

    // --- Document building ---

    private static final String FIELD_ID_ENTITY = "id_entity";
    private static final String FIELD_TITLE = "title";
    private static final String FIELD_DATE_CREATION = "date_creation";

    private Document buildDocument( Entity entity )
    {
        Document doc = new Document( );

        // ID — IntPoint for range queries + stored for retrieval
        doc.add( new IntPoint( FIELD_ID_ENTITY, entity.getId( ) ) );
        doc.add( new NumericDocValuesField( FIELD_ID_ENTITY, entity.getId( ) ) );
        doc.add( new StringField( SearchItem.FIELD_UID,
                String.valueOf( entity.getId( ) ), Field.Store.YES ) );

        // Title — searchable + sortable
        doc.add( new TextField( FIELD_TITLE, entity.getTitle( ), Field.Store.YES ) );
        doc.add( new SortedDocValuesField( FIELD_TITLE,
                new BytesRef( entity.getTitle( ) ) ) );

        // Full-text content
        StringBuilder sbContent = new StringBuilder( );
        sbContent.append( entity.getTitle( ) ).append( " " );
        sbContent.append( entity.getDescription( ) );
        doc.add( new TextField( SearchItem.FIELD_CONTENTS,
                sbContent.toString( ), Field.Store.NO ) );

        // Date — LongPoint for range queries + stored
        if ( entity.getDateCreation( ) != null )
        {
            long lDate = entity.getDateCreation( ).getTime( );
            doc.add( new LongPoint( FIELD_DATE_CREATION, lDate ) );
            doc.add( new NumericDocValuesField( FIELD_DATE_CREATION, lDate ) );
        }

        return doc;
    }
}
```

## Step 3 — Index Factory

Manages index lifecycle (create, open, swap, close):

```java
import jakarta.enterprise.context.ApplicationScoped;

import org.apache.lucene.index.IndexWriter;
import org.apache.lucene.index.IndexWriterConfig;
import org.apache.lucene.store.FSDirectory;

@ApplicationScoped
public class LuceneEntitySearchFactory
{
    private static final String PROPERTY_INDEX_PATH = "myplugin.indexer.lucene.indexPath";
    private static final String PROPERTY_INDEX_IN_WEBAPP = "myplugin.indexer.lucene.indexInWebapp";

    private IndexWriter _writer;

    public IndexWriter getIndexWriter( boolean bTemp )
    {
        Path indexPath = getIndexPath( bTemp );
        FSDirectory directory = FSDirectory.open( indexPath );
        IndexWriterConfig config = new IndexWriterConfig( new StandardAnalyzer( ) );
        _writer = new IndexWriter( directory, config );
        return _writer;
    }

    public void closeWriter( )
    {
        if ( _writer != null )
        {
            _writer.close( );
            _writer = null;
        }
    }

    /**
     * Atomically replace main index with temp index
     */
    public void swapIndex( )
    {
        Path mainPath = getIndexPath( false );
        Path tempPath = getIndexPath( true );
        Path backupPath = mainPath.resolveSibling( mainPath.getFileName( ) + "_backup" );

        // Rename: main → backup, temp → main, delete backup
        Files.move( mainPath, backupPath );
        Files.move( tempPath, mainPath );
        FileUtils.deleteDirectory( backupPath.toFile( ) );
    }

    public boolean isIndexExists( )
    {
        return Files.exists( getIndexPath( false ) );
    }

    private Path getIndexPath( boolean bTemp )
    {
        String strPath = AppPropertiesService.getProperty( PROPERTY_INDEX_PATH );
        boolean bInWebapp = Boolean.parseBoolean(
                AppPropertiesService.getProperty( PROPERTY_INDEX_IN_WEBAPP, "true" ) );

        Path path;
        if ( bInWebapp )
        {
            path = Paths.get( AppPathService.getWebAppPath( ), strPath );
        }
        else
        {
            path = Paths.get( strPath );
        }

        return bTemp ? path.resolveSibling( path.getFileName( ) + "_tmp" ) : path;
    }
}
```

## Step 4 — Daemon

```java
import fr.paris.lutece.portal.service.daemon.Daemon;
import fr.paris.lutece.portal.service.datastore.DatastoreService;
import jakarta.enterprise.inject.spi.CDI;

public class EntitySearchDaemon extends Daemon
{
    private static final String DATASTORE_KEY_FULL_INDEX = "myplugin.index.full";

    @Override
    public void run( )
    {
        IEntitySearchIndexer indexer = CDI.current( )
                .select( IEntitySearchIndexer.class ).get( );

        // Auto-initialize on first run
        if ( !indexer.isIndexerInitialized( ) )
        {
            setLastRunLogs( indexer.fullIndexing( ) );
            return;
        }

        // Full reindex if flag set in datastore
        String strFullIndex = DatastoreService.getDataValue( DATASTORE_KEY_FULL_INDEX, "false" );

        if ( Boolean.parseBoolean( strFullIndex ) )
        {
            DatastoreService.setDataValue( DATASTORE_KEY_FULL_INDEX, "false" );
            setLastRunLogs( indexer.fullIndexing( ) );
        }
        else
        {
            setLastRunLogs( indexer.incrementalIndexing( ) );
        }
    }
}
```

Declare in plugin.xml:
```xml
<daemons>
    <daemon>
        <daemon-id>entitySearchDaemon</daemon-id>
        <daemon-name>myplugin.daemon.entitySearchDaemon.name</daemon-name>
        <daemon-description>myplugin.daemon.entitySearchDaemon.description</daemon-description>
        <daemon-class>fr.paris.lutece.plugins.myplugin.service.search.EntitySearchDaemon</daemon-class>
        <daemon-interval>60</daemon-interval>
    </daemon>
</daemons>
```

## Step 5 — CDI Event Listener

```java
import fr.paris.lutece.portal.business.indexeraction.IndexerAction;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.ObservesAsync;
import jakarta.inject.Inject;

@ApplicationScoped
public class EntityIndexerEventListener
{
    @Inject
    private IEntitySearchIndexer _indexer;

    public void onEntityCreated( @ObservesAsync EntityCreatedEvent event )
    {
        _indexer.addIndexerAction( event.getEntityId( ),
                IndexerAction.TASK_CREATE, event.getPlugin( ) );
    }

    public void onEntityUpdated( @ObservesAsync EntityUpdatedEvent event )
    {
        _indexer.addIndexerAction( event.getEntityId( ),
                IndexerAction.TASK_MODIFY, event.getPlugin( ) );
    }

    public void onEntityDeleted( @ObservesAsync EntityDeletedEvent event )
    {
        _indexer.addIndexerAction( event.getEntityId( ),
                IndexerAction.TASK_DELETE, event.getPlugin( ) );
    }
}
```

Fire events from Service:
```java
@Inject
private Event<EntityCreatedEvent> _entityCreatedEvent;

public Entity create( Entity entity )
{
    EntityHome.create( entity );
    _entityCreatedEvent.fireAsync( new EntityCreatedEvent( entity.getId( ), _plugin ) );
    return entity;
}
```

## Step 6 — IndexerAction (queue table)

SQL for the plugin's own action queue:
```sql
CREATE TABLE myplugin_indexer_action (
    id_action INT AUTO_INCREMENT PRIMARY KEY,
    id_document INT NOT NULL,
    id_task INT NOT NULL
);
```

With corresponding `IndexerAction` entity, DAO, Home in the `business/` package.

## Lucene Field Types

| Type | For | Example |
|------|-----|---------|
| `StringField` | Exact match, stored IDs | UIDs, type codes |
| `TextField` | Full-text search | Title, description, content |
| `IntPoint` | Integer range queries | `IntPoint.newExactQuery(field, value)` |
| `LongPoint` | Long/date range queries | Timestamps |
| `NumericDocValuesField` | Sorting on numbers | Sort by ID, date |
| `SortedDocValuesField` | Sorting on strings | Sort by title |
| `StoredField` | Store-only (no search) | Display values |

## Configuration Properties

```properties
# Index location
myplugin.indexer.lucene.indexPath=WEB-INF/plugins/myplugin/lucene
myplugin.indexer.lucene.indexInWebapp=true

# Batch size for full reindex
myplugin.indexer.commitSize=100

# Daemon interval (seconds)
# Configured in plugin.xml <daemon-interval>
```

Datastore flag for full reindex: `myplugin.index.full` = `true` triggers full reindex on next daemon run.

## File Checklist

| File | What to create |
|------|----------------|
| `IEntitySearchIndexer.java` | Interface in `service/search/` |
| `LuceneEntitySearchIndexer.java` | Implementation `@ApplicationScoped` |
| `LuceneEntitySearchFactory.java` | Index lifecycle (open, close, swap) |
| `EntitySearchDaemon.java` | Daemon extending `Daemon` |
| `EntityIndexerEventListener.java` | CDI `@ObservesAsync` listener |
| `IndexerAction.java` + DAO + Home | Queue entity in `business/` |
| `create_db_myplugin.sql` | `myplugin_indexer_action` table |
| `plugin.xml` | `<daemon>` declaration |
| `myplugin.properties` | Index path, batch size |

## Reference Sources

| Need | File to consult |
|------|----------------|
| Indexer interface | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/search/IFormSearchIndexer.java` |
| Lucene implementation | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/search/LuceneFormSearchIndexer.java` |
| Index factory (swap, lock) | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/search/LuceneFormSearchFactory.java` |
| Daemon | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/search/FormsSearchIndexerDaemon.java` |
| CDI event listener | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/listener/FormResponseEventListener.java` |
| SearchItem (field names) | `~/.lutece-references/lutece-core/src/java/**/service/search/SearchItem.java` |
