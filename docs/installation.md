First, install [pgrx](https://github.com/tcdi/pgrx) by running `cargo install --locked cargo-pgrx@version`, where version should be compatible with the [pgrx version used by pg_graphql](https://github.com/supabase/pg_graphql/blob/master/Cargo.toml#L16).

Then clone the repo and install using:

```bash
git clone https://github.com/supabase/pg_graphql.git
cd pg_graphql
cargo pgrx install --release
```

Before enabling the extension you need to initialize `pgrx`. The easiest way to get started is to allow `pgrx` to manage its own version/s of Postgres:

```bash
cargo pgrx init --pg16=download
```

For more advanced configuration options, like building against an existing Postgres installation from e.g. Homebrew, see the [pgrx docs](https://github.com/pgcentralfoundation/pgrx)

To start the database:

```bash
cargo pgrx start pg16
```

To connect:

```bash
cargo pgrx connect pg16
```

Finally, to enable the `pg_graphql` extension in Postgres, execute the `create extension` statement. This extension creates its own schema/namespace named `graphql` to avoid naming conflicts.

```psql
create extension pg_graphql;
```

These steps ensure that `pgrx` is properly initialized, and the database is started and connected before attempting to install and use the `pg_graphql` extension.
