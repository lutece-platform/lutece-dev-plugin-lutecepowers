# Persistence Patterns (to v8)

How a plugin that already uses JPA (or Spring JDBC) reaches Lutece 8. New code uses `DAOUtil` (`rules/dao-patterns.md`, `/lutece-dao`); an existing JPA model stays on JPA and takes the provider the container ships. Target: Open Liberty 26 / EclipseLink 4.0.9.

> **Reference-First Principle:** search `~/.lutece-references/` for `persistence.xml` and `@Entity` before writing any mapping.

## 1. Decision

| Data layer found by the scan | Target |
|---|---|
| `DAOUtil` only | unchanged (`rules/dao-patterns.md`) |
| JPA (`@Entity`, `persistence.xml`, `EntityManager`) | JPA kept, **EclipseLink of the container** (`persistence-3.1`), code on the `jakarta.persistence` API only |
| Spring JDBC (`JdbcTemplate`, `RowMapper`) | kept as a **library**, no Spring container: CDI producer of the JNDI `DataSource` and of the templates, `@Repository`/`@Service` → `@ApplicationScoped`, Spring `@Transactional` → `jakarta.transaction.Transactional` |

No JPA provider in the war. Hibernate through `persistenceContainer-3.1` + `bells-1.0` is possible but untested on the Lutece platform; not the norm.

## 2. persistence.xml

```xml
<persistence xmlns="https://jakarta.ee/xml/ns/persistence"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="https://jakarta.ee/xml/ns/persistence https://jakarta.ee/xml/ns/persistence/persistence_3_0.xsd"
             version="3.0">
    <persistence-unit name="myplugin" transaction-type="JTA">
        <provider>org.eclipse.persistence.jpa.PersistenceProvider</provider>
        <jta-data-source>jdbc/portal</jta-data-source>
        <exclude-unlisted-classes>false</exclude-unlisted-classes>
        <shared-cache-mode>NONE</shared-cache-mode>
        <properties>
            <property name="eclipselink.target-database" value="PostgreSQL"/>
            <property name="eclipselink.ddl-generation" value="none"/>
        </properties>
    </persistence-unit>
</persistence>
```

- `version="3.0"`: Liberty's descriptor parser knows 1.0, 2.0, 2.1, 2.2, 3.0 and 3.2; `3.1` fails with `CWWJP0018E`.
- `transaction-type="JTA"` + `jta-data-source`: the `EntityManager` joins the container transaction; a write outside `@Transactional` raises `TransactionRequiredException`.
- `shared-cache-mode NONE`: EclipseLink enables a shared second-level cache by default; Lutece caching belongs to the cache services (`cache-patterns.md`), batches and scripts write outside JPA, and the scalability skill runs several instances. `ENABLE_SELECTIVE` with `@Cacheable` entities is the only alternative, with cache coordination.
- No `hibernate.*` property, no dialect class. The container sets `eclipselink.target-server` and routes EclipseLink logging.
- Weaving is dynamic in Liberty: lazy `@ManyToOne`/`@OneToOne`, attribute change tracking and fetch groups need no build step.

## 3. Site configuration

`server.xml`:

```xml
<feature>jdbc-4.2</feature>
<feature>persistence-3.1</feature>
<dataSource jndiName="jdbc/portal" transactional="true">…</dataSource>
```

`db.properties`:

```properties
portal.poolservice=fr.paris.lutece.util.pool.service.ManagedConnectionService
portal.ds=jdbc/portal
```

The default Lutece pool is not a JTA resource. `DAOUtil` and `EntityManager` share a unit of work only under `@Transactional` with the managed datasource (`TransactionSynchronizationRegistry`); outside JTA, Lutece's `TransactionManager` holds its own thread-local connection and atomicity is not guaranteed.

## 4. pom.xml

```xml
<dependency>
    <groupId>jakarta.persistence</groupId>
    <artifactId>jakarta.persistence-api</artifactId>
    <version>3.1.0</version>
    <scope>provided</scope>
</dependency>
```

Remove `hibernate-core`, `hibernate-entitymanager`, `module-jpa-hibernate`, `spring-orm`, `spring-data-jpa`, `javax.persistence` and their transitive jars (`byte-buddy`, `jandex`, `classmate`, `jboss-logging`, `antlr4-runtime`). `hibernate-validator` in `test` scope is Bean Validation, unrelated: keep it (`rules/testing.md`).

## 5. JPQL and native SQL

EclipseLink parses JPQL strictly; HQL accepts more. Each row is a runtime failure, not a compile error.

| Accepted by HQL | JPQL (EclipseLink) |
|---|---|
| `FROM Entity e ORDER BY e.id` | `SELECT e FROM Entity e ORDER BY e.id` |
| native `createNativeQuery( "… WHERE id = :id" )` | positional only: `… WHERE id = ?1`, `setParameter( 1, id )`; a reused parameter keeps its number in every branch of a `UNION` |
| `e.id IN (:ids)` | `e.id IN :ids` (a parenthesised parameter is read as one scalar) |
| `REPLACE( x, ' ', '' )`, `unaccent( x )`, any database function | `FUNCTION( 'REPLACE', x, ' ', '' )`, `FUNCTION( 'unaccent', x )`; a parameter is a valid argument |
| `JOIN e.items i WITH i.flag = true` | `JOIN e.items i ON i.flag = true` |
| unqualified property `WHERE immatriculation = …` | qualified `WHERE e.immatriculation = …` |
| `query.setHint( "org.hibernate.cacheable", true )` | removed; `eclipselink.*` hints only when needed (`eclipselink.read-only`, `eclipselink.batch`) |
| `?1` in JPQL | unchanged |
| `SELECT COUNT( e )` → `Long`, native `bigint` → `Long` | unchanged |

Native SQL stays native: `?` positional JDBC style is valid, `::` casts and `unaccent( )` calls are the database's business.

## 6. Entities

- `equals` / `hashCode` never include a collection attribute. `IndirectList` hashes its content (it extends `Vector`); two entities linked both ways loop into `StackOverflowError`. Hibernate's bag compares by instance and hides the cycle. Identifier-based `equals`/`hashCode` are unaffected.
- No transient object hanging on a relation without `cascade = PERSIST` when a flush runs, inverse side (`@OneToMany( mappedBy )`) included: EclipseLink raises `IllegalStateException: new object found during commit`. Hibernate ignores the inverse side. Typical case: a DTO converted to an entity carries child DTOs converted to new entities; clear the inverse collection before `persist`, children are persisted by their own service.
- `@Lob` only on a real LOB column; on `text` it maps to `oid`.
- `@Transient` on an `isX( )` getter that duplicates `getX( )` (ambiguous property).
- Property access (annotations on getters) and field access both weave.

## 7. Hibernate API replacements

| Hibernate | jakarta.persistence |
|---|---|
| `em.unwrap( Session.class ).setDefaultReadOnly( true ); session.setHibernateFlushMode( FlushMode.MANUAL )` | `em.setFlushMode( FlushModeType.COMMIT )` |
| custom `Dialect` registering SQL functions | `FUNCTION( 'name', … )` in JPQL |
| `org.hibernate.SessionException` (or any Hibernate exception used as an application marker) | an application `RuntimeException` |
| Dozer `HibernateProxyResolver` (`dozer.properties`) | removed: woven entities are the classes themselves, no proxy |
| `hibernate.enhancer.*`, `hibernate.hbm2ddl.auto`, `hibernate.dialect` | removed |

The plugin ends with zero `org.hibernate` / `org.eclipse.persistence` import.

## 8. Runtime verification

Enable, on the bench only:

```xml
<logging traceSpecification="eclipselink.sql=all:eclipselink.weaver=all" traceFileName="trace.log"/>
```

Expected in `trace.log`: `Weaved change tracking (ChangeTracker) [Entity]` for every entity, `Weaved lazy (ValueHolder indirection) [Entity]` for entities with lazy to-one relations, and the SQL of every query. Then the full e2e campaign on a fresh bench: three of the five JPQL traps above only appear in business scenarios, not in screen crawls.

## 9. Spring JDBC kept as a library

```java
@ApplicationScoped
public class DataSourceProducer
{
    @Produces
    @ApplicationScoped
    public JdbcTemplate jdbcTemplate( ) throws NamingException
    {
        return new JdbcTemplate( (DataSource) new InitialContext( ).lookup( "jdbc/portal" ) );
    }
}
```

`JdbcTemplate`, `NamedParameterJdbcTemplate`, `RowMapper` unchanged; `spring-jdbc` and `spring-tx` in the pom, nothing else from Spring; transactions by `jakarta.transaction.Transactional` on the managed datasource.

## 10. References

- Open Liberty `persistence-3.1` feature: https://openliberty.io/docs/latest/reference/feature/persistence-3.1.html
- EclipseLink JPQL extensions: https://eclipse.dev/eclipselink/documentation/3.0/jpa/extensions/jpql.htm
- EclipseLink persistence properties: https://eclipse.dev/eclipselink/documentation/3.0/jpa/extensions/persistenceproperties_ref.htm
- EclipseLink query hints: https://eclipse.dev/eclipselink/documentation/3.0/jpa/extensions/queryhints.htm
