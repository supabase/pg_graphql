Functions can be exposed by pg_graphql to allow running custom queries or mutations.

For example, a function to add two numbers will be available on the query type as a field:

=== "Function"

    ```sql
    create function "addNums"(a int, b int)
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

    create function "addAccount"(email text)
      returns int language sql volatile
    as $$ insert into account (email) values (email) returning id; $$;
    ```

=== "Query"

    ```graphql
    mutation {
      addAccount(email: "email@example.com")
    }
    ```

=== "Response"

    ```json
    {
      "data": {
        "addAccount": 1
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

    create function "accountById"("accountId" int)
      returns account language sql stable
    as $$ select id, email from account where id = "accountId"; $$;
    ```

=== "Query"

    ```graphql
    query {
      accountById(accountId: 1) {
          id
          email
      }
    }
    ```

=== "Response"

    ```json
    {
      "data": {
        "accountById": {
          "id": 1,
          "email": "a@example.com"
        }
      }
    }
    ```

Functions returning multiple rows of a table or view are exposed as [collections](/pg_graphql/api/#collections).

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

    create function "accountsByEmail"("emailToSearch" text)
      returns setof account language sql stable
    as $$ select id, email from account where email = "emailToSearch"; $$;
    ```

=== "Query"

    ```graphql
    query {
      accountsByEmail(emailToSearch: "a@example.com", first: 1) {
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

!!! note

    A set returning function with any of its argument names clashing with argument names of a collection (`first`, `last`, `before`, `after`, `filter`, or `orderBy`) will not be exposed.

The following functions are not supported:

* Functions that accept or return a record type.
* Overloaded functions.
* Functions with a nameless argument.
* Functions with a default argument.
* Variadic functions.
