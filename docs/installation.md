First, install [pgx](https://github.com/tcdi/pgx) by running `cargo install --locked cargo-pgx@version`, where version should be compatible with the [pgx version used by pg_graphl](https://github.com/supabase/pg_graphql/blob/master/Cargo.toml#L16)

Then clone the repo and install using

```bash
git clone https://github.com/supabase/pg_graphql.git
cd pg_graphql
cargo pgx install --release
```

To enable the extension in PostgreSQL we must execute a `create extension` statement. The extension creates its own schema/namespace named `graphql` to avoid naming conflicts.

```psql
create extension pg_graphql;
```
