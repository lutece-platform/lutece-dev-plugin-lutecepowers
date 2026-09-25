# FO templates — full page examples

Complete templates to copy from.

## Contents
- Page skeleton
- Typical error page
- Typical choice list
- Typical registration form
- Typical login form
- Typical multi-step recap page (with cStepDone, cStepCurrent, cStepNext)
- Article / rich content page (semantic HTML5 + dynamic breadcrumb)

### Page skeleton

Every page the core ships (`skin/site/page_template1.html`, `page_home.html`) and every recent front-end rewrite:

```freemarker
<@cTpl>
<#-- page-local macros and <#assign> first; FreeMarker hoists macro definitions, position is style -->
<@cContainer>
    <@cRow>
        <@cCol cols='12 col-md-9'>
            <@cTitle level=2>#i18n{myplugin.xpage.title}</@cTitle>
            <#-- content -->
        </@cCol>
        <@cCol cols='12 col-md-3'>
            <@cBlock type='aside' class='article-list'>...</@cBlock>
        </@cCol>
    </@cRow>
</@cContainer>
<#-- scripts after the markup, inside cTpl: <script type="module"> vanilla JS, guarded if (el) -->
</@cTpl>
```

`cTpl` looks up a site override under `skin/themes/<code>/tpl/<same path>` and renders `<#nested>` otherwise
(`skin/themes/global_theme_commons.ftl`). `cContainer` performs the same lookup itself. A fragment included by
another template (portlet body, component) has no `cTpl` and no `cContainer`.

### Typical error page

`skin/site/page_error500.html` on the core `develop` branch:

```freemarker
<#include "minimal_header.html" />
<@cTpl>
<@cErrorMessage title='#i18n{portal.theme.error500.title}' text='#i18n{portal.theme.error500.text}<br><small>(code: ${.now?long})</small>' linkUrl=footerLinkContact linkLabelUrl='#i18n{portal.theme.labelContact}' >
<#if error_cause??><@cAccordion id='expert' title='#i18n{portal.theme.error500.more}' class='alert alert-outline alert-warning' state=false>${error_cause!}</@cAccordion></#if>
</@cErrorMessage>
</@cTpl>
<#include "minimal_footer.html" />
```

`footerLinkContact` is a theme variable of `skin/themes/lutece/_theme.ftl`.

### Typical choice list

```freemarker
<@cTpl>
<@cContainer>
<@cRow>
    <@cCol>
        <@cTitle level=2>#i18n{mylutece.xpage.create_account.pageTitle}</@cTitle>
        <#if list_authentications?has_content>
            <@cText>#i18n{mylutece.xpage.create_account.contentMessage}</@cText>
            <@chList class='list-group'>
            <#list list_authentications as authentication>
                <@chItem class='list-group-item'>
                    <@cLink href='${authentication.newAccountPageUrl}' label='${authentication.authServiceName!}' title='${authentication.authServiceName!}' nestedPos='before'>
                        <@cImg src='${authentication.iconUrl!}' alt='${authentication.authServiceName!}' />
                    </@cLink>
                </@chItem>
            </#list>
            </@chList>
        <#else>
            <@cAlert type='warning' title='#i18n{mylutece.xpage.create_account.noAuthentication}' />
        </#if>
    </@cCol>
</@cRow>
</@cContainer>
</@cTpl>
```

### Typical registration form

The password field is one macro (`cInputPassword`, strength meter and confirmation pairing included); every
field has `for=` and `required=true`; the size of a column is `cols`, the class of a button is the colour only.

```freemarker
<@cTpl>
<@cContainer>
<@cRow class='justify-content-center'>
    <@cCol cols='12 col-md-6'>
        <@cTitle level=2>#i18n{...pageTitle}</@cTitle>
        <#if error_code?has_content>
            <@cAlert type='danger' title='#i18n{...errorMessage}' />
        </#if>
        <@cForm id='createAccount' name='createAccount' action='...'>
            <@cInput type='hidden' name='plugin_name' value='${plugin_name}' class='' />
            <@cField label='#i18n{...email}' for='email' required=true>
                <@cInput type='email' name='email' id='email' maxlength=100 value='${(user.email)!}' />
            </@cField>
            <@cInputPassword label='#i18n{...password}' name='password' id='password' icon='lock' passwordMeter=true pmConfirmFieldId='confirmation_password' helpMsg='#i18n{portal.theme.labelPasswordHelp}' />
            <@cInputPassword label='#i18n{...confirmation}' name='confirmation_password' id='confirmation_password' icon='lock' passwordMeter=false />
            <@cRow class='mt-3'>
                <@cCol>
                    <@cBtn class='primary' type='submit' label='#i18n{...btnCreateAccount}'>
                        <@cIcon name='user-check' />
                    </@cBtn>
                    <@cBtn class='secondary' href='${url_back}' label='#i18n{...btnBack}'>
                        <@cIcon name='arrow-left' />
                    </@cBtn>
                </@cCol>
            </@cRow>
        </@cForm>
    </@cCol>
</@cRow>
</@cContainer>
</@cTpl>
```

### Typical login form

Shape of `lutece-auth-plugin-mylutece/.../login_form_multi.html` on `develop` (its hard-coded French strings
replaced by keys; a template never carries literal copy):

```freemarker
<@cTpl>
<@cContainer>
<@cRow>
    <@cCol cols='12 col-md-6'>
        <@cTitle level=2>#i18n{mylutece.xpage.login_form.pageTitle}</@cTitle>
        <@cForm method='post' action='${url_dologin}' class='login-form' params='autocomplete="on"'>
            <@cInput type='hidden' name='page' value='mylutece' class='' />
            <@cInput type='hidden' name='action' value='doLogin' class='' />
            <@cInput type='hidden' name='token' value='${token}' class='' />
            <#if error_message?has_content>
                <@cAlert type='warning' title='${error_message}' />
            </#if>
            <@cField label='#i18n{mylutece.xpage.login_form.labelAccessCode}' for='username'>
                <@cInputGroup>
                    <@cIcon name='user' />
                    <@cInput name='username' id='username' placeholder='name@example.com' />
                </@cInputGroup>
            </@cField>
            <@cInputPassword label='#i18n{mylutece.xpage.login_form.labelPassword}' name='password' id='password' icon='lock' autocomplete='current-password' />
            <@cBtn class='primary' type='submit' label='#i18n{mylutece.xpage.login_form.labelButton}' nestedPos='after'>
                <@cIcon name='arrow-right' class='ms-2' />
            </@cBtn>
            <@cBlock class='lost-row'>
                <#if lostPasswordUrl?has_content><@cLink href='${lostPasswordUrl}' label='#i18n{mylutece.xpage.login_form.labelButtonLostPassword}' /></#if>
            </@cBlock>
        </@cForm>
    </@cCol>
</@cRow>
</@cContainer>
</@cTpl>
```

### Typical multi-step recap page (with cStepDone, cStepCurrent, cStepNext)

```freemarker
<@cStepDone step='1' title='#i18n{...stepOneTitle}' idx=0>
    ${form.description!}
</@cStepDone>
<@cStepDone step='2' title='#i18n{...stepTwoTitle}' idx=1 actionHref='jsp/site/Portal.jsp?page=appointment&view=getViewAppointmentCalendar&id_form=${form.idForm}' actionLabel='#i18n{portal.util.labelModify}'>
    <@chList>
        <@chItem>#i18n{...labelDate} ${appointment.dateOfTheAppointment}</@chItem>
    </@chList>
</@cStepDone>
<@cStepDone step='3' title='#i18n{...stepThreeTitle}' idx=2 actionHref='javascript:history.back()' actionLabel='#i18n{portal.util.labelModify}'>
    <@chList>
        <@chItem>${formMessages.fieldLastNameTitle!} : ${appointment.lastName}</@chItem>
        <@chItem>${formMessages.fieldFirstNameTitle!} : ${appointment.firstName}</@chItem>
        <@chItem>${formMessages.fieldEmailTitle!} : ${appointment.email}</@chItem>
        <#list listResponseRecapDTO as response>
            <#if response.recapValue?? && response.recapValue?has_content>
            <@chItem>${response.entry.title} : ${response.recapValue}</@chItem>
            </#if>
        </#list>
    </@chList>
</@cStepDone>
<@cStepCurrent step='4' title='#i18n{...validationTitle}' hasMandatory=false>
    <@cForm action='jsp/site/Portal.jsp' method='post'>
        <@cInput type='hidden' name='page' value='appointment' class='' />
        <@cInput type='hidden' name='action' value='doMakeAppointment' class='' />
        <@cInput type='hidden' name='token' value='${token}' class='' />
        <@cText>#i18n{...validationText}</@cText>
        <@cBtn type='submit' class='primary' label='#i18n{...labelValidate}'>
            <@cIcon name='check' />
        </@cBtn>
    </@cForm>
</@cStepCurrent>
<@cStepNext step='5' title='#i18n{...confirmationTitle}' />
```

### Article / rich content page (semantic HTML5 + dynamic breadcrumb)

Recommended pattern for an article detail page (blog, news, etc.) with:
- Breadcrumb built dynamically from URL parameters
- Header with metadata (tags, date, reading time)
- Hero image via `<@cFigure caption=...>`
- Aside with table of contents (TOC)
- Related articles section at the bottom

```freemarker
<@cTpl>
<#assign readingTimeLabel = "#i18n{plugin.readingTime.label}">
<@cContainer>
    <@cRow>
        <@cCol>
            <@cArticle class='bg-light'>
                <#-- Dynamic breadcrumb built from the received params -->
                <#assign breadcrumbItems = []>
                <#if from_page_name?? && from_page_name != ''>
                    <#assign fromPageUrl = ''>
                    <#if from_page_id??><#assign fromPageUrl = 'jsp/site/Portal.jsp?page_id=' + from_page_id?c></#if>
                    <#assign breadcrumbItems = breadcrumbItems + [{ 'title': from_page_name, 'url': fromPageUrl }]>
                </#if>
                <@cBreadCrumb items=breadcrumbItems />

                <@cHeader class='hero'>
                    <@cBlock>
                        <@cBlock class='hero__meta'>
                            <#if blog.tag?has_content>
                                <#list blog.tag as tg>
                                    <@cInline class='tag'>${tg.name}</@cInline>
                                </#list>
                            </#if>
                            <@cInline>·</@cInline>
                            <#if blog.updateDate??>
                                <#assign dateIso = blog.updateDate?string('yyyy-MM-dd')>
                                <@cInline type='time' params='datetime="${dateIso}"'>${blog.updateDate?string('d MMMM yyyy')}</@cInline>
                            </#if>
                            <@cInline>·</@cInline>
                            <@cInline class='reading-time' params='data-reading-time-label="${readingTimeLabel}"'></@cInline>
                        </@cBlock>
                        <@cTitle level=2 class='hero__title'>${blog.contentLabel}</@cTitle>
                        <@cText class='hero__lede'>${blog.description!}</@cText>
                    </@cBlock>
                    <#if blog.docContent?? && blog.docContent?size != 0>
                        <#list blog.docContent?sort_by('priority') as doc>
                            <#if doc.contentType.idContentType == 1>
                                <@cFigure class='hero__img' caption=blog.contentLabel>
                                    <@cImg src='servlet/plugins/myplugin/file?id_file=${doc.id!}' alt=blog.contentLabel />
                                </@cFigure>
                                <#break>
                            </#if>
                        </#list>
                    </#if>
                </@cHeader>

                <#assign bodyClass = 'body'>
                <#if !blog.displayToc><#assign bodyClass = bodyClass + ' body--one-col'></#if>
                <@cBlock class=bodyClass>
                    <#if blog.displayToc>
                        <@cBlock type='aside' class='toc'>
                            <@cBlock class='toc__title'>#i18n{plugin.tocTitle}</@cBlock>
                            <@chList id='toc-list'></@chList>
                        </@cBlock>
                    </#if>
                    <@cBlock class='article-content'>
                        ${blog.htmlContent}
                    </@cBlock>
                </@cBlock>
            </@cArticle>

            <#if blog.displayRelated && related_blogs?? && related_blogs?size gt 0>
                <@cSection class='related'>
                    <@cBlock class='related__title'>#i18n{plugin.relatedTitle}</@cBlock>
                    <@cBlock class='cards'>
                        <#list related_blogs as relBlog>
                            <#assign relUrl>jsp/site/Portal.jsp?page=myplugin&id=${relBlog.id}<#if blog.attachedPortletId gt 0>&portlet_id=${blog.attachedPortletId}</#if></#assign>
                            <@cLink href=relUrl class='card' label=''>
                                <@cBlock class='card__body'>
                                    <@cTitle level=3>${relBlog.contentLabel}</@cTitle>
                                    <@cText>${relBlog.description!}</@cText>
                                </@cBlock>
                            </@cLink>
                        </#list>
                    </@cBlock>
                </@cSection>
            </#if>
        </@cCol>
    </@cRow>
</@cContainer>
</@cTpl>
```

**Key points of this pattern**:
- `<@cArticle>`, `<@cHeader>`, `<@cSection>`, `<@cBlock type='aside'>` for HTML5 semantics
- `<#assign>` blocks to pre-build URLs, ISO dates and dynamic class names (never inline FreeMarker in macro parameters)
- `<@cInline type='time'>` for the `<time>` tag (no dedicated macro)
- `<@cFigure caption=...>` rather than separate `<figure>` + `<figcaption>`
- `<@cLink class='card' label=''>` for clickable cards (not `<@cBtn>`)
- `<@chList id='...'></@chList>` for an empty list to fill on the JS side
