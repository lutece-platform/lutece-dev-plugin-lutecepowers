# Cache Migration Patterns (v7 → v8)

v7 → v8 cache migration (EhCache 2.x → JCache/JSR-107). This file holds the before/after transformations only; the target shape (guards, key builders, CDI access, invalidation) is described once in the `lutece-cache` skill.

> **Reference-First Principle:** Before writing any cache service, **search `~/.lutece-references/` for existing `AbstractCacheableService` implementations** (e.g., `Grep AbstractCacheableService ~/.lutece-references/`). Reproduce the reference structure exactly.

## 1. API Replacement

Replace EhCache 2.x API with JCache (JSR-107) or `@LuteceCache` annotation:

- `net.sf.ehcache.Cache` → `javax.cache.Cache` or `Lutece107Cache`
- `new Element(key, value)` → `cache.put(key, value)`
- `cache.get(key).getObjectValue()` → `cache.get(key)`

## 2. Cache Injection

```java
@Inject
@LuteceCache(cacheName = "myCache", keyType = String.class, valueType = MyObject.class, enable = true)
private Lutece107Cache<String, MyObject> _cache;
```

## 3. Full Cache Service Migration

**Before (v7):**
```java
public class MyCacheService extends AbstractCacheableService implements EventRessourceListener {
    @Override
    public void initCache() {
        super.initCache();
        ResourceEventManager.register(this);
    }
    public void addedResource(ResourceEvent event) { handleEvent(event); }
    public void deletedResource(ResourceEvent event) { handleEvent(event); }
    public void updatedResource(ResourceEvent event) { handleEvent(event); }
}
```

**After (v8):**
```java
@ApplicationScoped
public class MyCacheService extends AbstractCacheableService<String, Object> {
    @PostConstruct
    public void init() {
        initCache(CACHE_NAME, String.class, Object.class);
    }

    public void processEvent(@Observes MyEvent event) {
        if (isCacheEnable()) { resetCache(); }
    }
}
```

Then apply the target shape from `lutece-cache` Step 1: override `put`/`get`/`remove` with `isCacheEnable() && isCacheAvailable()` guards (the inherited methods dereference `_cache`, which is `null` while the cache is disabled).

## 4. Cache Method Renames

| v7 (deprecated) | v8 |
|---|---|
| `putInCache(key, value)` | `put(key, value)` |
| `getFromCache(key)` | `get(key)` |
| `removeKey(key)` | `remove(key)` |

## 5. Cache Service Access

Delete any `getInstance()` on the cache service (`rules/service-layer.md`). Access patterns (`@Inject` in CDI beans, static field init in Home classes): `lutece-cache` Step 3.

## 6. AbstractCacheableService Type Parameters

Raw type `AbstractCacheableService` must be parameterized. The typed `initCache(String, Class<K>, Class<V>)` replaces the no-arg `initCache()`. Use `<String, Object>` as default when the cache stores heterogeneous values.

```java
// BEFORE
public class MyCacheService extends AbstractCacheableService
{
    @PostConstruct
    public void init( )
    {
        initCache( );
    }
}

// AFTER
@ApplicationScoped
public class MyCacheService extends AbstractCacheableService<String, Object>
{
    @PostConstruct
    public void init( )
    {
        initCache( CACHE_NAME, String.class, Object.class );
    }
}
```
