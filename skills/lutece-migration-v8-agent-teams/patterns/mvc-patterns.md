# MVC Patterns — Lutece v8

> Canonical rules: `rules/web-bean.md` (@Controller attributes, Models, CSRF policy, CRUD lifecycle). This file only shows the rewrites to v8.
> Core sources: `~/.lutece-references/lutece-core/src/java/fr/paris/lutece/portal/util/mvc/` (`commons/annotations/*`, `binding/BindingResult.java`, `binding/ParamError.java`, `admin/MVCAdminJspBean.java`, `xpage/MVCApplication.java`).

## 1. @RequestParam

Binds query parameters directly to method parameters.

### Before (pre-v8)
```java
String strName = request.getParameter("name");
int nPage = Integer.parseInt(request.getParameter("page"));
```

### After (v8)
```java
@View(VIEW_LIST)
public String getList(@RequestParam(value = "page", defaultValue = "1") int nPage,
                      @RequestParam(value = "query", defaultValue = "") String strQuery,
                      Models model) {
    return getPage(PROPERTY_PAGE_TITLE, TEMPLATE_LIST);
}
```

## 2. @RequestHeader / @CookieValue

```java
@View(VIEW_LIST)
public String getList(@RequestHeader(value = "Accept-Language") String strLang,
                      @CookieValue(value = "sessionId", defaultValue = "") String strSession) {
}
```

## 3. @ModelAttribute + BindingResult

Auto-binds request parameters to a Java bean. `BindingResult` must be the parameter right after the bound bean. Reference: xmltransformer `StylesJspBean.doCreateStyle`.

```java
@Action(ACTION_CREATE)
public String doCreate(@Valid @ModelAttribute MyItem item, BindingResult bindingResult,
                       Models model, HttpServletRequest request) {
    if (bindingResult.isFailed()) {
        model.put(MVCUtils.MARK_ERRORS, bindingResult.getAllErrors());
        return getCreate(model, request);
    }
    MyItemHome.create(item);
    return redirectView(request, VIEW_LIST);
}
```

`BindingResult` API: `isFailed()`, `getAllMessages()` (`List<String>`), `getAllErrors()` (`Set<ParamError>`), `getBindingErrors()`, `getValidationErrors()`, `getErrors(param)`. `ParamError`: `getMessage()`, `getParamName()`. There is no `hasErrors()` nor `getDefaultMessage()`.

## 4. @Validated + BindingResult

Bean validation with groups.

```java
@Action(ACTION_CREATE)
public String doCreate(@Validated({ValidationGroups.Creation.class}) @ModelAttribute MyItem item,
                       BindingResult bindingResult, HttpServletRequest request) {
    if (bindingResult.isFailed()) {
        bindingResult.getAllMessages().forEach(this::addError);
        return redirectView(request, VIEW_CREATE);
    }
    MyItemHome.create(item);
    return redirectView(request, VIEW_LIST);
}
```

## 5. @ResponseBody

Return JSON/XML directly from a method (no template rendering).

```java
@Action("getData")
@ResponseBody
public List<MyItem> getData(@RequestParam("page") int nPage) {
    return MyItemHome.getItemsList(nPage, ITEMS_PER_PAGE);
}
```

Used for AJAX pagination with the `paginationAjax` macro — see `/lutece-patterns` §5 for the macro and the JSON endpoint. GET requests are never filtered by the CSRF filter; add `securityTokenDisabled = true` only if the endpoint is called by POST without a form token.

## 6. @RequestBody

Bind HTTP body (JSON/XML) to a Java object.

```java
@Action(ACTION_API_CREATE)
public String doApiCreate(@RequestBody MyItem item, HttpServletRequest request) {
    MyItemHome.create(item);
    return redirectView(request, VIEW_LIST);
}
```

## 7. CSRF — `securityTokenEnabled = true`

Policy and mechanism: `rules/web-bean.md` § CSRF Policy. Migration steps for a `@Controller` bean:

1. Add `securityTokenEnabled = true` to `@Controller`.
2. Remove `SecurityTokenService.MARK_TOKEN` puts, `getSecurityTokenService().getToken()/validate()`, `_securityTokenService` injection and `SecurityTokenService.getInstance()`.
3. Make sure each form view and its action share the same constant value (`VIEW_CREATE = ACTION_CREATE = "createItem"`), or set `@View(securityTokenAction = ACTION_X)`.
4. Confirm dialogs: `@View(value = VIEW_CONFIRM_REMOVE, securityTokenAction = ACTION_REMOVE)` redirecting to `AdminMessageService.getMessageUrl(..., TYPE_CONFIRMATION)`; the remove `@Action` needs nothing.
5. POST actions that cannot carry a form token (external clients, imports validated otherwise): `@Action(value = ACTION_X, securityTokenDisabled = true)`. GET requests are never filtered.
6. Templates: remove `<input type="hidden" name="token" ...>`; the core injects `_csrftoken` into every `<form>`.

Non-MVC beans (no `@Controller`, portlets): keep `getSecurityTokenService().getToken()/validate()` (inherited accessor), never `SecurityTokenService.getInstance()`.

## 8. MultipartItem for File Upload

See `fileupload-patterns.md` for complete migration guide.

## 9. Pagination

`@Inject @Pager IPager` and the `paginationAdmin` / `paginationAjax` macros: `/lutece-patterns` §5 (single source). List layout choice (`@manageFeature` vs `@table`): `rules/template-back-office.md`.

## 10. XSL portlet → HTML portlet (MANDATORY, no exception)

**Any portlet still rendered by XSL must be ported to HTML during the migration.** This is not
a choice between two options: an XSL
portlet whose type does not start with `DOCUMENT` **cannot be created or modified from the back
office at all**. `create_portlet.html` and `modify_portlet.html` render the style select under
`<#if portletType.id?starts_with('DOCUMENT')>`, so no `style` parameter is posted, and
`PortletJspBean.setPortletCommonData` returns `MANDATORY_FIELDS` for any XSL portlet without a
style. The `return` sits outside the `if` that looks for the xmltransformer plugin, so
installing that plugin changes nothing but a log line.

Depending on `plugin-xmltransformer` is a stopgap for an existing install, never the migration
target. The port is four moves:

**1. Extend the core base class.** `PortletHtmlContent` forces the HTML path: it makes
`getHtmlContent` abstract, neutralises `getXml`/`getXmlDocument` (both return `null`) and
returns `false` from `isContentGeneratedByXmlAndXsl()`. Never override that method by hand.
Build the model with `createPortletModel( )` (the portlet, its id, its device display classes, its
name when the title is shown) and render with `renderTemplate( request, TEMPLATE_DEFAULT, model )`:
it applies the template chosen for the portlet in the back office, and the default template of the
type otherwise.

```java
// Before
public class MyPortlet extends Portlet
{
    public String getXml( HttpServletRequest request ) { StringBuffer b = new StringBuffer( ); … }
    public String getXmlDocument( HttpServletRequest request ) { return XmlUtil.getXmlHeader( ) + getXml( request ); }
}
// After
public class MyPortlet extends PortletHtmlContent
{
    private static final String TEMPLATE_DEFAULT = "skin/plugins/myplugin/portlet/my_portlet.html";

    @Override
    public String getHtmlContent( HttpServletRequest request )
    {
        Map<String, Object> model = createPortletModel( );
        model.put( MARK_ITEMS, MyPortletHome.getItems( getId( ) ) );
        return renderTemplate( request, TEMPLATE_DEFAULT, model );
    }
}
```

**2. Write the skin template**, one per XSL it replaces, under
`webapp/WEB-INF/templates/skin/plugins/<plugin>/portlet/`. Reference: an HTML portlet template of a
migrated plugin under `~/.lutece-references/` (`find ~/.lutece-references -path '*templates/skin/*portlet*'`).
Port the XSL structure, do not invent a new markup: the XSL is the specification of what the
page looked like.

**3. Delete the XSL and its rows.** Remove `webapp/WEB-INF/xsl/**` for that portlet and every
`INSERT INTO core_style`, `core_style_mode_stylesheet` and `core_stylesheet` from
`src/sql/**`. Those tables left the core, so the inserts fail at install time anyway.

**4. Drop the xmltransformer dependency** if it was only there for this portlet.

What the port also fixes: the style column of `core_portlet` stops mattering, and tests no
longer need `PortletHome.getStylesList(...)`, which returns an empty list as soon as
xmltransformer is absent.

## 11. Portlet JspBean — the plugin carries its own CSRF token

The automatic filter of §7 only sees MVC controllers. A `PortletJspBean` has no `@Controller`,
no `@Action`, no `@View`, so nothing protects its mutations, and the core's own
`create_portlet.html` / `modify_portlet.html` render a bare `<form>` with no token. Most v7
portlet plugins therefore have none at all, and a bench proves it in one line: a GET on
`DoCreatePortletXxx.jsp` with the right parameters creates the portlet.

**The plugin can close it alone.** Its `create_specific` / `modify_specific` template is
included *inside* the core form, and `getCreateTemplate( pageId, typeId, model )` /
`getModifyTemplate( portlet, model )` take a model. Checked by `CS01`.

```java
private static final String ACTION_CREATE_PORTLET = "myplugin.createPortlet";
private static final String MESSAGE_INVALID_TOKEN = "myplugin.message.invalidToken";

public String getCreate( HttpServletRequest request )
{
    model.put( SecurityTokenService.MARK_TOKEN, getSecurityTokenService( ).getToken( request, ACTION_CREATE_PORTLET ) );
    ...
}

public String doCreate( HttpServletRequest request )
{
    if ( !getSecurityTokenService( ).validate( request, ACTION_CREATE_PORTLET ) )
    {
        return AdminMessageService.getMessageUrl( request, MESSAGE_INVALID_TOKEN, AdminMessage.TYPE_STOP );
    }
    ...
}
```

```html
<@input type='hidden' name='token' value='${token}' />
```

`getSecurityTokenService( )` is inherited from `AdminFeaturesPageJspBean`; never
`SecurityTokenService.getInstance( )`. `doCreate` / `doModify` are abstract **without**
`throws`, so report the refusal with an `AdminMessage`, not an `AccessDeniedException`.

Four traps:

- **One action name per operation**, and the same one on both sides. A token is one-shot:
  `validate` removes it from the session, so a page showing N rows needs N tokens for the same
  action — that works, the session holds a set per action.
- **Every mutation, not only creation.** A row deletion reached by `<@aButton href='…Do…?id=1'>`
  is a GET that writes: it needs `&token=${token_x}` and its own `validate`. Give each its own
  mark (`token_order`, `token_unselect`) so one template can carry several.
- **A specific template that opens with `</form>`** (a v7 habit to nest its own forms) closes
  the core form early: the hidden field must come *before* that tag, or it lands outside.
- **The bench's own scenarios break.** Any scenario that drove a mutation by a forged URL now
  gets refused, and one that only asserted "an error is shown" turns green for the wrong
  reason. Rewrite them to submit the real form, which is the real user path anyway.
