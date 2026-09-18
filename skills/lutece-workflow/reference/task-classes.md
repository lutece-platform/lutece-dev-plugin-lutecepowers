# Workflow task — the six back-end classes

Full templates for steps 1 to 6. The order and what each one is for are in SKILL.md.

## Contents
- 1. Task Implementation
- 2. Task Config
- 3. Task Config DAO
- 4. TaskType Producer (CDI)
- 5. Config Producer
- 6. ConfigService Producer

## 1. Task Implementation

### Simple Task (no internal state)

```java
package fr.paris.lutece.plugins.workflow.modules.{pluginName}.service;

import fr.paris.lutece.plugins.workflowcore.service.task.SimpleTask;
import fr.paris.lutece.plugins.workflowcore.service.config.ITaskConfigService;
import fr.paris.lutece.plugins.workflowcore.service.resource.IResourceHistoryService;
import fr.paris.lutece.plugins.workflowcore.business.resource.ResourceHistory;
import fr.paris.lutece.api.user.User;
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
    public void processTask( int nIdResourceHistory, HttpServletRequest request, Locale locale, User user )
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

`ITask` signatures (library-workflow-core `ITask.java`): the 3-arg `processTask( int, HttpServletRequest, Locale )` is `@Deprecated`; override the 4-arg one with `fr.paris.lutece.api.user.User`.

### Task with Result (conditional branching)

```java
@Dependent
@Named( "workflow-{pluginName}.task{Name}" )
public class Task{Name} extends Task
{
    @Override
    public boolean processTaskWithResult( int nIdResource, String strResourceType, int nIdResourceHistory, HttpServletRequest request, Locale locale, User user )
    {
        // return true  → default state
        // return false → alternative state
        return someCondition;
    }
}
```

The 4-arg `processTaskWithResult( int, HttpServletRequest, Locale, User )` is `@Deprecated`; only the 6-arg overload above is current.

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
| `configBeanName` | `ITaskConfig` producer bean name (@Named) — resolved by `TaskFactory.newTaskConfig` via `CDI.current().select( ITaskConfig.class, NamedLiteral.of( configBeanName ) )`, never the component |
| `configRequired` | true = config mandatory before use |
| `formTaskRequired` | true = requires a form during action execution |
| `taskForAutomaticAction` | true = can be used in automatic actions |

## 5. Config Producer

`TaskFactory` needs a `@Named` producer for the config object itself (reference: workflow-forms `EditFormResponseConfigProducer`):

```java
package fr.paris.lutece.plugins.workflow.modules.{pluginName}.service;

import fr.paris.lutece.plugins.workflow.modules.{pluginName}.business.Task{Name}Config;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.context.Dependent;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Named;

@ApplicationScoped
public class Task{Name}ConfigProducer
{
    @Produces
    @Dependent
    @Named( "workflow-{pluginName}.task{Name}Config" )
    public Task{Name}Config produceTask{Name}Config( )
    {
        return new Task{Name}Config( );
    }
}
```

## 6. ConfigService Producer

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

