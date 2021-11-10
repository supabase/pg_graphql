pg_graphql aims to implement all of the [GraphQL core specification](https://spec.graphql.org/October2021/) and as much of the [relay server specification](https://relay.dev/docs/guides/graphql-server-specification/) as is practical.

### Language
- [x] Parser
- [x] Fragments
- [x] Variables
- [x] Named Operations

- [ ] Introspection Schema

At time of writing, the introspection schema is a partial implementation. It is complete enough

### Relay
- [x] Opaque Cursors
- [x] Global NodeId
- [x] Node Types
    * [x] Arguments
        * [x] nodeId
- [ ] Connection Types
    * [x] totalCount
    * [x] PageInfo
    *   * [x] hasNextPage
    *   * [x] hasPreviousPage
    *   * [x] startCursor
    *   * [x] endCursor
    * [x] Edges
    *   * [x] cursor
    * [x] Pagination
    * [ ] Arguments
    *   * [x] first
    *   * [x] last
    *   * [x] before
    *   * [x] after
    *   * [ ] condition

### Relationships
- [x] One-to-Many
- [x] Many-to-Many
- [x] Many-to-One
- [ ] One-to-One

### Mutations
- [ ] Upsert
- [ ] User Defined Functions

### Error Handling
- [ ] Display parser syntax errors
- [ ] Useful error on non-existent type
- [ ] Useful error on non-existent field

### Configuration
- [ ] Max Query Depth
- [ ] Documentation
    * [ ] Role based schema/table/column exclusion
    * [ ] Override Type/Field names

### Optimizations
- [x] Prepared statement query cached
