# Pattern — CDI scopes & end of static singletons

> Reference: lutece-core `RSAKeyPairUtil` / `RSAKeyDatastoreProvider` (cluster-safe shared key), `RoleHome`; forms `FormHome`. A mutable `static` lives in ONE JVM only → diverges across nodes.

## Anti-pattern
```java
public final class XService {
    private static XService _instance = new XService();   // mutable JVM-local state
    public static XService getInstance() { return _instance; }
    private final Map<...> _cache = new HashMap<>();      // diverges across instances
}
```

## Target pattern
**Stateless service/DAO → `@ApplicationScoped`** ; init in `@PostConstruct` (never the constructor).
```java
@ApplicationScoped
public class XService {
    @Inject private IXDao _dao;          // injection, no static
    @PostConstruct void init() { ... }   // thread-safe init
}
```
**Remove `getInstance()` entirely** (rule: `rules/service-layer.md`). Migrate every caller:
- in a CDI bean → `@Inject` the service;
- in a Home facade or static util → `private static final XService _x = CDI.current().select(XService.class).get();` — the static initializer is the core idiom (`RoleHome.java:58`, forms `FormHome.java:52`); the reference is effectively immutable, not divergent state;
- in an object created with `new` → cached `private final` field.
**Proxyability**: a normal-scoped bean resolved by its **concrete class** must be **non-`final`** + have a **non-private no-arg ctor** (alongside the `@Inject` ctor). A bean resolved only through its interface may stay `final` (core/forms DAOs).

**Optional / multi-implementation dependency**: `@Inject @Any Instance<I>` + `isResolvable()`/`stream()` collected in `@PostConstruct` — never a direct `@Named IService` of an optional plugin.

**Non-CDI object serialised into the session** (created with `new`, e.g. a display tree): dependencies as **`transient` + lazy getter** `if(_x==null) _x=CDI.current().select(...).get()`. This lazy rule applies to serialised objects only, not to Home facades.

**Value genuinely shared across nodes** (keys, secrets): move it to the **database** with an **atomic** write `DatastoreService.insertDataValueIfAbsent` (reference: core `RSAKeyDatastoreProvider`; relies on the PK; tolerate `false` = another node won) — **never** `setDataValue`/upsert (overwrite race).

## Scope → usage
| Component | Scope |
|---|---|
| Stateless business service, DAO, producer | `@ApplicationScoped` |
| BO JspBean with state | `@SessionScoped @Named` (+ `Serializable`) |
| Stateless BO JspBean, FO XPage | `@RequestScoped @Named` |
| Home (facade) | non-bean, `static`, DAO resolved once via CDI (no mutable state) |

## Rules
- DO: explicit scope; **stateless** services, shared state in DB; `@PostConstruct` for init; inject (reserve `CDI.current()` for Home/non-CDI objects).
- DON'T: mutable `static`; `CDI.current()` field init inside a serialised non-CDI object; mutable business state in an `@ApplicationScoped`; `final` or `@Inject`-only ctor on a bean resolved by its concrete class.
