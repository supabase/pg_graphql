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

## Properties

### Webserver Simplicity/Throughput

Moving all GraphQL related work to the database reduces webserver complexity to the point where an API gateway (kong, nginx, etc) can likely function as the GraphQL API server by proxying request post bodies to `select gql.execute(...)`. Kong already supports a postgres connection for its own configuration so it may be possible to leverage that connection to execute arbitrary statements on the db (further research needed). In other words, no additional services/containers would be required to expose a GraphQL API.

### No resolver network latency

GraphQL is notorious for the resolver N+1 problem. Some GraphQL <-> PostgreSQL tools like graphile and hasura handle this by building up complex queries to return all results as JSON from a single SQL query.

When the resolver is located on the the PostgreSQL server, there is no network latency, so the negative impact of making multiple SQL queries is (mostly) mitigated. That improves our ability to write clear, modular, maintainable code & reduces time-to-v1.


## Try it Out

As a proof-of-concept, try out the commands below to spin up a database with the extension installed & query a table using GraphQL. Experiment with aliasing field/table names and filtering on different columns. Note: only single row returns are supported. Queries resulting in multi-rows yields undefined behavior.


Set up an interactive psql prompt with the extension installed using docker
```bash
# Build image
docker build -t pg_graphql -f Dockerfile .

# Run container 
docker run --rm --name pg_gql -p 5085:5432 -d -e POSTGRES_DB=gqldb -e POSTGRES_PASSWORD=password -e POSTGRES_USER=postgres -d pg_graphql

# Attach to container
docker exec -it pg_gql psql -U postgres gqldb
```

Now we'll create the extension, and create a test table with some data to query 

```sql
gqldb= create extension pg_graphql;
CREATE EXTENSION

gqldb= create table book(id int primary key, title text);
CREATE TABLE

gqldb= insert into book(id, title) values (1, 'book 1'); 
INSERT 0 1
```

Finally, execute some graphql queries against the table.
```sql
gqldb=# select gql.execute($$
query {
  book(id: 1) {
    book_id: id
    title
  }
}
$$);
             execute            
----------------------------------
 {"data": {"book": {"book_id": 1, "title": "book 1"}}}
```

## Progress

### Query

- [x] query for single row from any table
- [x] select subset of columns
- [x] filter by any column
- [x] alias operation names
- [x] alias field names
- [ ] restrict filtering to primary key + unique columns
- [ ] validate query against schema before resolving
- [ ] multi-row response
- [ ] connections


### Mutations
- [ ] everything


### Error Handling
- [ ] display statement syntax errors
- [ ] non-existent tables
- [ ] non-existent columns


### Configuration
- [ ] restrict to single schema
- [ ] override table names
- [ ] exclude tables
- [ ] override column names
- [ ] exclude columns
- [ ] max query depth
- [ ] resolver timeout


### Run the Tests

Requires:

- Python 3.6+
- Docker 

```shell
pip intall -e .

docker build -t pg_graphql -f Dockerfile . && pytest
```
