# Event Migration Patterns (v7 → v8)

Single source of truth for all event/listener migration patterns.

> **Reference-First Principle:** Before writing any event listener or firing code, **search `~/.lutece-references/` for existing `@Observes` implementations** (e.g., `Grep @Observes ~/.lutece-references/`). Reproduce the reference structure exactly.

## 1. ResourceEventManager → CDI Events

`ResourceEventManager` is `@Deprecated(forRemoval = true)` in lutece-core v8. The `EventRessourceListener` interface that goes with it is also deprecated. Both must be replaced by CDI `@Observes` with `@Type(EventAction.*)` qualifiers.

### 1.1 Listener Side — EventRessourceListener → @Observes

```java
// BEFORE: EventRessourceListener interface + manual registration
@ApplicationScoped
public class MyEventListener implements EventRessourceListener
{
    public void register( )
    {
        ResourceEventManager.register( this );
    }

    @Override
    public String getName( )
    {
        return "myEventListener";
    }

    @Override
    public void addedResource( ResourceEvent event )
    {
        // handle create
    }

    @Override
    public void updatedResource( ResourceEvent event )
    {
        // handle update
    }

    @Override
    public void deletedResource( ResourceEvent event )
    {
        // handle delete
    }
}

// AFTER: CDI @Observes — auto-discovered, no registration needed
@ApplicationScoped
public class MyEventListener
{
    public void addedResource( @Observes @Type( EventAction.CREATE ) ResourceEvent event )
    {
        // handle create
    }

    public void updatedResource( @Observes @Type( EventAction.UPDATE ) ResourceEvent event )
    {
        // handle update
    }

    public void deletedResource( @Observes @Type( EventAction.REMOVE ) ResourceEvent event )
    {
        // handle delete
    }
}
```

Key changes:
1. **Remove** `implements EventRessourceListener`
2. **Remove** `register()` method — CDI auto-discovers `@Observes` methods
3. **Remove** `getName()` method — no longer needed
4. **Add** `@Observes @Type(EventAction.XXX)` on each handler method parameter
5. **Remove** empty handler methods (e.g., `updatedResource` with empty body) — no need to observe events you don't handle
6. **Remove** imports: `EventRessourceListener`, `ResourceEventManager`
7. **Add** imports: `jakarta.enterprise.event.Observes`, `fr.paris.lutece.portal.service.event.EventAction`, `fr.paris.lutece.portal.service.event.Type`

### 1.2 Firing Side — fireXxx() → CDI event firing

```java
// BEFORE
ResourceEventManager.fireAddedResource( event );
ResourceEventManager.fireUpdatedResource( event );
ResourceEventManager.fireDeletedResource( event );

// AFTER
CDI.current( ).getBeanManager( ).getEvent( )
    .select( ResourceEvent.class, new TypeQualifier( EventAction.CREATE ) ).fire( event );

CDI.current( ).getBeanManager( ).getEvent( )
    .select( ResourceEvent.class, new TypeQualifier( EventAction.UPDATE ) ).fire( event );

CDI.current( ).getBeanManager( ).getEvent( )
    .select( ResourceEvent.class, new TypeQualifier( EventAction.REMOVE ) ).fire( event );
```

Required imports for the firing side:
```java
import fr.paris.lutece.portal.business.event.ResourceEvent;
import fr.paris.lutece.portal.service.event.EventAction;
import fr.paris.lutece.portal.service.event.Type.TypeQualifier;
import jakarta.enterprise.inject.spi.CDI;
```

**Tip for static utility classes** (Home-like classes with private constructor): Since `@Inject Event<ResourceEvent>` cannot be used in static context, use `CDI.current().getBeanManager().getEvent()` directly. Create a helper method to avoid repetition:

```java
private static void fireResourceEvent( int resourceId, String resourceType, EventAction action )
{
    ResourceEvent event = new ResourceEvent( );
    event.setIdResource( String.valueOf( resourceId ) );
    event.setTypeResource( resourceType );
    CDI.current( ).getBeanManager( ).getEvent( )
        .select( ResourceEvent.class, new TypeQualifier( action ) ).fire( event );
}
```

### 1.3 Plugin init() Cleanup

Remove any `ResourceEventManager.register()` calls from the plugin's `init()` method. CDI auto-discovers `@Observes` methods — no manual registration is needed.

```java
// BEFORE
@Override
public void init( )
{
    CDI.current( ).select( MyEventListener.class ).get( ).register( );  // REMOVE this line
    FileImagePublicService.init( );
}

// AFTER
@Override
public void init( )
{
    FileImagePublicService.init( );
}
```

Do not keep a `CDI.current().select( MyCacheService.class ).get()` warm-up call either: no reference plugin does it, and the cache is created on first injection.

Also remove the import for the listener class if it was only used in `init()`.

### 1.4 Action Mapping Table

| v7 method | EventAction | @Observes qualifier |
|-----------|------------|-------------------|
| `ResourceEventManager.fireAddedResource()` | `EventAction.CREATE` | `@Type(EventAction.CREATE)` |
| `ResourceEventManager.fireUpdatedResource()` | `EventAction.UPDATE` | `@Type(EventAction.UPDATE)` |
| `ResourceEventManager.fireDeletedResource()` | `EventAction.REMOVE` | `@Type(EventAction.REMOVE)` |

---

## 2. Spring Listener Interface → CDI @Observes

Replace custom Spring listener interfaces (discovered via `SpringContextService.getBeansOfType()`) with CDI `@Observes`:

```java
// BEFORE: custom listener interface + Spring discovery
public interface MyEventListener {
    void processEvent(MyEvent event);
}

// Firing:
for (MyListener l : SpringContextService.getBeansOfType(MyListener.class)) {
    l.onEvent(event);
}

// AFTER: CDI observer
@ApplicationScoped
public class MyEventObserver {
    public void processEvent(@Observes MyEvent event) {
        // Handle event
    }
}

// Firing:
CDI.current().getBeanManager().getEvent().fire(event);
```

---

## 3. CDI Events with TypeQualifier

Fire/observe table (sync, async, qualifier): `lutece-patterns` skill §8. Actions: `EventAction.CREATE` / `UPDATE` / `REMOVE`, observed with `@Type(EventAction.X)`.

Use `@ObservesAsync` for events that don't need to block the caller (e.g., indexation, notifications). Use `@Observes` for events that must complete before the caller continues.

---

## 4. LuteceUserEventManager Migration

`LuteceUserEventManager` (extends `AbstractEventManager`) is `@Deprecated(forRemoval = true)` in lutece-core v8.

```java
// BEFORE
LuteceUserEventManager.getInstance().register("myListener", event -> handleEvent(event));
LuteceUserEventManager.getInstance().notifyListeners(new LuteceUserEvent(user, EventType.LOGIN_SUCCESSFUL));

// AFTER — Listener: CDI observer
@ApplicationScoped
public class MyUserEventListener
{
    public void onUserEvent( @Observes LuteceUserEvent event )
    {
        if ( LuteceUserEvent.EventType.LOGIN_SUCCESSFUL.equals( event.getEventType( ) ) )
        {
            handleEvent( event );
        }
    }
}

// AFTER — Firing:
CDI.current( ).getBeanManager( ).getEvent( ).fire( new LuteceUserEvent( user, EventType.LOGIN_SUCCESSFUL ) );
```

---

## 5. QueryListenersService Migration

`QueryListenersService` is `@Deprecated(forRemoval = true)` in lutece-core v8. Plugins implementing `QueryEventListener` need migration.

```java
// BEFORE
public class MyQueryListener implements QueryEventListener
{
    public MyQueryListener( )
    {
        QueryListenersService.getInstance( ).registerQueryListener( this );
    }
    @Override
    public void processQueryEvent( QueryEvent event ) { ... }
}

// AFTER
@ApplicationScoped
public class MyQueryListener
{
    public void processQueryEvent( @Observes QueryEvent event )
    {
        // handle query event
    }
}
```

---

## 6. Firing Events from CDI Beans with @Inject Event<T>

When firing events from CDI-managed beans (classes with `@ApplicationScoped`, `@RequestScoped`, etc.), prefer `@Inject Event<T>` over programmatic `CDI.current().getBeanManager().getEvent()` access.

```java
@ApplicationScoped
public class MyService
{
    @Inject
    private Event<ResourceEvent> _resourceEvent;

    public void updateResource( int resourceId, String resourceType )
    {
        // Update logic...

        // Fire event with qualifier
        ResourceEvent event = new ResourceEvent( );
        event.setIdResource( String.valueOf( resourceId ) );
        event.setTypeResource( resourceType );
        _resourceEvent.select( new TypeQualifier( EventAction.UPDATE ) ).fire( event );
    }
}
```

**When to use @Inject Event<T>:**
- In CDI-managed beans (`@ApplicationScoped`, `@RequestScoped`, `@SessionScoped`, `@Dependent`)
- When firing multiple events of the same type in the class
- For cleaner, more testable code

**When to use CDI.current().getBeanManager().getEvent():**
- In static contexts (Home classes, utility classes with private constructor)
- When firing events infrequently (once or twice in the entire class)

---

## 7. Typed Qualifiers for Events

The action travels in the `@Type` qualifier, not in the event payload. Forms' `FormResponseEvent` carries only the id (constructors `(int)` and `(int, boolean bUpdateDateFormResponse)`, accessor `getFormResponseId()`):

```java
@ApplicationScoped
public class FormService
{
    @Inject
    private Event<FormResponseEvent> _formResponseEvent;

    public void createFormResponse( FormResponse response )
    {
        _formResponseEvent.select( new TypeQualifier( EventAction.CREATE ) )
                          .fireAsync( new FormResponseEvent( response.getId( ) ) );
    }

    public void deleteFormResponse( int nIdFormResponse )
    {
        _formResponseEvent.select( new TypeQualifier( EventAction.REMOVE ) )
                          .fireAsync( new FormResponseEvent( nIdFormResponse ) );
    }
}
```

Observer side (one method per action, `@ObservesAsync @Type(EventAction.X)`): listener skeleton in the `lutece-lucene-indexer` skill Step 5 and reference `FormResponseEventListener.java` below.

**Custom qualifiers for domain-specific filtering:**

```java
@Qualifier
@Retention( RetentionPolicy.RUNTIME )
@Target( { ElementType.FIELD, ElementType.PARAMETER, ElementType.TYPE } )
public @interface FormType
{
    String value( );
}

_formResponseEvent.select( new FormType.Literal( "contact" ) ).fire( new FormResponseEvent( responseId ) );

public void onContactFormResponse( @Observes @FormType( "contact" ) FormResponseEvent event )
{
}
```

---

## 8. Already-Migrated Listeners in lutece-core v8

The following listeners are **already migrated to CDI @Observes in lutece-core v8**. Plugins do NOT need to migrate these — they are handled by the core:

| Listener Class | Event Type | Location |
|----------------|-----------|----------|
| `PageEventListener` | `PageEvent` | `fr.paris.lutece.portal.service.page.PageEventListener` |
| `PluginEventListener` | `PluginEvent` | `fr.paris.lutece.portal.service.plugin.PluginEventListener` |
| `QueryEventListener` (core impl) | `QueryEvent` | `fr.paris.lutece.portal.service.search.QueryEventListener` |
| `PortletEventListener` | `PortletEvent` | `fr.paris.lutece.portal.service.portlet.PortletEventListener` |

`ResourceEventManager`, `LuteceUserEventManager` and `QueryListenersService` are **deprecated** (§1, §4, §5), not migrated listeners. Core bridges CDI events back to them in `fr.paris.lutece.portal.service.event.LegacyEventObserver` (`@Observes @Type(EventAction.*) ResourceEvent`, `LuteceUserEvent`, `QueryEvent`), so a plugin that fires CDI events still reaches legacy listeners; a plugin that still registers on them must migrate to `@Observes`.

**What this means for plugin migration:**
- If a plugin **fires** these events (e.g., `PageEventManager.firePageCreated()`), migrate the firing code to CDI events
- If a plugin **listens** to these events by implementing core listener interfaces, migrate to `@Observes`
- The core's own handling of these events is already done — no need to migrate core listeners

**Example — Plugin fires PageEvent:**
```java
// Plugin code (needs migration)
// BEFORE
PageEventManager.firePageCreated( page );

// AFTER
CDI.current( ).getBeanManager( ).getEvent( )
    .select( PageEvent.class, new TypeQualifier( EventAction.CREATE ) ).fire( pageEvent );
```

**Example — Plugin observes PageEvent:**
```java
// Plugin code (needs migration)
// BEFORE
public class MyPageListener implements PageEventListener
{
    public MyPageListener( )
    {
        PageEventManager.register( this );
    }
    @Override
    public void processPageEvent( PageEvent event ) { ... }
}

// AFTER
@ApplicationScoped
public class MyPageListener
{
    public void processPageEvent( @Observes @Type( EventAction.CREATE ) PageEvent event )
    {
        // handle page creation
    }
}
```

---

## Reference

See the forms plugin for a complete v8 event implementation:
- **Listener**: `~/.lutece-references/lutece-form-plugin-forms/src/java/fr/paris/lutece/plugins/forms/service/listener/FormResponseEventListener.java`
- **Firing**: `~/.lutece-references/lutece-form-plugin-forms/src/java/fr/paris/lutece/plugins/forms/service/FormService.java` (search for `fireAsync`)
