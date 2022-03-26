The public facing API consists of a two SQL functions. One resolves GraphQL queries and the other rebuild the GraphQL schema. All other entities in the `graphql` schema are private.


### graphql.rebuild_schema

##### description
Re-synchronizes the GraphQL schema cache with the SQL schema.

##### signature
```sql
graphql.rebuild_schema()
    returns void
    language plpgsql
```

##### usage
```sql
-- Create the extension
graphqldb= create extension pg_graphql cascade;
CREATE EXTENSION

-- Rebuild the GraphQL schema
graphqldb= select graphql.rebuild_schema();

 rebuild_schema
----------------
(1 row)
```

### graphql.resolve

##### description
Resolves a GraphQL query, returning JSONB.

##### signature
```sql
graphql.resolve(
    -- the graphql query/mutation
    stmt text,
    -- json key/values pairs for variables
    variables jsonb default '{}'::jsonb,
)
    returns jsonb

    strict
    volatile
    parallel safe
    language plpgsql
```

##### usage

```sql
-- Create the extension
graphqldb= create extension pg_graphql cascade;
CREATE EXTENSION

-- Create an example table
graphqldb= create table book(id int primary key, title text);
CREATE TABLE

-- Rebuild the GraphQL schema
graphqldb= select graphql.rebuild_schema();

 rebuild_schema
----------------
(1 row)

-- Insert a record
graphqldb= insert into book(id, title) values (1, 'book 1');
INSERT 0 1

-- Query the table via GraphQL
graphqldb= select graphql.resolve($$
query {
  bookCollection {
    edges {
      node {
        id
      }
    }
  }
}
$$);

             resolve
----------------------------------------------------------------------
{"data": {"bookCollection": {"edges": [{"node": {"id": 1}}]}}, "errors": []}
```
