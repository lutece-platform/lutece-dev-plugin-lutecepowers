# FO templates — full page examples

Complete templates to copy from.

## Contents
- Typical error page
- Typical choice list
- Typical registration form (with input-group and progress)
- Typical login form
- Typical multi-step recap page (with cStepDone, cStepCurrent, cStepNext)
- Article / rich content page (semantic HTML5 + dynamic breadcrumb)

### Typical error page

```freemarker
<#include "minimal_header.html" />
<@cTpl>
<@cContainer class='vh-80 pt-5'>
    <@cRow class='pt-5 mt-5'>
        <@cCol cols='12 col-md-3' class='pt-5 mt-5'>
            <@cImg src='themes/skin/shared/images/500.png' alt='#i18n{portal.util.error500.title}' id='error500-img' />
        </@cCol>
        <@cCol cols='12 col-md-6' class='pt-5 mt-5'>
            <@cCard class='border border-danger mt-5' header='Error 500' headerLevel=1 headerLabelClass='text-danger fw-bold h2' title='#i18n{portal.util.error500.title}' titleClass='h2' titleLevel=2>
                <@cText class='my-5 fs-2'>#i18n{portal.util.error500.text}</@cText>
                <#if error_cause??>
                <@cAlert type='danger' class='fs-3'>${error_cause}</@cAlert>
                </#if>
                <@cText class='text-center mt-5'>
                    <@cBtn href='./' label='#i18n{portal.util.labelBackHome}'>
                        <@cIcon name='home' />
                    </@cBtn>
                </@cText>
            </@cCard>
        </@cCol>
    </@cRow>
</@cContainer>
</@cTpl>
<#include "minimal_footer.html" />
```

### Typical choice list

```freemarker
<@cTpl>
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
        </#if>
        <@cAlert type='warning' title='#i18n{mylutece.xpage.create_account.noAuthentication}' />
    </@cCol>
</@cRow>
</@cTpl>
```

### Typical registration form (with input-group and progress)

```freemarker
<@cTpl>
<@cRow>
    <@cCol cols='12 col-md-4 offset-md-4'>
        <#if error_code?has_content>
            <@cAlert type='danger'>#i18n{...errorMessage}</@cAlert>
        </#if>
        <@cTitle level=2>#i18n{...pageTitle}</@cTitle>
        <@cForm id='createAccount' action='...' method='post' params='name="createAccount"'>
            <@cInput type='hidden' name='plugin_name' value='${plugin_name}' class='' />
            <@cField label='#i18n{...email}' required=true>
                <@cInput type='text' name='email' id='email' class='form-control ${classEmail?if_exists}' params='maxlength="100"' value='${(user.email)?if_exists}' />
            </@cField>
            <@cField label='#i18n{...password}' required=true>
                <@cInputGroup>
                    <@cInput type='password' id='password' name='password' class='form-control ${classPassword?if_exists}' params='maxlength="100"' />
                    <@cBtn href='#' class='secondary btn-sm p-2' id='lutece-password-toggler' label='' params='title="Show / hide the password"'>
                        <@cIcon name='eye' />
                    </@cBtn>
                    <@cBtn href='#' class='secondary btn-sm p-2' id='generate_password' label='' params='title="Generate a password"'>
                        <@cIcon name='settings' class='me-1' />
                        <@cInline class='d-none'>Generate a password</@cInline>
                    </@cBtn>
                </@cInputGroup>
            </@cField>
            <@cBlock class='py-3'>
                <@cProgress label='#i18n{...passwordComplexity}' progressId='progress_bar_first_password' color='danger' value=0 />
            </@cBlock>
            <@cRow>
                <@cCol>
                    <@cBtn class='primary' type='submit' label='' params='name="createAccountBtn"'>
                        <@cIcon name='user-check' /> #i18n{...btnCreateAccount}
                    </@cBtn>
                    <@cBtn class='secondary' type='button' label='' params='name="back" onclick="javascript:history.go(-1)"'>
                        <@cIcon name='circle-x' /> #i18n{...btnBack}
                    </@cBtn>
                </@cCol>
            </@cRow>
        </@cForm>
    </@cCol>
</@cRow>
</@cTpl>
```

### Typical login form

```freemarker
<@cTpl>
<@cCol>
    <@cForm method='post' action='${url_dologin}'>
    <@cInput type='hidden' name='page' value='mylutece' class='' />
    <@cInput type='hidden' name='action' value='doLogin' class='' />
    <@cInput type='hidden' name='token' value='${token}' class='' />
    <@cRow class='mt-xxl'>
        <@cCol cols='12 col-md-6' class='mt-xxl'>
            <#if error_message?? && error_message != ''>
                <@cAlert type='warning' title='${error_message!}' />
            </#if>
            <@cCard title='#i18n{mylutece.xpage.login_form.pageTitle}' class='my-l'>
                <@cField label='#i18n{mylutece.xpage.login_form.labelAccessCode}' for='username'>
                    <@cInput type='text' name='username' id='username' placeholder='name@example.com' />
                </@cField>
                <@cField label='#i18n{mylutece.xpage.login_form.labelPassword}' for='password'>
                    <@cInput type='password' name='password' id='password' placeholder='#i18n{mylutece.xpage.login_form.labelPassword}' />
                </@cField>
                <@cBtn class='primary w-100 py-m mt-l' type='submit' label='#i18n{mylutece.xpage.login_form.labelButton}' />
                <@cRow class='justify-content-center mt-l'>
                    <@cCol class='d-flex justify-content-end'>
                        <@cBtn href='${lostPasswordUrl!}' label='' params='title="..."'>
                            <@cIcon name='password-user' /> #i18n{...labelButtonLostPassword}
                        </@cBtn>
                    </@cCol>
                </@cRow>
            </@cCard>
        </@cCol>
        <@cCol cols='12 col-md-3' class='mt-xxl'>
            <@cImg src='themes/skin/lutece/images/signin.png' alt='#i18n{mylutece.xpage.login_form.labelButton}' />
        </@cCol>
    </@cRow>
    </@cForm>
</@cCol>
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
        <@cBtn type='submit' class='primary'>
            <@cIcon name='check' /> #i18n{...labelValidate}
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
                <@cBreadCrumb home='Home' type='fluid' items=breadcrumbItems />

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
                        <@cTitle level=1 class='hero__title'>${blog.contentLabel}</@cTitle>
                        <@cText class='hero__lede'>${blog.description!}</@cText>
                    </@cBlock>
                    <#if blog.docContent?? && blog.docContent?size != 0>
                        <#list blog.docContent?sort_by('priority') as doc>
                            <#if doc.contentType.idContentType == 1>
                                <@cFigure class='hero__img' caption=blog.contentLabel>
                                    <@cImg src='servlet/plugins/blogs/file?id_file=${doc.id!}' alt=blog.contentLabel />
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
                            <#assign relUrl>jsp/site/Portal.jsp?page=blog&id=${relBlog.id}<#if blog.attachedPortletId gt 0>&portlet_id=${blog.attachedPortletId}</#if></#assign>
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
