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

## Introspection

`__schema` and `__type` introspection queries are **disabled by default**. Listing the full API surface area makes it easier for attackers to enumerate poorly secured projects, so introspection must be opted into per schema:

```sql
comment on schema public is e'@graphql({"introspection": true})';
```

Enable it during development for tooling like GraphiQL and codegen, then disable it again before exposing the API publicly. Disabling introspection does not restrict actual queries or mutations — those are governed by PostgreSQL roles and Row Level Security. See [configuration → Introspection](configuration.md#introspection).
