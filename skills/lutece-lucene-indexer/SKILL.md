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
LuceneMyPluginSearchIndexer (@ApplicationScoped, owns its Lucene index,
                             runs under a DB lease lock: ILuceneLockManager)
    ↓ triggered by
MyPluginSearchDaemon (declared in plugin.xml, interval from daemon.<id>.interval)
    ↓ fed by
EventListener (@ObservesAsync domain events → queues IndexerAction)
```

A plugin manages its own Lucene index independently from the core. This allows custom fields, sorting, filtering and dedicated search UI in the back-office.

Two constraints come from the forms reference and from the cluster rules (`lutece-scalability-v8` distributed-lock.md):
- The index lives **outside the webapp**, on a path every node can mount (`indexInWebapp=false`, absolute `indexPath`). `FormsPlugin.warnIfIndexPathIsNodeLocal()` logs an error when the path is under the webapp or `java.io.tmpdir`.
- Full and incremental indexing run under a **database lease lock** with heartbeat (forms `LuceneLockManagerDB` + `LockDAO`, table `forms_lucene_lock`), so a daemon that fires on every node writes the index from one node at a time.

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
    private static final String LOCKNAME = "myplugin.lucene.lock";
    private static final long MS_TIMEOUT_LOCK = AppPropertiesService.getPropertyLong( "myplugin.index.writer.ms.timeout.lock", 900000L );

    @Inject
    private LuceneEntitySearchFactory _factory;

    private final ILuceneLockManager _lockManager;

    public LuceneEntitySearchIndexer( )
    {
        this( null );
    }

    @Inject
    public LuceneEntitySearchIndexer( @Named( "myplugin.luceneLockManager" ) ILuceneLockManager lockManager )
    {
        _lockManager = lockManager;
    }

    // --- Full reindex ---

    @Override
    public String fullIndexing( )
    {
        LockResult lock;
        try
        {
            lock = _lockManager.acquireLock( LOCKNAME, MS_TIMEOUT_LOCK );
        }
        catch ( LockException e )
        {
            return "Indexing already in progress, full indexing aborted";
        }

        IndexWriter writer = _factory.getIndexWriter( true ); // temp = true
        List<Integer> listIds;

        try
        {
            listIds = EntityHome.findAllIds( );

            for ( int i = 0; i < listIds.size( ); i += BATCH_SIZE )
            {
                List<Integer> batch = listIds.subList( i,
                        Math.min( i + BATCH_SIZE, listIds.size( ) ) );

                List<Entity> listEntities = EntityHome.findByPrimaryKeyList( batch );

                for ( Entity entity : listEntities )
                {
                    writer.addDocument( buildDocument( entity ) );
                }

                writer.commit( );
                lock = _lockManager.refreshLock( lock, MS_TIMEOUT_LOCK );
            }

            _factory.swapIndex( );
        }
        finally
        {
            _factory.closeWriter( );
            _lockManager.releaseLock( lock );
        }

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

        LockResult lock;
        try
        {
            lock = _lockManager.acquireLock( LOCKNAME, MS_TIMEOUT_LOCK );
        }
        catch ( LockException e )
        {
            return "Indexing already in progress, incremental indexing aborted";
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
            _lockManager.releaseLock( lock );
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

`ILuceneLockManager` is plugin-local, copied from forms: interface `FormsDistributedLockManager` (`acquireLock( name, timeoutMs )`, `refreshLock`, `releaseLock`, `LockResult`, `LockException`), implementation `LuceneLockManagerDB` (`@ApplicationScoped @Named( "forms.luceneLockManager" )`) backed by `LockDAO` on a `<plugin>_lucene_lock` table (`index_name` PK, `instance_name`, `is_locked`, `date_begin`, `expired_date`, `uuid`). Forms renews the lock from a heartbeat thread at TTL/3 (`startLockHeartbeat`); the per-batch `refreshLock` above is the minimal form of the same idea.

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
        boolean bInWebapp = AppPropertiesService.getPropertyBoolean( PROPERTY_INDEX_IN_WEBAPP, false );

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

In `MyPlugin.init()`, log an error when `indexInWebapp` is true or `indexPath` is under `java.io.tmpdir` (copy `FormsPlugin.warnIfIndexPathIsNodeLocal()`): both are node-local and produce one diverging index per node.

## Step 4 — Daemon

```java
import fr.paris.lutece.portal.service.daemon.Daemon;
import fr.paris.lutece.portal.service.datastore.DatastoreService;
import jakarta.enterprise.inject.spi.CDI;

public class EntitySearchDaemon extends Daemon
{
    private static final String DATASTORE_KEY_FULL_INDEX = "myplugin.index.full";

    private final IEntitySearchIndexer _indexer = CDI.current( ).select( IEntitySearchIndexer.class ).get( );

    @Override
    public void run( )
    {
        if ( !_indexer.isIndexerInitialized( ) )
        {
            setLastRunLogs( _indexer.fullIndexing( ) );
            return;
        }

        String strFullIndex = DatastoreService.getDataValue( DATASTORE_KEY_FULL_INDEX, DatastoreService.VALUE_FALSE );

        if ( DatastoreService.VALUE_TRUE.equals( strFullIndex ) )
        {
            try
            {
                setLastRunLogs( _indexer.fullIndexing( ) );
            }
            finally
            {
                DatastoreService.setDataValue( DATASTORE_KEY_FULL_INDEX, DatastoreService.VALUE_FALSE );
            }
        }
        else
        {
            setLastRunLogs( _indexer.incrementalIndexing( ) );
        }
    }
}
```

The daemon is instantiated by `Class.forName` (core `DaemonEntry.loadDaemon`), never by CDI: no scope annotation, dependencies through `CDI.current()` (forms `FormsSearchIndexerDaemon`).

Declare in plugin.xml (no interval element exists in `plugin-digester-rules.xml`):
```xml
<daemons>
    <daemon>
        <daemon-id>entitySearchDaemon</daemon-id>
        <daemon-name>myplugin.daemon.entitySearchDaemon.name</daemon-name>
        <daemon-description>myplugin.daemon.entitySearchDaemon.description</daemon-description>
        <daemon-class>fr.paris.lutece.plugins.myplugin.service.search.EntitySearchDaemon</daemon-class>
    </daemon>
</daemons>
```

Interval and startup come from properties read by `AppDaemonService.registerDaemon` (seconds, default 10, then persisted in the datastore):
```properties
daemon.entitySearchDaemon.interval=30
daemon.entitySearchDaemon.onstartup=1
```

## Step 5 — CDI Event Listener

```java
import fr.paris.lutece.plugins.myplugin.business.search.IndexerAction;
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

## Step 6 — IndexerAction queue and lock tables

The queue entity is **plugin-local** (`business/search/IndexerAction` with `TASK_CREATE`, `TASK_MODIFY`, `TASK_DELETE`, `getIdDocument()`, `getIdTask()`), like forms' `business/form/search/IndexerAction`; the core `fr.paris.lutece.portal.business.indexeraction.IndexerAction` belongs to the core indexer and is not used here.

`src/sql/plugins/myplugin/plugin/create_db_myplugin.sql` (Liquibase header required, `rules/sql-liquibase.md`):
```sql
-- liquibase formatted sql
-- changeset myplugin:create_db_myplugin.sql
-- preconditions onFail:MARK_RAN onError:WARN
DROP TABLE IF EXISTS myplugin_indexer_action;
CREATE TABLE myplugin_indexer_action (
    id_action INT AUTO_INCREMENT,
    id_document INT DEFAULT 0 NOT NULL,
    id_task INT DEFAULT 0 NOT NULL,
    PRIMARY KEY (id_action)
);
CREATE INDEX idx_mia_id_document ON myplugin_indexer_action ( id_document );

DROP TABLE IF EXISTS myplugin_lucene_lock;
CREATE TABLE myplugin_lucene_lock (
    index_name VARCHAR(50),
    instance_name VARCHAR(50),
    is_locked SMALLINT,
    date_begin TIMESTAMP NULL,
    expired_date TIMESTAMP NULL,
    uuid VARCHAR(50),
    PRIMARY KEY (index_name)
);
```

With the corresponding `IndexerAction` and `Lock` entities, DAOs and Homes in the `business/` package.

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
# Index location: absolute path on a volume mounted R/W by every node (NFS, PV).
# Never under the webapp nor java.io.tmpdir (node-local, one diverging index per node).
myplugin.indexer.lucene.indexPath=/var/lib/lutece/myplugin/index
myplugin.indexer.lucene.indexInWebapp=false

# Batch size for full reindex
myplugin.indexer.commitSize=100

# Lease lock TTL (ms) held in myplugin_lucene_lock; renewed while indexing runs
myplugin.index.writer.ms.timeout.lock=900000

# Daemon schedule (seconds); read by AppDaemonService, not by plugin.xml
daemon.entitySearchDaemon.interval=30
daemon.entitySearchDaemon.onstartup=1
```

Datastore flag for full reindex: `myplugin.index.full` = `true` triggers full reindex on next daemon run.

## File Checklist

| File | What to create |
|------|----------------|
| `IEntitySearchIndexer.java` | Interface in `service/search/` |
| `LuceneEntitySearchIndexer.java` | Implementation `@ApplicationScoped` |
| `LuceneEntitySearchFactory.java` | Index lifecycle (open, close, swap) |
| `EntitySearchDaemon.java` | Daemon extending `Daemon` (reflection-instantiated, no CDI scope) |
| `EntityIndexerEventListener.java` | CDI `@ObservesAsync` listener |
| `IndexerAction.java` + DAO + Home | Queue entity in `business/search/` |
| `ILuceneLockManager.java` + `LuceneLockManagerDB.java` + `LockDAO.java` | DB lease lock, copied from forms `service/lock/` and `business/form/lock/` |
| `create_db_myplugin.sql` | Liquibase header + `myplugin_indexer_action` + `myplugin_lucene_lock` |
| `plugin.xml` | `<daemon>` declaration (`<daemon-class>`, no interval) |
| `myplugin.properties` | Index path outside the webapp, lock TTL, `daemon.<id>.interval` |

## Reference Sources

| Need | File to consult |
|------|----------------|
| Indexer interface | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/search/IFormSearchIndexer.java` |
| Lucene implementation | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/search/LuceneFormSearchIndexer.java` |
| Index factory (swap, lock) | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/search/LuceneFormSearchFactory.java` |
| Daemon | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/search/FormsSearchIndexerDaemon.java` |
| Lease lock (interface, DB impl, DAO) | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/lock/` and `**/business/form/lock/LockDAO.java` |
| Node-local index warning | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/FormsPlugin.java` (`warnIfIndexPathIsNodeLocal`) |
| Index and daemon properties | `~/.lutece-references/lutece-form-plugin-forms/webapp/WEB-INF/conf/plugins/forms.properties` |
| CDI event listener | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/listener/FormResponseEventListener.java` |
| SearchItem (field names) | `~/.lutece-references/lutece-core/src/java/**/service/search/SearchItem.java` |
