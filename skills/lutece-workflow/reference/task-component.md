# Workflow task — the UI half

The TaskComponent and its FreeMarker templates: steps 7 and 10. The rest is in SKILL.md.

## Contents
- 7. Task Component (UI)
- 10. Templates

## 7. Task Component (UI)

`TaskComponentManager.getTaskComponent( key )` iterates every `ITaskComponent` bean and keeps the one whose `isInvoked( key )` is true; `TaskComponent.isInvoked` compares `_taskType.getKey()`. A component that never receives its `ITaskType` is never matched: inject it in the constructor and call `setTaskType` (reference: `EditFormResponseTaskComponent` constructor).

```java
package fr.paris.lutece.plugins.workflow.modules.{pluginName}.web;

import fr.paris.lutece.plugins.workflow.web.task.AbstractTaskComponent;
import fr.paris.lutece.plugins.workflowcore.business.task.ITaskType;
import fr.paris.lutece.plugins.workflowcore.service.config.ITaskConfigService;
import fr.paris.lutece.plugins.workflowcore.service.task.ITask;
import fr.paris.lutece.portal.service.template.AppTemplateService;
import fr.paris.lutece.util.html.HtmlTemplate;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.inject.Named;
import jakarta.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

@ApplicationScoped
@Named( "workflow-{pluginName}.task{Name}Component" )
public class {Name}TaskComponent extends AbstractTaskComponent
{
    private static final String TEMPLATE_CONFIG = "admin/plugins/workflow/modules/{pluginName}/task_{name}_config.html";
    private static final String TEMPLATE_FORM = "admin/plugins/workflow/modules/{pluginName}/task_{name}_form.html";
    private static final String TEMPLATE_INFO = "admin/plugins/workflow/modules/{pluginName}/task_{name}_information.html";

    private static final String MARK_CONFIG = "config";

    private ITaskConfigService _taskConfigService;

    public {Name}TaskComponent( )
    {
    }

    @Inject
    public {Name}TaskComponent( @Named( "workflow-{pluginName}.taskType{Name}" ) ITaskType taskType,
            @Named( Task{Name}.BEAN_CONFIG_SERVICE ) ITaskConfigService taskConfigService )
    {
        _taskConfigService = taskConfigService;
        setTaskType( taskType );
        setTaskConfigService( taskConfigService );
    }

    /**
     * Displays the task configuration form (workflow admin)
     */
    @Override
    public String getDisplayConfigForm( HttpServletRequest request, Locale locale, ITask task )
    {
        Map<String, Object> model = new HashMap<>( );
        Task{Name}Config config = _taskConfigService.findByPrimaryKey( task.getId( ) );
        model.put( MARK_CONFIG, config );

        HtmlTemplate template = AppTemplateService.getTemplate( TEMPLATE_CONFIG, locale, model );
        return template.getHtml( );
    }

    /**
     * Saves the task configuration
     */
    @Override
    public String doSaveConfig( HttpServletRequest request, Locale locale, ITask task )
    {
        String strTitle = request.getParameter( "title" );
        String strTargetState = request.getParameter( "target_state" );
        boolean bNotifyUser = request.getParameter( "notify_user" ) != null;

        Task{Name}Config config = _taskConfigService.findByPrimaryKey( task.getId( ) );

        if ( config == null )
        {
            config = new Task{Name}Config( );
            config.setIdTask( task.getId( ) );
            config.setTitle( strTitle );
            config.setTargetState( strTargetState );
            config.setNotifyUser( bNotifyUser );
            _taskConfigService.create( config );
        }
        else
        {
            config.setTitle( strTitle );
            config.setTargetState( strTargetState );
            config.setNotifyUser( bNotifyUser );
            _taskConfigService.update( config );
        }

        return null; // null = no error
    }

    /**
     * Displays the form during workflow action execution
     */
    @Override
    public String getDisplayTaskForm( int nIdResource, String strResourceType, HttpServletRequest request, Locale locale, ITask task )
    {
        Map<String, Object> model = new HashMap<>( );
        Task{Name}Config config = _taskConfigService.findByPrimaryKey( task.getId( ) );
        model.put( MARK_CONFIG, config );

        HtmlTemplate template = AppTemplateService.getTemplate( TEMPLATE_FORM, locale, model );
        return template.getHtml( );
    }

    /**
     * Validates the action form data
     * @return error message or null if OK
     */
    @Override
    public String doValidateTask( int nIdResource, String strResourceType, HttpServletRequest request, Locale locale, ITask task )
    {
        return null; // null = validation OK
    }

    /**
     * Displays the executed task history
     */
    @Override
    public String getDisplayTaskInformation( int nIdHistory, HttpServletRequest request, Locale locale, ITask task )
    {
        Map<String, Object> model = new HashMap<>( );
        Task{Name}Config config = _taskConfigService.findByPrimaryKey( task.getId( ) );
        model.put( MARK_CONFIG, config );

        HtmlTemplate template = AppTemplateService.getTemplate( TEMPLATE_INFO, locale, model );
        return template.getHtml( );
    }
}
```

`ITaskComponent` methods: `setTaskType`, `isInvoked`, `getDisplayTaskForm`, `getDisplayConfigForm`, `getDisplayTaskInformation`, `doValidateTask`, `doSaveConfig`. There is no `getTaskInformationXml`.

## 10. Templates

### Config (workflow admin)

**`task_{name}_config.html`**

```html
<@row>
    <@columns>
        <@formGroup labelKey="#i18n{module.workflow.{pluginName}.task.{name}.config.title}" mandatory=true>
            <@input type="text" name="title" id="title" value=config.title!'' />
        </@formGroup>

        <@formGroup labelKey="#i18n{module.workflow.{pluginName}.task.{name}.config.targetState}">
            <@input type="text" name="target_state" id="target_state" value=config.targetState!'' />
        </@formGroup>

        <@formGroup>
            <@checkBox name="notify_user" id="notify_user" orientation='switch' value='true'
                labelKey="#i18n{module.workflow.{pluginName}.task.{name}.config.notifyUser}"
                checked=config.notifyUser!false />
        </@formGroup>
    </@columns>
</@row>
```

### Form (action execution)

**`task_{name}_form.html`**

```html
<#if config??>
    <@alert color='info'>
        #i18n{module.workflow.{pluginName}.task.{name}.form.info}
        <strong>${config.targetState!}</strong>
    </@alert>
</#if>
```

### Information (history)

**`task_{name}_information.html`**

```html
<div class="task-information">
    <#if config??>
        <p>
            <strong>#i18n{module.workflow.{pluginName}.task.{name}.info.targetState}:</strong>
            ${config.targetState!}
        </p>
    <#else>
        <p class="text-muted">#i18n{module.workflow.{pluginName}.task.{name}.info.noConfig}</p>
    </#if>
</div>
```

