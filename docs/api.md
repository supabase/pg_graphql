The public API consists of a single function to resolve GraphQL queries. All other entities in the `graphql` schema are private.

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
-- Setup
graphqldb= create extension pg_graphql cascade;
CREATE EXTENSION

graphqldb= create table book(id int primary key, title text);
CREATE TABLE

graphqldb= insert into book(id, title) values (1, 'book 1');
INSERT 0 1

-- Example
graphqldb= select graphql.resolve($$
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


