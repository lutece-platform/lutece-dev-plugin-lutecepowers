---
name: lutece-rbac
description: "Use when adding or reviewing permissions in a Lutece 8 plugin: RBAC entity permissions, ResourceIdService, plugin.xml declaration, JspBean authorization checks. Triggers on 'RBAC', 'permission', 'right', 'authorization', 'ResourceIdService'."
---

# Lutece 8 RBAC Implementation

> Before implementing RBAC, consult `~/.lutece-references/lutece-form-plugin-forms/` — specifically `FormsResourceIdService.java`, `AbstractJspBean.java`, and `FormJspBean.java`. Caveat: `FormJspBean` still uses the deprecated `getModel()`, manual `LocalizedPaginator` pagination and manual `MARK_TOKEN` puts although its `@Controller` has `securityTokenEnabled=true`; copy its RBAC logic only, and follow `rules/web-bean.md` for Models, pagination and CSRF.

## Architecture Overview

```
Entity (implements RBACResource)
    ↓ getResourceTypeCode() / getResourceId()
ResourceIdService (registers type + permissions)
    ↓ register() → ResourceTypeManager
plugin.xml (declares <rbac-resource-type-class>)
    ↓
RBACService.isAuthorized(type, id, permission, user)
    ↓ checks user roles against RBAC table
JspBean (enforces authorization)
```

## Step 1 — Entity Implements RBACResource

```java
import fr.paris.lutece.portal.service.rbac.RBACResource;

public class Entity implements RBACResource
{
    public static final String RESOURCE_TYPE = "MYPLUGIN_ENTITY";

    private int _nId;

    @Override
    public String getResourceTypeCode( )
    {
        return RESOURCE_TYPE;
    }

    @Override
    public String getResourceId( )
    {
        return String.valueOf( _nId );
    }
}
```

**Rules:**
- `RESOURCE_TYPE` is a unique constant — use `PLUGINNAME_ENTITYNAME` in uppercase
- `getResourceId()` returns the ID as a String
- The entity class must also have its normal fields, getters/setters

## Step 2 — ResourceIdService

```java
import fr.paris.lutece.portal.service.rbac.Permission;
import fr.paris.lutece.portal.service.rbac.ResourceIdService;
import fr.paris.lutece.portal.service.rbac.ResourceType;
import fr.paris.lutece.portal.service.rbac.ResourceTypeManager;

public class EntityResourceIdService extends ResourceIdService
{
    public static final String PERMISSION_CREATE = "CREATE";
    public static final String PERMISSION_MODIFY = "MODIFY";
    public static final String PERMISSION_DELETE = "DELETE";
    public static final String PERMISSION_VIEW = "VIEW";

    private static final String PROPERTY_LABEL_RESOURCE_TYPE = "myplugin.permission.resourceType.entity.label";
    private static final String PROPERTY_LABEL_CREATE = "myplugin.permission.resourceType.entity.create";
    private static final String PROPERTY_LABEL_MODIFY = "myplugin.permission.resourceType.entity.modify";
    private static final String PROPERTY_LABEL_DELETE = "myplugin.permission.resourceType.entity.delete";
    private static final String PROPERTY_LABEL_VIEW = "myplugin.permission.resourceType.entity.view";

    public EntityResourceIdService( )
    {
        setPluginName( "myplugin" );
    }

    @Override
    public void register( )
    {
        ResourceType rt = new ResourceType( );
        rt.setResourceIdServiceClass( EntityResourceIdService.class.getName( ) );
        rt.setPluginName( getPluginName( ) );
        rt.setResourceTypeKey( Entity.RESOURCE_TYPE );
        rt.setResourceTypeLabelKey( PROPERTY_LABEL_RESOURCE_TYPE );

        Permission permission;

        permission = new Permission( );
        permission.setPermissionKey( PERMISSION_CREATE );
        permission.setPermissionTitleKey( PROPERTY_LABEL_CREATE );
        rt.registerPermission( permission );

        permission = new Permission( );
        permission.setPermissionKey( PERMISSION_MODIFY );
        permission.setPermissionTitleKey( PROPERTY_LABEL_MODIFY );
        rt.registerPermission( permission );

        permission = new Permission( );
        permission.setPermissionKey( PERMISSION_DELETE );
        permission.setPermissionTitleKey( PROPERTY_LABEL_DELETE );
        rt.registerPermission( permission );

        permission = new Permission( );
        permission.setPermissionKey( PERMISSION_VIEW );
        permission.setPermissionTitleKey( PROPERTY_LABEL_VIEW );
        rt.registerPermission( permission );

        ResourceTypeManager.registerResourceType( rt );
    }

    @Override
    public ReferenceList getResourceIdList( Locale locale )
    {
        return EntityHome.findReferenceList( );
    }

    @Override
    public String getTitle( String strId, Locale locale )
    {
        Entity entity = EntityHome.findByPrimaryKey( Integer.parseInt( strId ) );
        return ( entity != null ) ? entity.getTitle( ) : "";
    }
}
```

**Rules:**
- One `ResourceIdService` per RBAC-protected entity
- Permission constants are `public static final` — reused in JspBean
- `PROPERTY_LABEL_*` keys use the full prefix (plugin name included) because they are Java constants used with `I18nService`
- `register()` creates the ResourceType, registers all permissions, and calls `ResourceTypeManager.registerResourceType()`
- `getResourceIdList()` returns all resources for the admin RBAC configuration UI
- `getTitle()` returns a human-readable name for a specific resource

## Step 3 — plugin.xml Declaration

```xml
<rbac-resource-types>
    <rbac-resource-type>
        <rbac-resource-type-class>
            fr.paris.lutece.plugins.myplugin.service.EntityResourceIdService
        </rbac-resource-type-class>
    </rbac-resource-type>
</rbac-resource-types>
```

Add inside `<plug-in>`, after `<admin-features>`. One `<rbac-resource-type>` per ResourceIdService.

## Step 4 — i18n (messages.properties)

```properties
# RBAC resource type label
permission.resourceType.entity.label=MyPlugin - Entities

# Permission labels
permission.resourceType.entity.create=Create an entity
permission.resourceType.entity.modify=Modify an entity
permission.resourceType.entity.delete=Remove an entity
permission.resourceType.entity.view=View an entity
```

No prefix in the properties file (prefix is added in Java/templates only).

## Step 5 — JspBean Authorization Checks

### Check on wildcard (all resources of a type)

```java
// Before allowing access to a CREATE form
User user = getUser( );

if ( !RBACService.isAuthorized( Entity.RESOURCE_TYPE, RBAC.WILDCARD_RESOURCES_ID,
        EntityResourceIdService.PERMISSION_CREATE, user ) )
{
    throw new AccessDeniedException( "Unauthorized" );
}
```

### Check on a specific resource

```java
// Before allowing MODIFY or DELETE on a specific entity
String strId = request.getParameter( PARAMETER_ID );
Entity entity = EntityHome.findByPrimaryKey( Integer.parseInt( strId ) );

if ( entity == null || !RBACService.isAuthorized( Entity.RESOURCE_TYPE,
        String.valueOf( entity.getId( ) ), EntityResourceIdService.PERMISSION_MODIFY, user ) )
{
    throw new AccessDeniedException( "Unauthorized" );
}
```

### Pass permissions to template (for conditional display)

```java
// In the manage view — pass permission flags to template (Models model is a method parameter, see rules/web-bean.md)
model.put( "canCreate", RBACService.isAuthorized( Entity.RESOURCE_TYPE,
    RBAC.WILDCARD_RESOURCES_ID, EntityResourceIdService.PERMISSION_CREATE, getUser( ) ) );
model.put( "canDelete", RBACService.isAuthorized( Entity.RESOURCE_TYPE,
    RBAC.WILDCARD_RESOURCES_ID, EntityResourceIdService.PERMISSION_DELETE, getUser( ) ) );
```

### Template conditional display

```html
<#if canCreate>
    <@aButton href='jsp/admin/plugins/myplugin/ManageEntities.jsp?view=createEntity' buttonIcon='plus' title='#i18n{myplugin.manage_entities.buttonAdd}' color='primary' />
</#if>

<#if canDelete>
    <@aButton href='jsp/admin/plugins/myplugin/ManageEntities.jsp?view=confirmRemoveEntity&id=${entity.id}' buttonIcon='trash' color='danger' title='#i18n{portal.util.labelDelete}' />
</#if>
```

### Filter collections by permission

```java
// Filter a list to only authorized resources
Collection<Entity> authorizedEntities = RBACService.getAuthorizedCollection(
    EntityHome.findAll( ),
    EntityResourceIdService.PERMISSION_VIEW,
    getUser( )
);
```

### Filter actions per entity (forms pattern)

```java
// Each entity gets only the actions the user is authorized to perform
for ( Entity entity : paginator.getPageItems( ) )
{
    List<EntityAction> listAuthorizedActions =
        (List<EntityAction>) RBACService.getAuthorizedActionsCollection(
            listAllActions, entity, (User) getUser( ) );
    entity.setActions( listAuthorizedActions );
}
```

Requires `EntityAction` to implement `RBACAction` (return permission key via `getPermission()`).

## Advanced — Helper Method

CSRF is handled by the core when the `@Controller` has `securityTokenEnabled = true` (`rules/web-bean.md` § CSRF Policy): no `SecurityTokenService` injection nor `validate()` in the bean. The helper only checks RBAC:

```java
protected void checkUserPermission( String strResourceType, String strResourceId, String strPermission, HttpServletRequest request )
    throws AccessDeniedException
{
    if ( !RBACService.isAuthorized( strResourceType, strResourceId, strPermission, (User) AdminUserService.getAdminUser( request ) ) )
    {
        throw new AccessDeniedException( "Unauthorized" );
    }
}
```

Usage:
```java
@View( VIEW_CREATE_ENTITY )
public String getCreateEntity( HttpServletRequest request ) throws AccessDeniedException
{
    checkUserPermission( Entity.RESOURCE_TYPE, RBAC.WILDCARD_RESOURCES_ID, EntityResourceIdService.PERMISSION_CREATE, request );
    // ...
}

@Action( ACTION_CREATE_ENTITY )
public String doCreateEntity( HttpServletRequest request ) throws AccessDeniedException
{
    checkUserPermission( Entity.RESOURCE_TYPE, RBAC.WILDCARD_RESOURCES_ID, EntityResourceIdService.PERMISSION_CREATE, request );
    // ...
}
```

The forms `AbstractJspBean.checkUserPermission( ..., strCsrfAction )` variant that also calls `_securityTokenService.validate()` is the legacy form; do not copy it into a `securityTokenEnabled = true` bean.

## Advanced — Workgroup Authorization (forms pattern)

Workgroups are an additional authorization layer on top of RBAC. An entity can belong to an admin workgroup, and only users in that workgroup can see it.

```java
import fr.paris.lutece.portal.service.workgroup.AdminWorkgroupService;

// Filter list by workgroup membership
List<Entity> listEntities = EntityHome.findAll( );
listEntities = (List<Entity>) AdminWorkgroupService.getAuthorizedCollection(
    listEntities, (User) getUser( ) );

// Check single entity workgroup authorization
if ( !AdminWorkgroupService.isAuthorized( entity, (User) getUser( ) ) )
{
    throw new AccessDeniedException( "Unauthorized" );
}
```

Requires the entity to implement `AdminWorkgroupResource`:
```java
public interface AdminWorkgroupResource
{
    String getWorkgroup( );
}
```

**When to use:** When entities need to be partitioned by admin workgroup (e.g., different departments manage different forms).

## Wildcard Constants

| Constant | Meaning | Usage |
|----------|---------|-------|
| `RBAC.WILDCARD_RESOURCES_ID` (`"*"`) | All resources of a type | `isAuthorized(type, RBAC.WILDCARD_RESOURCES_ID, perm, user)` |
| `RBAC.WILDCARD_PERMISSIONS_KEY` (`"*"`) | All permissions | Granted when configuring a role in admin |

## Common Permissions

| Permission | Constant | When to check |
|------------|----------|---------------|
| CREATE | `PERMISSION_CREATE` | Before showing create form / processing create action |
| MODIFY | `PERMISSION_MODIFY` | Before showing modify form / processing modify action |
| DELETE | `PERMISSION_DELETE` | Before delete confirmation / processing delete action |
| VIEW | `PERMISSION_VIEW` | Before listing or viewing details |
| PUBLISH | `PERMISSION_PUBLISH` | Before changing visibility/status |

## File Checklist

| File | What to add |
|------|-------------|
| `Entity.java` | `implements RBACResource`, `RESOURCE_TYPE` constant, `getResourceTypeCode()`, `getResourceId()` |
| `EntityResourceIdService.java` | New class extending `ResourceIdService`, permission constants, `register()` |
| `plugin.xml` | `<rbac-resource-type>` with `<rbac-resource-type-class>` |
| `messages.properties` | `permission.resourceType.entity.label` + one key per permission |
| `EntityJspBean.java` | `RBACService.isAuthorized()` calls, `AccessDeniedException` throws, permission flags in model |
| Templates | `<#if canXxx>` conditionals around protected buttons/links |

## Reference Sources

### Forms plugin (RBAC + workgroups)
| Need | File to consult |
|------|----------------|
| ResourceIdService (fine-grained, 13 perms) | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/service/FormsResourceIdService.java` |
| checkUserPermission() helper (legacy CSRF part, see caveat above) | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/web/admin/AbstractJspBean.java` |
| Workgroup + RBAC combined | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/web/admin/FormJspBean.java` |
| Action filtering per entity | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/web/admin/FormJspBean.java` (getManageForms) |
| Multiple resource types | `~/.lutece-references/lutece-form-plugin-forms/webapp/WEB-INF/plugins/forms.xml` |

### Core
| Need | File to consult |
|------|----------------|
| RBACService | `~/.lutece-references/lutece-core/src/java/**/service/rbac/RBACService.java` |
| ResourceIdService abstract class | `~/.lutece-references/lutece-core/src/java/**/service/rbac/ResourceIdService.java` |
| ResourceTypeManager | `~/.lutece-references/lutece-core/src/java/**/service/rbac/ResourceTypeManager.java` |
| AdminWorkgroupService | `~/.lutece-references/lutece-core/src/java/**/service/workgroup/AdminWorkgroupService.java` |
