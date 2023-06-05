
In our API, each SQL table is reflected as a set of GraphQL types. At a high level, tables become types and columns/foreign keys become fields on those types.


By default, PostgreSQL table and column names are not inflected when reflecting GraphQL  names. For example, an `account_holder` table has GraphQL type name `account_holder`. In cases where SQL entities are named using `snake_case`, [enable inflection](/pg_graphql/configuration/#inflection) to match GraphQL/Javascript conventions e.g. `account_holder` -> `AccountHolder`.

Individual table, column, and relationship names may also be [manually overridden](/pg_graphql/configuration/#tables-type).


## QueryType

The `Query` type is the entrypoint for all read access into the graph.

### Node

The `node` interface allows for retrieving records that are uniquely identifiable by a globally unique `nodeId: ID!` field. For more information about nodeId, see [nodeId](#nodeid).

**SQL Setup**
```sql
create table "Blog"(
  id serial primary key,
  name varchar(255) not null,
  description varchar(255),
  "createdAt" timestamp not null,
  "updatedAt" timestamp not null
);
```

**GraphQL Types**
=== "QueryType"

    ```graphql
    """The root type for querying data"""
    type Query {

      """Retrieve a record by its `ID`"""
      node(nodeId: ID!): Node

    }
    ```

To query the `node` interface effectively, use [inline fragments](https://graphql.org/learn/queries/#inline-fragments) to specify which fields to return for each type.

**Example**
=== "Query"

    ```graphql
    {
      node(
        nodeId: "WyJwdWJsaWMiLCAiYmxvZyIsIDFd"
      ) {
        nodeId
        # Inline fragment for `Blog` type
        ... on Blog {
          name
          description
        }
      }
    }
    ```

=== "Response"

    ```json
    {
      "data": {
        "node": {
          "name": "Some Blog",
          "nodeId": "WyJwdWJsaWMiLCAiYmxvZyIsIDFd",
          "description": "Description of Some Blog"
        }
      }
    }
    ```


### Collections

Each table has top level entry in the `Query` type for selecting records from that table. Collections return a connection type and can be [paginated](#pagination), [filtered](#filtering), and [sorted](#ordering) using the available arguments.

**SQL Setup**

```sql
create table "Blog"(
  id serial primary key,
  name varchar(255) not null,
  description varchar(255),
  "createdAt" timestamp not null,
  "updatedAt" timestamp not null
);
```


**GraphQL Types**
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


Connection types are the primary interface to returning records from a collection.

Connections wrap a result set with some additional metadata.


=== "BlogConnection"

    ```graphql
    type BlogConnection {

      # Count of all records matching the *filter* criteria
      totalCount: Int!

      # Pagination metadata
      pageInfo: PageInfo!

      # Result set
      edges: [BlogEdge!]!

    }
    ```

=== "BlogEdge"

    ```graphql
    type BlogEdge {

      # Unique identifier of the record within the query
      cursor: String!

      # Contents of a record/row in the results set
      node: Blog

    }
    ```

=== "PageInfo"

    ```graphql
    type PageInfo {

      # unique identifier of the first record within the query
      startCursor: String

      # unique identifier of the last record within the query
      endCursor: String

      # is another page of content available
      hasNextPage: Boolean!

      # is another page of content available
      hasPreviousPage: Boolean!
    }
    ```


=== "Blog"

    ```graphql
    # A record from the `blog` table
    type Blog {

      # globally unique identifier
      nodeId: ID!

      # Value from `id` column
      id: Int!

      # Value from `name` column
      name: String!

      # Value from `description` column
      description: String

      # Value from `createdAt` column
      createdAt: Datetime!

      # Value from `updatedAt` column
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
      nodeId: IDFilter
      id: IntFilter
      name: StringFilter
      description: StringFilter
      createdAt: DatetimeFilter
      updatedAt: DatetimeFilter
    }
    ```

!!! note

    The `totalCount` field is disabled by default because it can be expensive on large tables. To enable it use a [comment directive](configuration.md#totalcount)




#### Pagination

Paginating forwards and backwards through collections is handled using the `first`, `last`, `before`, and `after` parameters, following the [relay spec](https://relay.dev/graphql/connections.htm#).

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
        after: Cursor

        ...truncated...

      ): BlogConnection
    }
    ```



Metadata relating to the current page of a result set is available on the `pageInfo` field of the connection type returned from a collection.

=== "PageInfo"
    ```graphql
    type PageInfo {

      # unique identifier of the first record within the query
      startCursor: String

      # unique identifier of the last record within the query
      endCursor: String

      # is another page of content available
      hasNextPage: Boolean!

      # is another page of content available
      hasPreviousPage: Boolean!
    }
    ```

=== "BlogConnection"

    ```graphql
    type BlogConnection {

      # Pagination metadata
      pageInfo: PageInfo!

      # Result set
      edges: [BlogEdge!]!

    }
    ```

To paginate forward in the collection, use the `first` and `after` aguments. To retrive the first page, the `after` argument should be null or absent.

**Example**

=== "Query"

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

To retrieve the next page, provide the cursor value from `data.blogCollection.pageInfo.endCursor` to the `after` argument of another query.

=== "Query"

    ```graphql
    {
      blogCollection(
        first: 2,
        after: "WzJd"
      ) {
      ...truncated...
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

once the collection has been fully enumerated, `data.blogConnection.pageInfo.hasNextPage` returns false.


To paginate backwards through a collection, repeat the process substituting `first` -> `last`, `after` -> `before`, `hasNextPage` -> `hasPreviousPage`


#### Filtering

To filter the result set, use the `filter` argument.

=== "QueryType"

    ```graphql
    type Query {

      blogCollection(

        """Filters to apply to the results set when querying from the collection"""
        filter: BlogFilter

        ...truncated...

      ): BlogConnection
    }
    ```

Where the `<Table>Filter` type enumerates filterable fields and their associated `<Type>Filter`.


=== "BlogFilter"

    ```graphql
    input BlogFilter {
      nodeId: IDFilter
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
      in: [Int!]
      lt: Int
      lte: Int
      neq: Int
      is: FilterIs
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
      in: [String!]
      lt: String
      lte: String
      neq: String
      is: FilterIs
      startsWith: String
      like: String
      ilike: String
      regex: String
      iregex: String
    }
    ```

=== "FilterIs"

    ```graphql
    enum FilterIs {
      NULL
      NOT_NULL
    }
    ```

The following list shows the operators that may be available on `<Type>Filter` types.


| Operator    | Description                                      |
| ----------- | -------------------------------------------------|
| eq          | Equal To                                         |
| neq         | Not Equal To                                     |
| gt          | Greater Than                                     |
| gte         | Greater Than Or Equal To                         |
| in          | Contained by Value List                          |
| nin         | Not Contained by Value List                      |
| lt          | Less Than                                        |
| lte         | Less Than Or Equal To                            |
| is          | Null or Not Null                                 |
| startsWith  | Starts with prefix                               |
| like        | Pattern Match. '%' as wildcard                   |
| ilike       | Pattern Match. '%' as wildcard. Case Insensitive |
| regex       | POSIX Regular Expression Match                   |
| iregex      | POSIX Regular Expression Match. Case Insensitive |

Not all operators are available on every `<Type>Filter` type. For example, `UUIDFilter` only supports `eq` and `neq` because `UUID`s are not ordered.


**Example**

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


#### Ordering

The default order of results is defined by the underlying table's primary key column in ascending order. That default can be overridden by passing an array of `<Table>OrderBy` to the collection's `orderBy` argument.

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


=== "OrderByDirection"

    ```graphql
    """Defines a per-field sorting order"""
    enum OrderByDirection {
      """Ascending order, nulls first"""
      AscNullsFirst

      """Ascending order, nulls last"""
      AscNullsLast

      """Descending order, nulls first"""
      DescNullsFirst

      """Descending order, nulls last"""
      DescNullsLast
    }
    ```


**Example**

=== "Query"

    ```graphql
    {
      blogCollection(
        orderBy: [{id: DescNullsLast}]
      ) {
        edges {
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
                "id": 4
              }
            },
            {
              "node": {
                "id": 3
              }
            },
            {
              "node": {
                "id": 2
              }
            },
            {
              "node": {
                "id": 1
              }
            }
          ]
        }
      }
    }
    ```

Note, only one key value pair may be provided to each element of the input array. For example, `[{name: AscNullsLast}, {id: AscNullFirst}]` is valid. Passing multiple key value pairs in a single element of the input array e.g. `[{name: AscNullsLast, id: AscNullFirst}]`, is invalid.

## MutationType

The `Mutation` type is the entrypoint for mutations/edits.

Each table has top level entry in the `Mutation` type for [inserting](#insert) `insertInto<Table>Collection`, [updating](#update) `update<Table>Collection` and [deleting](#delete) `deleteFrom<Table>Collection`.

**SQL Setup**
```sql
create table "Blog"(
  id serial primary key,
  name varchar(255) not null,
  description varchar(255),
  "createdAt" timestamp not null default now(),
  "updatedAt" timestamp
);
```

=== "MutationType"

    ```graphql
    """The root type for creating and mutating data"""
    type Mutation {

      """Adds one or more `BlogInsertResponse` records to the collection"""
      insertIntoBlogCollection(

        """Records to add to the Blog collection"""
        objects: [BlogInsertInput!]!

      ): BlogInsertResponse

      """Updates zero or more records in the collection"""
      updateBlogCollection(
        """
        Fields that are set will be updated for all records matching the `filter`
        """
        set: BlogUpdateInput!

        """Restricts the mutation's impact to records matching the critera"""
        filter: BlogFilter

        """
        The maximum number of records in the collection permitted to be affected
        """
        atMost: Int! = 1

      ): BlogUpdateResponse!

      """Deletes zero or more records from the collection"""
      deleteFromBlogCollection(
        """Restricts the mutation's impact to records matching the critera"""
        filter: BlogFilter

        """
        The maximum number of records in the collection permitted to be affected
        """
        atMost: Int! = 1

      ): BlogDeleteResponse!

    }
    ```

### Insert

To add records to a collection, use the `insertInto<Table>Collection` field on the `Mutation` type.

**SQL Setup**
```sql
create table "Blog"(
  id serial primary key,
  name varchar(255) not null,
  description varchar(255),
  "createdAt" timestamp not null default now(),
  "updatedAt" timestamp
);
```

**GraphQL Types**
=== "MutationType"

    ```graphql
    """The root type for creating and mutating data"""
    type Mutation {

      """Adds one or more `BlogInsertResponse` records to the collection"""
      insertIntoBlogCollection(

        """Records to add to the Blog collection"""
        objects: [BlogInsertInput!]!

      ): BlogInsertResponse

    }
    ```

=== "BlogInsertInput"

    ```graphql
    input BlogInsertInput {
      name: String
      description: String
      createdAt: Datetime
      updatedAt: Datetime
    }
    ```

=== "BlogInsertResponse"

    ```graphql
    type BlogInsertResponse {
      """Count of the records impacted by the mutation"""
      affectedCount: Int!

      """Array of records impacted by the mutation"""
      records: [Blog!]!
    }
    ```

Where elements in the `objects` array are inserted into the underlying table.


**Example**

=== "Query"
    ```graphql
    mutation {
      insertIntoBlogCollection(
        objects: [
          {name: "foo"},
          {name: "bar"},
        ]
      ) {
        affectedCount
        records {
          id
          name
        }
      }
    }
    ```

=== "Result"

    ```json
    {
      "data": {
        "insertIntoBlogCollection": {
          "records": [
            {
              "id": 1,
              "name": "foo"
            },
            {
              "id": 2,
              "name": "bar"
            }
          ],
          "affectedCount": 2
        }
      }
    }
    ```

### Update


To update records in a collection, use the `update<Table>Collection` field on the `Mutation` type.

**SQL Setup**
```sql
create table "Blog"(
  id serial primary key,
  name varchar(255) not null,
  description varchar(255),
  "createdAt" timestamp not null default now(),
  "updatedAt" timestamp
);
```

**GraphQL Types**
=== "MutationType"

    ```graphql
    """The root type for creating and mutating data"""
    type Mutation {

      """Updates zero or more records in the collection"""
      updateBlogCollection(
        """
        Fields that are set will be updated for all records matching the `filter`
        """
        set: BlogUpdateInput!

        """Restricts the mutation's impact to records matching the critera"""
        filter: BlogFilter

        """
        The maximum number of records in the collection permitted to be affected
        """
        atMost: Int! = 1

      ): BlogUpdateResponse!

    }
    ```

=== "BlogUpdateInput"

    ```graphql
    input BlogUpdateInput {
      name: String
      description: String
      createdAt: Datetime
      updatedAt: Datetime
    }
    ```

=== "BlogUpdateResponse"

    ```graphql
    type BlogUpdateResponse {

      """Count of the records impacted by the mutation"""
      affectedCount: Int!

      """Array of records impacted by the mutation"""
      records: [Blog!]!

    }
    ```


Where the `set` argument is a key value pair describing the values to update, `filter` controls which records should be updated, and `atMost` restricts the maximum number of records that may be impacted. If the number of records impacted by the mutation exceeds the `atMost` parameter the operation will return an error.

**Example**

=== "Query"
    ```graphql
    mutation {
      updateBlogCollection(
        set: {name: "baz"}
        filter: {id: {eq: 1}}
      ) {
        affectedCount
        records {
          id
          name
        }
      }
    }
    ```

=== "Result"

    ```json
    {
      "data": {
        "updateBlogCollection": {
          "records": [
            {
              "id": 1,
              "name": "baz"
            }
          ],
          "affectedCount": 1
        }
      }
    }
    ```



### Delete

To remove records from a collection, use the `deleteFrom<Table>Collection` field on the `Mutation` type.


**SQL Setup**
```sql
create table "Blog"(
  id serial primary key,
  name varchar(255) not null,
  description varchar(255),
  "createdAt" timestamp not null default now(),
  "updatedAt" timestamp
);
```

**GraphQL Types**
=== "MutationType"

    ```graphql
    """The root type for creating and mutating data"""
    type Mutation {

      """Deletes zero or more records from the collection"""
      deleteFromBlogCollection(
        """Restricts the mutation's impact to records matching the critera"""
        filter: BlogFilter

        """
        The maximum number of records in the collection permitted to be affected
        """
        atMost: Int! = 1

      ): BlogDeleteResponse!

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

=== "BlogDeleteResponse"

    ```graphql
    type BlogDeleteResponse {
      """Count of the records impacted by the mutation"""
      affectedCount: Int!

      """Array of records impacted by the mutation"""
      records: [Blog!]!
    }
    ```

Where `filter` controls which records should be deleted and `atMost` restricts the maximum number of records that may be deleted. If the number of records impacted by the mutation exceeds the `atMost` parameter the operation will return an error.

**Example**
=== "Query"

    ```graphql
    mutation {
      deleteFromBlogCollection(
        filter: {id: {eq: 1}}
      ) {
        affectedCount
        records {
          id
          name
        }
      }
    }
    ```

=== "Result"

    ```json
    {
      "data": {
        "deleteFromBlogCollection": {
          "records": [
            {
              "id": 1,
              "name": "baz"
            }
          ],
          "affectedCount": 1
        }
      }
    }
    ```


## Concepts

### nodeId

The base GraphQL type for every table with a primary key is automatically assigned a `nodeId: ID!` field. That value, can be passed to the [node](#node) entrypoint of the `Query` type to retrieve its other fields. `nodeId` may also be used as a caching key.

!!!note "relay support"
    By default relay expects the `ID` field for types to have the name `id`. pg_graphql uses `nodeId` by default to avoid conflicting with user defined `id` columns. You can configure relay to work with pg_graphql's `nodeId` field with relay's `nodeInterfaceIdField` option. More info available [here](https://github.com/facebook/relay/tree/main/packages/relay-compiler#supported-compiler-configuration-options).



**SQL Setup**
```sql
create table "Blog"(
    id serial primary key,
    name varchar(255) not null
);
```

**GraphQL Types**
=== "Blog"

    ```sql
    type Blog {
      nodeId: ID! # this field
      id: Int!
      name: String!
    }
    ```


### Relationships

Relationships between collections in the Graph are derived from foreign keys.

#### One-to-Many

A foreign key on table A referencing table B defines a one-to-many relationship from table A to table B.

**SQL Setup**
```sql
create table "Blog"(
    id serial primary key,
    name varchar(255) not null
);

create table "BlogPost"(
    id serial primary key,
    "blogId" integer not null references "Blog"(id),
    title varchar(255) not null,
    body varchar(10000)
);
```

**GraphQL Types**
=== "Blog"

    ```sql
    type Blog {

      # globally unique identifier
      nodeId: ID!

      id: Int!
      name: String!
      description: String

      blogPostCollection(
        """Query the first `n` records in the collection"""
        first: Int

        """Query the last `n` records in the collection"""
        last: Int

        """Query values in the collection before the provided cursor"""
        before: Cursor

        """Query values in the collection after the provided cursor"""
        after: Cursor

        """Filters to apply to the results set when querying from the collection"""
        filter: BlogPostFilter

        """Sort order to apply to the collection"""
        orderBy: [BlogPostOrderBy!]
      ): BlogPostConnection

    }
    ```


Where `blogPostCollection` exposes the full `Query` interface to `BlogPost`s.


**Example**
=== "Query"

    ```graphql
    {
      blogCollection {
        edges {
          node {
            name
            blogPostCollection {
              edges {
                node {
                  id
                  title
                }
              }
            }
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
                "name": "pg_graphql blog",
                "blogPostCollection": {
                  "edges": [
                    {
                      "node": {
                        "id": 2,
                        "title": "fIr3t p0sT"
                      }
                    },
                    {
                      "node": {
                        "id": 3,
                        "title": "graphql with postgres"
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

#### Many-to-One

A foreign key on table A referencing table B defines a many-to-one relationship from table B to table A.

**SQL Setup**
```sql
create table "Blog"(
    id serial primary key,
    name varchar(255) not null
);

create table "BlogPost"(
    id serial primary key,
    "blogId" integer not null references "Blog"(id),
    title varchar(255) not null,
    body varchar(10000)
);
```

**GraphQL Types**
=== "BlogPost"

    ```sql
    type BlogPost {
      nodeId: ID!
      id: Int!
      blogId: Int!
      title: String!
      body: String

      blog: Blog
    }
    ```

Where `blog` exposes the `Blog` record associated with the `BlogPost`.

=== "Query"

    ```graphql
    {
      blogPostCollection {
        edges {
          node {
            title
            blog {
              name
            }
          }
        }
      }
    }
    ```

=== "Result"

    ```json
    {
      "data": {
        "blogPostCollection": {
          "edges": [
            {
              "node": {
                "blog": {
                  "name": "pg_graphql blog"
                },
                "title": "fIr3t p0sT"
              }
            },
            {
              "node": {
                "blog": {
                  "name": "pg_graphql blog"
                },
                "title": "graphql with postgres"
              }
            }
          ]
        }
      }
    }
    ```

#### One-to-One

A one-to-one relationship is defined by a foreign key on table A referencing table B where the columns making up the foreign key on table A are unique.

**SQL Setup**
```sql
create table "EmailAddress"(
    id serial primary key,
    address text unique not null
);

create table "Employee"(
    id serial primary key,
    name text not null,
    email_address_id int unique references "EmailAddress"(id)
);
```

**GraphQL Types**
=== "Employee"

    ```sql
    type Employee {
      nodeId: ID!
      id: Int!
      name: String!
      emailAddressId: Int
      emailAddress: EmailAddress
    }
    ```

=== "EmployeeAddress"
    ```sql
    type EmailAddress {
      nodeId: ID!
      id: Int!
      address: String!
      employee: Employee
    }
    ```

**Example**
=== "Query"

    ```graphql
    {
      employeeCollection {
        edges {
          node {
            name
            emailAddress {
              address
              employee {
                name
              }
            }
          }
        }
      }
    }
    ```

=== "Result"

    ```json
    {
      "data": {
        "employeeCollection": {
          "edges": [
            {
              "node": {
                "name": "Foo Barington",
                "emailAddress": {
                  "address": "foo@bar.com",
                  "employee": {
                    "name": "Foo Barington"
                  }
                }
              }
            }
          ]
        }
      }
    }
    ```

## Custom Scalars

Due to differences among the types supported by PostgreSQL, JSON, and GraphQL, `pg_graphql` adds several new Scalar types to handle PostgreSQL builtins that require special handling.

### JSON

`pg_graphql` serializes `json` and `jsonb` data types as `String` under the custom scalar name `JSON`.

```graphql
scalar JSON
```

**Example**

Given the setup

=== "SQL"
    ```sql
    create table "User"(
        id bigserial primary key,
        config jsonb
    );

    insert into "User"(config)
    values (jsonb_build_object('palette', 'dark-mode'));
    ```

=== "GraphQL"
    ```sql
    type User {
      nodeId: ID!
      id: BigInt!
      config: JSON
    }
    ```

The query


```graphql
{
  userCollection {
    edges {
      node {
        config
      }
    }
  }
}
```

The returns the following data. Note that `config` is serialized as a string

```json
{
  "data": {
    "userCollection": {
      "edges": [
        {
          "node": {
            "config": "{\"palette\": \"dark-mode\"}"
          }
        }
      ]
    }
  }
}
```

Use serialized JSON strings when updating or inserting `JSON` fields via the GraphQL API.

JSON does not currently support filtering.

### BigInt

PostgreSQL `bigint` and `bigserial` types are 64 bit integers. In contrast, JSON supports 32 bit integers.

Since PostgreSQL `bigint` values may be outside the min/max range allowed by JSON, they are represented in the GraphQL schema as `BigInt`s and values are serialized as strings.

```graphql
scalar BigInt

input BigIntFilter {
  eq: BigInt
  gt: BigInt
  gte: BigInt
  in: [BigInt!]
  lt: BigInt
  lte: BigInt
  neq: BigInt
  is: FilterIs
}
```

**Example**

Given the setup

=== "SQL"
    ```sql
    create table "Person"(
        id bigserial primary key,
        name text
    );

    insert into "Person"(name)
    values ('J. Bazworth');
    ```

=== "GraphQL"
    ```sql
    type Person {
      nodeId: ID!
      id: BigInt!
      name: String
    }
    ```

The query


```graphql
{
  personCollection {
    edges {
      node {
        id
        name
      }
    }
  }
}
```

The returns the following data. Note that `id` is serialized as a string

```json
{
  "data": {
    "personCollection": {
      "edges": [
        {
          "node": {
            "id": "1",
            "name": "Foo Barington",
          }
        }
      ]
    }
  }
}
```

### BigFloat

PostgreSQL's `numeric` type supports arbitrary precision floating point values. JSON's `float` is limited to 64-bit precision.

Since a PostgreSQL `numeric` may require more precision than can be handled by JSON, `numeric` types are represented in the GraphQL schema as `BigFloat` and values are serialized as strings.

```graphql
scalar BigFloat

input BigFloatFilter {
  eq: BigFloat
  gt: BigFloat
  gte: BigFloat
  in: [BigFloat!]
  lt: BigFloat
  lte: BigFloat
  neq: BigFloat
  is: FilterIs
}
```

**Example**

Given the SQL setup

```sql
create table "GeneralLedger"(
    id serial primary key,
    amount numeric(10,2)
);

insert into "GeneralLedger"(amount)
values (22.15);
```

The query

```graphql
{
  generalLedgerCollection {
    edges {
      node {
        id
        amount
      }
    }
  }
}
```

The returns the following data. Note that `amount` is serialized as a string

```json
{
  "data": {
    "generalLedgerCollection": {
      "edges": [
        {
          "node": {
            "id": 1,
            "amount": "22.15",
          }
        }
      ]
    }
  }
}
```

### Opaque

PostgreSQL's type system is extensible and not all types handle all operations e.g. filtering with `like`. To account for these, `pg_graphql` introduces a scalar `Opaque` type. The `Opaque` type uses PostgreSQL's `to_json` method to serialize values. That allows complex or unknown types to be included in the schema by delegating handling to the client.

```graphql
scalar Opaque

input OpaqueFilter {
  eq: Opaque
  is: FilterIs
}
```
