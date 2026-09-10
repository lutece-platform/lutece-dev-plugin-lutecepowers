# Lutece Migration v7 to v8 - Complete Generic Skill

## Purpose

This skill provides a **complete, verified migration plan** for migrating any Lutece plugin/module/library from v7 to v8. The AI MUST follow every step and verify each change systematically.

---

## MIGRATION EXECUTION PLAN

The AI MUST execute the following phases **in order**. Each phase has mandatory verification steps. **Do NOT skip any phase.**

---

### PHASE 0: ANALYSIS (Mandatory Before Any Code Change)

**Steps:**
1. Read the full project structure (`find . -type f -name "*.java" -o -name "*.xml" -o -name "*.html" -o -name "*.properties"`)
2. Identify the project type: **plugin**, **module**, or **library**
3. Read `pom.xml` completely
4. List all `*_context.xml` files
5. List all Java files with their current imports
6. List all template files (`.html`)
7. List all `.properties` files
8. Identify all Spring beans declared in context XML files
9. Identify all `SpringContextService.getBean()` calls
10. Identify all singleton patterns (`getInstance()`)
11. Identify all `javax.*` imports
12. Identify all cache usage (EhCache 2.x)
13. Identify all custom event/listener patterns
14. Identify all REST endpoints (JAX-RS)

**Output:** A migration impact report listing everything that needs to change.

---

### PHASE 1: POM.XML Migration

**Steps:**
1. Update parent POM: `lutece-global-pom` version `6.x.x` → `8.0.2`
2. Update artifact version to `8.0.0` (or appropriate v8 version)
3. Remove Spring dependencies:
   - `spring-aop`, `spring-beans`, `spring-context`, `spring-core`, `spring-orm`, `spring-tx`, `spring-web`
4. Remove old cache dependencies:
   - `net.sf.ehcache:ehcache-core`, `net.sf.ehcache:ehcache-web`
5. Remove old mail dependency: `com.sun.mail:javax.mail`
6. Remove old persistence: `org.eclipse.persistence:javax.persistence`
7. Remove Quartz if present: `org.quartz-scheduler:quartz`
8. Remove Scannotation if present: `org.scannotation:scannotation`
9. Update `lutece-core` dependency version to `8.0.0` (for plugins/modules)
10. Update related library versions:
    - `library-workflow-core` → `4.0.0-SNAPSHOT`
    - `library-lucene` → `6.0.0-SNAPSHOT`
    - `library-freemarker` → `2.0.0-SNAPSHOT`
    - `library-httpaccess` → check v8 version
11. Add new dependencies if needed (JCache API, classgraph, etc.)
11b. Rename the test EL implementation: `org.glassfish:jakarta.el` → `org.glassfish.expressly:expressly` (the old artifact is no longer managed by the parent)
11c. Drop any `<version>` on a parent-managed dependency (`library-lutece-unit-testing`, `hibernate-validator`, `expressly`, `jaxb-runtime`)
11d. Stay on Jakarta EE 10 — no `jakarta.annotation-api` 3.x, no `weld-junit5` 5.x
12. Remove `<springVersion>` property if present
13. Remove Jira properties: `<jiraProjectName>` and `<jiraComponentId>` from `<properties>` block
14. Convert bounded version ranges to open ranges: `[X,Y)` → `[X,)`. Upper bounds are unnecessary in v8

**Verification:**
- [ ] No `org.springframework` dependency remains
- [ ] No `net.sf.ehcache` dependency remains
- [ ] No `javax.mail` dependency remains
- [ ] Parent POM is `8.0.2`
- [ ] No `org.glassfish:jakarta.el` remains (renamed to `org.glassfish.expressly:expressly`)
- [ ] `mvn enforcer:enforce` passes — the `test` scope is inspected too
- [ ] Core dependency is v8
- [ ] No `<jiraProjectName>` or `<jiraComponentId>` properties remain
- [ ] No bounded version ranges `[X,Y)` remain

---

### PHASE 2: javax → jakarta Package Renames

**Global search-and-replace for ALL Java files:**

| Old Import | New Import |
|-----------|-----------|
| `javax.servlet.*` | `jakarta.servlet.*` |
| `javax.validation.*` | `jakarta.validation.*` |
| `javax.annotation.PostConstruct` | `jakarta.annotation.PostConstruct` |
| `javax.annotation.PreDestroy` | `jakarta.annotation.PreDestroy` |
| `javax.inject.*` | `jakarta.inject.*` |
| `javax.enterprise.*` | `jakarta.enterprise.*` |
| `javax.ws.rs.*` | `jakarta.ws.rs.*` |

**IMPORTANT:** Do NOT replace `javax.cache.*` — JCache (JSR-107) still uses `javax.cache`.

**Additional replacements:**

| Old Import | New Import |
|-----------|-----------|
| `javax.xml.bind.*` | `jakarta.xml.bind.*` |
| `org.apache.commons.fileupload.FileItem` | `fr.paris.lutece.portal.service.upload.MultipartItem` |

**API changes:**
| Old | New |
|-----|-----|
| `File.getIdFile()` / `File.setIdFile()` | `File.getFileKey()` / `File.setFileKey()` |

**Verification:**
- [ ] No `javax.servlet` imports remain
- [ ] No `javax.validation` imports remain
- [ ] No `javax.annotation.PostConstruct` or `javax.annotation.PreDestroy` remain
- [ ] No `javax.inject` imports remain
- [ ] No `javax.ws.rs` imports remain
- [ ] No `javax.xml.bind` imports remain
- [ ] No `org.apache.commons.fileupload.FileItem` imports remain
- [ ] `javax.cache` imports are preserved (NOT replaced)

---

### PHASE 3: Spring to CDI Migration

#### 3.1 Remove Spring Context XML Files

1. Delete all `*_context.xml` files (e.g., `webapp/WEB-INF/conf/plugins/myPlugin_context.xml`)
2. Before deleting, **catalog every bean** defined in these files — each one must be migrated

#### 3.2 Add CDI beans.xml

Create `src/main/resources/META-INF/beans.xml`:
```xml
<beans xmlns="https://jakarta.ee/xml/ns/jakartaee"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xsi:schemaLocation="https://jakarta.ee/xml/ns/jakartaee https://jakarta.ee/xml/ns/jakartaee/beans_4_0.xsd"
       version="4.0" bean-discovery-mode="annotated">
</beans>
```

#### 3.3 Annotate DAO Classes

Every DAO class must get `@ApplicationScoped`:
```java
import jakarta.enterprise.context.ApplicationScoped;

@ApplicationScoped
public class MyDAO implements IMyDAO { ... }
```

#### 3.4 Annotate Service Classes

Every service class must get `@ApplicationScoped`:
```java
import jakarta.enterprise.context.ApplicationScoped;

@ApplicationScoped
public class MyService { ... }
```

- Remove `final` keyword from class if present (CDI cannot proxy final classes)
- Remove private constructors used for singleton enforcement
- Remove static `_instance` / `_singleton` fields
- Convert `getInstance()` to use CDI:
```java
public static MyService getInstance() {
    return CDI.current().select(MyService.class).get();
}
```

#### 3.5 Replace SpringContextService Calls

| v7 Pattern | v8 Pattern |
|-----------|-----------|
| `SpringContextService.getBean("beanId")` | `CDI.current().select(InterfaceType.class).get()` |
| `SpringContextService.getBean("namedBean")` | `CDI.current().select(Type.class, NamedLiteral.of("namedBean")).get()` |
| `SpringContextService.getBeansOfType(Type.class)` | `CDI.current().select(Type.class)` (returns `Instance<Type>`) |
| `SpringContextService.getBeansOfType(Type.class)` in loop | `CDI.current().select(Type.class).forEach(...)` |

#### 3.6 Replace Static DAO References in Home Classes

```java
// BEFORE
private static IMyDAO _dao = SpringContextService.getBean("myDAO");

// AFTER
private static IMyDAO _dao = CDI.current().select(IMyDAO.class).get();
```

#### 3.7 CDI Producers (for complex bean definitions)

When a Spring XML bean had constructor args, property values, or list configurations, create a Producer class:

```java
@ApplicationScoped
public class MyProducer {

    @Produces
    @Named("beanName")
    @ApplicationScoped
    public MyType produce() {
        // Recreate the bean configuration from the old XML
        return new MyType(...);
    }
}
```

#### 3.8 CDI Injection

For CDI-managed beans (classes annotated with `@ApplicationScoped`), prefer `@Inject` over `CDI.current().select()`:

```java
@Inject
private IMyDAO _dao;

@Inject
@Named("namedBean")
private IMyService _service;
```

Use `Instance<T>` for optional or multiple beans:
```java
@Inject
Instance<IMyProvider> _providers;

// Optional bean
@Inject
@Named("optionalBean")
Instance<IMyProvider> _optionalProvider;
```

**Verification:**
- [ ] No `SpringContextService` import remains in any Java file
- [ ] No `*_context.xml` file remains
- [ ] All DAOs have `@ApplicationScoped`
- [ ] All Services have `@ApplicationScoped`
- [ ] `beans.xml` exists in `META-INF/`
- [ ] No Spring imports remain (`org.springframework.*`)

---

### PHASE 4: Event/Listener Migration

#### 4.1 CDI Observer Pattern

Replace custom listener interfaces with CDI `@Observes`:

```java
// BEFORE: listener interface + registration
public interface MyEventListener {
    void processEvent(MyEvent event);
}

// AFTER: CDI observer
@ApplicationScoped
public class MyEventObserver {
    public void processEvent(@Observes MyEvent event) {
        // Handle event
    }
}
```

#### 4.2 Firing Events

```java
// BEFORE
for (MyListener l : SpringContextService.getBeansOfType(MyListener.class)) {
    l.onEvent(event);
}

// AFTER
CDI.current().getBeanManager().getEvent().fire(event);
```

**Verification:**
- [ ] No custom listener iteration via SpringContextService remains
- [ ] Events are fired via CDI `getBeanManager().getEvent().fire()`

---

### PHASE 5: Cache Migration

If the plugin uses caching:

1. Replace EhCache 2.x API with JCache (JSR-107) or `@LuteceCache` annotation
2. Replace `net.sf.ehcache.Cache` with `javax.cache.Cache` or `Lutece107Cache`
3. Replace `new Element(key, value)` pattern with direct `cache.put(key, value)`
4. Replace `cache.get(key).getObjectValue()` with `cache.get(key)`

```java
// v8 Cache injection
@Inject
@LuteceCache(cacheName = "myCache", keyType = String.class, valueType = MyObject.class, enable = true)
private Lutece107Cache<String, MyObject> _cache;
```

**Verification:**
- [ ] No `net.sf.ehcache` imports remain
- [ ] Cache API uses JCache or Lutece107Cache

---

### PHASE 6: Configuration Migration

If the plugin uses `AppPropertiesService` for injected config in CDI beans, optionally use MicroProfile Config:

```java
@Inject
@ConfigProperty(name = "myplugin.myProperty", defaultValue = "default")
private String _myProperty;
```

**Note:** `AppPropertiesService.getProperty()` still works in v8. MicroProfile Config is optional but preferred in CDI beans.

---

### PHASE 7: REST API Migration (if applicable)

#### 7.1 Import Migration
Replace `javax.ws.rs.*` imports with `jakarta.ws.rs.*`.

#### 7.2 Jersey → Jakarta JAX-RS
If the plugin uses Jersey directly:
- Replace `ResourceConfig` with standard `Application` class using `@ApplicationPath`
- Remove Jersey-specific dependencies (`jersey-server`, `jersey-spring5`, `jersey-media-*`)
- Remove manual `register()` calls — use `@Provider` auto-discovery instead
- Remove Jersey filter registrations from `plugin.xml`

```java
// BEFORE (v7) - Jersey ResourceConfig
public class MyRestConfig extends ResourceConfig {
    public MyRestConfig() {
        register(MyExceptionMapper.class);
    }
}

// AFTER (v8) - Standard JAX-RS Application
@ApplicationPath("/rest/")
public class MyRestApplication extends Application { }
```

#### 7.3 REST Authentication Filter
Replace servlet-based auth filters with JAX-RS `ContainerRequestFilter`:

```java
// AFTER (v8)
@Provider
@PreMatching
@Priority(Priorities.AUTHENTICATION)
public class MyAuthFilter implements ContainerRequestFilter {
    @Inject
    private HttpServletRequest _httpRequest;

    @Inject
    @MyAuthenticatorQualifier
    private RequestAuthenticator _authenticator;

    @Override
    public void filter(ContainerRequestContext ctx) throws IOException {
        if (!_authenticator.isRequestAuthenticated(_httpRequest)) {
            ctx.abortWith(Response.status(Response.Status.UNAUTHORIZED).build());
        }
    }
}
```

#### 7.4 Custom CDI Qualifier for Authenticators
```java
@Qualifier
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.FIELD, ElementType.METHOD, ElementType.PARAMETER, ElementType.TYPE})
public @interface MyAuthenticatorQualifier { }
```

#### 7.5 Exception Mappers
Add `@Provider` annotation for auto-discovery (no manual registration):
```java
@Provider
public class MyExceptionMapper implements ExceptionMapper<Throwable> { ... }
```

#### 7.6 REST plugin.xml changes
- Remove `<filters>` section — JAX-RS auto-discovers via `@ApplicationPath`
- Remove Jersey init-params

**Verification:**
- [ ] No `javax.ws.rs` imports remain
- [ ] No Jersey dependencies remain (`org.glassfish.jersey`)
- [ ] REST classes use CDI annotations
- [ ] `@Provider` on all ExceptionMappers, Filters
- [ ] No manual filter registration in plugin.xml

---

### PHASE 8: Web.xml Updates (if applicable, mainly for plugins with web.xml fragments)

1. Update namespace from `http://java.sun.com/xml/ns/javaee` to `https://jakarta.ee/xml/ns/jakartaee`
2. Update version to `6.0`
3. Remove Spring listeners if present

---

### PHASE 9: Template Verification

1. Check all Freemarker templates (`.html`) for any Java class references that may have changed
2. Verify macro includes paths are correct
3. Verify i18n keys are correctly prefixed in templates (prefix in template, NOT in properties file)

---

### PHASE 10: Final Verification Checklist

Run these checks on the entire project:

- [ ] `grep -r "org.springframework" src/` → **must return nothing**
- [ ] `grep -r "javax.servlet" src/` → **must return nothing**
- [ ] `grep -r "javax.validation" src/` → **must return nothing**
- [ ] `grep -r "javax.annotation.PostConstruct\|javax.annotation.PreDestroy" src/` → **must return nothing**
- [ ] `grep -r "javax.inject" src/` → **must return nothing**
- [ ] `grep -r "javax.ws.rs" src/` → **must return nothing**
- [ ] `grep -r "SpringContextService" src/` → **must return nothing**
- [ ] `grep -r "net.sf.ehcache" src/` → **must return nothing**
- [ ] `grep -r "_context.xml" webapp/` → **no context XML files remain**
- [ ] `beans.xml` exists at correct location
- [ ] All DAO classes have `@ApplicationScoped`
- [ ] All Service classes have `@ApplicationScoped`
- [ ] All `getInstance()` methods use `CDI.current().select()` if kept
- [ ] No `final` class that is CDI-managed
- [ ] Project compiles: `mvn clean compile`

---

## COMMON MIGRATION PATTERNS REFERENCE

### Pattern: Static DAO in Home class
```java
// v7
private static IMyDAO _dao = SpringContextService.getBean("myDAO");
// v8
private static IMyDAO _dao = CDI.current().select(IMyDAO.class).get();
```

### Pattern: Named bean lookup
```java
// v7
IProvider p = SpringContextService.getBean("myNamedProvider");
// v8
IProvider p = CDI.current().select(IProvider.class, NamedLiteral.of("myNamedProvider")).get();
```

### Pattern: Iterate beans of type
```java
// v7
List<IProvider> list = SpringContextService.getBeansOfType(IProvider.class);
// v8
Instance<IProvider> list = CDI.current().select(IProvider.class);
```

### Pattern: Singleton service
```java
// v7
public final class MyService {
    private static MyService _instance;
    public static synchronized MyService getInstance() { ... }
}
// v8
@ApplicationScoped
public class MyService {
    public static MyService getInstance() {
        return CDI.current().select(MyService.class).get();
    }
}
```

### Pattern: Spring XML complex bean → CDI Producer
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

---

## PHASE 3 ADDENDUM: XPage Migration

XPage classes require special CDI scope annotations:

### Pattern: XPage with session state → `@SessionScoped`
```java
// BEFORE (v7)
@Controller( xpageName = "myXPage", pageTitleI18nKey = "...", pagePathI18nKey = "..." )
public class MyXPage extends MVCApplication {
    private static MyService _service = SpringContextService.getBean( MyService.BEAN_NAME );
    private ICaptchaSecurityService _captchaSecurityService = new CaptchaSecurityService();
}

// AFTER (v8)
@SessionScoped
@Named( "myplugin.xpage.myXPage" )
@Controller( xpageName = "myXPage", pageTitleI18nKey = "...", pagePathI18nKey = "...", securityTokenEnabled=false )
public class MyXPage extends MVCApplication {
    @Inject
    private MyService _service;
    @Inject
    @Named(BeanUtils.BEAN_CAPTCHA_SERVICE)
    private Instance<ICaptchaService> _captchaService;
    @Inject
    private SecurityTokenService _securityTokenService;
}
```

### Pattern: XPage without session state → `@RequestScoped`
```java
@RequestScoped
@Named( "myplugin.xpage.myOtherXPage" )
@Controller( xpageName = "myOtherXPage", ... )
public class MyOtherXPage extends MVCApplication { ... }
```

### Key XPage migration rules:
1. Add `@SessionScoped` or `@RequestScoped` (choose based on whether the XPage maintains state)
2. Add `@Named("pluginName.xpage.xpageName")` to identify the bean
3. Replace all `SpringContextService.getBean()` with `@Inject`
4. Replace `SecurityTokenService.getInstance()` with `@Inject private SecurityTokenService`
5. Replace `WorkflowService.getInstance()` with `@Inject private WorkflowService`
6. Replace `new CaptchaSecurityService()` with `@Inject @Named(BeanUtils.BEAN_CAPTCHA_SERVICE) Instance<ICaptchaService>`
7. Replace static upload handler access with `@Inject`

---

## PHASE 3 ADDENDUM: EntryType Classes (GenericAttributes-based plugins)

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

---

## PHASE 3 ADDENDUM: CDI Producers with @ConfigProperty

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

---

## PHASE 5 ADDENDUM: Cache Service Class Migration

### Full cache service migration pattern:
```java
// BEFORE (v7)
public class MyCacheService extends AbstractCacheableService implements EventRessourceListener {
    @Override
    public void initCache() {
        super.initCache();
        ResourceEventManager.register(this);
    }
    public void addedResource(ResourceEvent event) { handleEvent(event); }
    public void deletedResource(ResourceEvent event) { handleEvent(event); }
    public void updatedResource(ResourceEvent event) { handleEvent(event); }
}

// AFTER (v8)
@ApplicationScoped
public class MyCacheService extends AbstractCacheableService<String, Object> {
    @PostConstruct
    public void initCache() {
        initCache(CACHE_NAME, String.class, Object.class);
    }
    @Override
    public void put(String key, Object value) { ... }
    @Override
    public Object get(String key) { ... }
    @Override
    public boolean remove(String key) { ... }

    // CDI observer replaces EventRessourceListener
    public void processEvent(@Observes MyEvent event) {
        if (isCacheEnable()) { resetCache(); }
    }
}
```

### Cache method name changes:
| v7 | v8 |
|----|-----|
| `getFromCache(key)` | `get(key)` |
| `putInCache(key, value)` | `put(key, value)` |
| `removeKey(key)` | `remove(key)` |

---

## PHASE 3 ADDENDUM: Business Objects - Serializable

Business objects used in `@SessionScoped` beans or passed through CDI events should implement `Serializable`:

```java
// AFTER (v8)
public class MyBusinessObject implements Cloneable, Serializable {
    private static final long serialVersionUID = 1L;
    // ...
}
```

---

## PHASE 9 ADDENDUM: Plugin XML Changes

### Update plugin descriptor (`plugin.xml` or `pluginName.xml`):
1. Update `<version>` to v8 version
2. Update `<min-core-version>` to `8.0.0`
3. **Remove `<application-class>`** from `<application>` elements — XPages are auto-discovered via CDI
4. Update `<icon-url>` if new icon paths are used

```xml
<!-- BEFORE -->
<application>
    <application-id>myPlugin</application-id>
    <application-class>fr.paris.lutece.plugins.myplugin.web.MyXPage</application-class>
</application>

<!-- AFTER -->
<application>
    <application-id>myPlugin</application-id>
    <!-- No application-class: auto-discovered via CDI -->
</application>
```

---

## PHASE 1 ADDENDUM: Library-specific POM Changes

For **libraries** (not plugins/modules), the `lutece-core` dependency may be **replaced** by `library-core-utils`:
```xml
<!-- REMOVED for libraries -->
<dependency>
    <groupId>fr.paris.lutece</groupId>
    <artifactId>lutece-core</artifactId>
    <type>lutece-core</type>
</dependency>

<!-- ADDED -->
<dependency>
    <groupId>fr.paris.lutece.plugins</groupId>
    <artifactId>library-core-utils</artifactId>
    <version>1.0.0-SNAPSHOT</version>
</dependency>
```

Also update repository URLs from `http://` to `https://`.

---

## PHASE 2 ADDENDUM: Logging Migration

### AppLogService → Log4j2 Logger (in libraries)
```java
// BEFORE (v7)
import fr.paris.lutece.portal.service.util.AppLogService;
AppLogService.error("message", e);

// AFTER (v8)
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
private static Logger _logger = LogManager.getLogger("lutece.application");
_logger.error("message", e);
```

### Log4j 1.x → Log4j 2.x (in tests/older code)
```java
// BEFORE
import org.apache.log4j.Logger;
private Logger _logger = Logger.getLogger(this.getClass());

// AFTER
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
private Logger _logger = LogManager.getLogger(this.getClass());
```

---

## PHASE 6 ADDENDUM: AppPropertiesService → MicroProfile Config (in libraries)

For libraries that don't have CDI injection context, use `ConfigProvider.getConfig()` directly:

```java
// BEFORE (v7)
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

---

## PHASE 4 ADDENDUM: CDI Events with TypeQualifier

For fine-grained event filtering, use `@Type(EventAction.*)` qualifier:

```java
// Firing with qualifier
CDI.current().getBeanManager().getEvent()
    .select(MyEvent.class, new TypeQualifier(EventAction.CREATE))
    .fire(event);

// Observing with qualifier (async)
public void onCreated(@ObservesAsync @Type(EventAction.CREATE) MyEvent event) { ... }
```

| Action | EventAction |
|--------|------------|
| Create | `EventAction.CREATE` |
| Update | `EventAction.UPDATE` |
| Delete | `EventAction.REMOVE` |

---

## PHASE 3 ADDENDUM: JspBean Model Injection

In v8, JspBeans can inject a `Models` helper instead of using `getModel()` or `new HashMap<>()`:

```java
import fr.paris.lutece.portal.web.cdi.mvc.Models;

@RequestScoped
@Named
@Controller(controllerJsp = "Manage.jsp", ..., securityTokenEnabled = true)
public class MyJspBean extends MVCAdminJspBean {
    @Inject
    private Models model;

    @View(value = VIEW_MANAGE, defaultView = true)
    public String getManage(HttpServletRequest request) {
        model.put(MARK_KEY, value);
        // ...
    }
}
```

### Session state removal
JspBeans are `@RequestScoped`, not session-scoped. Pass state via request parameters:
```java
// BEFORE (v7) - session field
private int _nIdTask;

// AFTER (v8) - read from request each time
int nIdTask = NumberUtils.toInt(request.getParameter(PARAMETER_TASK_ID), 0);
```

Use `redirect(request, viewName, mapParameters)` instead of `redirectView(request, viewName)` when parameters must be preserved.

---

## PHASE 11: JSP Migration (if applicable)

```jsp
<!-- BEFORE (v7) -->
<jsp:useBean id="myBean" scope="session"
    class="fr.paris.lutece.plugins.myplugin.web.MyJspBean" />
<% String strContent = myBean.processController(request, response); %>
<%= strContent %>

<!-- AFTER (v8) -->
${ pageContext.setAttribute('strContent',
    myJspBean.processController(pageContext.request, pageContext.response)) }
${ pageContext.getAttribute('strContent') }
```

Rules:
- Remove `<jsp:useBean>` tags
- Use EL expressions with CDI-managed bean name (camelCase of class name or `@Named` value)
- Use `pageContext.request` / `pageContext.response` instead of implicit `request` / `response`

---

## PHASE 12: JspBean (Admin) Migration

JspBean classes need CDI scope and `@Named`:

```java
// BEFORE (v7)
@Controller(controllerJsp = "ManageMyPlugin.jsp", ...)
public class MyPluginJspBean extends MVCAdminJspBean { ... }

// AFTER (v8)
@SessionScoped
@Named
@Controller(controllerJsp = "ManageMyPlugin.jsp", ...)
public class MyPluginJspBean extends MVCAdminJspBean { ... }
```

---

## PHASE 13: Test Migration (JUnit 4 → JUnit 5)

### Annotation changes:
| JUnit 4 | JUnit 5 |
|---------|---------|
| `import org.junit.Test` | `import org.junit.jupiter.api.Test` |
| `import org.junit.Before` | `import org.junit.jupiter.api.BeforeEach` |
| `import org.junit.After` | `import org.junit.jupiter.api.AfterEach` |
| `@Before` | `@BeforeEach` |
| `@After` | `@AfterEach` |
| `@BeforeClass` | `@BeforeAll` |
| `@AfterClass` | `@AfterAll` |

### Assertion parameter order change:
```java
// JUnit 4
assertEquals("Message", expected, actual);
// JUnit 5
assertEquals(expected, actual, "Message");
```

### Mock class renames:
| v7 | v8 |
|----|-----|
| `MokeHttpServletRequest` | `MockHttpServletRequest` |
| `request.addMokeHeader(name, value)` | `request.addHeader(name, value)` |

### Assertion style (JUnit 5):
```java
// v7: static import
import static org.junit.Assert.*;
assertTrue(condition);

// v8: use Assertions class
import org.junit.jupiter.api.Assertions;
Assertions.assertTrue(condition);
```

### CDI Test Extension (for dynamic bean registration in tests):

Create `src/test/resources/META-INF/services/jakarta.enterprise.inject.spi.Extension` listing your test extension class. The extension can dynamically register mock beans:

```java
public class MyTestExtension implements Extension {
    protected void addBeans(@Observes AfterBeanDiscovery abd, BeanManager bm) {
        abd.addBean()
            .beanClass(MockService.class)
            .name("mockBeanName")
            .addTypes(MockService.class, IService.class)
            .addQualifier(NamedLiteral.of("mockBeanName"))
            .scope(ApplicationScoped.class)
            .produceWith(obj -> new MockService());
    }
}
```

---

## PHASE 2 ADDENDUM: JSON Library Migration (if applicable)

If the plugin uses `net.sf.json-lib`, migrate to Jackson (`com.fasterxml.jackson`):

| v7 (json-lib) | v8 (Jackson) |
|---------------|-------------|
| `JSONObject json = new JSONObject()` | `ObjectMapper mapper = new ObjectMapper(); ObjectNode json = mapper.createObjectNode()` |
| `json.element("key", "value")` | `json.put("key", "value")` |
| `json.accumulate("key", obj)` | Build `ArrayNode`, add to it, then `json.set("key", arrayNode)` |
| `JSONSerializer.toJSON(obj)` | `mapper.valueToTree(obj)` |
| `jsonArray.getString(i)` | `jsonArray.get(i).asText()` |
| `json.accumulateAll(other)` | `json.setAll(otherObjectNode)` |

Remove dependency:
```xml
<!-- REMOVE -->
<dependency>
    <groupId>net.sf.json-lib</groupId>
    <artifactId>json-lib</artifactId>
</dependency>
```

---

## PHASE 2 ADDENDUM: MultipartItem.delete() Exception Handling

`MultipartItem.delete()` throws `IOException` (unlike `FileItem.delete()` which was unchecked):

```java
// v7
fileItem.delete();

// v8
try {
    fileItem.delete();
} catch (IOException e) {
    AppLogService.error(e.getMessage(), e);
}
```

---

## PHASE 9 ADDENDUM: Frontend/Template Changes

### Template macro renames (asynchronous upload):
| v7 Macro | v8 Macro |
|---------|---------|
| `addFileInput` | `addFileBOInput` |
| `addUploadedFilesBox` | `addBOUploadedFilesBox` |
| `addFileInputAndfilesBox` | `addFileBOInputAndfilesBox` |

### Skin templates: wrap with `<@cTpl>`:
```html
<!-- v8 -->
<@cTpl>
  <!-- template content -->
</@cTpl>
```

### Use core macros for file uploads:
```html
<@inputDropFiles name=fieldName handler=handler type=type>
    <#nested>
</@inputDropFiles>
```

### Frontend library: jQuery File Upload → Uppy
If the plugin uses jQuery File Upload, it must be replaced by Uppy in v8. Remove all jQuery File Upload JS/CSS files and replace with Uppy integration.

---

## PHASE 3 ADDENDUM: CDI Scope for Spring Prototype Beans

Spring `scope="prototype"` beans become CDI `@Dependent`:

```java
// v7 Spring XML: <bean id="myBean" class="..." scope="prototype" />
// v8:
@Dependent
@Named("myBean")
public class MyBean { ... }
```

---

## PHASE 3 ADDENDUM: Transaction Annotation Simplification

```java
// BEFORE (v7)
@Transactional(MyPlugin.BEAN_TRANSACTION_MANAGER)

// AFTER (v8) - no transaction manager reference
@Transactional
```

Import change: `org.springframework.transaction.annotation.Transactional` → `jakarta.transaction.Transactional`

---

## PHASE 3 ADDENDUM: Constructor Injection Pattern (Workflow Tasks/Components)

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

---

## PHASE 3 ADDENDUM: TaskType Producer Pattern (Workflow modules)

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

---

## PHASE 3 ADDENDUM: CDI Impl Classes for Abstract Library Services

When a library provides abstract service classes (e.g., `ActionService` from `library-workflow-core`), create empty CDI implementation classes:

```java
@ApplicationScoped
@Named(ActionService.BEAN_SERVICE)
public class ActionServiceImpl extends ActionService {
    // Empty - provides CDI annotations for parent abstract class
}
```

This is needed because CDI cannot proxy abstract classes without a concrete subclass.

---

## PHASE 3 ADDENDUM: Default Constructor for CDI Proxies

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

---

## PHASE 3 ADDENDUM: DAOUtil try-with-resources

Replace manual `daoUtil.free()` with try-with-resources:

```java
// BEFORE (v7)
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

---

## PHASE 3 ADDENDUM: RBAC User Cast

v8 requires explicit `(User)` cast for RBAC calls:
```java
// BEFORE (v7)
RBACService.isAuthorized(resource, permission, adminUser)

// AFTER (v8)
RBACService.isAuthorized(resource, permission, (User) adminUser)
```

---

## PHASE 10 ADDENDUM: SQL Migration

### Liquibase headers for SQL scripts
All SQL scripts must start with liquibase headers:
```sql
-- liquibase formatted sql
-- changeset pluginName:script_name.sql
-- preconditions onFail:MARK_RAN onError:WARN
```

### Upgrade scripts
Create upgrade SQL scripts: `update_db_pluginName-oldVersion-newVersion.sql`

---

## PHASE 3 ADDENDUM: Async Processing Migration

Replace `CompletableFuture.runAsync()` with Jakarta `@Asynchronous`:

```java
// BEFORE (v7)
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

---

## PHASE 3 ADDENDUM: CdiHelper for Programmatic Lookup

Use `CdiHelper.getReference()` for programmatic CDI lookup with qualifiers in producers:

```java
CdiHelper.getReference(IMyService.class, "namedBeanName");
```

---

## PHASE 3 ADDENDUM: Spring InitializingBean → @PostConstruct

Replace Spring's `InitializingBean.afterPropertiesSet()` with Jakarta `@PostConstruct`:

```java
// BEFORE (v7)
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

---

## PHASE 3 ADDENDUM: Workflow Task Signature Changes

If implementing `ITask.processTaskWithResult()`, update to the new signature:

```java
// BEFORE (v7)
boolean processTaskWithResult(int nIdResourceHistory, HttpServletRequest request, Locale locale, User user);

// AFTER (v8) - includes resource info
boolean processTaskWithResult(int nIdResource, String strResourceType, int nIdResourceHistory,
    HttpServletRequest request, Locale locale, User user);
```

Similarly for `AsynchronousSimpleTask.processAsynchronousTask()`.

---

## PHASE 14: Logging Migration

Update string concatenation to parameterized logging:

```java
// BEFORE (v7)
AppLogService.info(MyClass.class.getName() + " : message " + variable);

// AFTER (v8)
AppLogService.info("{} : message {}", MyClass.class.getName(), variable);
```

---

## KEY IMPORTS REFERENCE

```java
// CDI Core
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.context.RequestScoped;
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
import jakarta.enterprise.context.Initialized;
import jakarta.annotation.Priority;

// Lifecycle
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;

// Servlet
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

// REST
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;

// Validation
import jakarta.validation.ConstraintViolation;

// Config
import org.eclipse.microprofile.config.inject.ConfigProperty;

// Cache
import javax.cache.Cache; // NOTE: javax, NOT jakarta
```
