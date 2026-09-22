# BO templates — full page examples

Complete templates to copy from. Each one is a real page shape, not a fragment.

## Contents
- Management page with @manageFeature (list + creation modal)
- Management page with @table (tabular data)
- Edit form (dedicated page)
- Page with tabs (internal)
- Page with tabs (URL navigation)
- Advanced management page (search modal + bulk actions + empty state)
- Editor page (create/modify with toolbar, properties modal, rich content)
- Embedded panel / fragment (tab content, without page structure)

### Management page with @manageFeature (list + creation modal)

```freemarker
<@pageContainer>
	<@pageColumn>
		<@pageHeader title='#i18n{plugin.manage_items.title}'>
			<@button type='button' title='#i18n{plugin.create_item.title}' buttonIcon='plus' color='primary' params='data-bs-toggle="modal" data-bs-target="#createModal"' />
		</@pageHeader>
		<@modal id='createModal'>
			<@modalHeader modalTitle='#i18n{plugin.create_item.title}' />
			<@modalBody>
				<@tform name='create_item' id='create_item' action='jsp/admin/plugins/myplugin/ManageItems.jsp'>
					<@formGroup labelFor='name' labelKey='#i18n{plugin.create_item.labelName}' helpKey='#i18n{plugin.create_item.labelName.help}' mandatory=true>
						<@input type='text' name='name' id='name' value='' mandatory=true />
					</@formGroup>
				</@tform>
			</@modalBody>
			<@modalFooter>
				<@button type='button' title='#i18n{portal.util.labelCancel}' color='light' params='data-bs-dismiss="modal"' />
				<@button type='submit' formId='create_item' name='action_createItem' buttonIcon='check' title='#i18n{portal.admin.message.buttonValidate}' color='primary' />
			</@modalFooter>
		</@modal>
		<@messages errors=errors infos=infos />
		<@manageFeature>
			<#list item_list as item>
			<@manageFeatureItem>
				<@manageFeatureItemColumn>
					<strong>${item.name}</strong>
				</@manageFeatureItemColumn>
				<@manageFeatureItemColumn auto=true align='end'>
					<@aButton href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=modifyItem&id=${item.id}' title='#i18n{portal.util.labelModify}' buttonIcon='edit' color='primary' class='me-1' hideTitle=['all'] />
					<@aButton href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=confirmRemoveItem&id=${item.id}' title='#i18n{portal.util.labelDelete}' buttonIcon='trash' color='danger' size='' hideTitle=['all'] />
				</@manageFeatureItemColumn>
			</@manageFeatureItem>
			</#list>
		</@manageFeature>
		<@paginationAdmin paginator=paginator combo=1 />
	</@pageColumn>
</@pageContainer>
```

### Management page with @table (tabular data)

```freemarker
<@pageContainer>
	<@pageColumn>
		<@pageHeader title='#i18n{plugin.manage_data.title}'>
			<@aButton href='jsp/admin/plugins/myplugin/CreateData.jsp' buttonIcon='plus' color='primary' title='#i18n{plugin.manage_data.buttonCreate}' />
		</@pageHeader>
		<@messages infos=infos />
		<@box>
			<@boxBody>
				<@table headBody=true>
					<@tr>
						<@th>#i18n{plugin.manage_data.columnName}</@th>
						<@th>#i18n{plugin.manage_data.columnStatus}</@th>
						<@th>#i18n{plugin.manage_data.columnDate}</@th>
						<@th>#i18n{portal.util.labelActions}</@th>
					</@tr>
					<@tableHeadBodySeparator />
					<#list data_list as data>
					<@tr>
						<@td>${data.name}</@td>
						<@td><@tag color='${data.active?then("success","danger")}'>${data.active?then("Actif","Inactif")}</@tag></@td>
						<@td>${data.date}</@td>
						<@td>
							<@aButton href='jsp/admin/plugins/myplugin/ModifyData.jsp?id=${data.id}' buttonIcon='edit' color='primary' title='#i18n{portal.util.labelModify}' size='' hideTitle=['all'] />
							<@aButton href='jsp/admin/plugins/myplugin/ManageData.jsp?view=confirmRemoveData&id=${data.id}' buttonIcon='trash' color='danger' title='#i18n{portal.util.labelDelete}' size='' hideTitle=['all'] />
						</@td>
					</@tr>
					</#list>
				</@table>
				<@paginationAdmin paginator=paginator combo=1 />
			</@boxBody>
		</@box>
	</@pageColumn>
</@pageContainer>
```

### Edit form (dedicated page)

```freemarker
<@pageContainer>
	<@pageColumn>
		<@pageHeader title='#i18n{plugin.modify_item.title}' />
		<@box>
			<@boxBody>
				<@messages errors=errors />
				<@tform name='modify_item' action='jsp/admin/plugins/myplugin/ManageItems.jsp'>
					<@input type='hidden' name='id' value='${item.id}' />
					<@formGroup labelFor='name' labelKey='#i18n{plugin.modify_item.labelName}' mandatory=true>
						<@input type='text' name='name' value='${item.name!}' />
					</@formGroup>
					<@formGroup labelFor='description' labelKey='#i18n{plugin.modify_item.labelDescription}'>
						<@input type='textarea' name='description' value='${item.description!}' />
					</@formGroup>
					<@formGroup labelFor='status' labelKey='#i18n{plugin.modify_item.labelStatus}'>
						<@select name='status' items=status_list default_value='${item.status}' />
					</@formGroup>
					<@actionButtons button1Name='action_modifyItem' button2Name='view_manageItems' />
				</@tform>
			</@boxBody>
		</@box>
	</@pageColumn>
</@pageContainer>
```

### Page with tabs (internal)

Internal tabs: `href='#panelId'` with `data-bs-toggle="tab"` added automatically.

```freemarker
<@pageContainer>
	<@pageColumn>
		<@pageHeader title='#i18n{plugin.detail_item.title}' />
		<@tabs id="item-tabs">
			<@tabList>
				<@tabLink active=true href='#general' title='#i18n{plugin.detail_item.tabGeneral}' />
				<@tabLink href='#advanced' title='#i18n{plugin.detail_item.tabAdvanced}' />
			</@tabList>
			<@tabContent>
				<@tabPanel id='general' active=true>
					<@box>
						<@boxBody>
							...
						</@boxBody>
					</@box>
				</@tabPanel>
				<@tabPanel id='advanced'>
					<@box>
						<@boxBody>
							...
						</@boxBody>
					</@box>
				</@tabPanel>
			</@tabContent>
		</@tabs>
	</@pageColumn>
</@pageContainer>
```

### Page with tabs (URL navigation)

Tabs that navigate to JSPs: `href='jsp/admin/...'` (no `#`, no `@tabPanel`).

```freemarker
<@pageContainer>
	<@pageColumn>
		<@pageHeader title='#i18n{plugin.manage_item.title}' />
		<@tabs>
			<@tabList>
				<@tabLink active=true href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=list' title='#i18n{plugin.tab.list}' />
				<@tabLink href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=settings' title='#i18n{plugin.tab.settings}' />
			</@tabList>
		</@tabs>
		...current page content...
	</@pageColumn>
</@pageContainer>
```

### Advanced management page (search modal + bulk actions + empty state)

```freemarker
<@pageContainer>
	<@pageColumn>
		<@pageHeader title='#i18n{plugin.manage_items.title}'>
			<#if item_list?has_content && item_list?size gt 1>
				<@button type='button' title='#i18n{plugin.manage_items.search}' buttonIcon='search' class='me-1' hideTitle=['xs'] params='data-bs-toggle="modal" data-bs-target="#searchModal"' />
			</#if>
			<#if permission_create>
				<@aButton href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=createItem' buttonIcon='plus' color='primary' title='#i18n{plugin.manage_items.buttonAdd}' hideTitle=['xs'] />
			</#if>
		</@pageHeader>
		<#if item_list?has_content && item_list?size gt 1>
			<@modal id='searchModal'>
				<@modalHeader modalTitle='#i18n{plugin.manage_items.search}' />
				<@modalBody>
					<@tform id='form-search' method='get' action='jsp/admin/plugins/myplugin/ManageItems.jsp'>
						<@formGroup labelFor='search_text' labelKey='#i18n{plugin.manage_items.search}'>
							<@input type='text' id='search_text' name='search_text' value='${search_text!\'\'}' />
						</@formGroup>
						<@formGroup labelFor='status' labelKey='#i18n{plugin.manage_items.labelStatus}'>
							<@select id='status' name='status'>
								<@option value="0" label='#i18n{plugin.manage_items.labelAll}' />
								<@option value="1" label='#i18n{plugin.manage_items.labelActive}' />
								<@option value="2" label='#i18n{plugin.manage_items.labelInactive}' />
							</@select>
						</@formGroup>
					</@tform>
				</@modalBody>
				<@modalFooter>
					<@button type='submit' formId='form-search' color='light' buttonIcon='x me-1' name='button_reset' title='#i18n{plugin.manage_items.reset}' />
					<@button type='submit' formId='form-search' color='primary' buttonIcon='search me-1' title='#i18n{plugin.manage_items.search}' />
				</@modalFooter>
			</@modal>
		</#if>
		<@messages infos=infos />
		<#if item_list?has_content && item_list?size gt 0>
			<@tform id='form_bulk_action' method='post' action='jsp/admin/plugins/myplugin/ManageItems.jsp' boxed=true>
				<@input type='hidden' id='action' name='action' value='bulk_action' />
				<#if permission_archive || permission_delete>
					<@row class='justify-content-end align-items-center'>
						<@columns md=2 offsetMd=5>
							<@inputGroup>
								<@select id='select_action' name='select_action' disabled=true>
									<@option value=0 selected=true label='#i18n{plugin.manage_items.labelArchive}' />
									<@option value=1 label='#i18n{plugin.manage_items.labelDelete}' />
								</@select>
								<@button type='submit' id='btn_apply' buttonIcon='check' hideTitle=['all'] disabled=true />
							</@inputGroup>
						</@columns>
						<@columns md=3>
							<@checkBox orientation='switch' name='select_all' id='select_all' labelKey='#i18n{plugin.manage_items.selectAll}' />
						</@columns>
					</@row>
				</#if>
				<@manageFeature>
					<#list item_list as item>
					<@manageFeatureItem>
						<#if permission_archive || permission_delete>
							<@manageFeatureItemColumn auto=true>
								<@checkBox orientation='switch' id='selected_${item.id}' name='select_id' value='${item.id}' />
							</@manageFeatureItemColumn>
						</#if>
						<@manageFeatureItemColumn auto=true flex=false>
							<@link href="jsp/admin/plugins/myplugin/ManageItems.jsp?view=modifyItem&amp;id=${item.id}" title="#i18n{portal.util.labelModify}">
								<strong>${item.name!}</strong>
							</@link>
							<@p class='my-1'><small>#i18n{plugin.manage_items.labelCreatedBy} <strong>${item.author!}</strong> ${item.creationDate!}</small></@p>
						</@manageFeatureItemColumn>
						<@manageFeatureItemColumn auto=true flex=false valign='top'>
							<@p class='fw-bold fs-3'>#i18n{plugin.manage_items.labelTags}</@p>
							<#if item.tags?size gt 0>
								<#list item.tags as tag><@tag color='info'>${tag.name!}</@tag></#list>
							<#else>
								<@tag color='info'>#i18n{plugin.manage_items.noTag}</@tag>
							</#if>
						</@manageFeatureItemColumn>
						<@manageFeatureItemColumn align='end'>
							<@aButton href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=modifyItem&amp;id=${item.id}' title='#i18n{portal.util.labelModify}' buttonIcon='pencil' hideTitle=['all'] />
							<@aButton href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=confirmRemoveItem&amp;id=${item.id}' title='#i18n{portal.util.labelDelete}' buttonIcon='trash' hideTitle=['all'] color='danger' />
						</@manageFeatureItemColumn>
					</@manageFeatureItem>
					</#list>
				</@manageFeature>
			</@tform>
			<#if item_list?size gte 10><@paginationAdmin paginator=paginator combo=1 /></#if>
		<#else>
			<@card>
				<#if permission_create>
					<@empty title='#i18n{plugin.manage_items.noResult}' iconName='inbox-off' subtitle='#i18n{plugin.manage_items.help}' actionTitle='#i18n{plugin.manage_items.buttonAdd}' actionUrl='jsp/admin/plugins/myplugin/ManageItems.jsp?view=createItem' />
				<#else>
					<@empty title='#i18n{plugin.manage_items.noResult}' iconName='inbox-off' subtitle='#i18n{plugin.manage_items.help}' />
				</#if>
			</@card>
		</#if>
	</@pageColumn>
</@pageContainer>
```

### Editor page (create/modify with toolbar, properties modal, rich content)

```freemarker
<@pageContainer>
	<@pageColumn>
		<@tform name='modify_item' class='position-relative' id='form-editor' enctype='multipart/form-data' action='jsp/admin/plugins/myplugin/ManageItems.jsp'>
			<@pageHeader title='#i18n{plugin.modify_item.pageTitle}'>
				<@input type='hidden' id='id' name='id' value=item.id />
				<@input type='hidden' id='action' name='action' value='modifyItem' />
				<@row id='toolbar-wrapper'>
					<@columns id='toolbar' class='d-flex justify-content-end align-items-center'>
						<@button class='me-1 action' type='submit' size='' buttonIcon='check me-2' title='#i18n{plugin.modify_item.labelSave}' id='action_save' name='action_save' hideTitle=['xs','sm', 'md', 'lg'] />
						<@aButton class='me-1' href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=confirmRemoveItem&amp;id=${item.id}' color='danger' title='#i18n{portal.util.labelDelete}' buttonIcon='trash' hideTitle=['xs','sm', 'md', 'lg'] size='' />
						<@aButton class='me-1' href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=previewItem&id=${item.id}' title='#i18n{plugin.modify_item.labelPreview}' hideTitle=['xs','sm', 'md', 'lg'] color='default' size='' buttonIcon='eye' />
						<@button type='button' class='me-1' title='#i18n{plugin.modify_item.labelProperties}' buttonIcon='cog me-2' hideTitle=['xs','sm', 'md', 'lg'] params='data-bs-toggle="modal" data-bs-target="#item-properties"' />
					</@columns>
				</@row>
			</@pageHeader>
			<@modal id='item-properties' size='lg'>
				<@modalHeader modalTitle='#i18n{plugin.modify_item.labelProperties}' />
				<@modalBody>
					<@box>
						<@boxHeader title='#i18n{plugin.modify_item.labelTags}'>
							<@icon style='tags' />
						</@boxHeader>
						<@boxBody>
							<@formGroup labelFor='addTag' labelKey='#i18n{plugin.manage_tags.buttonAdd}' rows=2>
								<@inputGroup>
									<@select name='tag_doc' default_value='' items=list_tag size='' />
									<@inputGroupItem type='btn'>
										<@button type='button' id='addTag' name='addTag' buttonIcon='bookmark-plus' size='' />
									</@inputGroupItem>
								</@inputGroup>
							</@formGroup>
							<@listGroup id='tag-list'>
								...dynamic tags...
							</@listGroup>
						</@boxBody>
					</@box>
					<@box>
						<@boxHeader title='#i18n{plugin.modify_item.labelAttachments}' boxTools=true>
							<@button title="#i18n{plugin.modify_item.labelAddFile}" id='btn-add-files' color='outline-primary' buttonIcon='plus' size='xs' />
						</@boxHeader>
						<@boxBody>
							<@input class='visually-hidden' name='attachment' id='attachment' type='file' />
							<@div class="resources">
								<@listGroup id='content-list'>
									...existing files...
								</@listGroup>
							</@div>
						</@boxBody>
					</@box>
				</@modalBody>
			</@modal>
			<@messages errors=errors />
			<@formGroup labelFor='title' labelKey='#i18n{plugin.create_item.labelTitle}' hideLabel=['all'] rows=2>
				<@input name='title' id='title' value='${item.title!?trim}' class='visually-hidden' />
				<@div id='div_title' class='content-head font-bold main-color lutece-charcounter' params='data-lutece-counter-max="75" contenteditable="true"'>${item.title!?trim}</@div>
			</@formGroup>
			<@formGroup labelFor='description' labelKey='#i18n{plugin.create_item.labelDescription}' hideLabel=['all'] rows=2>
				<@input name='description' id='description' value='${item.description!}' class='visually-hidden' />
				<@div id='div_description' class='content-desc lutece-charcounter' params='data-lutece-counter-max="300" contenteditable="true"'>${item.description!}</@div>
			</@formGroup>
			<@formGroup labelFor='html_content' labelKey='#i18n{plugin.create_item.labelContent}' hideLabel=['all'] rows=2>
				<@input type='textarea' name='html_content' id='html_content' value='${item.htmlContent!}' class='visually-hidden' />
				<@div id='div_html_content' class='content-body' params='contenteditable="true"'>${item.htmlContent!}</@div>
				<@button class='my-3 me-1 action' type='submit' size='' buttonIcon='check me-2' title='#i18n{plugin.modify_item.labelSave}' id='action_save_bottom' name='action_save' hideTitle=['xs','sm'] />
			</@formGroup>
		</@tform>
	</@pageColumn>
</@pageContainer>
```

### Embedded panel / fragment (tab content, without page structure)

Template included in a tab or a parent page. No `@pageContainer` / `@pageColumn` / `@pageHeader`. Each logical section is a `@box` with `@boxHeader boxTools=true` for the actions.

```freemarker
<@box>
	<@boxHeader title='#i18n{plugin.panel.titleSection1}' boxTools=true>
		<@tform action='jsp/admin/plugins/myplugin/DoAction.jsp' method='post'>
			<@button type='submit' color='primary' buttonIcon='sync' title='#i18n{plugin.panel.buttonAction}' hideTitle=['xs','sm','md'] size='' />
		</@tform>
	</@boxHeader>
	<@boxBody>
		<@p>#i18n{plugin.panel.explainSection1}</@p>
		<#if feature_enabled>
			<@p><@tag color='success' tagIcon='check-circle'>#i18n{portal.util.labelEnabled}</@tag> #i18n{plugin.panel.labelEnabled}</@p>
		<#else>
			<@p><@tag color='danger' tagIcon='times-circle'>#i18n{portal.util.labelDisabled}</@tag> #i18n{plugin.panel.labelDisabled}</@p>
		</#if>
	</@boxBody>
</@box>
<@box>
	<@boxHeader title='#i18n{plugin.panel.titleSection2}' boxTools=true>
		<@tform method='post' action='jsp/admin/plugins/myplugin/DoToggle.jsp'>
			<@input type='hidden' name='toggle' value='feature_key' />
			<#if feature_enabled>
				<@button type='submit' color='danger' buttonIcon='stop' title='#i18n{plugin.panel.buttonDisable}' hideTitle=['xs','sm','md'] size='' />
			<#else>
				<@button type='submit' color='success' buttonIcon='play' title='#i18n{plugin.panel.buttonEnable}' hideTitle=['xs','sm','md'] size='' />
			</#if>
		</@tform>
	</@boxHeader>
	<@boxBody>
		<@p>#i18n{plugin.panel.explainSection2}</@p>
		<@alert color='warning' iconTitle='exclamation-circle fa-2x'>
			#i18n{plugin.panel.warningMessage}
		</@alert>
	</@boxBody>
</@box>
```
