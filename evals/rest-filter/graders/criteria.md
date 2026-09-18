---
type: llm
weight: 1
---

The answer is correct only if it states that the descriptor filter **does not run** in v8 and that
the endpoints are therefore left unprotected.

Required:
- Says clearly the filter never fires. A `url-pattern` deeper than `/rest/*` can never match, because
  once the JAX-RS application is mounted the servlet path is `/rest`, so the pattern is compared
  against `/rest` and fails. Credit any explanation of that mechanism; do not require the exact class
  name `MainFilter` or the exact method.
- Warns the protection is lost silently — the filter may still look registered, and the endpoints
  answer unauthenticated requests.
- Recommends replacing it with a JAX-RS filter written in the plugin: a `ContainerRequestFilter`
  bound to the resources with a `@NameBinding` annotation (or an equivalent per-resource check inside
  the resource methods).

Fail the answer if it:
- says the filter keeps working, or only needs its `url-pattern` or class adjusted;
- presents `plugin-rest`'s global authentication (the `rest.security.activated` property) as the
  solution on its own — it is a site-wide switch shipped disabled, not a per-plugin protection;
- answers only in generalities about Jakarta migration without addressing whether this filter runs.
