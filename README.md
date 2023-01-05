# `pg_graphql`

<p>
<a href=""><img src="https://img.shields.io/badge/postgresql-14+-blue.svg" alt="PostgreSQL version" height="18"></a>
<a href="https://github.com/supabase/pg_graphql/blob/master/LICENSE"><img src="https://img.shields.io/pypi/l/markdown-subtemplate.svg" alt="License" height="18"></a>
<a href="https://github.com/supabase/pg_graphql/actions"><img src="https://github.com/supabase/pg_graphql/actions/workflows/test.yml/badge.svg" alt="tests" height="18"></a>

</p>

---

**Documentation**: <a href="https://supabase.github.io/pg_graphql" target="_blank">https://supabase.github.io/pg_graphql</a>

**Source Code**: <a href="https://github.com/supabase/pg_graphql" target="_blank">https://github.com/supabase/pg_graphql</a>

---

`pg_graphql` adds GraphQL support to your PostgreSQL database.

- [x] __Performant__
- [x] __Consistent__
- [x] __Serverless__
- [x] __Open Source__

### Overview
`pg_graphql` reflects a GraphQL schema from the existing SQL schema.

The extension keeps schema translation and query resolution neatly contained on your database server. This enables any programming language that can connect to PostgreSQL to query the database via GraphQL with no additional servers, processes, or libraries.


### TL;DR

The SQL schema

```sql
create table account(
    id serial primary key,
    email varchar(255) not null,
    created_at timestamp not null,
    updated_at timestamp not null
);

create table blog(
    id serial primary key,
    owner_id integer not null references account(id),
    name varchar(255) not null,
    description varchar(255),
    created_at timestamp not null,
    updated_at timestamp not null
);

create type blog_post_status as enum ('PENDING', 'RELEASED');

create table blog_post(
    id uuid not null default uuid_generate_v4() primary key,
    blog_id integer not null references blog(id),
    title varchar(255) not null,
    body varchar(10000),
    status blog_post_status not null,
    created_at timestamp not null,
    updated_at timestamp not null
);
```
Translates into a GraphQL schema displayed below.

Each table receives an entrypoint in the top level `Query` type that is a pageable collection with relationships defined by its foreign keys. Tables similarly recieve entrypoints in the `Mutation` schema that enable bulk operations for insert, update, and delete.

![GraphiQL](./docs/assets/quickstart_graphiql.png)
