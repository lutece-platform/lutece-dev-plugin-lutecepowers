# MVC Patterns — Lutece v8

> Canonical rules: `rules/web-bean.md` (@Controller attributes, Models, CSRF policy, CRUD lifecycle). This file only shows the v7 → v8 rewrites.
> Core sources: `~/.lutece-references/lutece-core/src/java/fr/paris/lutece/portal/util/mvc/` (`commons/annotations/*`, `binding/BindingResult.java`, `binding/ParamError.java`, `admin/MVCAdminJspBean.java`, `xpage/MVCApplication.java`).

## 1. @RequestParam

Binds query parameters directly to method parameters.

### Before (v7)
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
