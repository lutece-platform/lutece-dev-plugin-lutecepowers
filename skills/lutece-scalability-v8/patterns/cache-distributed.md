# Pattern — Distributed cache (JSR-107 / Hazelcast)

> Reference: lutece-core `Lutece107CacheManager`, `CacheConfigUtil`, `AbstractCacheableService`. The Lutece cache uses the standard **JSR‑107 (JCache)** API; provider is configurable: ehcache (local, default) → **Hazelcast** (distributed) **without code changes**, provided the JCache contract is respected.

## Anti-patterns (break in a cluster)
- **`synchronized(key)`** around the cache: a JVM monitor does not cross the JVM boundary → use atomic JCache ops (`putIfAbsent`, `invoke`).
- **`EntryProcessor` capturing request context** (`HttpServletRequest`, lambda, ThreadLocal) → non-serializable, shipped to the key-owner node → error. Replace with `get()` + local generation + `putIfAbsent()`.
- **Anonymous Listener/Factory** → non-serializable. Use **named static classes + `Serializable`**.
- **Static Map "beside" the cache** (parallel JVM-local state) → diverges across nodes. Remove it; everything goes through the cache.

## Target pattern
- Extend `AbstractCacheableService`; **keys AND values `Serializable`**; retrieve via `getKeys()` (don't store a catch-all "all" entry).
- **Invalidation via CDI events** (cf. the `lutece-cache` skill) to propagate eviction to all nodes.
- Provider chosen by a MicroProfile property: `lutece.cache.jcache.cachingprovider` (+ `lutece.cache.jcache.config.uri`). Hazelcast is **not** embedded in core (dependency + config to add — see the harness).

## Golden rule
**Test with Hazelcast enabled**: ehcache (local) hides serialization bugs. The skill harness already deploys Hazelcast → cache `NotSerializableException`s surface during the test.
