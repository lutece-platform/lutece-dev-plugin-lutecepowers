---
description: "Lutece 8 JAX-RS resources: application path, securing endpoints per resource, and how a bench tests them"
paths:
  - "**/rs/**/*.java"
  - "**/rest/**/*.java"
---

# JAX-RS resources in Lutece 8

## The application path is not yours

`plugin-rest` mounts one JAX-RS application at `/rest/` through `@ApplicationPath( RestConstants.APP_PATH )`. A
resource's `@Path` is therefore **relative** to it, which is why `RestConstants.BASE_PATH` is `""` in v8 where it
was `"/rest/"` before. Keep `@Path( RestConstants.BASE_PATH + PLUGIN_NAME )` unchanged, and use `APP_PATH` in any
code that builds an **absolute** url by hand — a WADL is the usual one. Both are compile-time constants, so a
class built against the v7 artefact keeps the old value inlined: a doubled `/rest/rest/` means a stale build, a
missing separator means `BASE_PATH` where `APP_PATH` was needed.

## Securing endpoints

Three mechanisms exist and only two work per resource:

- **The plugin descriptor's `<filters>`** — dead under `/rest/`. `MainFilter` matches the url-pattern against
  `request.getServletPath( )`, which is `/rest` once a servlet is mounted there, so a pattern like
  `/rest/<plugin>/*` never matches. The filter is still registered and simply never runs. Remove the block.
- **plugin-rest's global filter** — `rest.security.activated`, shipped `false`, covering every REST resource of
  the site. A site-level decision, never a substitute for a plugin's own protection.
- **A `@NameBinding` `ContainerRequestFilter` in the plugin** — the one that protects this plugin's resources and
  nothing else. This is what replaces a v7 `<url-pattern>`.

Write the third when the plugin protected its endpoints before: a migration is iso, and an endpoint that required
a signature keeps requiring one whatever the site's global switch says. Reproduce the v7 parameters exactly —
authenticator class, signature elements in the same order, private key, validity period — so existing clients sign
unchanged.

Rules that follow, each of which has cost a real defect:

- **`@PreMatching` and `@NameBinding` are mutually exclusive.** The javadoc says binding annotations are *ignored*
  on a pre-matching component: the combination compiles, deploys, and guards the whole site while reading as if it
  were scoped.
- **The binding goes on every resource class.** A class added later without it is served unauthenticated and
  nothing in the build reports it. Say so in the plugin's documentation, not only in a commit message.
- **Never let the authenticator read the body of a multipart request.** It collects its elements with
  `getParameter( )`, which drags the request into the container's multipart machinery and leaves the entity
  unusable: the upload method then binds nothing and answers 200 with an empty body. Wrap the request so that, for
  `multipart/*` only, the four parameter accessors answer from the query string alone.
- **A producer built on `AbstractSignRequestAuthenticatorProducer` must refuse `NoSecurityAuthenticator`.** That
  fallback authenticates everything; a missing or misspelled `<prefix>.name` would open the API silently. Throw,
  and name the key.
- **Give the check a switch, defaulted on**: `@ConfigProperty( name = "<plugin>.security.activated",
  defaultValue = "true" )`, returning before the request is touched. It replaces the v7 affordance of commenting
  the descriptor block out to drive a test page. Resolve the authenticator through `Instance<T>` in
  `@PostConstruct` so a misconfigured name still throws when the switch is off.

## Testing them

A REST resource is not a screen: a browser judges nothing useful about it. Drive it with the `http` step of a
scenario, and `sign` when it is protected — one call with a correct signature, one without, one with a wrong one.
Assert the **body and the state**, never the status alone: an endpoint whose parameters did not arrive answers 200
with an empty body, which a status matrix cannot see.
