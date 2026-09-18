# Lucene indexer — the implementation class

The full model for Step 2. The build order and the other steps are in SKILL.md.

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

