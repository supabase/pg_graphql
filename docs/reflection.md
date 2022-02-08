SQL tables are reflected into GraphQL types with columns and foreign keys represented as fields on those types.

## Naming

PostgreSQL tables/column names are automatically converted to pascal case for type names and camel case for field names.

For example, an `account` table has GraphQL type name `Account` and can be queried via the `accountCollection` field of the `Query` type.

Table, column, and relationship type and field names may be [manually overridden](/pg_graphql/configuration/#rename-a-tables-type) as needed.

## Type Conversion

### Connection Types

Connection types hande pagination best practices according to the [relay spec](https://relay.dev/graphql/connections.htm#). `pg_graphql` paginates via keyset pagination to enable consistent retrival times on every page.

## Example

```sql
--8<-- "docs/assets/demo_schema.sql"
```

```graphql
--8<-- "docs/assets/demo_schema.graphql"
```
