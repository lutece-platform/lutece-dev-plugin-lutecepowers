---
name: lutece-workflow
description: "Use when creating or modifying a Lutece 8 workflow module: tasks, CDI producers, task components, templates, configuration DAOs. Triggers on 'workflow', 'task', 'workflow module', 'TaskComponent'."
---

# Lutece 8 Workflow Module Development

Complete guide for creating and modifying Lutece 8 workflow modules.

> Before writing workflow code, consult `~/.lutece-references/lutece-wf-module-workflow-forms/` (the reference module) (search the references).

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
│   │   │   ├── Task{Name}ConfigProducer.java
│   │   │   └── Task{Name}ConfigServiceProducer.java
│   │   ├── web/
│   │   │   └── {Name}TaskComponent.java
│   │   └── resources/
│   │       └── workflow-{pluginName}_messages.properties
│   ├── sql/plugins/workflow/modules/{pluginName}/plugin/
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

## Build order

Thirteen files, in this order. Steps 1 to 7 and 10 are full class and template models, kept apart because
they are long; open the file when you reach them.

| # | Produces | Where |
|---|---|---|
| 1 | the `ITask` implementation — what the task does when the action fires | [reference/task-classes.md](reference/task-classes.md) |
| 2 | the config entity holding the task's settings | idem |
| 3 | the config DAO | idem |
| 4 | the `TaskType` CDI producer that registers the task | idem |
| 5 | the config producer | idem |
| 6 | the config service producer | idem |
| 7 | the `TaskComponent` — back-office display and validation | [reference/task-component.md](reference/task-component.md) |
| 10 | the FreeMarker templates for the config and information views | idem |
| 8, 9, 11, 12, 13 | properties, plugin descriptor, SQL, i18n, pom — below | this file |

## 8. Configuration Properties

**`webapp/WEB-INF/conf/plugins/workflow-{pluginName}.properties`**

```properties
# Task {Name} Configuration
workflow-{pluginName}.task{Name}.key=task{Name}
workflow-{pluginName}.task{Name}.titleI18nKey=module.workflow.{pluginName}.task.{name}.title
workflow-{pluginName}.task{Name}.beanName=workflow-{pluginName}.task{Name}
workflow-{pluginName}.task{Name}.configBeanName=workflow-{pluginName}.task{Name}Config
workflow-{pluginName}.task{Name}.configRequired=true
workflow-{pluginName}.task{Name}.formTaskRequired=false
workflow-{pluginName}.task{Name}.taskForAutomaticAction=true
```

## 9. Plugin Descriptor

**`webapp/WEB-INF/plugins/workflow-{pluginName}.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plug-in>
    <name>workflow-{pluginName}</name>
    <class>fr.paris.lutece.portal.service.plugin.PluginDefaultImplementation</class>
    <version>1.0.0-SNAPSHOT</version>
    <description>module.workflow.{pluginName}.plugin.description</description>
    <provider>module.workflow.{pluginName}.plugin.provider</provider>
    <provider-url>http://lutece.paris.fr</provider-url>
    <icon-url>themes/admin/shared/images/apps.svg</icon-url>
    <copyright>Copyright (c) {currentYear}</copyright>
    <db-pool-required>1</db-pool-required>

    <core-version-dependency>
        <min-core-version>8.0.0</min-core-version>
        <max-core-version/>
    </core-version-dependency>
</plug-in>
```

## 11. SQL

`src/sql/plugins/workflow/modules/{pluginName}/plugin/create_db_workflow-{pluginName}.sql` — Liquibase header required (`rules/sql-liquibase.md`; reference `create_db_workflow-forms.sql:1-3`):

```sql
-- liquibase formatted sql
-- changeset workflow-{pluginName}:create_db_workflow-{pluginName}.sql
-- preconditions onFail:MARK_RAN onError:WARN
DROP TABLE IF EXISTS workflow_task_{name}_config;
CREATE TABLE workflow_task_{name}_config (
    id_task INT NOT NULL,
    title VARCHAR(255) DEFAULT NULL,
    target_state VARCHAR(255) DEFAULT NULL,
    notify_user SMALLINT DEFAULT 0,
    PRIMARY KEY (id_task)
);
```

## 12. i18n

**`workflow-{pluginName}_messages.properties`**

```properties
# Plugin
plugin.description=Workflow module for {pluginName}
plugin.provider=City of Paris

# Task {Name}
task.{name}.title={Name} Task
task.{name}.config.title=Title
task.{name}.config.targetState=Target State
task.{name}.config.notifyUser=Notify User
task.{name}.form.info=This action will change the state to:
task.{name}.info.targetState=Target State
task.{name}.info.noConfig=No configuration found
```

## 13. pom.xml Dependencies

`library-workflow-core` comes transitively through `plugin-workflow`; do not declare it (reference: `module-workflow-forms/pom.xml`).

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
        <version>[7.0.0,)</version>
        <type>lutece-plugin</type>
    </dependency>
    <!-- Business plugin if needed -->
    <dependency>
        <groupId>fr.paris.lutece.plugins</groupId>
        <artifactId>plugin-{pluginName}</artifactId>
        <version>[1.0.0,)</version>
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
| TaskType producer | `TaskType{Name}Producer` | `TaskTypeProducer` (forms groups them) |
| Config producer | `Task{Name}ConfigProducer` | `EditFormResponseConfigProducer` |
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
- [ ] `Task{Name}ConfigProducer.java` - Producer @Produces @Dependent @Named config (the `configBeanName`)
- [ ] `Task{Name}ConfigServiceProducer.java` - Producer ITaskConfigService
- [ ] `{Name}TaskComponent.java` - UI with @ApplicationScoped @Named, ctor injecting `ITaskType` + `ITaskConfigService`
- [ ] `workflow-{plugin}.properties` - TaskType config
- [ ] `task_{name}_config.html` - Config template
- [ ] `task_{name}_form.html` - Form template
- [ ] `task_{name}_information.html` - Info template
- [ ] SQL table `workflow_task_{name}_config`
- [ ] i18n keys
