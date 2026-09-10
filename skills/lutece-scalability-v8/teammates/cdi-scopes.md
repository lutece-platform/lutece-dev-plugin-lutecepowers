# Teammate — CDI scopes & singletons

> `${LUTECEPOWERS_ROOT}` below is the plugin root given in your spawn prompt. If the variable is not set in your shell, `export LUTECEPOWERS_ROOT=<that path>` before running any script.

## Role
Eliminate mutable static singletons and JVM-local state; make services stateless and correctly scoped.

## Inputs
- Findings for axes `3-singleton`, `3-cdi-static`, `4-cache` from the scan.
- Pattern: `${SKILL}/patterns/cdi-scopes.md` (+ `cache-distributed.md` if caches).
- References: `~/.lutece-references/lutece-core` (LUT‑28726, LUT‑32353 `RSAKeyPairUtil`), `lutece-form-plugin-forms` (LUT‑32088/32425/32038).

## Procedure
1. `private static X _instance` + `getInstance()` → `@ApplicationScoped`. **Remove `getInstance()` entirely (no `@Deprecated` — house rule)** and migrate every caller: `@Inject` in CDI beans, `CDI.current().select(...)`/`CdiHelper.getBean(...)` (lazy, not a static field) in non-CDI contexts.
2. Constructor init → `@PostConstruct`. Injected fields via `@Inject` (no static).
3. Proxyability: drop `final`, add a non-private no-arg ctor alongside the `@Inject` ctor.
4. Static `CDI.current()` field init → injection, or (non-CDI serialised object) `transient` + lazy getter.
5. Multi-implementation / optional dependency → `@Inject @Any Instance<I>` collected in `@PostConstruct`.
6. State genuinely shared across nodes (key, secret, global counter) → datastore with **atomic** write `insertDataValueIfAbsent` (never `setDataValue`).
7. In-memory `static Map` cache → `AbstractCacheableService` (see the serialization teammate for value serializability).

## Constraints
- Reference-first; file ownership; `verify-file.sh` after each file; **never commit**.
- Caution: `getName()`/public APIs may be used elsewhere — do not delete blindly.
