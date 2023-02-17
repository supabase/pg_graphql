
Views, materialized views, and foreign tables can be exposed with pg_graphql.


## Primary Keys (Required)

A primary key is required for an entity to be reflected in the GraphQL schema. Tables can define primary keys with SQL DDL, but primary keys are not available for views, materialized views, or foreign tables. For those entities, you can set a "fake" primary key with a [comment directive](/pg_graphql/configuration/#comment-directives).
```json
{"primary_key_columns": [<column_name_1>, ..., <column_name_n>]}
```

For example:

```sql
create view "Person" as
  select
    id,
    name
  from
    "Account";

comment on view "Person" is e'@graphql({"primary_key_columns": ["id"]})';
```
tells pg_graphql to treat `"Person".id` as the primary key for the `Person` entity resulting in the following GraphQL type:

```graphql
type Person {
  nodeId: ID!
  id: Int!
  name: String!
}
```

!!! warning
    Values of the primary key column/s must be unique within the table. If they are not unique, you will experience inconsistent behavior with `ID!` types, sorting, and pagination.

[Updatable views](https://www.postgresql.org/docs/current/sql-createview.html#SQL-CREATEVIEW-UPDATABLE-VIEWS) are reflected in the `Query` and `Mutation` types identically to tables. Non-updatable views are read-only and accessible via the `Query` type only.

## Relationships

pg_graphql identifies relationships among entites by inspecting foreign keys. Views, materialized views, and foreign tables do not support foreign keys. For this reason, relationships can also be defined in [comment directive](/pg_graphql/configuration/#comment-directives) using the structure:



```json
{
  "foreign_keys": [
    {
      "local_name": "foo", // optional
      "local_columns": ["account_id"],
      "foreign_name": "bar", // optional
      "foriegn_schema": "public",
      "foriegn_table": "account",
      "foriegn_columns": ["id"]
    }
  ]
}
```

For example:

```sql
create table "Account"(
  id serial primary key,
  name text not null
);

create table "EmailAddress"(
  id serial primary key,
  "accountId" int not null, -- note: no foreign key
  "isPrimary" bool not null,
  address text not null
);

comment on table "EmailAddress" is e'
    @graphql({
        "foreign_keys": [
          {
            "local_name": "addresses",
            "local_columns": ["accountId"],
            "foreign_name": "account",
            "foreign_schema": "public",
            "foreign_table": "Account",
            "foreign_columns": ["id"]
          }
        ]
    })';
```
defines a relationship equivalent to the following foreign key
```sql
alter table "EmailAddress"
  add constraint fkey_email_address_to_account
  foreign key ("accountId")
  references "Account" ("id");

comment on constraint fkey_email_address_to_account
  on "EmailAddress"
  is E'@graphql({"foreign_name": "account", "local_name": "addresses"})';
```

yielding the GraphQL types:

```graphql
type Account {
  nodeId: ID!
  id: Int!
  name: String!
  addresses(
    after: Cursor,
    before: Cursor,
    filter: EmailAddressFilter,
    first: Int,
    last: Int,
    orderBy: [EmailAddressOrderBy!]
  ): EmailAddressConnection
}

type EmailAddress {
  nodeId: ID!
  id: Int!
  isPrimary: Boolean!
  address: String!
  accountId: Int!
  account: Account!
}
```
