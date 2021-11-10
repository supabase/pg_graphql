The public API consists of a single function to resolve GraphQL queries. All other entities in the `gql` schema are private.

### gql.resolve

##### description
Resolves a GraphQL query, returning JSONB.



##### signature
```sql
gql.resolve(
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
-- Setup
gqldb= create extension pg_graphql cascade;
CREATE EXTENSION

gqldb= create table book(id int primary key, title text);
CREATE TABLE

gqldb= insert into book(id, title) values (1, 'book 1');
INSERT 0 1

-- Example
gqldb= select gql.resolve($$
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

             resolve
----------------------------------------------------------------------
{"data": {"allBooks": {"edges": [{"node": {"id": 1}}]}}, "errors": []}
```


