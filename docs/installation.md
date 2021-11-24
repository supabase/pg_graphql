Tested with PostgreSQL 13.

## Direct Server Access

First, install [libgraphqlparser](https://github.com/graphql/libgraphqlparser)

Then clone the repo and install using

```bash
git clone https://github.com/supabase/pg_graphql.git
cd pg_graphql
make && make install
```

To make the extension available to the database add in `postgresql.conf`:

```
shared_preload_libraries = 'pg_graphql'
```

and restart the database server.

To enable the extension in PostgreSQL we must execute a `create extension` statement. The extension creates its own schema/namespace named `gql` to avoid naming conflicts.

```psql
create extension pg_graphql cascade;
```

## Hosted Databases e.g. RDS, Cloud SQL

Hosted database vendors do not provide the level of server access required to install `pg_graphql` at this time.

Given that third-party hosted databases are increasingly common, we are exploring including SQL implementations of `pg_graphql`'s C components so it can be installed as a single-file SQL script.

Stay tuned
