# Teammate — Serialization & session state

> `${LUTECEPOWERS_ROOT}` below is the plugin root given in your spawn prompt. If the variable is not set in your shell, `export LUTECEPOWERS_ROOT=<that path>` before running any script.

## Role
Make all session/cache state **cluster-safe** (serializable, light, free of non-replicable resources).

## Inputs
- Findings for axes `2-session`, `2-nonserial`, `2-sessionscoped` from the scan.
- Pattern: `${SKILL}/patterns/serialization-session.md`.
- References: `~/.lutece-references/lutece-core` (`LuteceUser`, LUT‑32341/32099/31371), `lutece-form-plugin-forms` (LUT‑31038, `FormXPageSessionPassivationTest`).

## Procedure
1. Every object put in session/cache → `implements Serializable` + `serialVersionUID`, cascading over the graph.
2. Indispensable non-serializable field → `transient` + lazy reload (CDI/singleton) + String consistency key.
3. Stored lambda → `SerializableFunction`. No `Optional`/request/response in session.
4. **Remove any `transient` on an `@Inject`** (CDI proxy is already serializable).
5. **Resource "hold" via `ScheduledFuture`/`Timer` in session → remove**: materialise in DB (row with expiry) + release daemon under a distributed lock (coordinate with the locks teammate).
6. Bound the session; clean on logout/init; do not use `session.getId()` as an identifier.
7. **Stateful `@SessionScoped`/`@ConversationScoped` bean** (axis `2-sessionscoped`): the whole field graph must be `Serializable` (it's a wizard kept across requests). **Flag the deployment requirement**: the cluster MUST set Liberty `writeContents="GET_AND_SET_ATTRIBUTES"` — without it the bean's in-place mutations are not replicated and the wizard breaks on node switch (the default `ONLY_SET_ATTRIBUTES` is the trap; it is infra, not plugin code, so note it for ops / the harness already sets it).
8. **Add a passivation test** (round-trip ObjectOutputStream/ObjectInputStream) over the plugin's session objects AND the `@SessionScoped` bean's stateful fields — cf. forms `FormXPageSessionPassivationTest`. This breaks the build if a non-serializable field ever enters the session.

## Constraints
- Reference-first; file ownership; `verify-file.sh` after each file; **never commit**.
