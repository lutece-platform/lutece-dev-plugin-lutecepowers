# Pattern — Distributed cache (JSR-107 / Hazelcast)

> Reference: lutece-core `Lutece107CacheManager`, `CacheConfigUtil`, `AbstractCacheableService`. The Lutece cache uses the standard **JSR‑107 (JCache)** API; provider is configurable: ehcache (local, default) → **Hazelcast** (distributed) **without code changes**, provided the JCache contract is respected. How a cache service is written: `lutece-cache` skill. This file holds what breaks once the cache is shared by several instances.

## Anti-patterns (break in a cluster)
- **`synchronized(key)`** around the cache: a JVM monitor does not cross the JVM boundary → use atomic JCache ops (`putIfAbsent`, `invoke`).
- **`EntryProcessor` capturing request context** (`HttpServletRequest`, lambda, ThreadLocal) → non-serializable, shipped to the key-owner node → error. Replace with `get()` + local generation + `putIfAbsent()`.
- **Anonymous Listener/Factory** → non-serializable. Use **named static classes + `Serializable`**.
- **Static Map "beside" the cache** (parallel JVM-local state) → diverges across nodes. Remove it; everything goes through the cache.

## Cache contract (each one observed with Hazelcast, 2 to 3 replicas)
- **Never modify an object read from the cache; return a copy of a cached collection.** With the Hazelcast near cache in `OBJECT` format every request of a pod gets the same instance (Ehcache copies on read): a caller that sorts or completes a cached list changes it for the concurrent requests. Seen: Forms multiview, two displays sorting the same list → `ConcurrentModificationException`; a menu tree completed and put back on every page, +368 bytes per page. Copy in the Home (copy constructor of each element, as `FormHome.findByPrimaryKey` and `getFormList` do) and build the value once, on a miss.
- **Values `Serializable`, whole graph** (`serialVersionUID`): Ehcache with its default copier and Hazelcast both serialize. Seen: a breadcrumb configuration object put in the Forms cache, 500 on every form step under both providers.
- **Catch the provider failure** in the cache service: `put`, `get`, `remove` catch `RuntimeException` (not only `CacheException`), log the key and the value class, and behave as a miss. A value the provider cannot serialize must not turn a page into a 500.
- **Never put `null`**: JCache refuses it (`NullPointerException`). Remove the key instead.
- **Typed cache**: `initCache( name, String.class, V.class )`, or, for a cache re-created by the back office toggle (`enableCache( true )` re-creates it from the `configuration` field), set `configuration = new MutableConfiguration<K, V>( ).setTypes( … )` in the `@PostConstruct`. An untyped cache keeps every value stored by value: a lutece-core whose cache layer stores immutable values (`String`, numbers) by reference does it only for a typed cache (measured: 128 µs per read of an upload script against 0.7 µs).
- **The key carries every input of the value**: front office / back office, locale, parameters. Seen: an upload script cached by field name only, built first by the back office, then served to front office users with the admin servlet URL.
- **No iteration of the cache on a hot path**: `getKeys()`, `getCacheSize()` and `iterator()` cross the network for every entry under Hazelcast. Keep an index entry (the list of ids) read by key, or one key for the "all" value.
- **Invalidate on every event that changes the source**, through CDI events (`@Observes` the core or plugin event): `remove( key )` when the event names the entry, `resetCache( )` otherwise. Never reset the caches of other plugins for a local change. Seen: a page change not seen by the menus; creating a page emptying every plugin cache.
- **Group the resets of a transaction**: an import or a copy writes hundreds of objects; a `resetCache( )` per write empties the shared cache hundreds of times and lets concurrent requests cache data read before the commit. Register one reset with `TransactionSynchronizationRegistry.registerInterposedSynchronization` and run it in `afterCompletion` (Forms `FormsCacheService`).
- **Re-register what the cache needs at each creation**: a listener added in `@PostConstruct` is lost when the back office disables then enables the cache (a new cache is created). Seen: the Quartz daemon screen no longer showing the runs of the other replicas. Register it in the method that creates the cache.
- **A cache disabled on one instance still forwards its removals**: under Hazelcast another instance reads the shared cache. A service overriding `remove` does not test `isCacheEnable( )` before forwarding.
- **Lifetime and size are not portable**: `caches.properties` reaches Ehcache directly; under Hazelcast the lifetime needs a lutece-core that passes it as the JCache expiry and the size a provider library (`lutece-site-multi-instance`). Code must not rely on an entry being evicted to see a change: invalidate it.

## Target pattern
- Extend `AbstractCacheableService`; **keys AND values `Serializable`**; typed cache; values never modified after `put`.
- **Invalidation via CDI events** (cf. the `lutece-cache` skill) to propagate eviction to all nodes.
- Provider chosen by a MicroProfile property: `lutece.cache.jcache.cachingprovider` (+ `lutece.cache.jcache.config.uri`). Hazelcast is **not** embedded in core (dependency + config to add — see the harness).

## Golden rule
**Test with Hazelcast enabled**: ehcache (local) hides serialization bugs. The skill harness already deploys Hazelcast → cache `NotSerializableException`s surface during the test. Its member-only JCache copies on every read, like Ehcache: a modified cached value shows only with a client near cache in `OBJECT` format (the site setup of `lutece-site-multi-instance`), under two concurrent requests on one node. Review the callers of each cached read for it rather than waiting for the harness to show it.
