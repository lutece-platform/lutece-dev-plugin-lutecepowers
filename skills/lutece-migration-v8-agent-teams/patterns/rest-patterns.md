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

### `RestConstants.BASE_PATH` moved, and it silently breaks hand-built URLs

In v7 `fr.paris.lutece.plugins.rest.service.RestConstants.BASE_PATH` was `"/rest/"`. In v8 it is `""`, and the
prefix lives in `RestConstants.APP_PATH`, used by `@ApplicationPath( RestConstants.APP_PATH )` on plugin-rest's
`LuteceRestApplication`, is `"/rest/"`.

So the same pair of constants has to be used differently in two places, and the compiler cannot tell you:

- `@Path( RestConstants.BASE_PATH + PLUGIN_NAME )` — **correct unchanged**: the path is relative to the application
  path, which already supplies `/rest/`.
- any code building an **absolute** URL by hand, typically a `getWADL` method doing
  `getBaseUrl( request )` → strip the trailing slash → `append( RestConstants.BASE_PATH + PLUGIN_NAME )` — **must
  become `APP_PATH`**, or it produces `http://host/ctx<plugin>` with no separator and advertises endpoints that 404.

Grep every module on plugin-rest for `RestConstants.BASE_PATH` outside an annotation. A WADL is the usual victim:
the document is served with a 200 and only its `base` attribute is wrong, so a bench that fetches the endpoint
without reading the body stays green.

Both constants are compile-time `String` finals, so javac folds them into the class file. Correctness therefore
depends on the jar present at **compile** time: a class built against v7 plugin-rest still carries `/rest/<plugin>`
inside its `@Path` and resolves to `/rest/rest/<plugin>`. The two failures are both silent 404s and are told apart
by the requested path — a doubled `/rest/rest/` means a stale artefact, a missing separator means this defect.

### Multipart upload: Jersey's `FormDataContentDisposition` → `EntityPart`

A pre-v8 upload binds its parts with Jersey annotations, `@FormParam` or `@FormDataParam` plus a
`FormDataContentDisposition` for the metadata. Both Jersey packages are gone in v8. The JAX-RS 3.1 standard type
is `jakarta.ws.rs.core.EntityPart`, supplied by the `jakarta.jakartaee-api` the parent already manages at
`provided`, so **nothing is added to the pom**: the method takes the entity as a `List<EntityPart>` and looks its
parts up by name.

`EntityPart` has no `getSize( )`, and that matters more than it looks. Jersey's version read the `size` parameter
of the `Content-Disposition` header, which no real client sends (neither a browser form nor
`HttpAccess.doPostMultiPart`, whose Apache builder emits none for a stream), so the stored size was `-1` and
had been for years. Count the bytes instead, while streaming, without materialising the blob:

```java
try ( BoundedInputStream content = BoundedInputStream.builder( ).setInputStream( part.getContent( ) ).get( ) )
{
    String strKey = service.storeInputStream( content );
    String strJson = buildFileMetadata( part.getFileName( ).orElse( part.getName( ) ), content.getCount( ), strKey,
            part.getMediaType( ).toString( ) );
}
```

`getCount( )` is read **after** the store call returns, and it is only exact if the consumer read the stream to the
end. Write the change down as a deliberate one: old rows keep their `-1`, new rows carry a true count, and the two
coexist — check what reads the value back before assuming they can.

## 3. REST Authentication Filter

**A module that protected its endpoints in v7 must protect them in v8, and it writes this filter to do it.** A
migration is iso: an endpoint that required a signature before requires one after. The descriptor filter that used
to do the job is dead (§6), so the module carries a `ContainerRequestFilter` bound to its own resource, reproducing
the v7 parameters exactly — same authenticator class, same signature elements in the same order, same private key,
same validity period. Trace that equivalence in the hand-over rather than claiming it.

plugin-rest's own `RestAuthenticatorRequestFilter` is **not** a substitute and does not enter the decision. It is
global to the site, it is shipped off (`rest.security.activated=false`), and turning it on is an operator's choice
about the whole site. A module must be protected whether that switch is on or off.

**Pick the scope first, because the two forms are mutually exclusive and the wrong one fails silently:**

- **Global** — every REST resource of the webapp. Add `@PreMatching`. This is plugin-rest's own filter, global by
  design.
- **Scoped to one resource**: declare a `@NameBinding` annotation, put it on the filter **and** on the resource
  class, and do **not** add `@PreMatching`. A pre-matching filter runs before the container has matched a resource
  method, so the binding has nothing to attach to. The Jakarta REST javadoc is explicit: *"Any named binding
  annotations will be ignored on a component annotated with the @PreMatching annotation."* **Ignored, not
  rejected** — the combination compiles, deploys, and guards the whole site while reading as if it were scoped.

```java
// AFTER (v8) — scoped form; drop @MyAuthBinding and add @PreMatching for the global one
@Provider
@MyAuthBinding
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

### The filter must not read the request body — it breaks multipart uploads

A signature authenticator collects its elements with `request.getParameter( )`. On Liberty that call runs
`parseParameters( )` unconditionally, which for a `multipart/form-data` body calls `prepareMultipart( )`, and the
JAX-RS servlet carries no `@MultipartConfig`, so it throws `multipart.no.multipart.config` and the exception is
swallowed into an FFDC. The parameter map stays empty — and the resource's `List<EntityPart>` then binds empty
too. The upload method sees nulls, takes its "mandatory fields" branch and answers **HTTP 200 with an empty
body**. A 401/401/200 matrix cannot see it: assert the response body and the row actually written.

Tomcat never folded multipart into the parameter map, so this did not happen before v8 and is easy to mis-predict
from the v7 behaviour. Hand the authenticator a request wrapper instead: for `multipart/*` only, answer
`getParameter`, `getParameterValues`, `getParameterMap` and `getParameterNames` from the **query string alone**
and never touch the entity; delegate untouched for every other content type, so an urlencoded endpoint keeps
signing over its form parameters. Override all four accessors, not just `getParameter` — another authenticator
reaching for any of them would drag the body back in.

The wrapper also makes the contract yours rather than the container's: a value sent only as a multipart part
never counts toward the signature, whatever the server does with parts. Say so in the plugin's documentation, and
say what a client must sign for the upload endpoint, because the wrapper is what decides it.

### Give the check an off switch, defaulted on

A v7 descriptor filter could be commented out to drive a test page; a JAX-RS filter has no such affordance, and a
module whose test console sends no signature becomes undrivable. Guard the filter body with
`@ConfigProperty( name = "<plugin>.security.activated", defaultValue = "true" )` and return before touching the
request when it is false — before the wrapper, before any `getParameter`, since touching the request is the thing
that breaks uploads. Ship the key visible with its `true` so the switch is discoverable, and log one line at
startup when it is off, or a trace of unauthenticated 200s has no explanation in it.

Keep the two failure modes apart: `activated=false` is a deliberate choice, a misconfigured `.name` is an error
that throws either way. Nothing degrades silently into serving everything. Note that an `@ApplicationScoped`
filter is lazy, so resolve the authenticator in `@PostConstruct` through an `Instance<T>` — otherwise the
producer's guard never runs while the switch is off and a misspelled key stays hidden until someone turns it on.

## 4. Custom CDI Qualifier for Authenticators

```java
@Qualifier
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.FIELD, ElementType.METHOD, ElementType.PARAMETER, ElementType.TYPE})
public @interface MyAuthenticatorQualifier { }
```

**A producer built on `AbstractSignRequestAuthenticatorProducer` must refuse what it cannot build.** That library
method ends its switch on `default -> new NoSecurityAuthenticator( )`, whose `isRequestAuthenticated` is
`return true;` unconditionally. So a `<prefix>.name` key that is missing, misspelled, or names an authenticator the
switch does not know yields a filter that authorises every call, answers 200 and logs nothing — worse than no
filter, because it looks like it works. Never return the result of that call as it comes:

```java
RequestAuthenticator authenticator = produceRequestAuthenticator( PREFIX );

if ( authenticator instanceof NoSecurityAuthenticator )
{
    throw new AppException( PREFIX + ".name names no known authenticator, so every call would be served unchecked" );
}
return authenticator;
```

A blind cast to the expected type is not enough on its own: it happens to fail here because
`NoSecurityAuthenticator` is not an `AbstractPrivateKeyAuthenticator`, but it fails with a `ClassCastException`
naming nothing, and it would pass silently for a producer whose declared type is the `RequestAuthenticator`
interface. Test for the fallback itself, and name the key in the message.

When the producer declares a narrower type — `AbstractPrivateKeyAuthenticator`, say, because the plugin signs URLs
— prefer the **positive** test, `instanceof AbstractPrivateKeyAuthenticator`: it rejects the fail-open fallback and
also every other authenticator the plugin cannot actually use, such as an IP one. The negative test against
`NoSecurityAuthenticator` is the form to use when the declared type is the interface and no positive test exists.

## 5. Exception Mappers

Add `@Provider` annotation for auto-discovery (no manual registration):
```java
@Provider
public class MyExceptionMapper implements ExceptionMapper<Throwable> { ... }
```

## 6. REST plugin.xml Changes

- **Remove the whole `<filters>` block of a REST module, including a per-path security filter**, because it does
  not fire: `MainFilter.matchMapping` compares the pattern to `request.getServletPath( )`, and
  `@ApplicationPath( "/rest/" )` mounts a real servlet, so that value is `/rest` and the rest of the url is in
  `getPathInfo( )`. `/rest/*` matches; **`/rest/<plugin>/*` never does.** The filter is registered at startup and
  never runs, with nothing in the log to say so: an unsigned call the v7 filter refused answers 200. Check `WB05`.
  Filters on `/jsp/*` and the like are unaffected and stay (mylutece, document, resource declare them).
  **Removing the block is half the work.** It is inert, so deleting it changes no behaviour, but the endpoints it
  named are then unprotected, and a migration does not open what was closed. Replace it with the name-bound JAX-RS
  filter of §3, carrying the same parameters, and say in the hand-over that the mechanism changed while the
  contract did not. No migrated reference carries a name-bound filter: the recipe rests on the Jakarta REST
  specification quoted in §3. plugin-rest's `RestAuthenticatorRequestFilter` (`@PreMatching`, global to the REST
  application, gated by `rest.security.activated`, shipped `false`, configured by `rest.requestAuthenticator.*`)
  is a separate, site-wide option, never the replacement.
  Do not treat this as a platform defect to be fixed: declaring a REST filter in the descriptor is a finished
  mechanism, and the core is not going back to it. The JAX-RS filter of §3 is the replacement, full stop.
- Remove Jersey init-params
