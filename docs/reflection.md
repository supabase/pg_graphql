SQL tables are reflected into GraphQL types with columns and foreign keys represented as fields on those types. Each table's GraphQL types are then registered against the top level `Query` type enabling selection of a record by its globally unique ID, or paging through all of the rows in a table.

## Naming

PostgreSQL tables/columns are are expected to be lowercase with underscores. To follow casing conventions, table and column are converted to pascal case for type name, camel case for field names and pluralized as necessary in the GraphQL schema.

For example, an `account` table has GraphQL type name `Account` and fields on the `Query` type of `account` and `allAccounts`.

The pluralization logic is extremely basic. Name overrides have not been implemented yet but are comming soon.


## Type Conversion

### ID

The "ID" GraphQL type is a globally unique identifer. It is represented as a string and is implemented as a base64 encoded json array of `[regclass, pkey_value1, ... pkey_valueN]`.


!!! warning
    Be careful when adding/removing schemas from the PostgreSQL `search_path` as these impact the string representation for `regclass` and will cause the global identifer to change.

### Connection Types

Connection types hande pagination best practices according to the [relay spec](https://relay.dev/graphql/connections.htm#). `pg_graphql` paginates via keyset pagination to enable consistent retrival times on every page.

#### Cursor

See [relay documentation](https://relay.dev/graphql/connections.htm#sec-Cursor)

A cursor is custom scalar, represented as an opaque string, that is used for pagination. Its implementation is identical to the ID type but that is an implementation detail and should not be relied upon.

#### PageInfo

See [relay documentation](https://relay.dev/graphql/connections.htm#sec-undefined.PageInfo)


### PostgreSQL Builtins

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


## Example

```sql
--8<-- "docs/assets/demo_schema.sql"
```

```graphql
--8<-- "docs/assets/demo_schema.graphql"
```
