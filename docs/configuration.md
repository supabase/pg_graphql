Extra configuration options can be set on SQL entities using comment directives.

## Comment Directives

Comment directives are snippets of configuration associated with SQL entities that alter how those entities behave.

The format of a comment directive is

```sql
@graphql(<JSON>)
```

### Inflection

Inflection describes how SQL entities' names are transformed into GraphQL type and field names. By default, inflection is disabled and SQL names are literally interpolated such that

```sql
create table "BlogPost"(
    id int primary key,
    ...
);
```

results in GraphQL type names like

```
BlogPost
BlogPostEdge
BlogPostConnection
...
```

Since snake case is a common casing structure for SQL types, `pg_graphql` support basic inflection from `snake_case` to `PascalCase` for type names, and `snake_case` to `camelCase` for field names to match Javascript conventions.

The inflection directive can be applied at the schema level with:

```sql
comment on schema <schema_name> is e'@graphql({"inflect_names": true})';
```

for example

```sql
comment on schema public is e'@graphql({"inflect_names": true})';

create table blog_post(
    id int primary key,
    ...
);
```

similarly would generated the GraphQL type names

```
BlogPost
BlogPostEdge
BlogPostConnection
...
```

For more fine grained adjustments to reflected names, see [renaming](#renaming).

### Max Rows

The default page size for collections is 30 entries. To adjust the number of entries on each page, set a `max_rows` directive on the relevant schema entity, table or view.

For example, to increase the max rows per page for each table in the `public` schema:

```sql
comment on schema public is e'@graphql({"max_rows": 100})';
```

To limit the max rows per page for the `blog_post` table and `Person` view:

```sql
comment on table blog_post is e'@graphql({"max_rows": 20})';
comment on view "Person" is e'@graphql({"primary_key_columns": ["id"], "max_rows": 10})';
```

The `max_rows` value falls back to the parent object if it is missing on the current object. For example, if a table doesn't have `max_rows` set, the value set on the table's schema will be used. If the schema also doesn't have `max_rows` set, then it falls back to default value 30. The parent object of a view is the schema, not the table on which the view is created.

### Introspection

GraphQL introspection is disabled by default to reduce the potential for API enumeration. Tools like GraphiQL, code generators, Apollo DevTools, and the Relay compiler rely on introspection. Opt in per schema when you need them.

To enable introspection on `public` schema:

```sql
comment on schema public is e'@graphql({"introspection": true})';
```

To explicitly disable it (same as the default):

```sql
comment on schema public is e'@graphql({"introspection": false})';
```

When no exposed schema has opted in, `__schema` and `__type` selections return an error:

```json
{ "errors": [{ "message": "Unknown field \"__schema\" on type Query" }] }
```

#### Partial introspection accross multiple schemas

!!!note "disable introspection for all schemas"

    It is recommended to disable introspection for all schemas in production.

The introspection directive is per schema. If two exposed schemas have introspection enabled for one but disabled for another, instead of returning `Unknown field...` errors, disabled schema's types are hidden from introspection fields.

Consider a setup with two schemas, where `public` has introspection enabled and `private` has it disabled:

```sql
-- public schema exists by default
create schema private;

comment on schema public  is e'@graphql({"inflect_names": true, "introspection": true})';
comment on schema private is e'@graphql({"inflect_names": true, "introspection": false})';

create table public.blog(id serial primary key, content text not null);
create table private.account(id serial primary key, email text not null);

set search_path = public, private;
```

`__schema` and `__type` will not return an error because at least one schema (`public`) has introspection enabled. If neither schema had it enabled, both fields would return `Unknown field "__schema" on type Query`.

**`__type` Field Queries**

The `__type` field successfully resolves types belonging to the `public` schema:

=== "Query"

    ```graphql
    { __type(name: "Blog") { kind name } }
    ```

=== "Response"

    ```json
    { "data": { "__type": { "kind": "OBJECT", "name": "Blog" } } }
    ```

But it returns `null` for types in the `private` schema:

=== "Query"

    ```graphql
    { __type(name: "Account") { kind name } }
    ```

=== "Response"

    ```json
    { "data": { "__type": null } }
    ```

Any non-existent types in the `private` schema also return null. In that case the introspecting user does not have visibility into if the requested type is in a schema without introspection, or if it doesn't exist. The two responses are indistinguishable:

=== "Query"

    ```graphql
    { __type(name: "User") { kind name } }
    ```

=== "Response"

    ```json
    { "data": { "__type": null } }
    ```

**`__schema` Field Queries**

`__schema` field also filters out types from the private schema. `Blog` and its derived types (`BlogEdge`, `BlogConnection`, `BlogFilter`, `BlogOrderBy`, etc.) appear in the list, while `Account` and its derivatives are absent:

=== "Query"

    ```graphql
    { __schema { types { kind name } } }
    ```

=== "Response"

    ```json
    {
      "data": {
        "__schema": {
          "types": [
            { "kind": "OBJECT", "name": "Blog" },
            { "kind": "OBJECT", "name": "BlogConnection" },
            { "kind": "OBJECT", "name": "BlogEdge" },
            { "kind": "INPUT_OBJECT", "name": "BlogFilter" },
            { "kind": "INPUT_OBJECT", "name": "BlogOrderBy" },
            // no Account, AccountConnection, AccountEdge, AccountFilter, AccountOrderBy, ...
          ]
        }
      }
    }
    ```

Note that built-in scalars and meta-types continue to appear:

=== "Query"

    ```graphql
    { __schema { types { kind name } } }
    ```

=== "Response"

    ```json
    {
      "data": {
        "__schema": {
          "types": [
            { "kind": "SCALAR", "name": "Boolean" },
            { "kind": "SCALAR", "name": "Int" },
            { "kind": "SCALAR", "name": "Float" },
            { "kind": "OBJECT", "name": "__Schema" }
            { "kind": "OBJECT", "name": "__Field" }
            // ... other fields omitted for brevity
          ]
        }
      }
    }
    ```

The Query type's field listing is filtered the same way. `blogCollection` appears, `accountCollection` is hidden:

=== "Query"

    ```graphql
    { __schema { queryType { fields { name } } } }
    ```

=== "Response"

    ```json
    {
      "data": {
        "__schema": {
          "queryType": {
            "fields": [
              { "name": "blogCollection" },
              { "name": "node" }
              // no accountCollection
            ]
          }
        }
      }
    }
    ```

Same for the the Mutation type's field listing, `Blog`'s mutation fields appear, `Account`'s are hidden:

=== "Query"

    ```graphql
    { __schema { mutationType { fields { name } } } }
    ```

=== "Response"

    ```json
    {
      "data": {
        "__schema": {
          "mutationType": {
            "fields": [
              { "name": "insertIntoBlogCollection" },
              { "name": "updateBlogCollection" },
              { "name": "deleteFromBlogCollection" }
              // no insertIntoAccountCollection, updateAccountCollection, deleteFromAccountCollection
            ]
          }
        }
      }
    }
    ```

#### Non-introspection Queries

Non-introspection queries are not affected by disabling introspection. `accountCollection`, `insertIntoAccountCollection`, etc. continue to resolve normally as long as the role has the underlying SQL privileges:

=== "Query"

    ```graphql
    {
      accountCollection {
        edges {
          node {
            id
            email
          }
        }
      }
    }
    ```

=== "Response"

    ```json
    {
      "data": {
        "accountCollection": {
          "edges": [
            { "node": { "id": 1, "email": "alice@example.com" } }
          ]
        }
      }
    }
    ```

The four combinations across the two schemas behave as follows:

| `public` | `private` | `__schema` / `__type` available | `Blog` visible | `Account` visible | Non-introspection queries |
| -------- | --------- | ------------------------------- | -------------- | ----------------- | ------------------------- |
| on       | on        | yes                             | yes            | yes               | unchanged                 |
| on       | off       | yes                             | yes            | no                | unchanged                 |
| off      | on        | yes                             | no             | yes               | unchanged                 |
| off      | off       | no (`Unknown field` error)      | n/a            | n/a               | unchanged                 |

### totalCount

`totalCount` is an opt-in field that extends a table's Connection type. It provides a count of the rows that match the query's filters, and ignores pagination arguments.

```graphql
type BlogPostConnection {
  edges: [BlogPostEdge!]!
  pageInfo: PageInfo!

  """
  The total number of records matching the `filter` criteria
  """
  totalCount: Int! # this field
}
```

to enable `totalCount` for a table, use the directive

```sql
comment on table "BlogPost" is e'@graphql({"totalCount": {"enabled": true}})';
```

for example

```sql
create table "BlogPost"(
    id serial primary key,
    email varchar(255) not null
);
comment on table "BlogPost" is e'@graphql({"totalCount": {"enabled": true}})';
```

### Aggregate

The `aggregate` field is an opt-in field that extends a table's Connection type. It provides various aggregate functions like count, sum, avg, min, and max that operate on the collection of records that match the query's filters.

```graphql
type BlogPostConnection {
  edges: [BlogPostEdge!]!
  pageInfo: PageInfo!

  """
  Aggregate functions calculated on the collection of `BlogPost`
  """
  aggregate: BlogPostAggregate # this field
}
```

To enable the `aggregate` field for a table, use the directive:

```sql
comment on table "BlogPost" is e'@graphql({"aggregate": {"enabled": true}})';
```

For example:

```sql
create table "BlogPost"(
    id serial primary key,
    title varchar(255) not null,
    rating int not null
);
comment on table "BlogPost" is e'@graphql({"aggregate": {"enabled": true}})';
```

You can combine both totalCount and aggregate directives:

```sql
comment on table "BlogPost" is e'@graphql({"totalCount": {"enabled": true}, "aggregate": {"enabled": true}})';
```

### Renaming

#### Table's Type

Use the `"name"` JSON key to override a table's type name.

```sql
create table account(
    id serial primary key
);

comment on table public.account is
e'@graphql({"name": "AccountHolder"})';
```

results in:

```graphql
type AccountHolder { # previously: "Account"
  id: Int!
}
```

#### Column's Field Name

Use the `"name"` JSON key to override a column's field name.

```sql
create table public."Account"(
    id serial primary key,
    email text
);

comment on column "Account".email is
e'@graphql({"name": "emailAddress"})';
```

results in:

```graphql
type Account {
  nodeId: ID!
  id: Int!
  emailAddress: String! # previously "email"
}
```

#### Computed Field

Use the `"name"` JSON key to override a [computed field's](computed_fields.md) name.

```sql
create table "Account"(
    id serial primary key,
    "firstName" varchar(255) not null,
    "lastName" varchar(255) not null
);

-- Extend with function
create function public."_fullName"(rec public."Account")
    returns text
    immutable
    strict
    language sql
as $$
    select format('%s %s', rec."firstName", rec."lastName")
$$;

comment on function public._full_name is
e'@graphql({"name": "displayName"})';
```

results in:

```graphql
type Account {
  nodeId: ID!
  id: Int!
  firstName: String!
  lastName: String!
  displayName: String # previously "fullName"
}
```

#### Relationship's Field

Use the `"local_name"` and `"foreign_name"` JSON keys to override a relationship's inbound and outbound field names.

```sql
create table "Account"(
    id serial primary key
);

create table "Post"(
    id serial primary key,
    "accountId" integer not null references "Account"(id),
    title text not null,
    body text
);

comment on constraint post_account_id_fkey
  on "Post"
  is E'@graphql({"foreign_name": "author", "local_name": "posts"})';
```

results in:

```graphql
type Post {
  nodeId: ID!
  id: Int!
  accountId: Int!
  title: String!
  body: String!
  author: Account # was "account"
}

type Account {
  id: Int!
  posts( # was "postCollection"
    after: Cursor
    before: Cursor
    filter: PostFilter
    first: Int
    last: Int
    orderBy: [PostOrderBy!]
  ): PostConnection
}
```

### Description

Tables, Columns, and Functions accept a `description` directive to populate user defined descriptions in the GraphQL schema.

```sql
create table "Account"(
    id serial primary key
);

comment on table public.account
is e'@graphql({"description": "A User Account"})';

comment on column public.account.id
is e'@graphql({"description": "The primary key identifier"})';
```

```graphql
"""
A User Account
"""
type Account implements Node {
  """
  The primary key identifier
  """
  id: Int!
}
```

#### Enum Variant

If a variant of a Postgres enum does not conform to GraphQL naming conventions, introspection returns an error:

For example:

```sql
create type "Algorithm" as enum ('aead-ietf');
```

causes the error:

```json
{
  "errors": [
    {
      "message": "Names must only contain [_a-zA-Z0-9] but \"aead-ietf\" does not."
    }
  ]
}
```

To resolve this problem, rename the invalid SQL enum variant to a GraphQL compatible name:

```sql
alter type "Algorithm" rename value 'aead-ietf' to 'AEAD_IETF';
```

or, add a comment directive to remap the enum variant in the GraphQL API

```sql
comment on type "Algorithm" is '@graphql({"mappings": {"aead-ietf": "AEAD_IETF"}})';
```

Which both result in the GraphQL enum:

```graphql
enum Algorithm {
  AEAD_IETF
}
```
