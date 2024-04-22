First, install [pgrx](https://github.com/tcdi/pgrx) by running `cargo install --locked cargo-pgrx@version`, where version should be compatible with the [pgrx version used by pg_graphql](https://github.com/supabase/pg_graphql/blob/master/Cargo.toml#L16).

Then clone the repo and install using:

```bash
git clone https://github.com/supabase/pg_graphql.git
cd pg_graphql
cargo pgrx install --release
```

Before enabling the extension in PostgreSQL, you need to initialize `pgrx`. Depending on your PostgreSQL installation, you might need to specify the path to `pg_config`. For example, on macOS with PostgreSQL installed via Homebrew:

```bash
cargo pgrx init --pg14 "/opt/homebrew/bin/pg_config"
```

To start the database:

```bash
cargo pgrx start pg14
```

To connect:

```bash
cargo pgrx connect pg14
```

Finally, to enable the `pg_graphql` extension in PostgreSQL, execute the `create extension` statement. This extension creates its own schema/namespace named `graphql` to avoid naming conflicts.

```psql
create extension pg_graphql;
```

These additional steps ensure that `pgrx` is properly initialized, and the database is started and connected before attempting to install and use the `pg_graphql` extension.