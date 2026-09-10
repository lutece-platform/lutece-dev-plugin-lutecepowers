---
name: lutece-workflow
description: "Use when creating or modifying a Lutece 8 workflow module: tasks, CDI producers, task components, templates, configuration DAOs. Triggers on 'workflow', 'task', 'workflow module', 'TaskComponent'."
---

# Lutece 8 Workflow Module Development

Complete guide for creating and modifying Lutece 8 workflow modules.

> Before writing workflow code, consult `~/.lutece-references/lutece-wf-module-workflow-forms/` (the reference module) using Read, Grep and Glob.

## Workflow Architecture

```
plugin-workflow (core)
├── library-workflow-core        # Base interfaces and classes
│   ├── ITask, Task, SimpleTask
│   ├── ITaskType, TaskType
│   ├── ITaskConfigService, TaskConfigService
│   └── ITaskConfigDAO
│
└── module-workflow-{xxx}        # Custom module
    ├── business/                # Config + DAO
    ├── service/                 # Task + Producers
    └── web/                     # TaskComponent
```

## Workflow Module Structure

```
module-workflow-{pluginName}/
├── pom.xml
├── src/
│   ├── java/fr/paris/lutece/plugins/workflow/modules/{pluginName}/
│   │   ├── business/
│   │   │   ├── Task{Name}Config.java
│   │   │   └── Task{Name}ConfigDAO.java
│   │   ├── service/
│   │   │   ├── Task{Name}.java
│   │   │   ├── TaskType{Name}Producer.java
│   │   │   └── Task{Name}ConfigServiceProducer.java
│   │   ├── web/
│   │   │   └── {Name}TaskComponent.java
│   │   └── resources/
│   │       └── workflow-{pluginName}_messages.properties
│   ├── sql/plugins/workflow/modules/
│   │   └── create_db_workflow-{pluginName}.sql
│   └── main/resources/META-INF/
│       └── beans.xml
└── webapp/WEB-INF/
    ├── conf/plugins/
    │   └── workflow-{pluginName}.properties
    ├── plugins/
    │   └── workflow-{pluginName}.xml
    └── templates/admin/plugins/workflow/modules/{pluginName}/
        ├── task_{name}_config.html
        ├── task_{name}_form.html
        └── task_{name}_information.html
```

## 1. Task Implementation

### Simple Task (no internal state)

```java
package fr.paris.lutece.plugins.workflow.modules.{pluginName}.service;

import fr.paris.lutece.plugins.workflowcore.service.task.SimpleTask;
import fr.paris.lutece.plugins.workflowcore.service.config.ITaskConfigService;
import fr.paris.lutece.plugins.workflowcore.service.resource.IResourceHistoryService;
import fr.paris.lutece.plugins.workflowcore.business.resource.ResourceHistory;
import fr.paris.lutece.portal.business.user.AdminUser;
import jakarta.enterprise.context.Dependent;
import jakarta.inject.Inject;
import jakarta.inject.Named;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Locale;

@Dependent
@Named( "workflow-{pluginName}.task{Name}" )
public class Task{Name} extends SimpleTask
{
    public static final String BEAN_CONFIG_SERVICE = "workflow-{pluginName}.task{Name}ConfigService";

    @Inject
    @Named( BEAN_CONFIG_SERVICE )
    private ITaskConfigService _taskConfigService;

    @Inject
    private IResourceHistoryService _resourceHistoryService;

    @Override
    public void processTask( int nIdResourceHistory, HttpServletRequest request, Locale locale )
    {
        ResourceHistory resourceHistory = _resourceHistoryService.findByPrimaryKey( nIdResourceHistory );
        Task{Name}Config config = _taskConfigService.findByPrimaryKey( this.getId( ) );

        // Business logic here
        // resourceHistory.getIdResource() = entity ID
        // resourceHistory.getResourceType() = resource type
    }

    @Override
    public String getTitle( Locale locale )
    {
        Task{Name}Config config = _taskConfigService.findByPrimaryKey( this.getId( ) );
        return config != null ? config.getTitle( ) : "Task {Name}";
    }

    @Override
    public void doRemoveConfig( )
    {
        _taskConfigService.remove( this.getId( ) );
    }
}
```

### Task with Result (conditional branching)

```java
@Dependent
@Named( "workflow-{pluginName}.task{Name}" )
public class Task{Name} extends Task
{
    @Override
    public boolean processTaskWithResult( int nIdResourceHistory, HttpServletRequest request, Locale locale, AdminUser user )
    {
        // return true  → default state
        // return false → alternative state
        return someCondition;
    }
}
```

## 2. Task Config

```java
package fr.paris.lutece.plugins.workflow.modules.{pluginName}.business;

import fr.paris.lutece.plugins.workflowcore.business.config.TaskConfig;

public class Task{Name}Config extends TaskConfig
{
    private String _strTitle;
    private String _strTargetState;
    private boolean _bNotifyUser;

    // Getters/Setters with Lutece conventions (_str, _b, _n, etc.)
    public String getTitle( ) { return _strTitle; }
    public void setTitle( String strTitle ) { _strTitle = strTitle; }

    public String getTargetState( ) { return _strTargetState; }
    public void setTargetState( String strTargetState ) { _strTargetState = strTargetState; }

    public boolean isNotifyUser( ) { return _bNotifyUser; }
    public void setNotifyUser( boolean bNotifyUser ) { _bNotifyUser = bNotifyUser; }
}
```

## 3. Task Config DAO

```java
package fr.paris.lutece.plugins.workflow.modules.{pluginName}.business;

import fr.paris.lutece.plugins.workflowcore.business.config.ITaskConfigDAO;
import fr.paris.lutece.util.sql.DAOUtil;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Named;

@ApplicationScoped
@Named( "workflow-{pluginName}.task{Name}ConfigDAO" )
public class Task{Name}ConfigDAO implements ITaskConfigDAO<Task{Name}Config>
{
    private static final String SQL_QUERY_SELECT = "SELECT id_task, title, target_state, notify_user FROM workflow_task_{name}_config WHERE id_task = ?";
    private static final String SQL_QUERY_INSERT = "INSERT INTO workflow_task_{name}_config ( id_task, title, target_state, notify_user ) VALUES ( ?, ?, ?, ? )";
    private static final String SQL_QUERY_UPDATE = "UPDATE workflow_task_{name}_config SET title = ?, target_state = ?, notify_user = ? WHERE id_task = ?";
    private static final String SQL_QUERY_DELETE = "DELETE FROM workflow_task_{name}_config WHERE id_task = ?";

    @Override
    public void insert( Task{Name}Config config )
    {
        try ( DAOUtil daoUtil = new DAOUtil( SQL_QUERY_INSERT ) )
        {
            int nIndex = 1;
            daoUtil.setInt( nIndex++, config.getIdTask( ) );
            daoUtil.setString( nIndex++, config.getTitle( ) );
            daoUtil.setString( nIndex++, config.getTargetState( ) );
            daoUtil.setBoolean( nIndex++, config.isNotifyUser( ) );
            daoUtil.executeUpdate( );
        }
    }

    @Override
    public void store( Task{Name}Config config )
    {
        try ( DAOUtil daoUtil = new DAOUtil( SQL_QUERY_UPDATE ) )
        {
            int nIndex = 1;
            daoUtil.setString( nIndex++, config.getTitle( ) );
            daoUtil.setString( nIndex++, config.getTargetState( ) );
            daoUtil.setBoolean( nIndex++, config.isNotifyUser( ) );
            daoUtil.setInt( nIndex++, config.getIdTask( ) );
            daoUtil.executeUpdate( );
        }
    }

    @Override
    public Task{Name}Config load( int nIdTask )
    {
        Task{Name}Config config = null;
        try ( DAOUtil daoUtil = new DAOUtil( SQL_QUERY_SELECT ) )
        {
            daoUtil.setInt( 1, nIdTask );
            daoUtil.executeQuery( );
            if ( daoUtil.next( ) )
            {
                config = new Task{Name}Config( );
                int nIndex = 1;
                config.setIdTask( daoUtil.getInt( nIndex++ ) );
                config.setTitle( daoUtil.getString( nIndex++ ) );
                config.setTargetState( daoUtil.getString( nIndex++ ) );
                config.setNotifyUser( daoUtil.getBoolean( nIndex++ ) );
            }
        }
        return config;
    }

    @Override
    public void delete( int nIdTask )
    {
        try ( DAOUtil daoUtil = new DAOUtil( SQL_QUERY_DELETE ) )
        {
            daoUtil.setInt( 1, nIdTask );
            daoUtil.executeUpdate( );
        }
    }
}
```

## 4. TaskType Producer (CDI)

```java
package fr.paris.lutece.plugins.workflow.modules.{pluginName}.service;

import fr.paris.lutece.plugins.workflowcore.business.task.ITaskType;
import fr.paris.lutece.plugins.workflowcore.business.task.TaskType;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Named;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
public class TaskType{Name}Producer
{
    @Produces
    @ApplicationScoped
    @Named( "workflow-{pluginName}.taskType{Name}" )
    public ITaskType produceTaskType{Name}(
        @ConfigProperty( name = "workflow-{pluginName}.task{Name}.key" ) String strKey,
        @ConfigProperty( name = "workflow-{pluginName}.task{Name}.titleI18nKey" ) String strTitleI18nKey,
        @ConfigProperty( name = "workflow-{pluginName}.task{Name}.beanName" ) String strBeanName,
        @ConfigProperty( name = "workflow-{pluginName}.task{Name}.configBeanName" ) String strConfigBeanName,
        @ConfigProperty( name = "workflow-{pluginName}.task{Name}.configRequired", defaultValue = "false" ) boolean bConfigRequired,
        @ConfigProperty( name = "workflow-{pluginName}.task{Name}.formTaskRequired", defaultValue = "false" ) boolean bFormTaskRequired,
        @ConfigProperty( name = "workflow-{pluginName}.task{Name}.taskForAutomaticAction", defaultValue = "false" ) boolean bTaskForAutomaticAction )
    {
        TaskType taskType = new TaskType( );
        taskType.setKey( strKey );
        taskType.setTitleI18nKey( strTitleI18nKey );
        taskType.setBeanName( strBeanName );
        taskType.setConfigBeanName( strConfigBeanName );
        taskType.setConfigRequired( bConfigRequired );
        taskType.setFormTaskRequired( bFormTaskRequired );
        taskType.setTaskForAutomaticAction( bTaskForAutomaticAction );
        return taskType;
    }
}
```

### TaskType Properties

| Property | Description |
|----------|-------------|
| `key` | Unique task identifier |
| `titleI18nKey` | i18n key for the title in admin |
| `beanName` | Task bean name (@Named) |
| `configBeanName` | TaskComponent bean name (@Named) |
| `configRequired` | true = config mandatory before use |
| `formTaskRequired` | true = requires a form during action execution |
| `taskForAutomaticAction` | true = can be used in automatic actions |

## 5. ConfigService Producer

```java
package fr.paris.lutece.plugins.workflow.modules.{pluginName}.service;

import fr.paris.lutece.plugins.workflowcore.business.config.ITaskConfigDAO;
import fr.paris.lutece.plugins.workflowcore.service.config.ITaskConfigService;
import fr.paris.lutece.plugins.workflowcore.service.config.TaskConfigService;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Named;

@ApplicationScoped
public class Task{Name}ConfigServiceProducer
{
    @Produces
    @ApplicationScoped
    @Named( Task{Name}.BEAN_CONFIG_SERVICE )
    public ITaskConfigService produceTask{Name}ConfigService(
        @Named( "workflow-{pluginName}.task{Name}ConfigDAO" ) ITaskConfigDAO<Task{Name}Config> taskConfigDAO )
    {
        TaskConfigService taskConfigService = new TaskConfigService( );
        taskConfigService.setTaskConfigDAO( (ITaskConfigDAO) taskConfigDAO );
        return taskConfigService;
    }
}
```

## 6. Task Component (UI)

```java
package fr.paris.lutece.plugins.workflow.modules.{pluginName}.web;

import fr.paris.lutece.plugins.workflow.web.task.AbstractTaskComponent;
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

    @Inject
    @Named( Task{Name}.BEAN_CONFIG_SERVICE )
    private ITaskConfigService _taskConfigService;

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

    @Override
    public String getTaskInformationXml( int nIdHistory, HttpServletRequest request, Locale locale, ITask task )
    {
        return null;
    }
}
```

## 7. Configuration Properties

**`webapp/WEB-INF/conf/plugins/workflow-{pluginName}.properties`**

```properties
# Task {Name} Configuration
workflow-{pluginName}.task{Name}.key=task{Name}
workflow-{pluginName}.task{Name}.titleI18nKey=module.workflow.{pluginName}.task.{name}.title
workflow-{pluginName}.task{Name}.beanName=workflow-{pluginName}.task{Name}
workflow-{pluginName}.task{Name}.configBeanName=workflow-{pluginName}.task{Name}Component
workflow-{pluginName}.task{Name}.configRequired=true
workflow-{pluginName}.task{Name}.formTaskRequired=false
workflow-{pluginName}.task{Name}.taskForAutomaticAction=true
```

## 8. Plugin Descriptor

**`webapp/WEB-INF/plugins/workflow-{pluginName}.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plug-in>
    <name>workflow-{pluginName}</name>
    <class>fr.paris.lutece.portal.service.plugin.PluginDefaultImplementation</class>
    <version>1.0.0-SNAPSHOT</version>
    <description>module.workflow.{pluginName}.plugin.description</description>
    <provider>City of Paris</provider>
    <provider-url>http://lutece.paris.fr</provider-url>
    <icon-url>images/admin/skin/feature_default_icon.png</icon-url>
    <copyright>Copyright (c) 2025</copyright>
    <db-pool-required>1</db-pool-required>

    <core-version-dependency>
        <min-core-version>8.0.0</min-core-version>
    </core-version-dependency>
</plug-in>
```

## 9. Templates

### Config (workflow admin)

**`task_{name}_config.html`**

```html
<@row>
    <@columns>
        <@formGroup labelKey="module.workflow.{pluginName}.task.{name}.config.title" mandatory=true>
            <@input type="text" name="title" id="title" value=config.title!'' />
        </@formGroup>

        <@formGroup labelKey="module.workflow.{pluginName}.task.{name}.config.targetState">
            <@input type="text" name="target_state" id="target_state" value=config.targetState!'' />
        </@formGroup>

        <@formGroup>
            <@checkBox name="notify_user" id="notify_user"
                labelKey="module.workflow.{pluginName}.task.{name}.config.notifyUser"
                checked=config.notifyUser!false />
        </@formGroup>
    </@columns>
</@row>
```

### Form (action execution)

**`task_{name}_form.html`**

```html
<div class="alert alert-info">
    <#if config??>
        #i18n{module.workflow.{pluginName}.task.{name}.form.info}
        <strong>${config.targetState!}</strong>
    </#if>
</div>
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

## 10. SQL

```sql
DROP TABLE IF EXISTS workflow_task_{name}_config;
CREATE TABLE workflow_task_{name}_config (
    id_task INT NOT NULL,
    title VARCHAR(255) DEFAULT NULL,
    target_state VARCHAR(255) DEFAULT NULL,
    notify_user SMALLINT DEFAULT 0,
    PRIMARY KEY (id_task)
);
```

## 11. i18n

**`workflow-{pluginName}_messages.properties`**

```properties
# Plugin
plugin.description=Workflow module for {pluginName}

# Task {Name}
task.{name}.title={Name} Task
task.{name}.config.title=Title
task.{name}.config.targetState=Target State
task.{name}.config.notifyUser=Notify User
task.{name}.form.info=This action will change the state to:
task.{name}.info.targetState=Target State
task.{name}.info.noConfig=No configuration found
```

## 12. pom.xml Dependencies

```xml
<dependencies>
    <dependency>
        <groupId>fr.paris.lutece</groupId>
        <artifactId>lutece-core</artifactId>
        <version>[8.0.0,)</version>
        <type>lutece-core</type>
    </dependency>
    <dependency>
        <groupId>fr.paris.lutece.plugins</groupId>
        <artifactId>plugin-workflow</artifactId>
        <version>[7.0.0-SNAPSHOT,)</version>
        <type>lutece-plugin</type>
    </dependency>
    <dependency>
        <groupId>fr.paris.lutece.plugins</groupId>
        <artifactId>library-workflow-core</artifactId>
        <version>[4.0.0-SNAPSHOT,)</version>
    </dependency>
    <!-- Business plugin if needed -->
    <dependency>
        <groupId>fr.paris.lutece.plugins</groupId>
        <artifactId>plugin-{pluginName}</artifactId>
        <version>[1.0.0-SNAPSHOT,)</version>
        <type>lutece-plugin</type>
    </dependency>
</dependencies>
```

## Naming Conventions

| Element | Pattern | Example |
|---------|---------|---------|
| Module | `module-workflow-{plugin}` | `module-workflow-forms` |
| Package | `fr.paris.lutece.plugins.workflow.modules.{plugin}` | |
| Task class | `Task{Name}` | `TaskEditFormResponse` |
| Config class | `Task{Name}Config` | `TaskEditFormResponseConfig` |
| DAO class | `Task{Name}ConfigDAO` | `TaskEditFormResponseConfigDAO` |
| Producer | `TaskType{Name}Producer` | `TaskTypeEditFormResponseProducer` |
| Component | `{Name}TaskComponent` | `EditFormResponseTaskComponent` |
| Bean names | `workflow-{plugin}.task{Name}` | `workflow-forms.taskEditFormResponse` |
| Properties prefix | `workflow-{plugin}.task{Name}.` | |
| Templates | `task_{name}_*.html` | `task_edit_form_response_config.html` |
| SQL table | `workflow_task_{name}_config` | `workflow_task_edit_form_response_config` |
| i18n prefix | `module.workflow.{plugin}.task.{name}` | |

## Reference Sources

| Need | Repo to consult | Key files |
|------|----------------|-----------|
| **Workflow core architecture** | `lutece-wf-library-workflow-core` | `src/java/**/service/task/`, `src/java/**/business/` |
| **Workflow plugin (engine)** | `lutece-wf-plugin-workflow` | `src/java/**/web/`, `src/java/**/service/` |
| **Complete workflow module (main example)** | `lutece-wf-module-workflow-forms` | Task, Producer, Component, DAO, templates |
| **Module with assignment** | `lutece-wf-module-workflow-forms-automatic-assignment` | Automatic assignment pattern |
| **Module with upload** | `lutece-wf-module-workflow-upload` | File handling in workflow |
| **PDF module** | `lutece-wf-module-workflow-formstopdf` | Document generation |

## New Task Checklist

- [ ] `Task{Name}Config.java` - Config entity
- [ ] `Task{Name}ConfigDAO.java` - DAO with @Named
- [ ] `Task{Name}.java` - Task with @Dependent @Named
- [ ] `TaskType{Name}Producer.java` - Producer @Produces ITaskType
- [ ] `Task{Name}ConfigServiceProducer.java` - Producer ITaskConfigService
- [ ] `{Name}TaskComponent.java` - UI with @ApplicationScoped @Named
- [ ] `workflow-{plugin}.properties` - TaskType config
- [ ] `task_{name}_config.html` - Config template
- [ ] `task_{name}_form.html` - Form template
- [ ] `task_{name}_information.html` - Info template
- [ ] SQL table `workflow_task_{name}_config`
- [ ] i18n keys
