# Scalability v8 — verification checklist

## Static (code) — run `scan-scalability.sh`, then per-file `verify-file.sh`
- [ ] **No JVM-local coordination** of a contended resource (`ReentrantLock`, `synchronized`, lock `Map`) → replaced by the right cluster-safe primitive: **counter → atomic CAS UPDATE** (`SET remaining=remaining-? WHERE remaining>=?`); **`COUNT(*)` → DB distributed lock**. Don't lock by default.
- [ ] **CAS guard is inside the UPDATE's `WHERE`**, never a `SELECT`-then-`UPDATE` read-modify-write (TOCTOU race).
- [ ] **`CHECK` invariant on counter resources** (`remaining + taken = capacity`) as defense in depth — and the deploy target is **MariaDB ≥ 10.2.1 / MySQL ≥ 8.0.16** (else `CHECK` is silently ignored).
- [ ] **No `SELECT MAX(+1)`** ID generation → auto-increment/sequence or `UNIQUE` constraint.
- [ ] **No mutable static singleton** (`private static X _instance`, `getInstance()`) → `@ApplicationScoped` bean; `getInstance()` **removed** (callers migrated; no `@Deprecated`).
- [ ] **No static `CDI.current()` field init** outside Home facades and static utils → injection or lazy resolution.
- [ ] **Session/cache objects `Serializable`** (whole graph) + `serialVersionUID`; non-serializables `transient` + lazy reload; **no `@Inject` marked `transient`**.
- [ ] **Stateful `@SessionScoped`/`@ConversationScoped` bean** → whole field graph `Serializable` + a **passivation test** (round-trip `ObjectOutputStream`/`ObjectInputStream`, cf. forms `FormXPageSessionPassivationTest`); AND the cluster sets `writeContents="GET_AND_SET_ATTRIBUTES"` (see empirical) — a serializable graph alone does NOT replicate in-place mutations.
- [ ] **No `Future`/`Timer`/`Thread`/`Stream`/`Optional` in session**; resource "hold" materialised in DB (row + expiry, daemon sweep), not a `ScheduledFuture`.
- [ ] **No JVM-local cache `static Map`** → `AbstractCacheableService` (JSR-107), CDI-event invalidation.
- [ ] **No hardcoded config/path/URL** → MicroProfile property (`@ConfigProperty`), defaults in `META-INF/microprofile-config.properties`; shared resources on a shared volume, not `java.io.tmpdir`.
- [ ] **Container streams** (`response.getOutputStream()/getWriter()`) not closed by hand; `IOException` rethrown; guarded by `!isCommitted()`.
- [ ] **`ThreadLocal.remove()`** in `finally` (never `set(null)`).
- [ ] **Ordered registration** via `Instance` uses an explicit `priority`+sort (determinism).

## Empirical (cluster) — run `cluster-verify.sh` against the running cluster
- [ ] The 3 instances serve (HTTP 200).
- [ ] nginx round-robin reaches all 3 backends.
- [ ] Shared MariaDB; **single** Liquibase migration (migrator pattern, no race).
- [ ] **BOTH** Hazelcast rings formed: session (5701) **and** JCache cache (5703) — not just one.
- [ ] **`httpSessionCache writeContents="GET_AND_SET_ATTRIBUTES"`** in `server.xml` (the default `ONLY_SET_ATTRIBUTES` silently breaks `@SessionScoped` replication while admin auth still works).
- [ ] HTTP session replicated: authenticated session recognized on every node (no sticky) — **necessary but not sufficient** (admin auth replicates even under the broken default; this is the false-green trap).
- [ ] **Stateful flow proof (the decisive one)**: drive the plugin's real multi-step flow through the round-robin LB; confirm the state **survives a node switch** (log the upstream per step). This is what actually validates `@SessionScoped` replication.
- [ ] **Failover proof**: `docker kill` the node that served the mid-point of a stateful flow, then complete the flow → it finishes on a **survivor** and the result lands in the DB (proves the session lives in Hazelcast, not on the origin node). Peers log only "removing dead endpoint" warnings; the killed node rejoins the mesh on restart.
- [ ] If the plugin manages a contended resource: under **N concurrent** real operations on one resource (capacity M) → **exactly M succeed, never more**, counters never drift (verified in the DB). For a counter resource, the over-capacity attempts are rejected by the CAS guard (`SlotFull`-style) in the logs.

A fix is **done only when the empirical run is green** — with Hazelcast enabled (ehcache hides serialization bugs), reading the docker logs **before AND after** the functional test.
