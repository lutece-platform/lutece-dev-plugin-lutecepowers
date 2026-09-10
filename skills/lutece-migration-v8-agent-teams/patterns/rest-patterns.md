# REST API Migration Patterns (to v8)

Single source of truth for Jersey → Jakarta JAX-RS migration.

> **Reference-First Principle:** Before writing any REST class, **search `~/.lutece-references/` for existing JAX-RS implementations** (e.g., `Grep @ApplicationPath ~/.lutece-references/`). Reproduce the reference structure exactly.

## 1. Import Migration

Replace `javax.ws.rs.*` imports with `jakarta.ws.rs.*`.

## 2. Jersey → Jakarta JAX-RS

If the plugin uses Jersey directly:
- Replace `ResourceConfig` with standard `Application` class using `@ApplicationPath`
- Remove Jersey-specific dependencies (`jersey-server`, `jersey-spring5`, `jersey-media-*`)
- Remove manual `register()` calls -- use `@Provider` auto-discovery instead
- Remove Jersey filter registrations from `plugin.xml`

```java
// BEFORE (pre-v8) - Jersey ResourceConfig
public class MyRestConfig extends ResourceConfig {
    public MyRestConfig() {
        register(MyExceptionMapper.class);
    }
}

// AFTER (v8) - Standard JAX-RS Application
@ApplicationPath("/rest/")
public class MyRestApplication extends Application { }
```

## 3. REST Authentication Filter

Replace servlet-based auth filters with JAX-RS `ContainerRequestFilter`:

```java
// AFTER (v8)
@Provider
@PreMatching
@Priority(Priorities.AUTHENTICATION)
public class MyAuthFilter implements ContainerRequestFilter {
    @Inject
    private HttpServletRequest _httpRequest;

    @Inject
    @MyAuthenticatorQualifier
    private RequestAuthenticator _authenticator;

    @Override
    public void filter(ContainerRequestContext ctx) throws IOException {
        if (!_authenticator.isRequestAuthenticated(_httpRequest)) {
            ctx.abortWith(Response.status(Response.Status.UNAUTHORIZED).build());
        }
    }
}
```

## 4. Custom CDI Qualifier for Authenticators

```java
@Qualifier
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.FIELD, ElementType.METHOD, ElementType.PARAMETER, ElementType.TYPE})
public @interface MyAuthenticatorQualifier { }
```

## 5. Exception Mappers

Add `@Provider` annotation for auto-discovery (no manual registration):
```java
@Provider
public class MyExceptionMapper implements ExceptionMapper<Throwable> { ... }
```

## 6. REST plugin.xml Changes

- Remove `<filters>` section -- JAX-RS auto-discovers via `@ApplicationPath`
- Remove Jersey init-params
