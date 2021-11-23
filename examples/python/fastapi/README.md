# `pg_graphql`: FastAPI

Example GraphQL API server implemented in with pg_graphql, python and FastAPI.


Usage:

First, launch start the demo database with
```shell
# clone the repo
git clone https://github.com/supabase/pg_graphql.git
cd pg_graphql

# start the demo database with pg_graphql installed
docker-compose up
```

The connection string for the demo database is `DB_URI=postgres://postgres:password@0.0.0.0:5404/gqldb`


```python
# Create and activate a virtual environment
python -m venv venv
source venv/bin/activate

# Install project dependencies
pip install -e .

# Export the database connection string
export DBI_URI=DB_URI=postgres://postgres:password@0.0.0.0:5404/gqldb

# Launch the server
uvicorn graphql_server:app --host=0.0.0.0 --port=8000
```

Then make a request against the GraphQL API endpoint `/rpc/graphql`

```shell
curl -X POST http://0.0.0.0:4002/rpc/graphql \
  -H 'Content-Type: application/json' -d '{"query": "{ allAccounts(first: 1) { edges { cursor node { email createdAt } } } }"}'
```

Response
```json
{
  "data": {
    "allAccounts": {
      "edges": [
        {
          "node": {
            "email": "aardvark@x.com",
            "createdAt": "2021-11-23T03:42:41.62354"
          },
          "cursor": "WyJhY2NvdW50IiwgMV0="
        }
      ]
    }
  },
  "errors": []
}
```
