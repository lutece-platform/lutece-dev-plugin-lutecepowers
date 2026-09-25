# Deprecated APIs a migration replaces, and what by

A migration leaves **zero compiler warning** in the plugin's sources (`final-gate.sh` step 2 refuses otherwise).
Run the compiler the way the gate does — `-q` hides warnings, never use it here:

```bash
mvn -B clean compile -Dmaven.compiler.showWarnings=true -Dmaven.compiler.showDeprecation=true 2>&1 | grep -E '^\[WARNING\] .*/src/.*\.java'
```

| Deprecated | Replacement | Note |
|---|---|---|
| `RBACService.isAuthorized( …, AdminUser )`, `getAuthorizedCollection( …, AdminUser )`, `getAuthorizedActionsCollection( …, AdminUser )` | the same methods taking `fr.paris.lutece.api.user.User` | `AdminUser implements User`, so the compiler picks the **deprecated** overload unless the argument is cast: `(User) getUser( )`, `(User) AdminUserService.getAdminUser( request )` |
| `AdminWorkgroupService.isAuthorized( …, AdminUser )`, `getAuthorizedCollection( …, AdminUser )` | same, with `User` | same cast |
| `MVCAdminJspBean.getModel( )` | a `Models` parameter on the view method (`lutece-patterns` §4) | a helper that filled the map takes `Models` and returns it; `models.asMap()` is unmodifiable |
| `StringUtils.equals`, `StringUtils.replace` (commons-lang3 ≥ 3.18) | `Strings.CS.equals`, `Strings.CS.replace` (`org.apache.commons.lang3.Strings`) | case-insensitive variants: `Strings.CI` |
| `org.apache.commons.lang3.StringEscapeUtils` | `org.apache.commons.text.StringEscapeUtils` | commons-text comes with the core |
| `Class.forName( x ).newInstance( )` | `Class.forName( x ).getDeclaredConstructor( ).newInstance( )` | the catch becomes `ReflectiveOperationException` |
| `BigDecimal.divide( divisor, scale )` | `divide( divisor, scale, RoundingMode.HALF_UP )` | state the rounding, never let it be implicit |
| `<Service>.getInstance( )` of a v8 plugin (`DocumentService`, `DocumentSpacesService`…) | `@Inject` in a CDI bean, `CDI.current( ).select( X.class ).get( )` in a class the core instantiates by reflection | the service is `@ApplicationScoped @Named` in its own plugin |
| `ITask.processTaskWithResult( int nIdResourceHistory, … )` | `processTaskWithResult( int nIdResource, String strResourceType, int nIdResourceHistory, … )` | the default method of the interface still delegates to the old one; override the new signature |
| `WorkgroupRemovalListenerService.getService( )` (and the other static `*RemovalListenerService`) | `@Inject @Named( "workgroupRemovalService" ) RemovalListenerService` in a CDI bean, which registers the listener in its own `init` | names in `BeanUtils` (`workgroupRemovalService`, `rbacRemovalService`, `portletRemovalService`, `mailinglistRemovalService`) |

**A deprecation the plugin owns is a decision, not a warning to silence.** When the plugin deprecated its own
method and there is no replacement with the same semantics (an overload that filters on something the other one
does not), remove the `@Deprecated` and say in the javadoc what the method is for — deprecating a method nobody
can stop calling only trains readers to ignore warnings.

**Never `@SuppressWarnings`** to reach zero: the gate counts warnings the compiler emits, and a suppression
hides the next real one.
