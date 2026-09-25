---
name: lutece-patterns
description: "Use before writing or reviewing any Lutece 8 code (CRUD, JspBean, XPage, service, DAO, daemon, template) and when answering questions about Lutece 8 architecture, layered design or coding conventions. Canonical patterns extracted from lutece-core."
---

# Lutece 8 — Architecture Patterns

Reference patterns extracted from `~/.lutece-references/lutece-core/`. Use these as the canonical way to write Lutece 8 code.

## Layered Architecture

Every Lutece feature follows 5 layers, top to bottom. Never skip a layer.

```
JspBean / XPage          ← web layer (request handling, validation, templates)
    ↓
Service                  ← business logic, cross-cutting concerns
    ↓
Home                     ← static facade (CDI lookup of DAO, cache coordination)
    ↓
DAO                      ← data access (DAOUtil, SQL, try-with-resources)
    ↓
Entity                   ← POJO (fields, getters/setters, interfaces)
```

## 1. Entity

```java
public class Task implements Serializable {
    private static final long serialVersionUID = 1L;

    private int _nIdTask;
    private String _strTitle;
    private boolean _bCompleted;
    private Timestamp _dateCreation;

    // Getters/setters only. No logic. No annotations except validation.
}
```

**Field prefixes**: `_str` (String), `_n` (int), `_b` (boolean), `_date` (Timestamp), `_list` (Collection).

**Interfaces to implement when needed**:
- `RBACResource` → RBAC permissions (`getResourceTypeCode()`, `getResourceId()`)
- `AdminWorkgroupResource` → workgroup filtering
- `IExtendableResource` → resource extension system

## 2. DAO

```java
@ApplicationScoped
public final class TaskDAO implements ITaskDAO {
    private static final String SQL_QUERY_SELECTALL = "SELECT id_task, title, completed FROM myplugin_task";
    private static final String SQL_QUERY_SELECT     = SQL_QUERY_SELECTALL + " WHERE id_task = ?";
    private static final String SQL_QUERY_INSERT     = "INSERT INTO myplugin_task ( title, completed ) VALUES ( ?, ? )";
    private static final String SQL_QUERY_UPDATE     = "UPDATE myplugin_task SET title = ?, completed = ? WHERE id_task = ?";
    private static final String SQL_QUERY_DELETE     = "DELETE FROM myplugin_task WHERE id_task = ?";

    @Override
    public void insert(Task task, Plugin plugin) {
        try (DAOUtil daoUtil = new DAOUtil(SQL_QUERY_INSERT, Statement.RETURN_GENERATED_KEYS, plugin)) {
            int nIndex = 1;
            daoUtil.setString(nIndex++, task.getTitle());
            daoUtil.setBoolean(nIndex++, task.isCompleted());
            daoUtil.executeUpdate();

            if (daoUtil.nextGeneratedKey()) {
                task.setIdTask(daoUtil.getGeneratedKeyInt(1));
            }
        }
    }

    @Override
    public Task load(int nId, Plugin plugin) {
        Task task = null;
        try (DAOUtil daoUtil = new DAOUtil(SQL_QUERY_SELECT, plugin)) {
            daoUtil.setInt(1, nId);
            daoUtil.executeQuery();

            if (daoUtil.next()) {
                task = dataToObject(daoUtil);
            }
        }
        return task;
    }

    private Task dataToObject(DAOUtil daoUtil) {
        int nIndex = 1;
        Task task = new Task();
        task.setIdTask(daoUtil.getInt(nIndex++));
        task.setTitle(daoUtil.getString(nIndex++));
        task.setCompleted(daoUtil.getBoolean(nIndex++));
        return task;
    }
}
```

**Rules**: `@ApplicationScoped`. Always try-with-resources. `nIndex++` for parameter binding. Extract `dataToObject()` to avoid duplication between `load()` and `selectAll()`.

## 3. Home (Static Facade)

```java
public final class TaskHome {
    private static ITaskDAO _dao = CDI.current().select(ITaskDAO.class).get();
    private static Plugin _plugin = PluginService.getPlugin("myplugin");

    private TaskHome() {}

    public static Task create(Task task) {
        _dao.insert(task, _plugin);
        return task;
    }

    public static Task findByPrimaryKey(int nId) {
        return _dao.load(nId, _plugin);
    }

    public static void update(Task task) {
        _dao.store(task, _plugin);
    }

    public static void remove(int nId) {
        _dao.delete(nId, _plugin);
    }

    public static List<Task> findAll() {
        return _dao.selectAll(_plugin);
    }
}
```

**Rules**: Private constructor. All methods static. CDI lookup for DAO. Plugin reference via `PluginService.getPlugin()`.

## 4. JspBean — CRUD Lifecycle

The bean extends `MVCAdminJspBean` with a CDI scope, `@Named` and a complete `@Controller`:

```java
@SessionScoped
@Named
@Controller( controllerJsp = "ManageTasks.jsp", controllerPath = "jsp/admin/plugins/myplugin/",
             right = "MYPLUGIN_MANAGEMENT", securityTokenEnabled = true )
public class TaskJspBean extends MVCAdminJspBean
```

- `@SessionScoped` when the bean keeps per-user state in instance fields (working object, filter, multi-step context). `@RequestScoped` when it is stateless. Pagination is not session state anymore: `@Inject @Pager IPager` (§5) keeps it for you.
- `controllerJsp`, `controllerPath` and `right` are mandatory (the core calls `init( request, right )` itself). `securityTokenEnabled = true` is the CSRF policy: the core injects the token in every form of the rendered page and validates every `@Action` POST. No `MARK_TOKEN`, no `validate()` in the bean (`rules/web-bean.md`).

**Method naming convention — strict**:

| Method | Role | HTTP | Returns |
|---|---|---|---|
| `getManageTasks()` | List view | GET | HTML (template) |
| `getCreateTask()` | Create form | GET | HTML (template) |
| `doCreateTask()` | Create action | POST | Redirect URL |
| `getModifyTask()` | Edit form | GET | HTML (template) |
| `doModifyTask()` | Edit action | POST | Redirect URL |
| `getConfirmRemoveTask()` | Confirmation dialog | GET | AdminMessage URL |
| `doRemoveTask()` | Delete action | POST | Redirect URL |

View and action constants share the same value for one form (`VIEW_CREATE_TASK = ACTION_CREATE_TASK = "createTask"`), so the token generated by the view matches its action. A confirmation view declares the action it protects: `@View( value = VIEW_CONFIRM_REMOVE_TASK, securityTokenAction = ACTION_REMOVE_TASK )`.

**View method** — `Models` as a parameter, never `getModel()`:

```java
@View( value = VIEW_CREATE_TASK )
public String getCreateTask( Models model )
{
    model.put( MARK_TASK, new Task( ) );
    return getPage( PROPERTY_PAGE_TITLE_CREATE_TASK, TEMPLATE_CREATE_TASK, model );
}
```

**Action method** — binding and validation by the framework (`@Valid @ModelAttribute` + `BindingResult`), business call, redirect:

```java
@Action( value = ACTION_CREATE_TASK )
public String doCreateTask( @Valid @ModelAttribute Task task, BindingResult bindingResult, Models model, HttpServletRequest request )
{
    if ( bindingResult.isFailed( ) )
    {
        model.put( MVCUtils.MARK_ERRORS, bindingResult.getAllErrors( ) );
        return getCreateTask( model );
    }
    TaskHome.create( task );
    addInfo( INFO_TASK_CREATED, getLocale( ) );
    return redirectView( request, VIEW_MANAGE_TASKS );
}
```

`BindingResult` (`fr.paris.lutece.portal.util.mvc.binding`): `isFailed()`, `getAllErrors()`, `getAllMessages()`, `getBindingErrors()`, `getValidationErrors()`; each `ParamError` has `getParamName()` and `getMessage()`. `redirectView( request, VIEW )` targets a view of this controller; `redirect( request, url )` takes a raw URL such as an `AdminMessageService.getMessageUrl(...)`. Reference: xmltransformer `StylesJspBean`, forms `FormJspBean`.

**IMPORTANT:** `getModel()` is deprecated. `models.asMap()` returns an **unmodifiable map**: never pass it to a method that calls `put()`; helper methods accept `Models` directly.

## 5. Pagination (List views) — `@Inject @Pager IPager` + `@paginationAdmin`

Inject an `IPager` instead of building a `LocalizedPaginator` by hand. `@Pager` configures it; a session-scoped handler keeps the page index and page size across requests. This is the pattern of the reference JspBeans. Reference: `lutece-cms-plugin-xmltransformer/src/java/fr/paris/lutece/portal/web/style/StylesJspBean.java` (`IPager<Style, Void>`, `withListItem`), `lutece-core/src/java/fr/paris/lutece/portal/web/style/PortletTemplateJspBean.java` (`withIdList`).

### JspBean

```java
@Inject
@Pager( listBookmark = "task_list", defaultItemsPerPage = "myplugin.task.itemsPerPage",
        baseUrl = "jsp/admin/plugins/myplugin/ManageTasks.jsp" )
private IPager<Task, Void> _pager;

@View( value = VIEW_MANAGE_TASKS, defaultView = true )
public String getManageTasks( HttpServletRequest request, Models model )
{
    _pager.withListItem( TaskHome.findAll( ) )
          .populateModels( request, model, getLocale( ) );
    return getPage( PROPERTY_PAGE_TITLE_MANAGE, TEMPLATE_MANAGE_TASKS, model );
}
```

`populateModels` puts three keys in the model: the list bookmark (`task_list`, current page items), `paginator` and `nb_items_per_page`.

### Lazy loading from IDs (large lists)

```java
private IPager<Integer, Task> _pager;

_pager.withIdList( TaskHome.findAllIds( filter ) )
      .populateModels( request, model, TaskHome::findByIds, getLocale( ) );
```

Only the current page is loaded. Refresh the ID list when the filter changes, keep it otherwise (appointment does this with a `bRefreshIds` test on the request parameters).

`IPager` API (`fr.paris.lutece.portal.web.util.IPager`): `withBaseUrl`, `withItemsPerPage`, `withIdList`, `withListItem`, `populateModels(request, models, locale)`, `populateModels(request, models, delegate, locale)`, `getPaginator()`.

### Template

```html
<#if task_list?has_content>
  <@manageFeature>
    <#list task_list as task>
      <@manageFeatureItem>
        <@manageFeatureItemColumn>
          <strong>${task.title!}</strong>
        </@manageFeatureItemColumn>
        <@manageFeatureItemColumn align='end'>
          <@aButton href='jsp/admin/plugins/myplugin/ManageTasks.jsp?view=modifyTask&id=${task.idTask}' buttonIcon='pencil' title='#i18n{portal.util.labelModify}' hideTitle=['all'] size='sm' />
          <@aButton href='jsp/admin/plugins/myplugin/ManageTasks.jsp?view=confirmRemoveTask&id=${task.idTask}' buttonIcon='trash' title='#i18n{portal.util.labelDelete}' hideTitle=['all'] color='danger' size='sm' />
        </@manageFeatureItemColumn>
      </@manageFeatureItem>
    </#list>
  </@manageFeature>
  <@paginationAdmin paginator=paginator combo=1 />
<#else>
  <@empty />
</#if>
```

`@paginationAdmin paginator class combo form nb_items_per_page showcount showall` is what every reference template uses. The core also ships `@paginationAjax paginator columns ajaxUrl tableId combo showcount actions` with a JSON endpoint (`@Action @ResponseBody` + `@RequestParam`, `fr.paris.lutece.portal.util.mvc.commons.annotations`); no reference template uses it, so treat it as an option, not the default. For the list layout (`@manageFeature` versus `@table`) see `rules/template-back-office.md`.

**`@Pager` attributes** (`fr.paris.lutece.portal.web.util.Pager`): `name` (default: the declaring class name, `PagerProducer`), `listBookmark` (default `item_list`), `defaultItemsPerPage` (property key or literal, default `50`), `baseUrl`.

## 6. XPage (Front-office)

A v8 XPage is a CDI MVC bean. The descriptor declares only the id; there is no `<application-class>` (the core resolves the bean `<plugin>.xpage.<id>`, and falls back to reflection only when the class tag is present).

```java
@SessionScoped
@Named( "myplugin.xpage.tasks" )
@Controller( xpageName = TasksXPage.XPAGE_NAME, pageTitleI18nKey = "myplugin.xpage.tasks.pageTitle",
             pagePathI18nKey = "myplugin.xpage.tasks.pagePathLabel", securityTokenEnabled = true )
public class TasksXPage extends MVCApplication
{
    protected static final String XPAGE_NAME = "tasks";
    private static final String VIEW_LIST = "listTasks";

    @Inject
    private TaskService _taskService;

    @View( value = VIEW_LIST, defaultView = true )
    public XPage getListTasks( HttpServletRequest request, Models model )
    {
        model.put( MARK_TASK_LIST, _taskService.findAll( ) );
        return getXPage( TEMPLATE_LIST_TASKS, getLocale( request ), model );
    }
}
```

```xml
<applications>
    <application>
        <application-id>tasks</application-id>
    </application>
</applications>
```

**Rules**: `@SessionScoped` when the page keeps state across steps (multi-step forms), `@RequestScoped` otherwise. Views and actions follow the JspBean conventions (`@View`, `@Action`, CSRF policy, `Models`): see `rules/web-bean.md`. Reference: forms `FormXPage`.

## 7. Daemon (Background task)

```java
public class TaskCleanupDaemon extends Daemon {
    @Override
    public void run() {
        int nCleaned = TaskHome.removeExpired();
        setLastRunLogs("Cleaned " + nCleaned + " expired tasks");
    }
}
```

Declared in plugin.xml:
```xml
<daemons>
    <daemon>
        <daemon-id>taskCleanup</daemon-id>
        <daemon-name>myplugin.daemon.taskCleanup.name</daemon-name>
        <daemon-description>myplugin.daemon.taskCleanup.description</daemon-description>
        <daemon-class>fr.paris.lutece.plugins.myplugin.daemon.TaskCleanupDaemon</daemon-class>
    </daemon>
</daemons>
```

Instantiated by the core through `Class.forName` (`DaemonEntry`): no CDI scope on the class, dependencies through `CDI.current().select(...)`.
Configuration via properties (seconds): `daemon.taskCleanup.interval=3600`, `daemon.taskCleanup.onstartup=0`. There is no interval tag in `plugin.xml`.
Signal on demand: `AppDaemonService.signalDaemon("taskCleanup")`.

## 8. CDI Patterns — Quick Reference

| Need | Pattern |
|---|---|
| Singleton service | `@ApplicationScoped` on class |
| Per-request bean | `@RequestScoped` on class |
| Stateful admin bean (pagination, working objects) | `@SessionScoped @Named` on class |
| Stateless admin bean (no session fields) | `@RequestScoped @Named` on class |
| Field injection | `@Inject private MyService _service;` |
| Static lookup (Home) | `CDI.current().select(IMyDAO.class).get()` |
| Multiple implementations | `CDI.current().select(IProvider.class)` → `.stream().filter(...)` |
| Fire event (sync) | `CDI.current().getBeanManager().getEvent().fire(new MyEvent(...))` |
| Fire event (async) | `CDI.current().getBeanManager().getEvent().fireAsync(new MyEvent(...))` |
| Fire with qualifier | `.select(new TypeQualifier(EventAction.CREATE)).fire(event)` or `.fireAsync(event)` |
| Observe sync | `public void onEvent(@Observes MyEvent event) { }` |
| Observe async | `public void onEvent(@ObservesAsync MyEvent event) { }` |
| Core resource events | `fr.paris.lutece.portal.business.event.ResourceEvent`, accessors `getIdResource()` / `getTypeResource()` |
| Config property | `@Inject @ConfigProperty(name = "my.key", defaultValue = "x")` |

## 9. Configuration Access

```java
// Properties (static, from .properties files)
String val = AppPropertiesService.getProperty("myplugin.my.key");
int n = AppPropertiesService.getPropertyInt("myplugin.items.per.page", 50);

// Datastore: database key-value store read explicitly. Not a ConfigSource, does not override properties (see rules/service-layer.md)
String ds = DatastoreService.getInstanceDataValue("myplugin.setting", "default");
DatastoreService.setInstanceDataValue("myplugin.setting", "newValue");

// In Freemarker templates
// #dskey{myplugin.setting}
```

## 10. Security Checklist

Every admin feature MUST:
1. Declare the right in `@Controller( right = ... )`: the core checks it in `processController` (no `init()` call in the bean or the JSP)
2. Set `securityTokenEnabled = true` on `@Controller`: the core injects the CSRF token in every form and validates every `@Action` POST (`rules/web-bean.md`)
3. Declare `securityTokenAction` on confirmation views so the AdminMessage confirm button carries the token of the protected action
4. Filter collections with `RBACService.getAuthorizedCollection()` when RBAC is enabled
5. Filter by workgroup with `AdminWorkgroupService.getAuthorizedCollection()` when needed
