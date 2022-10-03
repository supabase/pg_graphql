pg_graphql's public facing SQL interface consists of a single SQL function to resolve GraphQL requests. All other entities in the `graphql` schema are private.


### graphql.resolve

##### description
Resolves a GraphQL query, returning JSONB.

##### signature
```sql
graphql.resolve(
    -- graphql query/mutation
    query text,
    -- json key/values pairs for variables
    variables jsonb default '{}'::jsonb,
    -- the name of the graphql operation in *query* to execute
    "operationName" text default null,
    -- extensions to include in the request
    extensions jsonb default null,
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
graphqldb= create extension pg_graphql;
CREATE EXTENSION

-- Create an example table
graphqldb= create table book(id int primary key, title text);
CREATE TABLE

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
