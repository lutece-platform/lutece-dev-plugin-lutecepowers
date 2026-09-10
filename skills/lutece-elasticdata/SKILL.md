---
name: lutece-elasticdata
description: "Use when creating or modifying an Elasticsearch DataSource module for Lutece 8: DataSource and DataObject interfaces, CDI auto-discovery, @ConfigProperty injection, batch processing, two-daemon indexing, incremental updates through CDI events. Triggers on 'elasticdata', 'Elasticsearch', 'DataSource module'."
---

# Lutece 8 ElasticData DataSource Module

> Before implementing a DataSource, consult `~/.lutece-references/lutece-form-module-elasticdata-forms/` — the reference implementation. The framework plugin is at `~/.lutece-references/lutece-elk-plugin-elasticdata/` and the HTTP client library at `~/.lutece-references/lutece-elk-library-elastic/`.

## Architecture Overview

```
library-elastic (HTTP/JSON wrapper around Elasticsearch REST API)
    ↑ used by
plugin-elasticdata (framework — already deployed)
    ↓ auto-discovers via CDI
module-myentity-elasticdata (@ApplicationScoped DataSource)
    ↓ produces
MyEntityDataObject (extends AbstractDataObject)
    ↓ indexed by two daemons
FullIndexingDaemon (daily, bulk reindex)
IncrementalIndexingDaemon (interval `daemon.incrementalIndexingDaemon.interval`, processes IndexerAction queue)

Incremental path:
Entity CRUD → CDI event fired
    ↓ observed by
MyEntityIndexerEventListener (@ObservesAsync)
    ↓ calls
DataSourceIncrementalService.addTask(dataSourceId, entityId, taskType)
    ↓ queues in DB → daemon processes
```

A module provides a `DataSource` implementation. The plugin-elasticdata framework handles Elasticsearch communication, daemon scheduling, batch processing, and action queue management.

**CDI auto-discovery** — any `@ApplicationScoped` class implementing `DataSource` is automatically registered:
```java
// Inside DataSourceService (plugin-elasticdata)
CDI.current( ).select( DataSource.class ).stream( )
    .forEach( source -> _mapDataSources.put( source.getId( ), source ) );
```

**Three-layer architecture:**
- **library-elastic** — Low-level HTTP client (uses `library-httpaccess`, not the official ES Java client)
- **plugin-elasticdata** — Generic indexing framework (daemons, action queue, bulk API)
- **Your module** — Domain-specific DataSource and DataObject

## Step 1 — Maven Module Setup

```xml
<parent>
    <groupId>fr.paris.lutece.tools</groupId>
    <artifactId>lutece-global-pom</artifactId>
    <version>LATEST_RELEASED_8_X</version>
</parent>

<artifactId>module-elasticdata-myentity</artifactId>
<packaging>lutece-plugin</packaging>

<dependencies>
    <dependency>
        <groupId>fr.paris.lutece.plugins</groupId>
        <artifactId>plugin-elasticdata</artifactId>
        <version>[3.0.0,)</version>
        <type>lutece-plugin</type>
    </dependency>
    <dependency>
        <groupId>fr.paris.lutece.plugins</groupId>
        <artifactId>plugin-myentity</artifactId>
        <version>[X.0.0,)</version>
        <type>lutece-plugin</type>
    </dependency>
</dependencies>
```

Replace `LATEST_RELEASED_8_X` with the latest released `lutece-global-pom` 8.x (check the Lutece Maven repository, never hardcode a guess). The module is never its own parent (reference: `lutece-form-module-elasticdata-forms/pom.xml`).

## Step 2 — DataSource Implementation

```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import org.eclipse.microprofile.config.inject.ConfigProperty;

import fr.paris.lutece.plugins.elasticdata.business.AbstractDataSource;
import fr.paris.lutece.plugins.elasticdata.business.DataObject;

@ApplicationScoped
public class MyEntityDataSource extends AbstractDataSource
{
    public MyEntityDataSource( )
    {
    }

    @Inject
    public MyEntityDataSource(
            @ConfigProperty( name = "elasticdata-myentity.dataSource.id" ) String strId,
            @ConfigProperty( name = "elasticdata-myentity.dataSource.name" ) String strName,
            @ConfigProperty( name = "elasticdata-myentity.dataSource.targetIndexName" ) String strTargetIndex,
            @ConfigProperty( name = "elasticdata-myentity.dataSource.mappings" ) String strMappings )
    {
        setId( strId );
        setName( strName );
        setTargetIndexName( strTargetIndex );
        setMappings( strMappings );
    }

    // --- Return all entity IDs (for full indexing) ---
    @Override
    public List<String> getIdDataObjects( )
    {
        return MyEntityHome.findAllIds( ).stream( )
                .map( String::valueOf )
                .collect( Collectors.toList( ) );
    }

    // --- Fetch entities by ID batch (called by BatchDataObjectsIterator) ---
    @Override
    public List<DataObject> getDataObjects( List<String> listIds )
    {
        List<Integer> listIntIds = listIds.stream( )
                .map( Integer::parseInt )
                .collect( Collectors.toList( ) );

        List<MyEntity> listEntities = MyEntityHome.findByPrimaryKeyList( listIntIds );

        return listEntities.stream( )
                .map( this::buildDataObject )
                .collect( Collectors.toList( ) );
    }

    @Override
    public boolean isLocalizable( )
    {
        return false; // true if entities have geo_point fields
    }

    @Override
    public boolean usesFullIndexingDaemon( )
    {
        return true; // enable daily full reindex via FullIndexingDaemon
    }

    // --- Build a DataObject from an entity ---
    private DataObject buildDataObject( MyEntity entity )
    {
        // See Step 3
    }

    // --- Incremental indexing helper ---
    public void indexDocument( int nIdEntity, int nIdTask )
    {
        DataSourceIncrementalService.addTask(
                getId( ),
                String.valueOf( nIdEntity ),
                nIdTask );
    }
}
```

**Key points:**
- The no-arg constructor is required next to the `@Inject` one: `@ApplicationScoped` beans are proxied by their concrete class (reference `FormsDataSource.java:116`)
- `@ConfigProperty` injects values from properties file (MicroProfile Config)
- `getIdDataObjects()` returns ALL IDs — the framework handles batching via `BatchDataObjectsIterator`
- `getDataObjects(List)` fetches a batch of entities — keep this efficient (single SQL query for the batch)
- `AbstractDataSource` provides `getDataObjectsIterator()` implementation using `BatchDataObjectsIterator`

## Step 3 — DataObject Implementation

```java
import com.fasterxml.jackson.annotation.JsonIgnore;

import fr.paris.lutece.plugins.elasticdata.business.AbstractDataObject;

import java.util.HashMap;
import java.util.Map;

public class MyEntityDataObject extends AbstractDataObject
{
    // Typed fields (appear as JSON properties in ES document)
    private int _nFormId;
    private String _strEntityName;
    private String _strStatus;
    private String _strWorkflowState;

    // Dynamic fields (flexible key-value map)
    private Map<String, Object> _mapUserData = new HashMap<>( );

    // --- Required by DataObject ---

    @JsonIgnore  // ID is used for routing, not indexed as field
    @Override
    public String getId( )
    {
        return String.valueOf( _nFormId );
    }

    @Override
    public String getDocumentTypeName( )
    {
        return "myEntityResponse";
    }

    // --- Typed getters/setters ---

    public int getFormId( )
    {
        return _nFormId;
    }

    public void setFormId( int nFormId )
    {
        _nFormId = nFormId;
    }

    public String getEntityName( )
    {
        return _strEntityName;
    }

    public void setEntityName( String strEntityName )
    {
        _strEntityName = strEntityName;
    }

    public String getStatus( )
    {
        return _strStatus;
    }

    public void setStatus( String strStatus )
    {
        _strStatus = strStatus;
    }

    public String getWorkflowState( )
    {
        return _strWorkflowState;
    }

    public void setWorkflowState( String strWorkflowState )
    {
        _strWorkflowState = strWorkflowState;
    }

    // --- Dynamic user data (serialized as nested JSON) ---

    public Map<String, Object> getUserData( )
    {
        return _mapUserData;
    }

    public void setUserData( Map<String, Object> mapUserData )
    {
        _mapUserData = mapUserData;
    }
}
```

**Key points:**
- `AbstractDataObject` provides `getTimestamp()` with day/week/month extraction for analytics
- `@JsonIgnore` on `getId()` — the ID is used for ES document routing, not stored as a field
- `getDocumentTypeName()` — identifies the document type within the index
- Typed fields become JSON properties; `Map<String, Object>` allows flexible dynamic attributes
- Jackson serializes all public getters to JSON for indexing

## Step 4 — CDI Event Listener (Incremental Updates)

```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.ObservesAsync;
import jakarta.inject.Inject;

import fr.paris.lutece.plugins.elasticdata.business.IndexerAction;
import fr.paris.lutece.plugins.myentity.business.MyEntityEvent;

@ApplicationScoped
public class MyEntityIndexerEventListener
{
    @Inject
    private MyEntityDataSource _dataSource;

    public void onEntityCreated(
            @ObservesAsync @Type( EventAction.CREATE ) MyEntityEvent event )
    {
        _dataSource.indexDocument( event.getEntityId( ), IndexerAction.TASK_CREATE );
    }

    public void onEntityUpdated(
            @ObservesAsync @Type( EventAction.UPDATE ) MyEntityEvent event )
    {
        _dataSource.indexDocument( event.getEntityId( ), IndexerAction.TASK_CREATE );
    }

    public void onEntityDeleted(
            @ObservesAsync @Type( EventAction.REMOVE ) MyEntityEvent event )
    {
        _dataSource.indexDocument( event.getEntityId( ), IndexerAction.TASK_DELETE );
    }
}
```

Fire events from your Service layer — select the `@Type` qualifier to match the observer:

```java
import fr.paris.lutece.portal.service.event.EventAction;
import fr.paris.lutece.portal.service.event.Type.TypeQualifier;

@Inject
private Event<MyEntityEvent> _entityEvent;

public MyEntity create( MyEntity entity )
{
    MyEntityHome.create( entity );
    _entityEvent.select( new TypeQualifier( EventAction.CREATE ) )
            .fireAsync( new MyEntityEvent( entity.getId( ) ) );
    return entity;
}

public void remove( int nIdEntity )
{
    MyEntityHome.remove( nIdEntity );
    _entityEvent.select( new TypeQualifier( EventAction.REMOVE ) )
            .fireAsync( new MyEntityEvent( nIdEntity ) );
}
```

**Task types:**
- `IndexerAction.TASK_CREATE` (1) — Index new document (also used for updates)
- `IndexerAction.TASK_MODIFY` (2) — Partial update
- `IndexerAction.TASK_DELETE` (3) — Delete by query

The `IncrementalIndexingDaemon` processes the queue on the interval set by `daemon.incrementalIndexingDaemon.interval` (seconds; plugin-elasticdata ships `3000`, and `daemon.fullIndexingDaemon.interval=86400`). It handles conflict resolution automatically (e.g., CREATE followed by DELETE = task removed).

## Step 5 — Elasticsearch Mappings

Provide custom mappings via `@ConfigProperty` or override `getMappings()`:

```json
{
    "mappings": {
        "properties": {
            "timestamp": {
                "type": "date",
                "format": "yyyy-MM-dd HH:mm:ss||yyyy-MM-dd||epoch_millis"
            },
            "entityName": {
                "type": "text",
                "fields": { "keyword": { "type": "keyword" } }
            },
            "status": {
                "type": "keyword"
            },
            "workflowState": {
                "type": "keyword"
            }
        }
    }
}
```

**Default mappings** from `DataSourceUtils`:
- `TIMESTAMP_MAPPINGS` — timestamp field only
- `TIMESTAMP_AND_LOCATION_MAPPINGS` — timestamp + `geo_point` for spatial data

Use custom mappings when you need keyword fields for aggregations, specific analyzers, or nested objects.

## Step 6 — Configuration Properties

```properties
# elasticdata-myentity.properties (MicroProfile Config)

# DataSource identity (injected via @ConfigProperty)
elasticdata-myentity.dataSource.id=MyEntityDataSource
elasticdata-myentity.dataSource.name=My Entity Data Source
elasticdata-myentity.dataSource.targetIndexName=myentity
elasticdata-myentity.dataSource.mappings={"mappings":{"properties":{"timestamp":{"type":"date","format":"yyyy-MM-dd HH:mm:ss||yyyy-MM-dd||epoch_millis"}}}}
```

The Elasticsearch server connection is configured at the plugin-elasticdata level (not in your module):
```properties
# Already in plugin-elasticdata config (do NOT duplicate)
elasticdata.elastic_server.url=http://localhost:9200
elasticdata.elastic_server.login=
elasticdata.elastic_server.pwd=
elasticdata.bulk_batch_size=10000
```

## Step 7 — plugin.xml

```xml
<plug-in>
    <name>myentity-elasticdata</name>
    <class>fr.paris.lutece.portal.service.plugin.PluginDefaultImplementation</class>
    <version>1.0.0-SNAPSHOT</version>
    <description>ElasticData module for MyEntity plugin</description>
    <core-version-dependency>
        <min-core-version>8.0.0</min-core-version>
    </core-version-dependency>
    <db-pool-required>0</db-pool-required>
</plug-in>
```

No daemons or admin features needed — the plugin-elasticdata framework provides them.

## IDataSourceExternalAttributesProvider (Advanced)

Enrich data objects from other modules with additional attributes:

```java
@ApplicationScoped
public class MyAttributeProvider implements IDataSourceExternalAttributesProvider
{
    public void provideAttributes( DataObject dataObject )
    {
        // Enrich a single object
    }

    public void provideAttributes( List<DataObject> listDataObject )
    {
        // Batch enrichment (preferred for performance)
        for ( DataObject obj : listDataObject )
        {
            // Add external attributes
        }
    }
}
```

Providers are auto-discovered via CDI and called during full indexing (`completeDataObjectWithFullData`).

## Indexing Lifecycle

| Mode | Daemon | Interval | Trigger | What happens |
|------|--------|----------|---------|--------------|
| Full | `FullIndexingDaemon` | `daemon.fullIndexingDaemon.interval` (shipped: 86400 s) | Admin button or daemon schedule | Delete index → recreate with mappings → bulk index all DataObjects |
| Incremental | `IncrementalIndexingDaemon` | `daemon.incrementalIndexingDaemon.interval` (shipped: 3000 s) | CDI events → `DataSourceIncrementalService.addTask()` | Process IndexerAction queue (create/update/delete) |

**Transaction safety:** Incremental indexing wraps ES operations + DB task removal in a single transaction. If ES fails, the task remains in queue for retry.

## File Checklist

| File | What to create |
|------|----------------|
| `pom.xml` | Maven module with plugin-elasticdata dependency |
| `MyEntityDataSource.java` | `@ApplicationScoped` extending `AbstractDataSource`, `@ConfigProperty` constructor |
| `MyEntityDataObject.java` | Extends `AbstractDataObject`, typed fields + `Map<String,Object>` |
| `MyEntityIndexerEventListener.java` | `@ObservesAsync` CDI listener |
| `elasticdata-myentity.properties` | `@ConfigProperty` values (id, name, index, mappings) |
| `WEB-INF/plugins/myentity-elasticdata.xml` | plugin.xml descriptor |
| `webapp/WEB-INF/classes/META-INF/beans.xml` | CDI descriptor (empty `<beans>` tag) |

No daemon, no DAO, no SQL table needed — plugin-elasticdata provides all infrastructure.

## Reference Sources

| Need | File to consult |
|------|----------------|
| DataSource interface | `~/.lutece-references/lutece-elk-plugin-elasticdata/src/java/**/business/DataSource.java` |
| AbstractDataSource (batch iterator) | `~/.lutece-references/lutece-elk-plugin-elasticdata/src/java/**/business/AbstractDataSource.java` |
| DataObject interface | `~/.lutece-references/lutece-elk-plugin-elasticdata/src/java/**/business/DataObject.java` |
| AbstractDataObject (timestamp) | `~/.lutece-references/lutece-elk-plugin-elasticdata/src/java/**/business/AbstractDataObject.java` |
| DataSourceService (CDI discovery) | `~/.lutece-references/lutece-elk-plugin-elasticdata/src/java/**/service/DataSourceService.java` |
| Incremental service (addTask) | `~/.lutece-references/lutece-elk-plugin-elasticdata/src/java/**/service/DataSourceIncrementalService.java` |
| Complete DataSource (forms) | `~/.lutece-references/lutece-form-module-elasticdata-forms/src/java/**/FormsDataSource.java` |
| DataObject example (forms) | `~/.lutece-references/lutece-form-module-elasticdata-forms/src/java/**/FormResponseDataObject.java` |
| CDI event listener (forms) | `~/.lutece-references/lutece-form-module-elasticdata-forms/src/java/**/FormResponseIndexerEventListener.java` |
| Elastic HTTP client | `~/.lutece-references/lutece-elk-library-elastic/src/java/**/util/Elastic.java` |
| Default mappings | `~/.lutece-references/lutece-elk-plugin-elasticdata/src/java/**/service/DataSourceUtils.java` |
