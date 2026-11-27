# Step 2 — Java

`lutece-check.sh` and `verify-file.sh` report everything a script can see, each finding with what to do: javax →
jakarta (JX*), Spring annotations and lookups (SP*), deprecated core singletons (DP01), own singletons (GI01, CD01),
portlet homes (HM01), `DAOUtil` in `try` (DA*), core listeners (EV*). This step makes those changes and what no check
can decide.

Before writing any class or pattern, find the v8 implementation in `~/.lutece-references/`; the v7 code of the same
reference is on its `*_core7` branch (`develop7.x` for lutece-core), to compare before and after.

## 1. Spring context → CDI

From the catalog of step 1 (`.migration/context-beans.json`), for each bean of the project:

- **Scope** from its Spring scope and its role: singleton → `@ApplicationScoped`, prototype → `@Dependent`, request →
  `@RequestScoped`, session → `@SessionScoped` (`patterns/cdi-patterns.md` §2). If the v8 reference already declares
  the class, take its form.
- **Name**: `@Named( "<id>" )` when the id is looked up by name (a `getBean( "<id>" )`, SQL, templates, JSP,
  properties).
- **Lifecycle**: `init-method`, `destroy-method`, `afterPropertiesSet` → `@PostConstruct` / `@PreDestroy` (SP05).
- **Producers**: `needsProducer: true` (constructor arguments, literal or inner-bean properties, a factory, a class
  outside the project) is built by a producer (`patterns/cdi-patterns.md` §6), the class left unannotated.
- **Lookups**: `SpringContextService.getBean` → `@Inject` in a bean, `CDI.current( ).select( … )` elsewhere (SP01,
  `patterns/cdi-patterns.md` §3).

## 2. Designs a script cannot choose

- **Legacy admin JspBean → MVC** (`mvcPort: true` in `.migration/scan.json`: admin JSPs drive it and it is no
  `@Controller`): extend `MVCAdminJspBean` with `@Controller( …, securityTokenEnabled = true )`, one `@View` /
  `@Action` per former JSP, like core `ThemeJspBean`; step 3 collapses the JSPs. `rules/jsp-admin.md`.
- **XSL portlet → HTML portlet** (a portlet class that still defines `getXml` / `getXmlDocument`): extend
  `PortletHtmlContent`, write the skin template, delete the XSL and every `core_style*` insert. `patterns/mvc-patterns.md` §10.
- **Portlet JspBean CSRF**: the automatic token filter covers MVC controllers only; the plugin protects its portlet
  forms itself. `patterns/mvc-patterns.md` §11.
- **A `catch` guarding what v8 no longer throws**: check every `catch` against the current core source. v7 caught
  `AppException` from `PageHome.getPage`; v8 returns the row or nothing, so the guard becomes
  `if ( !PageHome.checkPageExist( nId ) )`. Conversely `PortletHome.findByPrimaryKey` dereferences the row it
  loaded: a lookup driven by a request parameter needs its own guard (`patterns/mvc-patterns.md` §11).
- **Startup initialisation** (PI01, DP04 on a `*RemovalListenerService`): a plugin `init( )` that initialises a
  service, and listeners registered on a static service, become an `@Observes @Initialized( ApplicationScoped.class )`
  method of the service with the core's removal services injected by name (`patterns/cdi-patterns.md` §23).
- **Manual pagination** → `@Inject @Pager IPager` (`patterns/cdi-patterns.md` §20); two lists in one bean need two
  pager names.
- **Conditional patterns**, from the flags of `.migration/scan.json`: events (`events-patterns.md`), cache
  (`cache-patterns.md`), JPA (`persistence-patterns.md` §5–§7), REST (`rest-patterns.md`), file upload
  (`fileupload-patterns.md`), `net.sf.json` → Jackson (`json-patterns.md`).
- **Deprecated API a script cannot replace**: `patterns/deprecation-fixes.md` (the RBAC and workgroup overloads need an
  explicit `(User)` cast).

At the end of the step, delete the Spring context files (step 1).
