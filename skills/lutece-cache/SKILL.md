---
name: lutece-cache
description: "Use when adding, fixing or reviewing a cache in a Lutece 8 plugin: AbstractCacheableService, CDI initialization, cache keys, invalidation through CDI events. Triggers on 'cache', 'cacheable', 'invalidate', 'CacheService'."
---

# Lutece 8 Cache Implementation

> Before implementing cache, consult `~/.lutece-references/lutece-form-plugin-forms/` — specifically `FormsCacheService.java`.

## Architecture Overview

```
AbstractCacheableService<K, V>  (lutece-core, JSR-107 JCache)
    ↑ extends
MyCacheService (@ApplicationScoped, @PostConstruct initCache)
    ↓ used by
Home / Service (put, get, remove, resetCache)
    ↓ invalidated by
CDI Events (@Observes)
```

## Step 1 — Cache Service Class

The JCache methods inherited from `AbstractCacheableService` (`get()`, `put()`, `remove()`, `getAll()`,
`putIfAbsent()`, …) are safe on a disabled cache, the default state in the datastore: a read misses, a write is
ignored. Only `invoke()` and `invokeAll()` throw `IllegalStateException` then. `isCacheEnable( )` tells whether the
cache is active; there is no `isCacheAvailable( )` method, do not write one, it does not compile.

```java
import fr.paris.lutece.portal.service.cache.AbstractCacheableService;
import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;

@ApplicationScoped
public class EntityCacheService extends AbstractCacheableService<String, Object>
{
    private static final String CACHE_NAME = "myplugin.entityCacheService";

    @PostConstruct
    public void init( )
    {
        initCache( CACHE_NAME, String.class, Object.class );
    }

    @Override
    public String getName( )
    {
        return CACHE_NAME;
    }
}
```

**Rules:**
- `@ApplicationScoped` — singleton CDI bean, one instance per application
- `@PostConstruct` calls `initCache( name, keyClass, valueClass )` — registers the cache with `CacheService`
- Cache name convention: `pluginName.entityCacheService`
- Generic types: `<String, Object>` is the standard — key is always String, value is the cached object
- Do not override `put`/`get`/`remove` to guard them: the core already does

## Step 2 — Cache Key Builders

Define static methods for consistent key generation:

```java
@ApplicationScoped
public class EntityCacheService extends AbstractCacheableService<String, Object>
{
    private static final String KEY_PREFIX = "myplugin.entity.";

    // Key for a single entity
    public static String getEntityCacheKey( int nIdEntity )
    {
        return KEY_PREFIX + nIdEntity;
    }

    // Key for the full list
    public static String getListCacheKey( )
    {
        return KEY_PREFIX + "list";
    }

    // Key with parameters (e.g., filtered list)
    public static String getFilteredCacheKey( int nIdCategory, int nPage )
    {
        return KEY_PREFIX + "category." + nIdCategory + ".page." + nPage;
    }

    // ...
}
```

## Step 3 — Usage in Home or Service

### Access pattern: `@Inject` (CDI-managed beans) vs `CDI.current().select()` (static contexts)

| Context | Pattern | Example |
|---------|---------|---------|
| CDI-managed bean (`@ApplicationScoped`, `@RequestScoped`, etc.) | `@Inject` | Service class |
| Static context (Home class, static utility) | `CDI.current().select()` direct field init | Home class |

No `getInstance()` on the cache service (`rules/service-layer.md`).

### Pattern A — `@Inject` in a CDI-managed Service (preferred)

```java
@ApplicationScoped
public class EntityService
{
    @Inject
    private EntityCacheService _cacheService;

    public Entity findByPrimaryKey( int nId )
    {
        String strCacheKey = EntityCacheService.getEntityCacheKey( nId );
        Entity entity = (Entity) _cacheService.get( strCacheKey );

        if ( entity == null )
        {
            entity = EntityHome.findByPrimaryKey( nId );

            if ( entity != null )
            {
                _cacheService.put( strCacheKey, entity );
            }
        }

        return entity;
    }

    public Entity update( Entity entity )
    {
        EntityHome.update( entity );

        _cacheService.remove( EntityCacheService.getEntityCacheKey( entity.getId( ) ) );
        _cacheService.remove( EntityCacheService.getListCacheKey( ) );

        return entity;
    }

    public void remove( int nId )
    {
        EntityHome.remove( nId );

        _cacheService.remove( EntityCacheService.getEntityCacheKey( nId ) );
        _cacheService.remove( EntityCacheService.getListCacheKey( ) );
    }
}
```

### Pattern B — `CDI.current().select()` in a static Home class

Use **direct field initialization** — no lazy-init getters. This is the pattern used by all Home classes in lutece-core (`RoleHome`, `PageHome`, `FileHome`) and in the Forms plugin (`FormHome`, `StepHome`). The CDI container is fully initialized before plugin classes are loaded.

```java
import jakarta.enterprise.inject.spi.CDI;

public class EntityHome
{
    private static IEntityDAO _dao = CDI.current( ).select( IEntityDAO.class ).get( );
    private static EntityCacheService _cacheService = CDI.current( ).select( EntityCacheService.class ).get( );
    private static final Plugin _plugin = PluginService.getPlugin( "pluginname" );

    private EntityHome( )
    {
    }

    public static Entity findByPrimaryKey( int nId )
    {
        String strCacheKey = EntityCacheService.getEntityCacheKey( nId );
        Entity entity = (Entity) _cacheService.get( strCacheKey );

        if ( entity == null )
        {
            entity = _dao.load( nId, _plugin );
            if ( entity != null )
            {
                _cacheService.put( strCacheKey, entity );
            }
        }
        return entity;
    }
}
```

## Step 4 — Cache Invalidation via CDI Events

Observe domain events to automatically invalidate cache:

```java
import fr.paris.lutece.portal.business.event.ResourceEvent;
import jakarta.enterprise.event.Observes;

@ApplicationScoped
public class EntityCacheService extends AbstractCacheableService<String, Object>
{
    // ...

    public void onResourceEvent( @Observes ResourceEvent event )
    {
        if ( isCacheEnable( ) && "MYPLUGIN_ENTITY".equals( event.getTypeResource( ) ) )
        {
            resetCache( );
        }
    }
}
```

For finer-grained invalidation (remove specific key instead of full reset):

```java
public void onResourceEvent( @Observes ResourceEvent event )
{
    if ( isCacheEnable( ) && "MYPLUGIN_ENTITY".equals( event.getTypeResource( ) ) )
    {
        String strId = event.getIdResource( );

        if ( strId != null )
        {
            remove( EntityCacheService.getEntityCacheKey( Integer.parseInt( strId ) ) );
            remove( EntityCacheService.getListCacheKey( ) );
        }
        else
        {
            resetCache( );
        }
    }
}
```

## Cache Operations Reference

| Method | Usage |
|--------|-------|
| `put( key, value )` | Add or update an entry |
| `get( key )` | Retrieve (returns `null` on miss) |
| `remove( key )` | Delete a single entry |
| `resetCache( )` | Clear all entries |
| `enableCache( boolean )` | Toggle cache on/off |
| `isCacheEnable( )` | Check if cache is active |
| `getCacheSize( )` | Current entry count |
| `getKeys( )` | List all keys |
| `containsKey( key )` | Check key existence |

## Optional — Prevent Global Reset

If your cache should survive when an admin clicks "Reset all caches":

```java
@Override
public boolean isPreventGlobalReset( )
{
    return true;
}
```

Use sparingly — only for caches that are expensive to rebuild (e.g., configuration caches).

## Configuration (properties)

Cache behavior can be tuned via `caches.properties` or datastore:

```properties
# Default settings (apply to all caches without specific config)
lutece.cache.default.maxElementsInMemory=1000
lutece.cache.default.eternal=false
lutece.cache.default.timeToIdleSeconds=1000
lutece.cache.default.timeToLiveSeconds=1000

# Per-cache override
core.cache.status.myplugin.entityCacheService.eternal=true
core.cache.status.myplugin.entityCacheService.enabled=1
```

Cache enabled/disabled state is persisted in the **datastore database** with key: `core.cache.status.{cacheName}.enabled`

## File Checklist

| File | What to add |
|------|-------------|
| `EntityCacheService.java` | New class in `service/cache/`, `@ApplicationScoped`, extends `AbstractCacheableService`, key builders |
| `EntityService.java` | `@Inject EntityCacheService`, cache-through logic (get → miss → load → put) |
| `beans.xml` | Already present (required for CDI) |

No changes needed in `plugin.xml` or `messages.properties` — cache is infrastructure, not UI.

## Reference Sources

| Need | File to consult |
|------|----------------|
| CDI cache service (v8 pattern) | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/FormsCacheService.java` |
| Core AbstractCacheableService | `~/.lutece-references/lutece-core/src/java/**/service/cache/AbstractCacheableService.java` |
| Core CacheService (static facade) | `~/.lutece-references/lutece-core/src/java/**/service/cache/CacheService.java` |
| Cache manager (JSR-107) | `~/.lutece-references/lutece-core/src/java/**/service/cache/Lutece107CacheManager.java` |
| Cache configuration | `~/.lutece-references/lutece-core/src/java/**/service/cache/CacheConfigUtil.java` |
