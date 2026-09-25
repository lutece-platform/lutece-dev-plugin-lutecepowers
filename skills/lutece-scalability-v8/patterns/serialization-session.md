# Pattern — Serialization (session & cache) + session state

> As soon as HTTP session and cache go through Hazelcast (replication/passivation), **every shared object is serialised**. A single non-serializable field in the graph → `NotSerializableException`. Reference: lutece-core `LuteceUser` (`transient` + lazy getter) and `AdminUser`, both `Serializable` for `sessionCache`; forms `FormXPageSessionPassivationTest` (passivation guard).

## Serialization rules
1. **`implements Serializable` + `serialVersionUID`** on every object put in the **session** or the **distributed cache**, cascading over the **whole** transitive graph.
2. **`transient` + lazy re-resolution** for an indispensable non-serializable field (service, `Locale`, …): re-resolved after deserialization via `CDI.current()`/a singleton, with a String key for consistency (cf. `LuteceUser._luteceAuthenticationService`).
3. **`SerializableFunction`** (`fr.paris.lutece.util.function`, not `Function`) for a stored lambda (e.g. the `IPager.populateModels` delegate) — a raw lambda is not `Serializable`.
4. **No `Optional`, `HttpServletRequest/Response`, `Future`/`Timer`/`Thread`/`Stream`** in session/cache. Unwrap them or mark `transient`.
5. **NEVER mark an injected CDI proxy (`@Inject`) `transient`**: a normal-scoped proxy is already `Serializable` and re-injects itself; `transient` nulls it on wake-up.
6. **Reduce scope**: `@SessionScoped` → `@RequestScoped` + reload from Home/DAO is often the best fix.

## Session state (what may / may not go in the session)
- **Bound it**: store only the strict minimum (an id, a light DTO), no large graphs.
- All session state must be `Serializable` → **add a passivation test** (round-trip `ObjectOutputStream`/`ObjectInputStream`) that breaks the build if a non-serializable field enters the session (cf. `FormXPageSessionPassivationTest`).
- **Never** identify a session by `session.getId()`; pass the `HttpSession` object.
- **Clean** the session on logout / tunnel init; validate consistency (the object in session matches the requested resource, cf. `isFormSessionValid`).
- A **resource "hold"** (provisional reservation) must NOT rely on a `ScheduledFuture`/`Timer` in the session (non-serializable, lost on restart, not distributed) → materialise it in the **database** (row with expiry) released by a daemon taking a **distributed lock**.

## Liberty `sessionCache` config — the silent gotcha (verify with real cluster)
A perfectly `Serializable` graph is **necessary but not sufficient**. Open Liberty's `<httpSessionCache>`
defaults to **`writeContents="ONLY_SET_ATTRIBUTES"`**: only attributes (re)written via `setAttribute`
are pushed to the distributed store at end of request. But a CDI **`@SessionScoped`** bean is mutated
**in place** by Weld (it sets its field, e.g. `_wizardState = ...`, without re-calling `setAttribute`
on the session). So with the default, those mutations stay **node-local** and are **never replicated** —
on a node switch (round-robin, failover) the bean is seen **empty** and any stateful wizard breaks
("session lost" / state reset), even though the cluster, the serialization and the session id are all fine.
- **Fix**: `<httpSessionCache cacheManagerRef="..." writeContents="GET_AND_SET_ATTRIBUTES"/>` — writes back
  any attribute *retrieved* via `getAttribute` (which Weld does each request), so the bean's full state replicates.
- **Why it's easy to miss**: plain `setAttribute` values (admin/`LuteceUser` auth, simple flags) replicate
  *either way*, so login survives node switching and the cluster looks healthy — only the stateful CDI flow fails.
- **Detect it**: a single empirical check beats any code review — drive a multi-step flow through the
  round-robin LB and confirm each step's server differs (log the upstream) yet the state survives. If step N
  returns "session lost" while a different node served step N-1, it's this. Ref: Open Liberty `httpSessionCache`
  `writeContents` (`ONLY_SET_ATTRIBUTES` | `GET_AND_SET_ATTRIBUTES` | `ALL_SESSION_ATTRIBUTES`).

## "Cluster-safe" checklist
- [ ] session/cache object `implements Serializable` + `serialVersionUID` ?
- [ ] entire transitive graph serializable ?
- [ ] non-serializables → `transient` + lazy reload ?
- [ ] no `@Inject` marked `transient` ?
- [ ] no `Future`/`Timer`/`Thread`/`Stream`/`Optional` in session ?
- [ ] passivation test present ?
- [ ] Liberty `httpSessionCache writeContents="GET_AND_SET_ATTRIBUTES"` (else in-place `@SessionScoped` mutations are not replicated) ?
