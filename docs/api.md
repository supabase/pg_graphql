SQL tables are reflected into GraphQL types with columns and foreign keys represented as fields on those types.


!!! note

    By default, PostgreSQL table and column names are not inflected when reflecting GraphQL type and field names. For example, an `account_holder` table has GraphQL type name `account_holder`.

    In cases where SQL entities are `snake_case`, you'll likely want to [enable inflection](/pg_graphql/configuration/#inflection) to re-case names to match GraphQL/Javascript conventions e.g. `account_holder` -> `AccountHolder`.

    Individual table, column, and relationship names may also be [manually overridden](/pg_graphql/configuration/#tables-type) as needed.

## Type Conversion

### QueryType

The `Query` type is the entrypoint for all read access into the graph.

#### Collections

Each table has top level entry in the `Query` type for selecting records from that table. Collections return a [connection type](#connection-types) and can be [paginated](#pagination), [filtered](#filtering), and [sorted](#sorting) using the available arguments.

=== "QueryType"

    ```graphql
    """The root type for querying data"""
    type Query {
      """A pagable collection of type `Blog`"""
      blogCollection(
        """Query the first `n` records in the collection"""
        first: Int

        """Query the last `n` records in the collection"""
        last: Int

        """Query values in the collection before the provided cursor"""
        before: Cursor

        """Query values in the collection after the provided cursor"""
        after: Cursor

        """Filters to apply to the results set when querying from the collection"""
        filter: BlogFilter

        """Sort order to apply to the collection"""
        orderBy: [BlogOrderBy!]
      ): BlogConnection
    }
    ```

=== "BlogConnection"

    ```graphql
    type BlogConnection {
      edges: [BlogEdge!]!
      pageInfo: PageInfo!
    }
    ```

=== "BlogEdge"

    ```graphql
    type BlogEdge {
      cursor: String!
      node: Blog
    }
    ```

=== "Blog"

    ```graphql
    type Blog {
      id: Int!
      name: String!
      description: String
      createdAt: Datetime!
      updatedAt: Datetime!
    }

    ```

=== "BlogOrderBy"

    ```graphql
    input BlogOrderBy {
      id: OrderByDirection
      name: OrderByDirection
      description: OrderByDirection
      createdAt: OrderByDirection
      updatedAt: OrderByDirection
    }
    ```

=== "BlogFilter"

    ```graphql
    input BlogFilter {
      id: IntFilter
      name: StringFilter
      description: StringFilter
      createdAt: DatetimeFilter
      updatedAt: DatetimeFilter
    }
    ```

=== "SQL"

    ```sql
    create table blog(
      id serial primary key,
      name varchar(255) not null,
      description varchar(255),
      "createdAt" timestamp not null,
      "updatedAt" timestamp not null
    );
    ```




##### Pagination

Paginating forwards and backwards through collections is handled using the `first`, `last`, `before`, and `after` parameters and follows the [relay spec](https://relay.dev/graphql/connections.htm#).

=== "QueryType"

    ```graphql
    type Query {

      blogCollection(
        """Query the first `n` records in the collection"""
        first: Int

        """Query the last `n` records in the collection"""
        last: Int

        """Query values in the collection before the provided cursor"""
        before: Cursor

        """Query values in the collection after the provided cursor"""
        after: Cursor    filter: BlogFilter

        ...truncated...
      ): BlogConnection
    }
    ```



Metadata relating to the current page of a result set is available on the `pageInfo` field of the connection type returned from a collection.


=== "GraphQL"
    ```graphql
    type BlogConnection {
      edges: [BlogEdge!]!
      pageInfo: PageInfo!
    }
    ```

    ```graphql
    type PageInfo {
      endCursor: String
      hasNextPage: Boolean!
      hasPreviousPage: Boolean!
      startCursor: String
    }
    ```

=== "SQL"

    ```sql
    create table blog(
      id serial primary key,
      name varchar(255) not null,
      description varchar(255),
      "createdAt" timestamp not null,
      "updatedAt" timestamp not null
    );
    ```

To paginate forwards in the collection, use the `first` and `after` aguments. To retrive the first page, the `after` argument should be null.

```graphql
{
  blogCollection(
    first: 2,
    after: null
  ) {
    pageInfo {
      startCursor
      endCursor
      hasPreviousPage
      hasNextPage
    }
    edges {
      cursor
      node {
        id
      }
    }
  }
}
```

To retrieve the next page, provide the cursor value from `data.blogCollection.pageInfo.endCursor` in the result set to the `after` argument of a second query.

i.e.

```graphql
{
  blogCollection(
    first: 2,
    after: "WzJd"
  ) ...truncated...
```

=== "Page 1"

    ```json
    {
      "data": {
        "blogCollection": {
          "edges": [
            {
              "node": {
                "id": 1
              },
              "cursor": "WzFd"
            },
            {
              "node": {
                "id": 2
              },
              "cursor": "WzJd"
            }
          ],
          "pageInfo": {
            "startCursor": "WzFd",
            "endCursor": "WzJd",
            "hasNextPage": true,
            "hasPreviousPage": false
          }
        }
      }
    }
    ```

=== "Page 2"

    ```json
    {
      "data": {
        "blogCollection": {
          "edges": [
            {
              "node": {
                "id": 3
              },
              "cursor": "WzNd"
            },
            {
              "node": {
                "id": 4
              },
              "cursor": "WzRd"
            }
          ],
          "pageInfo": {
            "startCursor": "WzNd",
            "endCursor": "WzRd",
            "hasNextPage": false,
            "hasPreviousPage": true
          }
        }
      }
    }
    ```

once the collection has been fully enumerated, `hasNextPage` returns false.


To paginate backwards through a collection, repeat the process substituting the values from `first` and `after` with `last` and `before`.

!!! warning
    Do not use cursors as unique identifiers.
    Cursors are not stable across versions of pg_graphql and should only be persisted within a single user session.


##### Filtering

To filter the result set, use the `filter` argument.

=== "QueryType"

    ```graphql
    type Query {
      blogCollection(
        filter: BlogFilter
        ...truncated...
      ): BlogConnection
    }
    ```

=== "SQL"

    ```sql
    create table blog(
      id serial primary key,
      name varchar(255) not null,
      description varchar(255),
      "createdAt" timestamp not null,
      "updatedAt" timestamp not null
    );
    ```

Where the `<Table>Filter` type enumerates filterable fields and their associated `<Type>Filter`.


=== "BlogFilter"

    ```graphql
    input BlogFilter {
      id: IntFilter
      name: StringFilter
      description: StringFilter
      createdAt: DatetimeFilter
      updatedAt: DatetimeFilter
    }
    ```

=== "IntFilter"

    ```graphql
    """
    Boolean expression comparing fields on type "Int"
    """
    input IntFilter {
      eq: Int
      gt: Int
      gte: Int
      lt: Int
      lte: Int
      neq: Int
    }
    ```

=== "StringFilter"

    ```graphql
    """
    Boolean expression comparing fields on type "String"
    """
    input StringFilter {
      eq: String
      gt: String
      gte: String
      lt: String
      lte: String
      neq: String
    }
    ```


The following list shows the operators that may be available on `<Type>Filter` types.


| Operator    | Description              |
| ----------- | ------------------------ |
| eq          | Equal To                 |
| neq         | Not Equal To             |
| gt          | Greater Than             |
| gte         | Greater Than Or Equal To |
| lt          | Less Than                |
| lte         | Less Than Or Equal To    |

Not all operators are avaiable on every `<Type>Filter` type. For example, `UUIDFilter` only supports `eq` and `neq` because `UUID`s are not ordered.


Example usage:


=== "Query"
    ```graphql
    {
      blogCollection(
        filter: {id: {lt: 3}},
      ) {
        edges {
          cursor
          node {
            id
          }
        }
      }
    }
    ```

=== "Result"

    ```json
    {
      "data": {
        "blogCollection": {
          "edges": [
            {
              "node": {
                "id": 1
              },
              "cursor": "WzFd"
            },
            {
              "node": {
                "id": 2
              },
              "cursor": "WzJd"
            }
          ]
        }
      }
    }
    ```

When multiple filters are provided to the `filter` argument, all conditions must be met for a record to be returned. In other words, multiple filters are composed with `AND` boolean logic.

We expect to expand support to user defined `AND` and `OR` composition in a future release.


##### Ordering

The default order of results is set by the underlying table's primary key. The default order can be overridden by passing an array of `<Table>OrderBy` to the collection's `orderBy` argument.

=== "QueryType"

    ```graphql
    type Query {

      blogCollection(

        """Sort order to apply to the collection"""
        orderBy: [BlogOrderBy!]

        ...truncated...

      ): BlogConnection
    }
    ```





#### Connection Types

Connection types are the primary interface to returning records from a collection.

Connections wrap a result set with some additional metadata.


=== "GraphQL"
    ```graphql
    type BlogConnection {

      # Count of all records matching the *filter* criteria
      totalCount: Int!

      # Pagination metadata
      pageInfo: PageInfo!

      # Result set
      edges: [BlogEdge!]!
    }

    type PageInfo {

      # unique identifier of the first record within the page
      startCursor: String

      # unique identifier of the last record within the page
      endCursor: String

      # is another page of content available
      hasNextPage: Boolean!

      # is another page of content available
      hasPreviousPage: Boolean!
    }
    ```

=== "SQL"

    ```sql
    create table blog(
        id serial primary key,
        name varchar(255) not null,
        description varchar(255),
        created_at timestamp not null,
        updated_at timestamp not null
    );
    ```

!!! note

    The `totalCount` field is disabled by default because it can be expensive on larget tables. To enable it use a [comment directive](configuration.md#totalcount)



### MutationType

#### Insert

#### Update

#### Delete
