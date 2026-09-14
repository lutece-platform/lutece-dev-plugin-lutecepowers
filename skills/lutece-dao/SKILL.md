---
name: lutece-dao
description: "Use when creating, modifying or reviewing a Lutece 8 DAO, Home or business class: DAOUtil lifecycle, SQL constants, Home static facade, CDI lookup, collection types, interface conventions. Must be consulted before touching anything under a business package."
---

# DAO & Home Patterns — Lutece 8

`DAOUtil` is the data layer of new code. A plugin that already carries a JPA model keeps it on the `jakarta.persistence` API with the EclipseLink provider of the container (`persistence-3.1`): `lutece-migration-v8-agent-teams/patterns/persistence-patterns.md`.

> Before writing DAO or Home code, consult `~/.lutece-references/lutece-core/` and `~/.lutece-references/lutece-form-plugin-forms/` using Read, Grep and Glob.

## DAO Class Structure

```java
@ApplicationScoped
public final class EntityDAO implements IEntityDAO
{
    private static final String SQL_QUERY_SELECT = "SELECT id_entity, title, description FROM myplugin_entity WHERE id_entity = ?";
    private static final String SQL_QUERY_INSERT = "INSERT INTO myplugin_entity ( title, description ) VALUES ( ?, ? )";
    private static final String SQL_QUERY_UPDATE = "UPDATE myplugin_entity SET title = ?, description = ? WHERE id_entity = ?";
    private static final String SQL_QUERY_DELETE = "DELETE FROM myplugin_entity WHERE id_entity = ?";
    private static final String SQL_QUERY_SELECTALL = "SELECT id_entity, title, description FROM myplugin_entity";
}
```

- The bean is resolved through `IEntityDAO`, so `final` is fine (core and forms DAOs are `final`). Drop `final` only if something injects the concrete class.
- No `@Named`: none of the core or forms DAOs carry one. Add `@Named( "myplugin.entityDAO" )` only when a producer resolves the DAO by name (workflow `ITaskConfigDAO`).

## SQL Constant Naming

| Constant | Usage |
|----------|-------|
| `SQL_QUERY_SELECT` | Single row by PK |
| `SQL_QUERY_INSERT` | Insert row |
| `SQL_QUERY_UPDATE` | Update row by PK |
| `SQL_QUERY_DELETE` | Delete row by PK |
| `SQL_QUERY_SELECTALL` | All rows |
| `SQL_QUERY_SELECT_BY_*` | Custom finders |
| `SQL_QUERY_COUNT_*` | Count queries |

No `SQL_QUERY_NEWPK` / `SELECT max( id )`: the primary key is an `AUTO_INCREMENT` column read back with generated keys (below).

## DAOUtil Lifecycle

Always use **try-with-resources** (auto-closes):

### INSERT (generated key)
```java
import java.sql.Statement;

public void insert( Entity entity, Plugin plugin )
{
    try ( DAOUtil daoUtil = new DAOUtil( SQL_QUERY_INSERT, Statement.RETURN_GENERATED_KEYS, plugin ) )
    {
        int nIndex = 1;
        daoUtil.setString( nIndex++, entity.getTitle( ) );
        daoUtil.setString( nIndex++, entity.getDescription( ) );
        daoUtil.executeUpdate( );

        if ( daoUtil.nextGeneratedKey( ) )
        {
            entity.setId( daoUtil.getGeneratedKeyInt( 1 ) );
        }
    }
}
```

### UPDATE / DELETE
```java
public void store( Entity entity, Plugin plugin )
{
    try ( DAOUtil daoUtil = new DAOUtil( SQL_QUERY_UPDATE, plugin ) )
    {
        int nIndex = 1;
        daoUtil.setString( nIndex++, entity.getTitle( ) );
        daoUtil.setString( nIndex++, entity.getDescription( ) );
        daoUtil.setInt( nIndex, entity.getId( ) );
        daoUtil.executeUpdate( );
    }
}
```

### SELECT (single row)
```java
public Entity load( int nKey, Plugin plugin )
{
    Entity entity = null;
    try ( DAOUtil daoUtil = new DAOUtil( SQL_QUERY_SELECT, plugin ) )
    {
        daoUtil.setInt( 1, nKey );
        daoUtil.executeQuery( );

        if ( daoUtil.next( ) )
        {
            int nIndex = 1;
            entity = new Entity( );
            entity.setId( daoUtil.getInt( nIndex++ ) );
            entity.setTitle( daoUtil.getString( nIndex++ ) );
            entity.setDescription( daoUtil.getString( nIndex++ ) );
        }
    }
    return entity;
}
```

### SELECT (collection)
```java
public List<Entity> selectAll( Plugin plugin )
{
    List<Entity> listEntities = new ArrayList<>( );
    try ( DAOUtil daoUtil = new DAOUtil( SQL_QUERY_SELECTALL, plugin ) )
    {
        daoUtil.executeQuery( );

        while ( daoUtil.next( ) )
        {
            int nIndex = 1;
            Entity entity = new Entity( );
            entity.setId( daoUtil.getInt( nIndex++ ) );
            entity.setTitle( daoUtil.getString( nIndex++ ) );
            entity.setDescription( daoUtil.getString( nIndex++ ) );
            listEntities.add( entity );
        }
    }
    return listEntities;
}
```

## DAOUtil Parameter Types

Parameters and results are **1-indexed**. Use `nIndex++` for sequential access.

| Type | Setter | Getter |
|------|--------|--------|
| int | `setInt( n, val )` | `getInt( n )` |
| String | `setString( n, val )` | `getString( n )` |
| long | `setLong( n, val )` | `getLong( n )` |
| boolean | `setBoolean( n, val )` | `getBoolean( n )` |
| double | `setDouble( n, val )` | `getDouble( n )` |
| Timestamp | `setTimestamp( n, val )` | `getTimestamp( n )` |
| Date | `setDate( n, val )` | `getDate( n )` |

## Interface Pattern

Every DAO has an interface:
```java
public interface IEntityDAO
{
    void insert( Entity entity, Plugin plugin );
    Entity load( int nKey, Plugin plugin );
    void store( Entity entity, Plugin plugin );
    void delete( int nKey, Plugin plugin );
    List<Entity> selectAll( Plugin plugin );
}
```

Add finders per need. A `ReferenceList selectEntitiesReferenceList( Plugin plugin )` exists only when a `<select>` consumes it (forms: `selectFormsReferenceList`); it is not part of the base contract.

## Home — Static Facade

```java
public final class EntityHome
{
    private static IEntityDAO _dao = CDI.current( ).select( IEntityDAO.class ).get( );
    private static Plugin _plugin = PluginService.getPlugin( "myplugin" );

    private EntityHome( ) { }

    public static Entity create( Entity entity )
    {
        _dao.insert( entity, _plugin );
        return entity;
    }

    public static Entity update( Entity entity )
    {
        _dao.store( entity, _plugin );
        return entity;
    }

    public static void remove( int nKey )
    {
        _dao.delete( nKey, _plugin );
    }

    public static Entity findByPrimaryKey( int nKey )
    {
        return _dao.load( nKey, _plugin );
    }

    public static List<Entity> findAll( )
    {
        return _dao.selectAll( _plugin );
    }
}
```

The `_dao` static field initializer is the idiom of every core and forms Home (`RoleHome`, `FormHome`): the CDI container is up before plugin classes load.

## Collection Types

| Return type | When |
|-------------|------|
| `List<Entity>` | Standard list of entities |
| `ReferenceList` | Key-value pairs for dropdowns (`<select>`) |
| `Optional<Entity>` | Optional single result (modern style) |

## Reference Sources

| Need | File to consult |
|------|----------------|
| Core DAO patterns | `~/.lutece-references/lutece-core/src/java/**/business/` |
| Core Home patterns | `~/.lutece-references/lutece-core/src/java/**/business/` |
| DAOUtil source | `~/.lutece-references/lutece-core/src/java/**/util/sql/DAOUtil.java` |
| Forms plugin DAO examples | `~/.lutece-references/lutece-form-plugin-forms/src/java/**/business/` |
