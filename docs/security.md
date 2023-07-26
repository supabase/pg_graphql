`pg_graphql` fully respects builtin PostgreSQL role and row security.

## Table/Column Visibility

Table and column visibility in the GraphQL schema are controlled by standard PostgreSQL role permissions. Revoking `SELECT` access from the user/role executing queries removes that entity from the visible schema.

For example:
```sql
revoke all privileges on public."Account" from api_user;
```

removes the `Account` GraphQL type.

Similarly, revoking `SELECT` access on a table's column will remove that field from the associated GraphQL type/s.

The permissions `SELECT`, `INSERT`, `UPDATE`, and `DELETE` all impact the relevant sections of the GraphQL schema.

## Row Visibility

Visibility of rows in a given table can be configured using PostgreSQL's built-in [row level security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html) policies.
