Functions can be exposed by pg_graphql to allow running custom queries or mutations.

For example, a function to add two numbers will be available on the query type as a field:

=== "Function"

    ```sql
    create function add_nums(a int, b int)
      returns int language sql immutable
    as $$ select a + b; $$;
    ```

=== "Query"

    ```graphql
    query {
      addNums(a: 2, b: 3)
    }
    ```

=== "Response"

    ```json
    {
      "data": {
        "addNums": 5
      }
    }
    ```

Only functions marked `immutable` or `stable` are available on the query type. For a function to be available on the mutation type, it must be marked as `volatile`:

=== "Function"

    ```sql
    create table account(
      id serial primary key,
      email varchar(255) not null
    );

    create function save_email(email text)
      returns int language sql volatile
    as $$ insert into account (email) values (email) returning id; $$;
    ```

=== "Query"

    ```graphql
    mutation {
      saveEmail(email: "email@example.com")
    }
    ```

=== "Response"

    ```json
    {
      "data": {
        "saveEmail": 1
      }
    }
    ```

Built-in GraphQL scalar types `Int`, `Float`, `String`, `Boolean` and [custom scalar types](/pg_graphql/api/#custom-scalars) are supported as function arguments and return types. Function types returning a table or view are supported as well:

=== "Function"

    ```sql
    create table account(
      id serial primary key,
      email varchar(255) not null
    );

    insert into account(email)
    values
      ('a@example.com'),
      ('b@example.com');

    create function account_by_id(account_id int)
      returns account language sql stable
    as $$ select id, email from account where id = account_id; $$;
    ```

=== "Query"

    ```graphql
    query {
      returnsAccount(accountId: 1) {
          id
          email
      }
    }
    ```

=== "Response"

    ```json
    {
      "data": {
          "returnsAccount": {
            "id": 1,
            "email": "email@example.com"
          }
      }
    }
    ```

Set returning functions are exposed as [collections](/pg_graphql/api/#collections).

=== "Function"

    ```sql
    create table account(
      id serial primary key,
      email varchar(255) not null
    );

    insert into account(email)
    values
      ('a@example.com'),
      ('a@example.com'),
      ('b@example.com');

    create function accounts_by_email(email_to_search text)
      returns setof account language sql stable
    as $$ select id, email from account where email = email_to_search; $$;
    ```

=== "Query"

    ```graphql
    query {
      accountsByEmail(email_to_search: "a@example.com", first: 1) {
      edges {
            node {
              id
              email
            }
        }
      }
    }
    ```

=== "Response"

    ```json
    {
      "data": {
        "accountsByEmail": {
          "edges": [
            {
              "node": {
                "id": 1,
                "email": "a@example.com"
              }
            }
          ]
        }
      }
    }
    ```

The following functions are not supported:

* Functions that return a record type.
* Overloaded functions.
* Functions with a nameless argument.
* Variadic functions.
