# Example

```sql
--8<-- "docs/assets/demo_schema.sql"
```

```graphql
--8<-- "docs/assets/demo_schema.graphql"
```

# Types

## PostgreSQL Builtins

|PostgreSQL     |GraphQL        |
|:--------------|:--------------|
|bool           |Boolean        |
|float4         |Float          |
|float8         |Float          |
|int2           |Int            |
|int4           |Int            |
|int8           |Int            |
|json           |JSON           |
|jsonb          |JSON           |
|jsonpath       |String         |
|numeric        |Float          |
|date           |DateTime       |
|daterange      |String         |
|timestamp      |DateTime       |
|timestamptz    |DateTime       |
|uuid           |UUID           |
|text           |String         |
|char           |String         |
|inet           |InternetAddress|
|inet           |InternetAddress|
|macaddr        |MACAddress     |
|*other*        |String         |

## ID

The "ID" GraphQL type is a globally unique identifer. It is represented as a string and is implemented as a base64 encoded json array of `[regclass, pkey_value1, ... pkey_valueN]`.


!!! warning
	Be careful when adding/removing schemas from the PostgreSQL `search_path` as these impact the string representation for `regclass` and will cause the global identifer to change.

## Connection Types

Connection types hande pagination best practices according to the [relay spec](https://relay.dev/graphql/connections.htm#). `pg_graphql` paginates via keyset pagination to enable consistent retrival times on every page.

### Cursor

See [relay documentation](https://relay.dev/graphql/connections.htm#sec-Cursor)

A cursor is custom scalar, represented as an opaque string, that is used for pagination. Its implementation is identical to the ID type but that is an implementation detail and should not be relied upon.

### PageInfo

See [relay documentation](https://relay.dev/graphql/connections.htm#sec-undefined.PageInfo)
