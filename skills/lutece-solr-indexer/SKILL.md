---
name: lutece-solr-indexer
description: "Use when creating or modifying a Solr search module for Lutece 8: SolrIndexer interface, CDI auto-discovery, SolrItem dynamic fields, batch indexing, incremental updates through CDI events. Triggers on 'Solr', 'search module', 'SolrIndexer'."
---

# Lutece 8 Solr Indexer Module

> Before implementing a Solr indexer, consult `~/.lutece-references/lutece-search-module-forms-solr/` — the reference implementation. The main plugin is at `~/.lutece-references/lutece-search-plugin-solr/`.

## Architecture Overview

```
plugin-solr (provides framework — already deployed)
    ↓ auto-discovers via CDI
module-myentity-solr (@ApplicationScoped SolrIndexer)
    ↓ builds
SolrItem (core fields + dynamic fields)
    ↓ writes via
SolrIndexerService.write(Collection<SolrItem>)
    ↓ committed to
Solr Server (HTTP/2 client)

Incremental path:
Entity CRUD → CDI ResourceEvent
    ↓ observed by
SolrEventRessourceListener (plugin-solr, queues SolrIndexerAction in DB)
    ↓ processed by
SolrIndexerDaemon → calls indexer.getDocuments(id)
```

A module provides a `SolrIndexer` implementation. The plugin-solr framework handles server communication, daemon scheduling, and action queue management.

**CDI auto-discovery** — any `@ApplicationScoped` class implementing `SolrIndexer` is automatically registered:
```java
// Inside SolrIndexerService (plugin-solr)
CDI.current( ).select( SolrIndexer.class ).stream( ).toList( );
```

## Step 1 — Maven Module Setup

```xml
<parent>
    <groupId>fr.paris.lutece.tools</groupId>
    <artifactId>lutece-global-pom</artifactId>
    <version>LATEST_RELEASED_8_X</version>
</parent>

<artifactId>module-myentity-solr</artifactId>
<packaging>lutece-plugin</packaging>

<dependencies>
    <dependency>
        <groupId>fr.paris.lutece.plugins</groupId>
        <artifactId>plugin-solr</artifactId>
        <version>[5.0.0,)</version>
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

Replace `LATEST_RELEASED_8_X` with the latest released `lutece-global-pom` 8.x (check the Lutece Maven repository, never hardcode a guess). The module is never its own parent (reference: `lutece-search-module-forms-solr/pom.xml`).

## Step 2 — SolrIndexer Implementation

```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.enterprise.inject.Instance;

import fr.paris.lutece.plugins.search.solr.indexer.SolrIndexer;
import fr.paris.lutece.plugins.search.solr.indexer.SolrItem;
import fr.paris.lutece.plugins.search.solr.business.field.Field;
import fr.paris.lutece.plugins.search.solr.service.SolrIndexerService;
import fr.paris.lutece.portal.service.util.AppPropertiesService;

@ApplicationScoped
public class SolrMyEntityIndexer implements SolrIndexer
{
    private static final String PROPERTY_INDEXER_ENABLE = "module-myentity-solr.indexer.enable";
    private static final String PROPERTY_NAME = "module-myentity-solr.indexer.name";
    private static final String PROPERTY_DESCRIPTION = "module-myentity-solr.indexer.description";
    private static final String PROPERTY_VERSION = "module-myentity-solr.indexer.version";
    private static final String SHORT_NAME = "mye";
    private static final int BATCH_SIZE = 100;

    public static final String RESOURCE_TYPE = "MYENTITY_ENTITY";

    // Use Instance<T> for optional dependencies (e.g., workflow)
    @Inject
    private Instance<IStateService> _stateServiceInstance;

    // --- Full reindex (called by admin "Index All") ---
    @Override
    public List<String> indexDocuments( )
    {
        List<Integer> listIds = MyEntityHome.findAllIds( );
        List<String> listErrors = new ArrayList<>( );

        for ( int i = 0; i < listIds.size( ); i += BATCH_SIZE )
        {
            List<Integer> batch = listIds.subList( i,
                    Math.min( i + BATCH_SIZE, listIds.size( ) ) );

            List<MyEntity> listEntities = MyEntityHome.findByPrimaryKeyList( batch );

            try
            {
                Collection<SolrItem> items = listEntities.stream( )
                        .map( this::buildSolrItem )
                        .collect( Collectors.toList( ) );

                SolrIndexerService.write( items );
            }
            catch ( Exception e )
            {
                listErrors.add( e.getMessage( ) );
            }
        }

        return listErrors;
    }

    // --- Incremental (called by daemon for queued actions) ---
    @Override
    public List<SolrItem> getDocuments( String strIdDocument )
    {
        MyEntity entity = MyEntityHome.findByPrimaryKey(
                Integer.parseInt( strIdDocument ) );

        if ( entity == null )
        {
            return Collections.emptyList( );
        }

        return List.of( buildSolrItem( entity ) );
    }

    // --- Resource types this indexer handles ---
    @Override
    public List<String> getResourcesName( )
    {
        return List.of( RESOURCE_TYPE );
    }

    // --- UID generation ---
    @Override
    public String getResourceUid( String strResourceId, String strResourceType )
    {
        if ( RESOURCE_TYPE.equals( strResourceType ) )
        {
            return strResourceId + "_" + SHORT_NAME;
        }
        return null;
    }

    // --- Metadata ---
    @Override
    public String getName( )
    {
        return AppPropertiesService.getProperty( PROPERTY_NAME );
    }

    @Override
    public String getVersion( )
    {
        return AppPropertiesService.getProperty( PROPERTY_VERSION );
    }

    @Override
    public String getDescription( )
    {
        return AppPropertiesService.getProperty( PROPERTY_DESCRIPTION );
    }

    @Override
    public boolean isEnable( )
    {
        return AppPropertiesService.getPropertyBoolean( PROPERTY_INDEXER_ENABLE, false );
    }

    @Override
    public List<Field> getAdditionalFields( )
    {
        return Collections.emptyList( );
    }

    // --- SolrItem builder (see Step 3) ---
    private SolrItem buildSolrItem( MyEntity entity )
    {
        // See Step 3
    }
}
```

## Step 3 — Building SolrItems

```java
private SolrItem buildSolrItem( MyEntity entity )
{
    SolrItem item = new SolrItem( );

    // Core fields
    item.setUid( entity.getId( ) + "_" + SHORT_NAME );
    item.setTitle( entity.getTitle( ) );
    item.setType( RESOURCE_TYPE );
    item.setSummary( entity.getDescription( ) );
    item.setContent( entity.getTitle( ) + " " + entity.getDescription( ) );
    item.setUrl( "jsp/site/Portal.jsp?page=myentity&id=" + entity.getId( ) );
    item.setSite( SolrIndexerService.getWebAppName( ) );
    item.setRole( "none" );

    if ( entity.getDateCreation( ) != null )
    {
        item.setDate( entity.getDateCreation( ) );
    }

    // Dynamic fields (see table below for suffixes)
    item.addDynamicField( "entity_status", entity.getStatus( ) );              // → entity_status_text
    item.addDynamicFieldNotAnalysed( "entity_code", entity.getCode( ) );       // → entity_code_string
    item.addDynamicField( "entity_count", (long) entity.getCount( ) );         // → entity_count_long
    item.addDynamicField( "entity_update", entity.getDateUpdate( ) );          // → entity_update_date
    item.addDynamicField( "entity_tags", entity.getTags( ) );                  // → entity_tags_list

    // Geolocation (address, longitude, latitude, docType)
    // item.addDynamicFieldGeoloc( "entity_location",
    //         entity.getAddress( ), entity.getLon( ), entity.getLat( ), "MyEntity" );

    return item;
}
```

## SolrItem Dynamic Fields Reference

| Method | Suffix | Solr type | Use for |
|--------|--------|-----------|---------|
| `addDynamicField(name, String)` | `_text` | Analyzed text | Full-text searchable strings |
| `addDynamicFieldNotAnalysed(name, String)` | `_string` | Keyword | Exact match, facets, filters |
| `addDynamicField(name, Long)` | `_long` | Long | Numbers, counts |
| `addDynamicField(name, Date)` | `_date` | Date | Dates, timestamps |
| `addDynamicField(name, Float)` | `_float` | Float | Decimal numbers |
| `addDynamicField(name, List<String>)` | `_list` | Multi-valued | Checkboxes, tags |
| `addDynamicFieldListDate(name, List<Date>)` | `_list_date` | Multi-valued date | Multiple dates |
| `addDynamicFieldGeoloc(name, addr, lon, lat, type)` | `_geoloc` + `_geojson` + `_address_text` | Geo | Map display, proximity search |

## Step 4 — CDI Event Listener (Incremental Updates)

The plugin-solr framework already has `SolrEventRessourceListener` that observes `ResourceEvent` and queues `SolrIndexerAction`. You just need to fire the right events from your service layer.

Fire `ResourceEvent` from your Service when entities are created/updated/deleted. The `SolrEventRessourceListener` uses `@Observes @Type(EventAction.X)`, so you must select the qualifier before firing synchronously:

```java
import fr.paris.lutece.portal.business.event.ResourceEvent;
import fr.paris.lutece.portal.service.event.EventAction;
import fr.paris.lutece.portal.service.event.Type.TypeQualifier;

@ApplicationScoped
public class MyEntityService
{
    @Inject
    private Event<ResourceEvent> _resourceEvent;

    public MyEntity create( MyEntity entity )
    {
        MyEntityHome.create( entity );

        ResourceEvent event = new ResourceEvent( );
        event.setIdResource( String.valueOf( entity.getId( ) ) );
        event.setTypeResource( SolrMyEntityIndexer.RESOURCE_TYPE );
        _resourceEvent.select( new TypeQualifier( EventAction.CREATE ) ).fire( event );

        return entity;
    }

    public MyEntity update( MyEntity entity )
    {
        MyEntityHome.update( entity );

        ResourceEvent event = new ResourceEvent( );
        event.setIdResource( String.valueOf( entity.getId( ) ) );
        event.setTypeResource( SolrMyEntityIndexer.RESOURCE_TYPE );
        _resourceEvent.select( new TypeQualifier( EventAction.UPDATE ) ).fire( event );

        return entity;
    }

    public void remove( int nIdEntity )
    {
        MyEntityHome.remove( nIdEntity );

        ResourceEvent event = new ResourceEvent( );
        event.setIdResource( String.valueOf( nIdEntity ) );
        event.setTypeResource( SolrMyEntityIndexer.RESOURCE_TYPE );
        _resourceEvent.select( new TypeQualifier( EventAction.REMOVE ) ).fire( event );
    }
}
```

The `SolrEventRessourceListener` in plugin-solr observes these events and queues `SolrIndexerAction` records. The `SolrIndexerDaemon` processes them by calling your indexer's `getDocuments(strIdDocument)`.

## Step 5 — Plugin Class (Resource Type Registration)

If your module supports multiple resource subtypes (e.g., one per form), register them dynamically:

```java
public class MyEntitySolrPlugin extends PluginDefaultImplementation
{
    @Override
    public void init( )
    {
        super.init( );

        // Static registration (single resource type)
        // Nothing needed — getResourcesName() handles it

        // Dynamic registration (multiple subtypes)
        List<String> listResourceTypes = new ArrayList<>( );
        listResourceTypes.add( SolrMyEntityIndexer.RESOURCE_TYPE );
        // Add per-entity subtypes if needed
        SolrMyEntityIndexer.initListResourceName( listResourceTypes );
    }
}
```

Most modules don't need this — `getResourcesName()` returning a static list is sufficient. Only use the Plugin `init()` pattern when resource types are dynamic (like forms-solr, which creates one type per form).

## Step 6 — Configuration Properties

```properties
# module-myentity-solr.properties

# Enable/disable this indexer
module-myentity-solr.indexer.enable=true

# Display metadata
module-myentity-solr.indexer.name=MyEntity Indexer
module-myentity-solr.indexer.description=Indexes MyEntity documents into Solr
module-myentity-solr.indexer.version=1.0.0

# Batch size for full reindex (optional, default 100)
module-myentity-solr.indexer.batchSize=100
```

The Solr server connection is configured at the plugin-solr level (not in your module):
```properties
# Already in plugin-solr config (do NOT duplicate)
solr.server.address=http://localhost:8983/solr/
```

## Step 7 — plugin.xml

```xml
<plug-in>
    <name>myentity-solr</name>
    <class>fr.paris.lutece.plugins.myentity.modules.solr.service.MyEntitySolrPlugin</class>
    <version>1.0.0-SNAPSHOT</version>
    <description>Solr indexer for MyEntity plugin</description>
    <core-version-dependency>
        <min-core-version>8.0.0</min-core-version>
    </core-version-dependency>
    <db-pool-required>0</db-pool-required>
</plug-in>
```

No daemons or admin features needed — the plugin-solr framework provides them.

## ISolrItemExternalFieldProvider (Advanced)

Add cross-cutting fields to all SolrItems before indexing (e.g., add workflow state to items from other indexers):

```java
@ApplicationScoped
public class MyFieldProvider implements ISolrItemExternalFieldProvider
{
    public void provideFields( Collection<SolrItem> solrItems )
    {
        for ( SolrItem item : solrItems )
        {
            // Add extra fields to items matching your type
            if ( "MYENTITY_ENTITY".equals( item.getType( ) ) )
            {
                item.addDynamicFieldNotAnalysed( "extra_field", "value" );
            }
        }
    }
}
```

These providers are auto-discovered via CDI and called by `SolrIndexerService` before writing items.

## File Checklist

| File | What to create |
|------|----------------|
| `pom.xml` | Maven module with plugin-solr + plugin-myentity dependencies |
| `SolrMyEntityIndexer.java` | `@ApplicationScoped` implementing `SolrIndexer` |
| `MyEntitySolrPlugin.java` | Plugin class (only if dynamic resource types needed) |
| `module-myentity-solr.properties` | Indexer name, description, enable flag |
| `WEB-INF/plugins/myentity-solr.xml` | plugin.xml descriptor |
| `webapp/WEB-INF/classes/META-INF/beans.xml` | CDI descriptor (empty `<beans>` tag) |

No daemon, no DAO, no SQL table needed — plugin-solr provides all infrastructure.

## Reference Sources

| Need | File to consult |
|------|----------------|
| SolrIndexer interface (9 methods) | `~/.lutece-references/lutece-search-plugin-solr/src/java/**/indexer/SolrIndexer.java` |
| SolrItem API (dynamic fields) | `~/.lutece-references/lutece-search-plugin-solr/src/java/**/indexer/SolrItem.java` |
| SolrIndexerService (write, commit) | `~/.lutece-references/lutece-search-plugin-solr/src/java/**/service/SolrIndexerService.java` |
| CDI event listener (plugin-solr) | `~/.lutece-references/lutece-search-plugin-solr/src/java/**/indexer/SolrEventRessourceListener.java` |
| Complete indexer (forms-solr) | `~/.lutece-references/lutece-search-module-forms-solr/src/java/**/SolrFormsIndexer.java` |
| Plugin init (forms-solr) | `~/.lutece-references/lutece-search-module-forms-solr/src/java/**/FormsSolrPlugin.java` |
| External field provider | `~/.lutece-references/lutece-search-plugin-solr/src/java/**/indexer/ISolrItemExternalFieldProvider.java` |
