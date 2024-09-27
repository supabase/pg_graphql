pg_graphql is OSS. PR and issues are welcome.

## Development

To start developing `pg_graphql`:

1. [Install Rust](https://www.rust-lang.org/tools/install).
2. [Install pgrx](https://github.com/pgcentralfoundation/pgrx)

### Testing

Tests are located in sql files in the `./test/sql` folder. Each sql file has a corresponding expected output file in `./test/expected` folder. For example, `./test/sql/aliases.sql`'s expected output is in `./tests/expected/aliases.out`. When a test runs, its actual output is saved in the `./results` folder. If the file in `./results` folder matches the corresponding file in the `./test/expected` folder, the test passes, otherwise it fails.

To run tests locally, first execute:

```bash
cargo pgrx install
```

to build and install the latest `pg_graphql` in the Postgres instance specified by `pg_config`. This step is needed when you have made any changes in the Rust code.

Next, run all the tests by executing:

```bash
./bin/installcheck
```

You can combine the last two steps to quickly run all the tests:

```bash
$ cargo pgrx install; ./bin/installcheck
```

You can run a single test by passing its name to the `installcheck` command. For example, the following runs the test in `./test/sql/aliases.sql`.

```bash
./bin/installcheck aliases
```

When writing a new test, or editing an existing one, the file in `./result` should be inspected manually and then copied over to the `./test/expected` folder to make the test pass.

### Debugging

You can print to the output by using the `pgrx_pg_sys::submodules::elog::info!` macro in the Rust code. Lines printed with this macro will show in the .out file in the `./results` folder.

### Interactive PSQL Development

To reduce the iteration cycle, you may want to launch a psql prompt with `pg_graphql` installed to experiment

```bash
cargo pgrx run pg16
```

Try out the commands below to spin up a database with the extension installed & query a table using GraphQL. Experiment with aliasing field/table names and filtering on different columns.

```sql
graphqldb= create extension pg_graphql cascade;
CREATE EXTENSION

graphqldb= create table book(id int primary key, title text);
CREATE TABLE

graphqldb= insert into book(id, title) values (1, 'book 1');
INSERT 0 1
```

Finally, execute some graphql queries against the table.
```sql
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

## Documentation

All public API must be documented. Building documentation requires python 3.6+


### Install Dependencies

Install mkdocs, themes, and extensions.

```shell
pip install -r docs/requirements_docs.txt
```

### Serving

To serve the documentation locally run

```shell
mkdocs serve
```

and visit the docs at [http://127.0.0.1:8000/pg_graphql/](http://127.0.0.1:8000/pg_graphql/)
