pg_graphql aims to implement all of the [GraphQL core specification](https://spec.graphql.org/October2021/) and as much of the [relay server specification](https://relay.dev/docs/guides/graphql-server-specification/) as is practical.

### Language
- [x] Parser
- [x] Fragments
- [x] Variables
- [x] Named Operations
- [x] Introspection Schema

### Query
- [x] Pageable Types
    * [x] totalCount
    * [x] PageInfo
    *   * [x] hasNextPage
    *   * [x] hasPreviousPage
    *   * [x] startCursor
    *   * [x] endCursor
    * [x] Edges
    *   * [x] cursor
    * [x] Pagination
    * [x] Arguments
    *   * [x] first
    *   * [x] last
    *   * [x] before
    *   * [x] after
    *   * [x] filter
    *   * [x] orderBy

### Relationships
- [x] One-to-Many
- [x] Many-to-Many
- [x] Many-to-One
- [ ] One-to-One

### Mutations
- [x] Insert
- [x] Update
- [x] Delete

### Error Handling
- [x] Display parser syntax errors
- [x] Useful error on non-existent field

### Configuration
- [x] Role based schema/table/column exclusion
- [x] Override Type/Field names

### Optimizations
- [x] Prepared statement query cached
