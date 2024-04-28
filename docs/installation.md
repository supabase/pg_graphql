First, install [pgrx](https://github.com/tcdi/pgrx) by running `cargo install --locked cargo-pgrx@version`, where version should be compatible with the [pgrx version used by pg_graphql](https://github.com/supabase/pg_graphql/blob/master/Cargo.toml#L16)

Then clone the repo and install using

```bash
git clone https://github.com/supabase/pg_graphql.git
cd pg_graphql
cargo pgrx install --release
```

To enable the extension in PostgreSQL we must execute a `create extension` statement. The extension creates its own schema/namespace named `graphql` to avoid naming conflicts.

```psql
create extension pg_graphql;
```
