## Computed Values

### PostgreSQL Builtin (Preferred)

PostgreSQL has a builtin method for adding [generated columns](https://www.postgresql.org/docs/14/ddl-generated-columns.html) to tables. Generated columns are reflected identically to non-generated columns. This is the recommended approach to adding computed fields when your computation meets the restrictions. Namely:

- expression must be immutable
- expression may only reference the current row

For example:
```sql
--8<-- "test/expected/extend_type_with_generated_column.out"
```


### Extending Types with Functions

For arbitrary computations that do not meet the requirements for [generated columns](https://www.postgresql.org/docs/14/ddl-generated-columns.html), a table's reflected GraphQL type can be extended by creating a function that:

- accepts a single argument of the table's tuple type

```sql
--8<-- "test/expected/extend_type_with_function.out"
```


## Computed Relationships

Computed relations can be helpful to express relationships:

- between entities that don't support foreign keys
- too complex to be expressed via a foreign key

If the relationship is simple, but involves an entity that does not support foreign keys e.g. Foreign Data Wrappers / Views, defining a comment directive is the easiest solution. See the [view doc](/pg_graphql/views) for a complete example. Note that for entities that do not support a primary key, like views, you must define one using a [comment directive](/pg_graphql/configuration/#comment-directives) to use them in a computed relationship.

Alternatively, if the relationship is complex, or you need compatibility with PostgREST, you can define a relationship using set returning functions.


### To-One

To One relationships can be defined using a function that returns `setof <entity> rows 1`

For example
```sql
create table "Person" (
    id int primary key,
    name text
);

create table "Address"(
    id int primary key,
    "isPrimary" bool not null default false,
    "personId" int references "Person"(id),
    address text
);

-- Example computed relation
create function "primaryAddress"("Person")
    returns setof "Address" rows 1
    language sql
    as
$$
    select addr
    from "Address" addr
    where $1.id = addr."personId"
          and addr."isPrimary"
    limit 1
$$;

insert into "Person"(id, name)
values (1, 'Foo Barington');

insert into "Address"(id, "isPrimary", "personId", address)
values (4, true, 1, '1 Main St.');
```

results in the GraphQL type

=== "Person"
    ```graphql
    type Person implements Node {
      """Globally Unique Record Identifier"""
      nodeId: ID!
      ...
      primaryAddress: Address
    }
    ```

and can be queried like a natively enforced relationship

=== "Query"

    ```graphql
    {
      personCollection {
        edges {
          node {
            id
            name
            primaryAddress {
              address
            }
          }
        }

      }
    }
    ```

=== "Response"

    ```json
    {
      "data": {
        "personCollection": {
          "edges": [
            {
              "node": {
                "id": 1,
                "name": "Foo Barington",
                "primaryAddress": {
                  "address": "1 Main St."
                }
              }
            }
          ]
        }
      }
    }
    ```



### To-Many

To-many relationships can be defined using a function that returns a `setof <entity>`


For example:
```sql
create table "Person" (
    id int primary key,
    name text
);

create table "Address"(
    id int primary key,
    address text
);

create table "PersonAtAddress"(
    id int primary key,
    "personId" int not null,
    "addressId" int not null
);


-- Computed relation to bypass "PersonAtAddress" table for cleaner API
create function "addresses"("Person")
    returns setof "Address"
    language sql
    as
$$
    select
        addr
    from
        "PersonAtAddress" pa
        join "Address" addr
            on pa."addressId" = "addr".id
    where
        pa."personId" = $1.id
$$;

insert into "Person"(id, name)
values (1, 'Foo Barington');

insert into "Address"(id, address)
values (4, '1 Main St.');

insert into "PersonAtAddress"(id, "personId", "addressId")
values (2, 1, 4);
```

results in the GraphQL type

=== "Person"
    ```graphql
    type Person implements Node {
      """Globally Unique Record Identifier"""
      nodeId: ID!
      ...
      addresses(
        first: Int
        last: Int
        before: Cursor
        after: Cursor
        filter: AddressFilter
        orderBy: [AddressOrderBy!]
      ): AddressConnection
    }
    ```

and can be queried like a natively enforced relationship

=== "Query"

    ```graphql
    {
      personCollection {
        edges {
          node {
            id
            name
            addresses {
              edges {
                node {
                  id
                  address
                }
              }
            }
          }
        }
      }
    }
    ```

=== "Response"

    ```json
    {
      "data": {
        "personCollection": {
          "edges": [
            {
              "node": {
                "id": 1,
                "name": "Foo Barington",
                "addresses": {
                  "edges": [
                    {
                      "node": {
                        "id": 4,
                        "address": "1 Main St."
                      }
                    }
                  ]
                }
              }
            }
          ]
        }
      }
    }
    ```
