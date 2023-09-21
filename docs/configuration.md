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

The default page size for collections is 30 entries. To adjust the number of entries on each page, set a `max_rows` directive on the relevant schema entity.

For example, to increase the max rows per page for each table in the `public` schema:

```sql
comment on schema public is e'@graphql({"max_rows": 100})';
```

### Resolve Base Type

By default, Postgres domain types are mapped to GraphQL `Opaque` type. For example:

```sql
create domain pos_int as int check (value > 0);

create table users (
  id serial primary key,
  age pos_int
);
```

The `age` field is an `Opaque` type:

```graphql
type Users {
  id: ID!
  age: Opaque
}
```

Set the `resolve_base_type` directive to `true` to resolve the domain types to their base types instead. For example:

```sql
comment on schema public is e'@graphql({"resolve_base_type": true})';
```

The `age` field is an `Int` type now:

```graphql
type Users {
  id: ID!
  age: Int
}
```

Note that a `not null` constraint on the domain type doesn't make the GraphQL type non-null. For example:

```sql
comment on schema public is e'@graphql({"resolve_base_type": true})';

create domain pos_int as int not null;

create table users {
  id serial primary key,
  age pos_int
};
```

The `age` field is still nullable:

```graphql
type Users {
  id: ID!
  age: Int
}
```

To make a domain type field non-null, add the `not null` constraint on the field in the table:

```sql
comment on schema public is e'@graphql({"resolve_base_type": true})';

create domain pos_int as int not null;

create table users {
  id serial primary key,
  age pos_int not null
};
```

The `age` field is now non-null:

```graphql
type Users {
  id: ID!
  age: Int!
}
```

### totalCount

`totalCount` is an opt-in field that extends a table's Connection type. It provides a count of the rows that match the query's filters, and ignores pagination arguments.

```graphql
type BlogPostConnection {
  edges: [BlogPostEdge!]!
  pageInfo: PageInfo!

  """The total number of records matching the `filter` criteria"""
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

Use the `"local_name"` and `"foreign_name"` JSON keys to override a a relationships inbound and outbound field names.

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

comment on constraint post_owner_id_fkey
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
    after: Cursor,
    before: Cursor,
    filter: PostFilter,
    first: Int,
    last: Int,
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
"""A User Account"""
type Account implements Node {

  """The primary key identifier"""
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
      "message": "Names must only contain [_a-zA-Z0-9] but \"aead-ietf\" does not.",
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
