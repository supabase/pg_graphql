Functions can be exposed by pg_graphql to allow running custom queries or mutations.

## Query vs Mutation

For example, a function to add two numbers will be available on the query type as a field:

=== "Function"

    ```sql
    create function "addNums"(a int, b int)
      returns int
      immutable
      language sql
    as $$ select a + b; $$;
    ```

=== "QueryType"

    ```graphql
    type Query {
      addNums(a: Int, b: Int): Int
    }
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

Functions marked `immutable` or `stable` are available on the query type. Functions marked with the default `volatile` category are available on the mutation type:

=== "Function"

    ```sql
    create table account(
      id serial primary key,
      email varchar(255) not null
    );

    create function "addAccount"(email text)
      returns int
      volatile
      language sql
    as $$ insert into account (email) values (email) returning id; $$;
    ```

=== "MutationType"

    ```graphql
    type Mutation {
      addAccount(email: String): Int
    }
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


## Supported Return Types


Built-in GraphQL scalar types `Int`, `Float`, `String`, `Boolean` and [custom scalar types](api.md#custom-scalars) are supported as function arguments and return types. Function types returning a table or view are supported as well. Such functions implement the [Node interface](api.md#node):

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
      returns account
      stable
      language sql
    as $$ select id, email from account where id = "accountId"; $$;
    ```

=== "MutationType"

    ```graphql
    type Mutation {
      addAccount(email: String): Int
    }
    ```

=== "Query"

    ```graphql
    query {
      accountById(accountId: 1) {
          id
          email
          nodeId
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
          "nodeId": "WyJwdWJsaWMiLCAiYWNjb3VudCIsIDFd"
        }
      }
    }
    ```

Since Postgres considers a row/composite type containing only null values to be null, the result can be a little surprising in this case. Instead of an object with all columns null, the top-level field is null:

=== "Function"

    ```sql
    create table account(
        id int,
        email varchar(255),
        name text null
    );

    insert into account(id, email, name)
    values
        (1, 'aardvark@x.com', 'aardvark'),
        (2, 'bat@x.com', null),
        (null, null, null);

    create function returns_account_with_all_null_columns()
        returns account language sql stable
    as $$ select id, email, name from account where id is null; $$;
    ```

=== "Query"

    ```graphql
    query {
      returnsAccountWithAllNullColumns {
        id
        email
        name
        __typename
      }
    }
    ```

=== "Response"

    ```json
    {
      "data": {
        "returnsAccountWithAllNullColumns": null
      }
    }
    ```

Functions returning multiple rows of a table or view are exposed as [collections](api.md#collections).

=== "Function"

    ```sql
    create table "Account"(
      id serial primary key,
      email varchar(255) not null
    );

    insert into "Account"(email)
    values
      ('a@example.com'),
      ('a@example.com'),
      ('b@example.com');

    create function "accountsByEmail"("emailToSearch" text)
      returns setof "Account"
      stable
      language sql
    as $$ select id, email from "Account" where email = "emailToSearch"; $$;
    ```

=== "QueryType"

    ```graphql
    type Query {
      accountsByEmail(
        emailToSearch: String

        """Query the first `n` records in the collection"""
        first: Int

        """Query the last `n` records in the collection"""
        last: Int

        """Query values in the collection before the provided cursor"""
        before: Cursor

        """Query values in the collection after the provided cursor"""
        after: Cursor

        """Filters to apply to the results set when querying from the collection"""
        filter: AccountFilter

        """Sort order to apply to the collection"""
        orderBy: [AccountOrderBy!]
      ): AccountConnection
    }
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

Functions accepting or returning arrays of non-composite types are also supported. In the following example, the `ids` array is used to filter rows from the `Account` table:

=== "Function"

    ```sql
    create table "Account"(
      id serial primary key,
      email varchar(255) not null
    );

    insert into "Account"(email)
    values
      ('a@example.com'),
      ('b@example.com'),
      ('c@example.com');

    create function "accountsByIds"("ids" int[])
      returns setof "Account"
      stable
      language sql
    as $$ select id, email from "Account" where id = any(ids); $$;
    ```

=== "QueryType"

    ```graphql
    type Query {
      accountsByIds(
        ids: Int[]!

        """Query the first `n` records in the collection"""
        first: Int

        """Query the last `n` records in the collection"""
        last: Int

        """Query values in the collection before the provided cursor"""
        before: Cursor

        """Query values in the collection after the provided cursor"""
        after: Cursor

        """Filters to apply to the results set when querying from the collection"""
        filter: AccountFilter

        """Sort order to apply to the collection"""
        orderBy: [AccountOrderBy!]
      ): AccountConnection
    }
    ```

=== "Query"

    ```graphql
    query {
      accountsByIds(ids: [1, 2]) {
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
        "accountsByIds": {
          "edges": [
            {
              "node": {
                "id": 1,
                "email": "a@example.com"
              }
            },
            {
              "node": {
                "id": 2,
                "email": "b@example.com"
              }
            }
          ]
        }
      }
    }
    ```

## Default Arguments

Functions with default arguments can have their default arguments omitted.

=== "Function"

    ```sql
    create function "addNums"(a int default 1, b int default 2)
      returns int
      immutable
      language sql
    as $$ select a + b; $$;
    ```

=== "QueryType"

    ```graphql
    type Query {
      addNums(a: Int, b: Int): Int
    }
    ```


=== "Query"

    ```graphql
    query {
      addNums(b: 20)
    }
    ```

=== "Response"

    ```json
    {
      "data": {
        "addNums": 21
      }
    }
    ```

## Limitations

The following features are not yet supported. Any function using these features is not exposed in the API:

* Functions that return a record type
* Functions that accept a table's tuple type
* Overloaded functions
* Functions with a nameless argument
* Functions returning void
* Variadic functions
* Functions that accept or return an array of composite type
