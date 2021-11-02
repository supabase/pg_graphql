# `pg_graphql`

<p>
<a href=""><img src="https://img.shields.io/badge/postgresql-12+-blue.svg" alt="PostgreSQL version" height="18"></a>
<a href="https://github.com/supabase/pg_graphql/blob/master/LICENSE"><img src="https://img.shields.io/pypi/l/markdown-subtemplate.svg" alt="License" height="18"></a>
<a href="https://github.com/supabase/pg_graphql/actions"><img src="https://github.com/supabase/pg_graphql/actions/workflows/main.yml/badge.svg" alt="Tests" height="18"></a>

</p>

---

**Source Code**: <a href="https://github.com/supabase/pg_graphql" target="_blank">https://github.com/supabase/pg_graphql</a>

---

## Summary

pg_graphql is an experimental PostgreSQL extension adding support for GraphQL.

The extension keeps schema generation, parsing, statement resolution, and configuration on the database server.

## Demo

### GraphiQL

The GraphiQL demo launches a database, webserver and the GraphiQL API explorer. If you are new to the project, start here.

Requires:

- docker-compose

```shell
docker-compose -f docker-compose.graphiql.yml down -v; docker rm pg_graphql_db; docker rmi pg_graphql_db; docker-compose -f docker-compose.graphiql.yml up
```
then navigate to `http://localhost:4000/` for an interactive [graphiql IDE](https://github.com/graphql/graphiql) instance.


### PSQL Prompt

The PSQL prompt demo launches only a database with `pg_graphql` installed.

Set up an interactive psql prompt with the extension installed
```bash
nix-shell --run "pg_13_graphql psql"
```

Try out the commands below to spin up a database with the extension installed & query a table using GraphQL. Experiment with aliasing field/table names and filtering on different columns.

```sql
gqldb= create extension pg_graphql cascade;
CREATE EXTENSION

gqldb= create table book(id int primary key, title text);
CREATE TABLE

gqldb= insert into book(id, title) values (1, 'book 1');
INSERT 0 1
```

Finally, execute some graphql queries against the table.
```sql
gqldb= select gql.dispatch($$
query {
  allBooks {
    edges {
      node {
        id
      }
    }
  }
}
$$);

             execute
----------------------------------------------------------------------
{"data": {"allBooks": {"edges": [{"node": {"id": 1}}]}}, "errors": []}
```

## Testing

Requires:

- nix-shell

```shell
nix-shell --run "pg_13_graphql make installcheck"
```

## Roadmap

### Language
- [x] Parser
- [x] Fragments
- [ ] Variables (WIP)
- [x] Named Operations
- [ ] Introspection Schema

### Relay
- [x] Opaque Cursors
- [x] Global NodeId
- [x] Node Types
  - [x] Selectable
  - [x] Arg: nodeId
- [ ] Connection Types
  - [x] Selectable
  - [ ] Forward pagination
    - [x] Arg: first
    - [ ] Arg: after
  - [ ] Reverse pagination
    - [ ] Arg: last
    - [ ] Arg: before
  - [ ] Arg: Condition

### Relationships
- [x] Connection to Connection
- [x] Connection to Node
- [x] Node to Connection
- [x] Node to Node

### Mutations
- [ ] Upsert
- [ ] Arbitrary Functions

### Error Handling
- [ ] Display parser syntax errors
- [ ] Useful error on non-existent type
- [ ] Useful error on non-existent field

### Configuration
- [ ] Max Query Depth
- [ ] Documentation
  - [ ] Role based schema/table/column exclusion
  - [ ] Override Type/Field names

### Optimizations
- [x] Prepared statement cache
