---
description: "Lutece 8 dependency convergence: global-pom 8.0.2 baseline, Jakarta EE 10 pins, expressly EL artifact, enforcer rules that now inspect the test scope"
paths:
  - "pom.xml"
---

# Dependency Convergence — Lutece 8

## The Baseline

Lutece 8 targets **Jakarta EE 10** (`jakarta.platform:jakarta.jakartaee-api:10.0.0`, `provided`, declared in the parent). Every dependency must stay inside that generation.

| Spec | EE 10 — correct | EE 11 — do NOT introduce |
|------|-----------------|--------------------------|
| Servlet | 6.0 | 6.1 |
| CDI | 4.0.x | 4.1 |
| `jakarta.annotation-api` | 2.1.x | 3.0.0 |
| `jakarta.el-api` | 5.0.x | 6.x |
| `jakarta.validation-api` | 3.0.x | 3.1.x |
| `weld-junit5` | 4.0.5.Final (Weld 5.1.6) | 5.x (Weld 6) |

Pulling an EE 11 artifact in — usually by bumping a test library — silently drags the whole test classpath forward and breaks at runtime, not at compile time.

## Parent POM Version

Use **`8.0.2`** as the parent for plugins, modules and libraries. It is the first version that makes the test classpath converge.

```xml
<parent>
    <artifactId>lutece-global-pom</artifactId>
    <groupId>fr.paris.lutece.tools</groupId>
    <version>8.0.2</version>
</parent>
```

Always a released version — never a SNAPSHOT parent.

## What 8.0.2 Brought

Kept here because it explains the coordinates below, and because a plugin still sitting on 8.0.1 will not behave the same way.

| | parent 8.0.1 | parent 8.0.2 |
|---|---|---|
| EL implementation | `org.glassfish:jakarta.el` (5.0.0-M1) | `org.glassfish.expressly:expressly` (5.0.0) |
| `library-lutece-unit-testing` | 5.0.1 | 5.0.2 |
| `hibernate-validator` | 8.0.1.Final | 8.0.5.Final |
| `jaxb-runtime` | 4.0.5 | 4.0.9 |
| `jboss-logging` | not managed | pinned 3.6.3.Final |
| `jakarta.el-api` | not managed | pinned 5.0.1 |
| `jakarta.annotation-api` | not managed | pinned 2.1.1 |
| enforcer `excludedScopes` | `test` + `provided` | `provided` only |

Two consequences:

- **The EL artifact was renamed.** `org.glassfish:jakarta.el` never released past the `5.0.0-M1` milestone; the successor is `org.glassfish.expressly:expressly`. The old coordinates are no longer managed — declaring them yields a dependency with no version and the build fails. Use `expressly`.
- **The `test` scope is now inspected** by `requireUpperBoundDeps` and `dependencyConvergence`. A version conflict confined to test dependencies used to pass unnoticed; it now fails the build.

## Never Pin a Managed Version

These are managed by the parent. Declare the coordinates and the scope, never a `<version>`:

- `fr.paris.lutece.plugins:library-lutece-unit-testing`
- `org.hibernate.validator:hibernate-validator`
- `org.glassfish.expressly:expressly`
- `org.glassfish.jaxb:jaxb-runtime`
- `org.jboss.logging:jboss-logging`, `jakarta.el-api`, `jakarta.annotation-api`

Pinning a version locally re-creates the divergence the parent exists to prevent.

## Reading an Enforcer Failure

```
Rule 0: ...RequireUpperBoundDeps failed with message:
Require upper bound dependencies error for org.jboss.logging:jboss-logging:3.4.3.Final
paths to dependency are:
  +-my-plugin:1.0.0-SNAPSHOT
    +-org.hibernate.validator:hibernate-validator:8.0.1.Final
      +-org.jboss.logging:jboss-logging:3.4.3.Final
```

Maven resolves the **nearest** declaration, not the highest. When two paths disagree, the shallower one wins and can downgrade a transitive dependency below what another library requires.

Fix it in this order:

1. **Align the real versions** — bump the library that pulls the old artifact. Preferred: no override to maintain.
2. **Pin in the parent's `dependencyManagement`** if several plugins hit the same conflict. Aligns the whole graph and is inherited.
3. **`<exclusions>`** only to remove an artifact that must genuinely disappear. An exclusion does not resolve a version conflict: with several paths to the artifact, excluding one leaves the divergence; excluding all removes the class from the classpath and produces a `NoClassDefFoundError` at runtime, not at build time.

Do NOT widen `excludedScopes` to silence a failure — that is the check, not the noise.

## Diagnosing

```bash
mvn dependency:tree -Dverbose -Dincludes=<groupId>:<artifactId>
mvn enforcer:enforce
```

`-Dverbose` shows the omitted-for-conflict branches, which is what identifies the winning path.

## Logging Backend

`jboss-logging` (used by Weld, SmallRye Config, Hibernate Validator) is a façade that picks its backend at first class load, in this order:

**JBoss LogManager → Log4j2 → SLF4J → Log4j 1.x → JDK**

On a Lutece classpath it selects `Log4j2LoggerProvider` natively — no bridge needed. Two things follow:

- If a dependency ever introduces `jboss-logmanager`, it takes priority over Log4j2 and silently diverts Weld / SmallRye / Hibernate Validator logs away from `log4j2.xml`. The enforcer will not catch it: it is a class arriving, not a version conflict. Force the backend with `-Dorg.jboss.logging.provider=log4j2` if needed.
- Those libraries log under `org.jboss.weld` / `io.smallrye.*`. With no explicit logger they inherit `<Root>`, which the test configuration sets to `ERROR` — INFO and DEBUG are dropped. Add an explicit logger, or run with `LOG4J_LEVEL=debug`, when debugging CDI or config startup.
