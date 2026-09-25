# Teammate — CDI scopes & singletons

> `${LUTECEPOWERS_ROOT}` is the plugin root from your spawn prompt (see `using-lutecepowers`, section Plugin root). `${SKILL}` = `${LUTECEPOWERS_ROOT}/skills/lutece-scalability-v8`; export both before running any script.

## Role
Eliminate mutable static singletons and JVM-local state; make services stateless and correctly scoped.

## Inputs
- Findings for axes `3-singleton`, `3-cdi-static`, `4-cache` from the scan.
- Pattern: `${SKILL}/patterns/cdi-scopes.md` (+ `cache-distributed.md` if caches).
- References: `~/.lutece-references/lutece-core` (`RSAKeyPairUtil`, `RSAKeyDatastoreProvider`, `RoleHome`), `lutece-form-plugin-forms` (`FormHome`).

## Procedure
1. `private static X _instance` + `getInstance()` → `@ApplicationScoped`. **Remove `getInstance()` entirely** (`rules/service-layer.md`) and migrate every caller: `@Inject` in CDI beans, `private static final X _x = CDI.current().select(...).get()` in Home facades / static utils, cached `private final` field in objects created with `new`.
2. Constructor init → `@PostConstruct`. Injected fields via `@Inject` (no static).
3. Proxyability: when the bean is resolved by its concrete class, drop `final` and add a non-private no-arg ctor alongside the `@Inject` ctor. Interface-resolved beans may stay `final`.
4. `CDI.current()` field init inside a CDI bean → `@Inject`; inside a Home facade → keep (idiom); inside a non-CDI serialised object → `transient` + lazy getter.
5. Multi-implementation / optional dependency → `@Inject @Any Instance<I>` collected in `@PostConstruct`.
6. State genuinely shared across nodes (key, secret, global counter) → datastore with **atomic** write `insertDataValueIfAbsent` (never `setDataValue`).
7. In-memory `static Map` cache → `AbstractCacheableService` (see the serialization teammate for value serializability).

## Constraints
- Reference-first; file ownership; `verify-file.sh` after each file; **never commit**.
- Caution: `getName()`/public APIs may be used elsewhere — do not delete blindly.
