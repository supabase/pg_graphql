## Table/Column Visibility
Table and column visibility in the GraphQL schema are controlled by standard PostgreSQL permissions. Revoking `SELECT` access from the user/role executing queries removes that entity from the schema.

For example:
```sql
revoke all privileges on public.account from api_user;
```
removes the `Account` GraphQL type.


## Names
Name configuration is a planned goal but not currently implemented:

The ability to:

- Override type names
- Override field names

are planned for future releases


