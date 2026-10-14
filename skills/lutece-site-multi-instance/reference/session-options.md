# Sharing the session and the cache: the options

A Lutece site runs on several replicas when two things are shared between them: the **HTTP session** (OpenLiberty) and
the **Lutece cache** (JCache, read by the core through `lutece.cache.jcache.cachingprovider` and
`lutece.cache.jcache.config.uri`). The configuration of this skill, a Hazelcast member per pod for the session and a
Hazelcast client with a near cache for the Lutece cache, is one way to do it, and the only one tested with Lutece: two and
three replicas, node switch on every request, forced pod deletion and rolling restart under load (`verification.md`).

The other ways below are supported by OpenLiberty or by the JCache standard. They have not been run with Lutece: a site
that chooses one of them proves it with the checks of `verification.md` first.

## HTTP session

| Option | OpenLiberty feature | Notes |
|---|---|---|
| Hazelcast, embedded member (this skill) | `sessionCache-1.0` | No extra server. Tested. |
| Another JCache provider: Infinispan, Hazelcast client of a separate cluster, Redis through a JCache implementation (Redisson) | `sessionCache-1.0` | Same `httpSessionCache` element, `libraryRef` on the provider jars, `uri` on its configuration. Keep `writeContents="GET_AND_SET_ATTRIBUTES"`. |
| Relational database | `sessionDatabase-1.0` | Sessions in a table of a data source: no cache server, more database load; `writeFrequency` and `writeContents` decide what is written and when. |

Links:
- Distributed session caching: https://openliberty.io/docs/latest/distributed-session-caching.html
- `sessionCache-1.0`: https://openliberty.io/docs/latest/reference/feature/sessionCache-1.0.html and
  `httpSessionCache`: https://openliberty.io/docs/latest/reference/config/httpSessionCache.html
- Infinispan as JCache provider: https://openliberty.io/docs/latest/configuring-infinispan-support.html
- Sessions in a database, `sessionDatabase-1.0`: https://openliberty.io/docs/latest/reference/feature/sessionDatabase-1.0.html,
  `httpSessionDatabase`: https://openliberty.io/docs/latest/reference/config/httpSessionDatabase.html, the session
  table: https://openliberty.io/docs/latest/create-session-table.html
- Distributed caching with JCache in OpenLiberty: https://openliberty.io/docs/latest/distributed-caching-jcache.html,
  `cacheManager`: https://openliberty.io/docs/latest/reference/config/cacheManager.html
- Redis through Redisson: JCache implementation https://redisson.org/docs/cache-api-implementations/, web sessions
  https://redisson.org/docs/web-session-management/
- Infinispan JCache: https://infinispan.org/docs/stable/titles/jcache/jcache.html

## Lutece cache

Whatever the session store, the Lutece cache must be shared too, or disabled: with a cache local to each pod, a change made
on one replica stays invisible on the others (measured: a site property changed on one pod was still the old value on the
other three seconds later). Any JCache provider fits: set `lutece.cache.jcache.cachingprovider` to its `CachingProvider`
class and `lutece.cache.jcache.config.uri` to its configuration (as `templates/cluster.xml` does for the Hazelcast client).
With sessions in a database, this is the only use of a cache server.

## What stays the same

Every other rule of the skill does not depend on the store: Quartz in cluster mode, Liquibase from one replica,
`plugins.dat`, the shared Forms index, `persistTimeout`, `remoteIp`, the bounded thread and connection pools, the
Kubernetes lifecycle and probes. `site_check.py` reports SI60 as INFO for sessions in a database and skips the Hazelcast
checks (SI61, SI63, SI64); SI62 (shared Lutece cache) applies to every option.
