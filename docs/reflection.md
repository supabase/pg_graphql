SQL tables are reflected into GraphQL types with columns and foreign keys represented as fields on those types.

## Naming

By default, PostgreSQL table and column names are not adjusted when reflecting GraphQL type and field names. For example, an `account_holder` table has GraphQL type name `account_holder` and can be queried via the `account_holderCollection` field of the `Query` type.

In cases, like the previous example, where the SQL name is `snake_case`, you'll likely want to [enable inflection](/pg_graphql/configuration/#inflection) to re-case names to match GraphQL/Javascript conventions e.g. `AccountHolder` and `accountHolderCollection`.

Table, column, and relationship type and field names may also be [manually overridden](/pg_graphql/configuration/#tables-type) as needed.

## Type Conversion

### Connection Types

Connection types handle pagination best practices according to the [relay spec](https://relay.dev/graphql/connections.htm#). `pg_graphql` uses keyset pagination to enable consistent retrival times on every page.

## Example

The following is a complete example showing how a sample SQL schema translates into a GraphQL schema.

```sql
--8<-- "docs/assets/demo_schema.sql"
```

```graphql
--8<-- "docs/assets/demo_schema.graphql"
```
