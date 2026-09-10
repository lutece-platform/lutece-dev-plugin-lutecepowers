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

The bean extends `MVCAdminJspBean` with `@Named`, `@Controller` and a CDI scope:
- `@SessionScoped` — if the bean stores per-user state as instance fields (working objects like `_task`, filters). This is the typical case for CRUD beans. Note: with `@Inject @Pager IPager` (§5), pagination state is managed automatically — no manual `_strCurrentPageIndex`/`_nItemsPerPage` fields needed.
- `@RequestScoped` — if the bean is stateless (no session instance fields, e.g., dashboard, simple actions).

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

**Action method structure** (every `do*` follows this exact order):

```java
public String doCreateTask(HttpServletRequest request) throws AccessDeniedException {
    // 1. CSRF token validation
    if (!getSecurityTokenService().validate(request, ACTION_CREATE_TASK)) {
        throw new AccessDeniedException(ERROR_INVALID_TOKEN);
    }

    // 2. Populate bean from request
    Task task = new Task();
    populate(task, request);

    // 3. Validate (Jakarta Bean Validation)
    Set<ConstraintViolation<Task>> errors = validate(task);
    if (!errors.isEmpty()) {
        return redirect(request, VIEW_CREATE_TASK);
    }

    // 4. Business logic
    TaskHome.create(task);

    // 5. Redirect to list
    return redirectView(request, VIEW_MANAGE_TASKS);
}
```

**View method structure** (every `get*` for forms) — uses `@Inject Models`, NOT `getModel()`:

```java
import fr.paris.lutece.portal.web.cdi.mvc.Models;

@Inject
private Models _models;

public String getCreateTask(HttpServletRequest request) {
    _models.put(MARK_TASK, new Task());
    _models.put(SecurityTokenService.MARK_TOKEN,
        getSecurityTokenService().getToken(request, ACTION_CREATE_TASK));

    return getPage(PROPERTY_PAGE_TITLE_CREATE_TASK, TEMPLATE_CREATE_TASK);
}
```

**IMPORTANT:** `getModel()` is deprecated. `_models.asMap()` returns an **unmodifiable map** — never pass it to a method that calls `put()`. Helper methods must accept `Models` directly.

## 5. Pagination (List views) — `@Inject @Pager IPager` + `paginationAjax`

Use CDI-injected `IPager` instead of manual `LocalizedPaginator`. The `@Pager` qualifier configures the paginator via annotation attributes. `PaginatorHandler` (session-scoped) manages pagination state automatically.

**Default approach: `paginationAjax`** — AJAX-driven table with JSON endpoint. The macro handles table rendering, sorting, pagination controls, and action buttons automatically.

### JspBean — Pager injection + JSON endpoint

```java
@Inject
@Pager( name = "taskList", listBookmark = "task_list",
        defaultItemsPerPage = "myplugin.task.itemsPerPage",
        baseUrl = "jsp/admin/plugins/myplugin/ManageTasks.jsp" )
private IPager<Task, Task> _pager;

@View( value = VIEW_MANAGE, defaultView = true )
public String getManageTasks( HttpServletRequest request )
{
    List<Task> listTasks = TaskHome.findAll();

    _pager.withListItem( listTasks )
          .populateModels( request, _models, getLocale() );
    // _models now contains: "task_list" (page items), "paginator", "nb_items_per_page"

    return getPage( PROPERTY_PAGE_TITLE_MANAGE, TEMPLATE_MANAGE_TASKS );
}

// JSON endpoint for AJAX pagination — called by the paginationAjax macro
@Action( value = ACTION_GET_ITEMS )
@ResponseBody
public List<Task> getTaskItems( @RequestParam( "page" ) int numPage )
{
    return _pager.getPaginator( ).get( ).getPageItems( numPage );
}
```

**Requires imports:**
- `fr.paris.lutece.portal.web.util.Pager` (annotation)
- `fr.paris.lutece.portal.web.util.IPager` (interface)
- `fr.paris.lutece.portal.util.mvc.commons.annotations.ResponseBody`
- `fr.paris.lutece.portal.util.mvc.commons.annotations.RequestParam`

### Template — `paginationAjax` macro

```html
<#assign taskColumns = [
  {"name": "#i18n{myplugin.model.entity.task.attribute.title}", "property": "title", "sortable": true},
  {"name": "#i18n{myplugin.model.entity.task.attribute.completed}", "property": "completed", "sortable": false}
]>
<#assign taskActions = {
  "edit": {
    "url": "jsp/admin/plugins/myplugin/ManageTasks.jsp?view=modifyTask&id={idTask}",
    "icon": "edit",
    "title": "#i18n{portal.util.labelModify}",
    "btnClass": "btn-primary btn-sm"
  },
  "delete": {
    "url": "jsp/admin/plugins/myplugin/ManageTasks.jsp?action=confirmRemoveTask&id={idTask}",
    "icon": "trash",
    "title": "#i18n{portal.util.labelDelete}",
    "btnClass": "btn-danger btn-sm",
    "confirm": "false"
  }
}>
<@paginationAjax paginator=paginator columns=taskColumns
    ajaxUrl='jsp/admin/plugins/myplugin/ManageTasks.jsp?action=getTaskItems'
    tableId='taskTable'
    combo=1 showcount=1
    actions=taskActions />
```

**Key points:**
- `columns`: array of `{name, property, sortable}` — `property` matches the entity's JSON bean property name
- `actions`: object with `edit` / `delete` keys — URL placeholders `{property}` are replaced by JS from the JSON data
- `ajaxUrl`: points to the `@Action @ResponseBody` endpoint
- The macro renders the complete table card with pagination controls, sorting, and action buttons

### With delegate (lazy loading from IDs)

```java
@Inject
@Pager( name = "taskList", listBookmark = "task_list",
        defaultItemsPerPage = "myplugin.task.itemsPerPage",
        baseUrl = "jsp/admin/plugins/myplugin/ManageTasks.jsp" )
private IPager<Integer, Task> _pager;

public String getManageTasks( HttpServletRequest request )
{
    List<Integer> listIds = TaskHome.findAllIds();

    _pager.withIdList( listIds )
          .populateModels( request, _models,
              ids -> TaskHome.findByIds( ids ),  // delegate: load only current page
              getLocale() );

    return getPage( PROPERTY_PAGE_TITLE_MANAGE, TEMPLATE_MANAGE_TASKS );
}
```

### Fallback: `paginationAdmin` (manual table)

Use `paginationAdmin` only when `paginationAjax` is not suitable (e.g., workflow state columns, child entity navigation buttons, or other per-row dynamic content that isn't part of the entity JSON):
```html
<@paginationAdmin paginator=paginator nb_items_per_page=nb_items_per_page />
```

**`@Pager` annotation attributes:**
| Attribute | Description |
|-----------|-------------|
| `name` | Unique name for session state (default: declaring class name) |
| `listBookmark` | Model key for the page items list (e.g., `"task_list"`) |
| `defaultItemsPerPage` | Property key or literal value (default: `"50"`) |
| `baseUrl` | JSP URL for pagination links |

## 6. XPage (Front-office)

```java
@RequestScoped
@Named("myplugin.xpage.tasks")
public class TasksApp extends AbstractXPageApplication {
    @Inject
    private TaskService _taskService;

    @Override
    public XPage getPage(HttpServletRequest request, int nMode, Plugin plugin) {
        XPage page = new XPage();
        page.setTitle(I18nService.getLocalizedString(PROPERTY_PAGE_TITLE, request.getLocale()));
        page.setContent(getTaskList(request));
        return page;
    }
}
```

**Rules**: `@RequestScoped`. Implements `XPageApplication`. Declared in plugin.xml `<applications>`.

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

Configuration via properties: `daemon.taskCleanup.interval=3600`, `daemon.taskCleanup.onstartup=0`.
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
| Config property | `@Inject @ConfigProperty(name = "my.key", defaultValue = "x")` |

## 9. Configuration Access

```java
// Properties (static, from .properties files)
String val = AppPropertiesService.getProperty("myplugin.my.key");
int n = AppPropertiesService.getPropertyInt("myplugin.items.per.page", 50);

// Datastore (runtime, from database — overrides properties)
String ds = DatastoreService.getInstanceDataValue("myplugin.setting", "default");
DatastoreService.setInstanceDataValue("myplugin.setting", "newValue");

// In Freemarker templates
// #{dskey{myplugin.setting}}
```

## 10. Security Checklist

Every admin feature MUST:
1. Call `init(request, RIGHT_MANAGE_TASKS)` to check the user right
2. Include `SecurityTokenService.MARK_TOKEN` in every form model
3. Validate `getSecurityTokenService().validate(request, ACTION)` in every `do*` method
4. Filter collections with `RBACService.getAuthorizedCollection()` when RBAC is enabled
5. Filter by workgroup with `AdminWorkgroupService.getAuthorizedCollection()` when needed
