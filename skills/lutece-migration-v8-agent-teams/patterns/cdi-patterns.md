# CDI Migration Patterns (to v8)

Single source of truth for all Spring-to-CDI, scope, injection, and related migration patterns.
Phases reference this file on demand. This is a pattern catalog, not a step-by-step guide.

> **Reference-First Principle:** This file is a static guide. Before applying ANY pattern below, **search `~/.lutece-references/` for an existing v8 implementation** of the same pattern (Grep for the class/interface/annotation). If a reference exists, reproduce its structure exactly — it is the living truth and takes priority over this document.

## 1. Context XML -> beans.xml

### Remove Spring Context XML

Delete all `*_context.xml` files (e.g., `webapp/WEB-INF/conf/plugins/myPlugin_context.xml`).
Before deleting, **catalog every bean** defined in these files -- each one must be migrated.

### Add CDI beans.xml

Create `src/main/resources/META-INF/beans.xml`:
```xml
<beans xmlns="https://jakarta.ee/xml/ns/jakartaee"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xsi:schemaLocation="https://jakarta.ee/xml/ns/jakartaee https://jakarta.ee/xml/ns/jakartaee/beans_4_0.xsd"
       version="4.0" bean-discovery-mode="annotated">
</beans>
```

## 2. CDI Scopes

### CRITICAL — Reflection-instantiated classes (DO NOT annotate)

Lutece's `Plugin.java` instantiates classes listed in plugin descriptor XML (`webapp/WEB-INF/plugins/*.xml`) via **reflection** (`Class.forName().newInstance()`). These classes are NOT CDI-managed — adding `@ApplicationScoped` creates two instances (one CDI, one reflection).

**Check these XML tags before assigning any CDI scope:**

| XML tag | Typical base class |
|---------|-------------------|
| `<content-service-class>` | `ContentService` |
| `<search-indexer-class>` | `SearchIndexer` |
| `<rbac-resource-type-class>` | `ResourceIdService` |
| `<filter-class>` | `jakarta.servlet.Filter` |
| `<servlet-class>` | `HttpServlet` |
| `<listener-class>` | `HttpSessionListener` |
| `<page-include-service-class>` | `PageInclude` |
| `<dashboard-component-class>` | `DashboardComponent` |
| `<daemon-class>` | `Daemon` (`DaemonEntry.loadDaemon` → `Class.forName`) |

**Exception:** `<application-class>` (XPages) — these tags are **removed** by the Config Migrator (v8 auto-discovers XPages via CDI), so the Java class DOES get `@SessionScoped`/`@RequestScoped` + `@Named`.

**Rule:** If a class is still listed in one of these XML tags and NOT removed by the Config Migrator, do NOT add a CDI scope. If you want to CDI-manage it, coordinate with the Config Migrator to remove the XML tag first.

### DAO and Service classes

Every DAO and Service class must get `@ApplicationScoped`:
```java
import jakarta.enterprise.context.ApplicationScoped;

@ApplicationScoped
public class MyDAO implements IMyDAO { ... }

@ApplicationScoped
public class MyService { ... }
```

- `final` stays when the bean is resolved only through its interface (core and forms DAOs are `@ApplicationScoped public final class`). Remove `final` and add a non-private no-arg constructor only when the concrete class is injected or looked up (`@Inject MyService`, `select(MyService.class)`)
- Remove private constructors used for singleton enforcement
- Remove static `_instance` / `_singleton` fields
- Delete `getInstance()` and migrate every caller — no `@Deprecated` bridge (`rules/service-layer.md`)

### JspBean classes (scope selection rules)

Inspect the JspBean's **instance fields**. If it stores per-user state across requests, use `@SessionScoped`. Otherwise, use `@RequestScoped`.

**`@SessionScoped`** -- bean has session state fields (working objects, filters, multi-step context, breadcrumb):
```java
@SessionScoped
@Named
@Controller(controllerJsp = "ManageMyPlugin.jsp", ...)
public class MyPluginJspBean extends MVCAdminJspBean {
    private MyEntity _entity;
    private MyFilter _filter;
}
```

Pagination fields (`_nItemsPerPage`, `_strCurrentPageIndex`) are not session state any more: they are replaced by `@Inject @Pager IPager` (§20), which is what lets a list bean become `@RequestScoped`.

**`@RequestScoped`** -- bean is stateless (no session instance fields):
```java
@RequestScoped
@Named
@Controller(controllerJsp = "Manage.jsp", ..., securityTokenEnabled = true)
public class MyJspBean extends MVCAdminJspBean {
    // No session-state instance fields
}
```

### XPage classes

**XPage with session state -> `@SessionScoped`:**
```java
// BEFORE (pre-v8)
@Controller( xpageName = "myXPage", pageTitleI18nKey = "...", pagePathI18nKey = "..." )
public class MyXPage extends MVCApplication {
    private static MyService _service = SpringContextService.getBean( MyService.BEAN_NAME );
    private ICaptchaSecurityService _captchaSecurityService = new CaptchaSecurityService();
}

// AFTER (v8)
@SessionScoped
@Named( "myplugin.xpage.myXPage" )
@Controller( xpageName = "myXPage", pageTitleI18nKey = "...", pagePathI18nKey = "...", securityTokenEnabled = true )
public class MyXPage extends MVCApplication {
    @Inject
    private MyService _service;
    @Inject
    @Named(BeanUtils.BEAN_CAPTCHA_SERVICE)
    private Instance<ICaptchaService> _captchaService;
}
```

**XPage without session state -> `@RequestScoped`:**
```java
@RequestScoped
@Named( "myplugin.xpage.myOtherXPage" )
@Controller( xpageName = "myOtherXPage", ... )
public class MyOtherXPage extends MVCApplication { ... }
```

Key XPage migration rules:
1. Add `@SessionScoped` or `@RequestScoped` (choose based on whether the XPage maintains state)
2. Add `@Named("pluginName.xpage.xpageName")` to identify the bean
3. Replace all `SpringContextService.getBean()` with `@Inject`
4. Remove `SecurityTokenService` usage: `securityTokenEnabled = true` on `@Controller` handles CSRF (`rules/web-bean.md`)
5. Replace `WorkflowService.getInstance()` with `@Inject private WorkflowService`
6. Replace `new CaptchaSecurityService()` with `@Inject @Named(BeanUtils.BEAN_CAPTCHA_SERVICE) Instance<ICaptchaService>`
7. Replace static upload handler access with `@Inject`

### EntryType classes (GenericAttributes-based plugins)

EntryType classes (extending `AbstractEntryType*`) need:
1. `@ApplicationScoped`
2. `@Named("pluginName.entryTypeName")` matching the bean name from the old context XML
3. Anonymization types injected via `@Inject` method with `@Named` parameters
4. Upload handler injected via `@Inject` instead of static access

```java
@ApplicationScoped
@Named( "myplugin.entryTypeText" )
public class EntryTypeText extends AbstractEntryTypeText {
    @Inject
    private MyAsynchronousUploadHandler _uploadHandler;

    @Inject
    public void addAnonymizationTypes(
        @Named("genericattributes.entryIdAnonymizationType") IEntryAnonymizationType entryId,
        @Named("genericattributes.entryCodeAnonymizationType") IEntryAnonymizationType entryCode,
        // ... other anonymization types
    ) {
        setAnonymizationTypes( List.of( entryId, entryCode, ... ) );
    }

    @Override
    public AbstractGenAttUploadHandler getAsynchronousUploadHandler() {
        return _uploadHandler;
    }
}
```

### Prototype beans -> @Dependent

Spring `scope="prototype"` beans become CDI `@Dependent`:
```java
// v7 Spring XML: <bean id="myBean" class="..." scope="prototype" />
// v8:
@Dependent
@Named("myBean")
public class MyBean { ... }
```

## 3. SpringContextService Replacement

| pre-v8 pattern | v8 pattern |
|-----------|-----------|
| `SpringContextService.getBean("beanId")` | `CDI.current().select(InterfaceType.class).get()` |
| `SpringContextService.getBean("namedBean")` | `CDI.current().select(Type.class, NamedLiteral.of("namedBean")).get()` |
| `SpringContextService.getBeansOfType(Type.class)` | `CDI.current().select(Type.class)` (returns `Instance<Type>`) |
| `SpringContextService.getBeansOfType(Type.class)` in loop | `CDI.current().select(Type.class).forEach(...)` |

## 4. Static DAO in Home Classes

A Home stays a plain static facade (never a CDI bean, keep `final`). The DAO is resolved once in the static field initializer — the idiom of every core and forms Home (`RoleHome.java:58`, `FormHome.java:52`).

```java
// BEFORE
public final class MyHome {
    private static IMyDAO _dao = SpringContextService.getBean("myDAO");
}

// AFTER
public final class MyHome {
    private static IMyDAO _dao = CDI.current().select(IMyDAO.class).get();
}
```

## 5. CDI Injection

### Field injection (@Inject)

For CDI-managed beans (classes annotated with `@ApplicationScoped`), prefer `@Inject` over `CDI.current().select()`:
```java
@Inject
private IMyDAO _dao;

@Inject
@Named("namedBean")
private IMyService _service;
```

### Instance<T> for optional/multiple beans (MANDATORY for optional services)

Use `Instance<T>` whenever the service may or may not be deployed (e.g., a plugin may not be installed). **Always check `isResolvable()` before calling `get()`.**

```java
// Optional service — plugin may not be installed
@Inject
@Named(BeanUtils.BEAN_CAPTCHA_SERVICE)
private Instance<ICaptchaService> _captchaService;

// Usage: ALWAYS check isResolvable() before get()
if ( _captchaService.isResolvable() )
{
    String strHtml = _captchaService.get().getHtmlCode();
    boolean bValid = _captchaService.get().validate( request );
}

// Multiple implementations — iterate all
@Inject
private Instance<IMyProvider> _providers;

for ( IMyProvider provider : _providers )
{
    provider.process();
}

// Check availability in @PostConstruct (like WorkflowService does)
@Inject
@Named("workflow.workflowProvider")
private Instance<IWorkflowProvider> _provider;

@PostConstruct
void init()
{
    _bServiceAvailable = _provider != null && _provider.isResolvable();
}
```

**Key `Instance<T>` methods:**
| Method | Purpose |
|--------|---------|
| `isResolvable()` | Exactly one bean matches — safe to call `get()` |
| `isUnsatisfied()` | No bean matches — the service is not deployed |
| `isAmbiguous()` | Multiple beans match — needs qualifier to disambiguate |
| `get()` | Returns the resolved bean instance (call only after `isResolvable()`) |
| `stream()` | Iterate all matching implementations |

### Constructor injection (workflow tasks/components)

For workflow task components, use constructor injection:
```java
@ApplicationScoped
@Named("myModule.myTaskComponent")
public class MyTaskComponent extends NoFormTaskComponent {
    @Inject
    public MyTaskComponent(
        @Named("myModule.taskType") ITaskType taskType,
        @Named("myModule.taskConfigService") ITaskConfigService configService
    ) {
        setTaskType(taskType);
        setTaskConfigService(configService);
    }
}
```

## 6. CDI Producers

### Simple producers (scalar properties only)

When a Spring XML bean had **scalar property values** (strings, numbers), create a Producer class.

**CRITICAL: Check the v8 API first.** Before writing a Producer, read the **v8 source** of the class being instantiated in `~/.lutece-references/`. The class constructors and setters may have changed in v8 (e.g., constructor args removed because the class is now CDI-managed with `@Inject`). If the v8 class is `@ApplicationScoped`, you probably don't need a Producer at all -- just `@Inject` it directly.

```java
// v7 XML: <bean id="x" class="Y"><property name="p" value="v"/></bean>
// v8:
@ApplicationScoped
public class YProducer {
    @Produces @Named("x") @ApplicationScoped
    public Y produce() {
        Y y = new Y();
        y.setP("v");
        return y;
    }
}
```

### Producers with @ConfigProperty

When Spring XML beans had property values, create a Producer that reads from `.properties` via `@ConfigProperty`:

```java
@ApplicationScoped
public class MyProducer {
    @Produces
    @ApplicationScoped
    @Named("myplugin.myBeanName")
    public MyType produce(
        @ConfigProperty(name = "myplugin.myBean.propertyA") String propA,
        @ConfigProperty(name = "myplugin.myBean.propertyB") String propB
    ) {
        return new MyType(propA, propB);
    }
}
```

The corresponding `.properties` file must contain the values:
```properties
myplugin.myBean.propertyA=valueA
myplugin.myBean.propertyB=valueB
```

### Producers referencing other named CDI beans (bean refs)

**CRITICAL PATTERN.** When a Spring XML bean's constructor-args or properties reference **other named beans** (`<constructor-arg ref="otherBean" />`), you MUST:
1. Make the bean names **configurable** via `@ConfigProperty` in the `.properties` file
2. Resolve them at runtime via `CdiHelper.getReference()` — **NEVER** use `@Inject @Named` with hardcoded bean names in the producer

**WRONG — hardcoded bean names in producer (NOT configurable):**
```java
// DO NOT DO THIS — the service names are hardcoded in Java
@ApplicationScoped
public class MyProducer {
    @Inject @Named("localDatabaseFileService")
    private IFileStoreService _fileStoreService;  // WRONG: hardcoded

    @Inject @Named("defaultFileDownloadService")
    private IFileDownloadUrlService _downloadService;  // WRONG: hardcoded

    @Produces @ApplicationScoped @Named("myplugin.myProvider")
    public IFileStoreServiceProvider produce() {
        return new FileStoreServiceProvider("myProvider",
            _fileStoreService, _downloadService, _rbacService, false);
    }
}
```

**CORRECT — configurable via properties + CdiHelper:**
```java
import org.eclipse.microprofile.config.inject.ConfigProperty;
import fr.paris.lutece.portal.service.util.CdiHelper;

@ApplicationScoped
public class MyPluginFileStoreServiceProviderProducer
{
    @Produces
    @ApplicationScoped
    @Named( "myplugin.fileStoreServiceProvider" )
    public IFileStoreServiceProvider createFileStoreProvider(
            @ConfigProperty( name = "myplugin.fileStoreServiceProvider.fileStoreService" ) String fileStoreImplName,
            @ConfigProperty( name = "myplugin.fileStoreServiceProvider.rbacService" ) String rbacImplName,
            @ConfigProperty( name = "myplugin.fileStoreServiceProvider.downloadService" ) String downloadImplName )
    {
        return new FileStoreServiceProvider( "myPluginFileStoreProvider",
                CdiHelper.getReference( IFileStoreService.class, fileStoreImplName ),
                CdiHelper.getReference( IFileDownloadUrlService.class, downloadImplName ),
                CdiHelper.getReference( IFileRBACService.class, rbacImplName ),
                false );
    }
}
```

With the corresponding `.properties` file:
```properties
myplugin.fileStoreServiceProvider.fileStoreService=localDatabaseFileService
myplugin.fileStoreServiceProvider.rbacService=myplugin.myFileRBACService
myplugin.fileStoreServiceProvider.downloadService=defaultFileDownloadService
```

**Required companion changes:**

1. **Add `@Named` to the custom `IFileRBACService`** so it can be referenced by name in properties:
```java
@ApplicationScoped
@Named( "myplugin.myFileRBACService" )
public class MyPluginFileRBACService implements IFileRBACService { ... }
```

2. **Consumers: replace runtime lookup with `@Inject @Named`:**
```java
// WRONG — runtime lookup via FileService
@Inject
private FileService _fileService;
// then: _fileService.getFileStoreServiceProvider("myPluginFileStoreProvider")

// CORRECT — direct CDI injection of the produced bean
@Inject
@Named( "myplugin.fileStoreServiceProvider" )
private IFileStoreServiceProvider _fileStoreProvider;
```

**Reference implementation:** `lutece-tech-plugin-filegenerator` — see `FileGeneratorFileStoreServiceProviderProducer.java`, `TemporaryFileRBACService.java`, and `filegenerator.properties` in `~/.lutece-references/`.

### TaskType producers (workflow)

TaskType beans from Spring XML become CDI producers with `@ConfigProperty`:

```java
@ApplicationScoped
public class MyTaskTypeProducer {
    @Produces @ApplicationScoped
    @Named("myModule.taskType")
    public ITaskType produce(
        @ConfigProperty(name = "myModule.taskType.key") String key,
        @ConfigProperty(name = "myModule.taskType.titleI18nKey") String titleI18nKey,
        @ConfigProperty(name = "myModule.taskType.beanName") String beanName,
        @ConfigProperty(name = "myModule.taskType.configBeanName") String configBeanName,
        @ConfigProperty(name = "myModule.taskType.configRequired", defaultValue = "false") boolean configRequired,
        @ConfigProperty(name = "myModule.taskType.taskForAutomaticAction", defaultValue = "false") boolean taskForAutomaticAction
    ) {
        TaskType t = new TaskType();
        t.setKey(key); t.setTitleI18nKey(titleI18nKey); t.setBeanName(beanName);
        t.setConfigBeanName(configBeanName); t.setConfigRequired(configRequired);
        t.setTaskForAutomaticAction(taskForAutomaticAction);
        return t;
    }
}
```

With corresponding `.properties`:
```properties
myModule.taskType.key=myTaskKey
myModule.taskType.titleI18nKey=module.workflow.mymodule.task_title
myModule.taskType.beanName=myModule.myTask
myModule.taskType.configBeanName=myModule.myTaskConfig
myModule.taskType.configRequired=true
myModule.taskType.taskForAutomaticAction=false
```

### CDI Impl Classes for abstract services

When a library provides abstract service classes (e.g., `ActionService` from `library-workflow-core`), create empty CDI implementation classes:

```java
@ApplicationScoped
@Named(ActionService.BEAN_SERVICE)
public class ActionServiceImpl extends ActionService {
    // Empty - provides CDI annotations for parent abstract class
}
```

This is needed because CDI cannot proxy abstract classes without a concrete subclass.

### Default constructor for CDI proxies

CDI-managed classes with `@Inject` constructor MUST also have a default (no-arg) constructor:

```java
@ApplicationScoped
@Named("myModule.myTaskComponent")
public class MyTaskComponent extends NoFormTaskComponent {
    MyTaskComponent() { } // Required for CDI proxy

    @Inject
    public MyTaskComponent(
        @Named("myModule.taskType") ITaskType taskType,
        @Named("myModule.configService") ITaskConfigService configService
    ) {
        setTaskType(taskType);
        setTaskConfigService(configService);
    }
}
```

## 7. Singleton Pattern Migration

```java
// v7
public final class MyService {
    private static MyService _instance;
    public static synchronized MyService getInstance() { ... }
}

// v8 -- remove getInstance() entirely, no @Deprecated bridge (rules/service-layer.md)
@ApplicationScoped
public class MyService {
    // No getInstance() -- callers use @Inject (CDI beans) or CDI.current().select(MyService.class).get() (static contexts)
}
```

### Deprecated `getInstance()` methods in lutece-core

lutece-core marks 23 of its own `getInstance()` methods `@Deprecated(since = "8.0", forRemoval = true)`. The single maintained list is the `DP01` check in `scripts/verify-migration.sh`; do not copy it here. Replace each call with `@Inject` in CDI-managed classes or `CDI.current().select()` in static contexts. `SecurityService.getInstance()` and `AdminAuthenticationService.getInstance()` are not deprecated and stay as they are.

Rules for replacement:
- Use the **interface type** when one exists (e.g., `ISecurityTokenService`, `IEditorBbcodeService`)
- Use the **concrete class** when no interface exists (e.g., `FileService`, `WorkflowService`)
- Keep static imports of the class for **constants** (`SecurityTokenService.MARK_TOKEN`, `SecurityTokenService.PARAMETER_TOKEN`, etc.)
- Field naming: `_securityTokenService`, `_fileService`, `_workflowService`, etc.

## 8. Business Objects

### Serializable requirement

Business objects used in `@SessionScoped` beans or passed through CDI events should implement `Serializable`:

```java
public class MyBusinessObject implements Cloneable, Serializable {
    private static final long serialVersionUID = 1L;
    // ...
}
```

## 9. Transaction Annotation

```java
// BEFORE (pre-v8)
@Transactional(MyPlugin.BEAN_TRANSACTION_MANAGER)

// AFTER (v8) - no transaction manager reference
@Transactional
```

Import change: `org.springframework.transaction.annotation.Transactional` -> `jakarta.transaction.Transactional`

## 10. DAOUtil try-with-resources

Replace manual `daoUtil.free()` with try-with-resources:

```java
// BEFORE (pre-v8)
DAOUtil daoUtil = new DAOUtil(SQL_QUERY, plugin);
daoUtil.setInt(1, id);
daoUtil.executeUpdate();
daoUtil.free();

// AFTER (v8)
try (DAOUtil daoUtil = new DAOUtil(SQL_QUERY, plugin)) {
    daoUtil.setInt(1, id);
    daoUtil.executeUpdate();
}
```

## 11. RBAC User Cast

v8 requires explicit `(User)` cast for RBAC calls:
```java
// BEFORE (pre-v8)
RBACService.isAuthorized(resource, permission, adminUser)

// AFTER (v8)
RBACService.isAuthorized(resource, permission, (User) adminUser)
```

## 12. Async Processing

Replace `CompletableFuture.runAsync()` with Jakarta `@Asynchronous`:

```java
// BEFORE (pre-v8)
import java.util.concurrent.CompletableFuture;
public void generateFile(IFileGenerator generator) {
    CompletableFuture.runAsync(new MyRunnable(generator));
}

// AFTER (v8)
import jakarta.enterprise.concurrent.Asynchronous;
@Asynchronous
public void generateFile(IFileGenerator generator) {
    new MyRunnable(generator).run();
}
```

## 13. CdiHelper

Use `CdiHelper.getReference()` for programmatic CDI lookup with qualifiers in producers:

```java
CdiHelper.getReference(IMyService.class, "namedBeanName");
```

## 14. InitializingBean -> @PostConstruct

Replace Spring's `InitializingBean.afterPropertiesSet()` with Jakarta `@PostConstruct`:

```java
// BEFORE (pre-v8)
import org.springframework.beans.factory.InitializingBean;
public class MyComponent implements InitializingBean {
    @Override
    public void afterPropertiesSet() throws Exception {
        Assert.notNull(_field, "Required");
    }
}

// AFTER (v8)
import jakarta.annotation.PostConstruct;
public class MyComponent {
    @PostConstruct
    public void afterPropertiesSet() {
        if (_field == null) throw new IllegalArgumentException("Required");
    }
}
```

Also remove `extends InitializingBean` from interfaces.

## 15. Workflow Task Signature Changes

If implementing `ITask.processTaskWithResult()`, update to the new signature:

```java
// BEFORE (pre-v8)
boolean processTaskWithResult(int nIdResourceHistory, HttpServletRequest request, Locale locale, User user);

// AFTER (v8) - includes resource info
boolean processTaskWithResult(int nIdResource, String strResourceType, int nIdResourceHistory,
    HttpServletRequest request, Locale locale, User user);
```

Similarly for `AsynchronousSimpleTask.processAsynchronousTask()`.

## 16. Models Injection (JspBean/XPage) — MANDATORY

**This migration is MANDATORY, not optional.** `getModel()` is deprecated and will cause runtime errors if mixed with `Models`. In Lutece 8, `Models.asMap()` returns an **unmodifiable map** — any code that calls `put()` on it will throw `UnsupportedOperationException` at runtime.

**Before (will crash in v8):**
```java
Map<String, Object> model = getModel( );
model.put( MARK_ITEM, item );
model.put( SecurityTokenService.MARK_TOKEN, _securityTokenService.getToken( request, ACTION ) );
XPage page = getXPage( TEMPLATE, locale, model );
// the manual token line disappears too: securityTokenEnabled = true on @Controller (rules/web-bean.md)
```

**After — Option A: Method parameter injection (PREFERRED for @View/@Action methods):**
```java
@View( value = VIEW_MANAGE )
public String getManage( Models model )
{
    model.put( MARK_LIST, list );
    return getPage( PROPERTY_PAGE_TITLE, TEMPLATE, model );
}
```

Reference: `~/.lutece-references/lutece-cms-plugin-xmltransformer/src/java/fr/paris/lutece/portal/web/style/StylesJspBean.java`

**After — Option B: Field injection (for methods outside @View/@Action, or shared model population):**
```java
@Inject
private Models _models;

// In view method:
_models.put( MARK_ITEM, item );
XPage page = getXPage( TEMPLATE, locale );
```

**Rules:**
- Inject `Models` (from `fr.paris.lutece.portal.web.cdi.mvc.Models`) — it is `@RequestScoped`
- Use `_models.put(key, value)` instead of `model.put(key, value)`
- Call `getXPage(template, locale)` (2 args) instead of `getXPage(template, locale, model)` (3 args)
- For back-office: `getPage(titleProperty, template)` (2 args) instead of `getPage(titleProperty, template, model)` (3 args)
- `Models.put()` returns `this` for chaining: `_models.put(A, a).put(B, b)`

**CRITICAL — asMap() is unmodifiable:**
- `_models.asMap()` returns an **unmodifiable view** of the map — calling `put()` on it throws `UnsupportedOperationException`
- NEVER pass `_models.asMap()` to a method that writes into the map
- If a helper method needs to add entries to the model, change its signature to accept `Models` (not `Map<String, Object>`)

**CSRF:** with `securityTokenEnabled = true` on `@Controller`, the core generates the token for each view (`@View.securityTokenAction` or the view name), injects it into every `<form>` of the rendered page and validates every `@Action` POST. Remove `SecurityTokenService.MARK_TOKEN` puts and manual `validate()` calls (single source: `rules/web-bean.md`).

**Helper method signatures — MUST be updated:**
Every method in the class hierarchy that receives the model as `Map<String, Object>` and calls `put()` on it **must** be changed to accept `Models`. This includes abstract methods in base classes and their implementations in subclasses.

```java
// Before — WILL CRASH if passed _models.asMap()
protected void addElementsToModel( MyDTO dto, User user, Locale locale, Map<String, Object> model )
{
    model.put( MARK_USER, user );  // UnsupportedOperationException!
}

// After — accepts Models directly
protected void addElementsToModel( MyDTO dto, User user, Locale locale, Models model )
{
    model.put( MARK_USER, user );  // OK
}
```

The `Models` interface supports `put(String, Object)` and `get(String)`, so most code using `Map.put()` works unchanged after the type change.

## 17. Configuration

### When to use which

| Context | Use | Why |
|---------|-----|-----|
| **Producers** (replace Spring XML `<property>`) | `@ConfigProperty` on method parameters | The v8 pattern for building configured beans |
| **CDI constructors** (immutable config) | `@ConfigProperty` on constructor parameters | Typed injection at construction |
| **Casual reads** in a service/JspBean | `AppPropertiesService` | Core does this — simple, direct, works everywhere |
| **Static context** (Home, utility, `static final`) | `AppPropertiesService` | No CDI injection available |
| **Non-CDI class** (reflection-instantiated) | `AppPropertiesService` | `@ConfigProperty` will NOT be injected — field stays `null` |

### @ConfigProperty in CDI beans

```java
@Inject
@ConfigProperty(name = "myplugin.myProperty", defaultValue = "default")
private String _myProperty;
```

### @ConfigProperty (MicroProfile Config) — Priority Hierarchy

Ordinal table (system 400 > env 300 > `override/` 250 > `WEB-INF/conf` 150 > `microprofile-config.properties` 100): `rules/service-layer.md` § Configuration.

Usage:
```java
@Inject @ConfigProperty(name = "myplugin.some.key", defaultValue = "default")
private String _strSomeKey;
```

Or programmatic:
```java
ConfigProvider.getConfig().getValue("key", String.class);
```

### AppPropertiesService -> MicroProfile Config (in libraries)

For libraries that don't have CDI injection context, use `ConfigProvider.getConfig()` directly:

```java
// BEFORE (pre-v8)
import fr.paris.lutece.portal.service.util.AppPropertiesService;
String value = AppPropertiesService.getProperty(PROPERTY_KEY);
String valueWithDefault = AppPropertiesService.getProperty(PROPERTY_KEY, "default");

// AFTER (v8)
import org.eclipse.microprofile.config.Config;
import org.eclipse.microprofile.config.ConfigProvider;
private static Config _config = ConfigProvider.getConfig();
String value = _config.getOptionalValue(PROPERTY_KEY, String.class).orElse(null);
String valueWithDefault = _config.getOptionalValue(PROPERTY_KEY, String.class).orElse("default");
```

## 18. Logging

Update string concatenation to parameterized logging:

```java
// BEFORE (pre-v8)
AppLogService.info(MyClass.class.getName() + " : message " + variable);

// AFTER (v8)
AppLogService.info("{} : message {}", MyClass.class.getName(), variable);
```

## 19. RedirectScope

Custom CDI scope that survives exactly one redirect (2 requests max).

```java
@RedirectScoped
@Named
public class MyRedirectBean implements Serializable {
    private String _strMessage;
    // getters/setters
}
```

Use case: pass data from an @Action (POST) to the redirect target @View (GET).
- Bean MUST implement Serializable
- Lives for max 2 requests (action + redirect target)
- Alternative to session storage for transient redirect data

## 20. Pager Injection

Replaces `AbstractPaginatorJspBean` and manual pagination (`_nItemsPerPage`, `_strCurrentPageIndex`, `new LocalizedPaginator`). Allows `@RequestScoped` instead of `@SessionScoped`.

`IPager` API (core `web/util/IPager.java`): `withBaseUrl`, `withItemsPerPage`, `withIdList`, `withListItem`, `populateModels( request, models, locale )`, `populateModels( request, models, delegate, locale )`, `getPaginator()`. Full JspBean + template example: `lutece-patterns` skill §5.

## 21. @LutecePriority for CDI Alternatives

When multiple implementations of an interface exist, use @Alternative + @LutecePriority.

```java
@ApplicationScoped
@Alternative
@LutecePriority( "myplugin.impl.priority" )
public class MyImplA implements IMyService { }
```

The positional value is the configuration key holding the priority (core usage: `@LutecePriority( "multipart.handler.TemporaryFileMultipartHandler" )` in `TemporaryFileMultipartHandler.java`). Higher value wins.

## 22. Eager CDI Bean Initialization (Constructor Self-Registration)

**Migration trap:** In Spring, beans declared in `_context.xml` were eagerly instantiated at startup. In CDI, `@ApplicationScoped` beans are **lazy** — they are only created when first injected. If nothing injects the bean, its constructor never runs.

This silently breaks the **self-registration pattern** where a bean registers itself with a global service in its constructor:

```java
// BROKEN in CDI — constructor never called because bean is never injected
@ApplicationScoped
public class MySearchIndexer implements SearchIndexer {
    public MySearchIndexer() {
        IndexationService.registerIndexer(this);  // NEVER EXECUTES
    }
}
```

**Fix (only when the class is NOT declared in plugin.xml):** if the indexer is still listed under `<search-indexer-class>`, `Plugin.registerSearchIndexers` already instantiates and registers it by reflection (§2) — do not add a scope. Otherwise move self-registration to a CDI startup observer:

```java
@ApplicationScoped
public class MySearchIndexer implements SearchIndexer {
    /**
     * CDI startup observer — registers the indexer when the application starts
     */
    public void onStartup(@Observes @Initialized(ApplicationScoped.class) ServletContext ctx) {
        IndexationService.registerIndexer(this);
    }
}
```

Common self-registration calls affected by this pattern:
- `IndexationService.registerIndexer(this)`
- `CacheService.registerCacheableService(this)`
- `ImageResourceManager.registerProvider(this)`
- Any `SomeService.register*(this)` in a constructor

## Key Imports Reference

```java
// CDI Core
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.context.RequestScoped;
import jakarta.enterprise.context.SessionScoped;
import jakarta.enterprise.context.Dependent;
import jakarta.enterprise.inject.spi.CDI;
import jakarta.enterprise.inject.Instance;
import jakarta.enterprise.inject.Produces;
import jakarta.enterprise.inject.Alternative;
import jakarta.enterprise.inject.literal.NamedLiteral;
import jakarta.inject.Inject;
import jakarta.inject.Named;
import jakarta.inject.Singleton;

// CDI Events
import jakarta.enterprise.event.Observes;
import jakarta.enterprise.event.ObservesAsync;
import jakarta.enterprise.context.Initialized;
import jakarta.annotation.Priority;
import fr.paris.lutece.portal.service.event.EventAction;
import fr.paris.lutece.portal.service.event.Type;
import fr.paris.lutece.portal.service.event.Type.TypeQualifier;
import fr.paris.lutece.portal.business.event.ResourceEvent;

// Lifecycle
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;

// Servlet
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import jakarta.servlet.ServletContext;

// REST
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;

// Validation
import jakarta.validation.ConstraintViolation;

// Config
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.config.ConfigProvider;

// Cache
import javax.cache.Cache; // NOTE: javax, NOT jakarta

// Lutece-specific CDI
import fr.paris.lutece.portal.web.cdi.mvc.Models;
import fr.paris.lutece.portal.web.cdi.mvc.RedirectScoped;
import fr.paris.lutece.portal.web.util.Pager;
import fr.paris.lutece.portal.web.util.IPager;
import fr.paris.lutece.portal.service.util.CdiHelper;
import fr.paris.lutece.plugins.priority.annotation.LutecePriority;
```
