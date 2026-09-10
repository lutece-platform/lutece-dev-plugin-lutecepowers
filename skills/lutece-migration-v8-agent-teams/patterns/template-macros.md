# Freemarker Macros — Lutece v8 Quick Reference

> Canonical rules: `rules/template-back-office.md` (BO) and `rules/template-front-office.md` (FO): layout, list layout choice, messages, null-safety, i18n keys, JavaScript. This file only lists macro signatures for the migration.
> Macro sources: BO `~/.lutece-references/lutece-core/webapp/WEB-INF/templates/admin/themes/tabler/{components,elements,forms,layout,utilities}/**/*.ftl`, FO `.../skin/themes/macros/{components,elements,forms,layout,utilities}/**/*.ftl`. Always read the `.ftl` signature before using a parameter.

## Layout Macros

### @pageContainer / @pageColumn / @pageHeader
```html
<@pageContainer>
    <@pageColumn>
        <@pageHeader title="#i18n{myplugin.manage.pageTitle}" description="#i18n{myplugin.manage.description}" />
        <!-- content here -->
    </@pageColumn>
</@pageContainer>
```

## Data Display

### @manageFeature (entity lists) / @table (tabular data)
`manageFeature class colClass listClass id` > `manageFeatureItem class align valign liClass bodyClass id` > `manageFeatureItemColumn bp auto flex dir cols valign align class id` (`components/features/features.ftl`). `table id class responsive condensed hover striped headBody bordered narrow collapsed caption` (`components/table/table.ftl`). Full example and the choice rule: `rules/template-back-office.md` § List Layout.

### @alert
`alert class color titleLevel title titleClass iconTitle iconClass dismissible id` (`components/alert/alert.ftl`). The parameter is `color`, not `type`.
```html
<@alert color="info">#i18n{myplugin.message.info}</@alert>
<@alert color="danger" title="#i18n{myplugin.message.error}" />
```

### @messages
`messages errors=[] infos=[] warnings=[]` (`components/alert/messages.ftl`). Use `<@messages errors=errors![] infos=infos![] warnings=warnings![] />`: see `rules/template-back-office.md` § Messages.

### @empty
`empty title subtitle id class iconName iconClass img imgClass actionTitle actionBtn actionIcon actionClass actionUrl` (`utilities/empty/empty.ftl`).

## Form Macros

### @tform / @formGroup / @input / @select / @checkBox / @radioButton
- `tform type class align hide required action method='post' name id role collapsed enctype boxed boxClass` (`forms/form/tform.ftl`)
- `formGroup id formStyle groupStyle class rows labelKey labelKeyDesc labelFor labelId labelClass helpKey mandatory hideLabel collapsed` (`forms/form/formGroup.ftl`) — `mandatory`, not `required`
- `input name id type='text' value class size helpKey inputSize maxlength placeHolder autoComplete rows cols richtext=false tabIndex disabled readonly pattern title min max step mandatory ...` (`forms/input/input.ftl`) — types: `text`, `textarea`, `password`, `email`, `number`, `date`, `hidden`, `url`, `tel`, `file`, `color`, `range`. No `richtext` type: `type='textarea' richtext=true`.
- `select name id class items='' default_value size sort multiple title disabled mandatory` (`forms/select/select.ftl`) — `items` is a `ReferenceList` from the model; for literal options nest `<@option value label selected />`
- `checkBox name id class labelKey labelClass wrapperClass orientation value title disabled readonly checked mandatory` (`forms/checkbox/checkBox.ftl`)
- `radioButton name id class labelKey labelClass labelFor orientation value title disabled readonly checked mandatory` (`forms/radio/radioButton.ftl`) — `labelKey`, not `label`

```html
<@tform action="jsp/admin/plugins/myplugin/ManageItems.jsp" method="post">
    <@input type="hidden" name="action" value="createItem" />
    <@formGroup labelFor="name" labelKey="#i18n{myplugin.label.name}" mandatory=true>
        <@input type="text" name="name" id="name" value="${item.name!}" mandatory=true />
    </@formGroup>
    <@formGroup labelFor="description" labelKey="#i18n{myplugin.label.description}">
        <@input type="textarea" name="description" id="description" rows=5>${item.description!}</@input>
    </@formGroup>
    <@formGroup labelFor="id_category" labelKey="#i18n{myplugin.label.category}">
        <@select name="id_category" id="id_category" items=category_list default_value="${item.idCategory!}" />
    </@formGroup>
    <@formGroup labelKey="#i18n{myplugin.label.status}">
        <@radioButton name="status" id="status_enabled" value="1" labelKey="#i18n{portal.util.labelEnabled}" checked=(item.status == 1) />
        <@radioButton name="status" id="status_disabled" value="0" labelKey="#i18n{portal.util.labelDisabled}" checked=(item.status == 0) />
    </@formGroup>
    <@formGroup labelFor="active" labelKey="#i18n{myplugin.label.active}">
        <@checkBox orientation="switch" name="active" id="active" value="true" labelKey="#i18n{myplugin.label.active}" checked=(item.active!false) />
    </@formGroup>
    <@button type="submit" color="primary" buttonIcon="check" title="#i18n{portal.util.labelValidate}" />
    <@aButton href="jsp/admin/plugins/myplugin/ManageItems.jsp" buttonIcon="x" title="#i18n{portal.util.labelCancel}" />
</@tform>
```

No `token` hidden field: the core injects `_csrftoken` when the bean has `securityTokenEnabled = true` (`rules/web-bean.md`).

## Button Macros

- `button name id type='button' size color style class value title tooltip tabIndex hideTitle buttonIcon disabled iconPosition dropdownMenu cancel formId buttonTargetId` (`components/button/button.ftl`)
- `aButton name id href target size color='primary' style class title tabIndex hideTitle buttonIcon disabled iconPosition dropdownMenu` (`components/button/aButton.ftl`)

`title` is the label, `buttonIcon` the Tabler icon name without the `ti ti-` prefix. There is no `labelKey` nor `iconClass`.

```html
<@button type="submit" color="primary" buttonIcon="check" title="#i18n{portal.util.labelValidate}" />
<@aButton href="..." size="sm" buttonIcon="edit" title="#i18n{portal.util.labelModify}" />
<@aButton href="..." size="sm" color="danger" buttonIcon="trash" title="#i18n{portal.util.labelDelete}" />
<@aButton href="..." color="success" buttonIcon="plus" title="#i18n{portal.util.labelCreate}" />
```

Colors: `primary`, `secondary`, `success`, `danger`, `warning`, `info`, `default`.

### @offcanvas
`offcanvas id position='end' class title btnColor btnTitle btnDropdown btnDropdownContent hideTitle btnIcon btnClass btnDisabled bodyClass badgeContent badgeColor backdrop size btnSize targetUrl targetElement useIframe redirectForm reloadOnClose keepPageHeader` (`components/offcanvas/offcanvas.ftl`). The side parameter is `position`, not `placement`.

## Upload Macros (Back-Office) — plugin-asynchronousupload

Not in the core. Requires the `plugin-asynchronousupload` dependency, the include and the JS bootstrap:

```html
<#include "/admin/plugins/asynchronousupload/upload_commons.html" />
<@addRequiredBOJsFiles />
<@addFileBOInput fieldName="file_upload" handler=uploadHandler cssClass="" multiple=false />
<@addBOUploadedFilesBox fieldName="file_upload" handler=uploadHandler listFiles=listFiles />
```

Signatures (`admin/plugins/asynchronousupload/upload_commons.html`): `addFileBOInput fieldName handler cssClass multiple=false submitBtnName hasError=false required=false`, `addBOUploadedFilesBox fieldName handler listFiles submitBtnName noJs=false`, `addFileBOInputAndfilesBox fieldName handler listUploadedFiles inputCssClass multiple=false`. `handler` is the `IAsyncUploadHandler` put in the model. Reference: forms `forms_commons.html:304-324`. FO equivalents: `skin/plugins/asynchronousupload/upload_commons.html` (`addFileInput`, `addUploadedFilesBox`). Core alternative without the plugin: `@inputDropFiles name handler ...` (`forms/upload/inputDropFiles.ftl`).

## Front-Office Macros

`rules/template-front-office.md` (paths, messages). Wrap every skin template:

```html
<@cTpl>
    <@cContainer>
        <@cTitle level=1>#i18n{myplugin.xpage.title}</@cTitle>
        <!-- content -->
    </@cContainer>
</@cTpl>
```

Available FO macros include `cAlert`, `cBtn`, `cForm`, `cField`, `cInput`, `cInputDate`, `cSelect`, `cCard`, `cTable`, `cFooter`, `cEmpty`, `cOffcanvas`, `cPagination`, `cTabs`/`cTab`/`cTabPane`, `cDropdown`, `cBadge`, `cIcon`, `cInline` (one `.ftl` per macro under `skin/themes/macros/`).

## Pagination

`<@paginationAdmin paginator=paginator combo=1 />` after the list (server-side). `@paginationAjax paginator columns ajaxUrl tableId combo showcount actions` with a `@ResponseBody` endpoint: `/lutece-patterns` §5.

## Icons

Tabler Icons: `ti ti-{name}` — https://tabler.io/icons. In macros pass the bare name (`buttonIcon='pencil'`).
Common: `pencil`, `edit`, `trash`, `plus`, `eye`, `search`, `download`, `upload`, `check`, `x`, `arrow-left`, `arrow-right`

## i18n

`#i18n{pluginName.key.subkey}`. Existing `portal.util.*` keys and the ones that do NOT exist: `rules/template-back-office.md` § i18n.

## Null Safety and Message Types

`rules/template-back-office.md` § Null Safety (BO) / `rules/template-front-office.md` § Model Messages (FO): `(errors![])`, `${error.message}` for errors, `${info}` / `${warning}` for infos and warnings.

## JavaScript Migration (jQuery → Vanilla ES6)

Conversion table: `skills/lutece-update-template-fo/SKILL.md` § jQuery → Vanilla JS. Neither the admin theme nor the site frameset loads jQuery. Code that depends on a jQuery plugin (DataTables, Select2, jQuery UI…) is a **WARN / manual port**: it will fail at runtime as-is; port it to a vanilla equivalent or a core macro, or add `library-theme-jquery` as an explicit dependency. Never mark it as PASS.
