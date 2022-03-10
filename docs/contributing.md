pg_graphql is OSS. PR and issues are welcome.


## Development

[Nix](https://nixos.org/download.html) is required to set up the environment.

### Testing

Tests are located in `./test/sql` with expected output in `./test/expected`

To run tests locally, execute:

```bash
# might take a few minutes downloading dependencies on the first run
$ nix-shell --run "pg_14_graphql make installcheck"
```


### Interactive PSQL Development

To reduce the iteration cycle, you may want to launch a psql prompt with `pg_graphql` installed to experiment

```bash
nix-shell --run "pg_14_graphql psql"
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
