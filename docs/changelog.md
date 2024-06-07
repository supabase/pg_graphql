## 1.0.0
- Initial release

## 1.0.1
- feature: Add support for Postgres 15

## 1.0.2
- bugfix: Correct inconsistent treatment of null literals

## 1.1.0
- feature: Add support for Views, Materialized Views, and Foreign Tables
- feature: Add support for filtering on `is null` and `is not null`
- feature: User configurable page size
- bugfix: Remove requirement for `insert` permission on every column for inserts to succeed
- bugfix: `hasNextPage` and `hasPreviousPage` during reverse pagination were backwards

## 1.2.0
- feature: `String` type filters support `ilike`, `like`, `startsWith`
- feature: Support for `@skip` and `@include` directives
- feature: Custom descriptions via comment directive `@graphql({"description": ...})`
- bugfix: Unknown types are represented in GraphQL schema as `Opaque` rather than `String`
- bugfix: PostgreSQL type modifiers, e.g. char(n), no longer truncate excess text
- bugfix: Creating a new enum variant between existing variants no longer errors

## 1.2.1
- feature: `String` type filters support `regex`, `iregex`
- feature: computed relationships via functions returning setof
- bugfix: function based computed columns with same name no longer error

## 1.2.2
- feature: reproducible builds

## 1.2.3
- bugfix: enums not on the roles `search_path` are excluded from introspection
- bugfix: remove duplicate Enum registration
- bugfix: foreign keys on non-null columns produce non-null GraphQL relationships

## 1.3.0
- feature: rename enum variants with comment directive `@graphql({"mappings": "sql-value": "graphql_value""})`
- bugfix: query with more than 50 fields fails
- bugfix: @skip and @include directives missing from introspection schema
- feature: Support for `and`, `or` and `not` operators in filters
- bugfix: queries failed to run if the database was in read-only replica mode

## 1.4.0
- feature: citext type represented as a GraphQL String
- feature: Support for Postgres 16
- feature: Support for user defined functions

## 1.4.1
- feature: Support for user defined functions with default arguments
- bugfix: Trigger functions excluded from API

## 1.4.2
- bugfix: UDF call returned null if the row returned by the function had any null column

## 1.4.3
- bugfix: make non-default args non-null in UDFs
- bugfix: default value of a string type argument in a UDF was wrapped in single quotes
- feature: add support for array types in UDFs
- bugfix: fix crash when there are cycles in fragments
- bugfix: function returning an inaccessible table's type no longer breaks introspection

## 1.4.4
- bugfix: function returning a noncompliant view's type no longer breaks introspection

## 1.5.0
- feature: `first`/`offset` based pagination
- feature: improved descriptions for all internal error states

## 1.5.1
- bugfix: reimplemented field merging to resolve a performance issue on large queries

## 1.5.2
- bugfix: enabled schema based multi-tenancy via filtering SQL context on schema permissions
- bugfix: function arguments with a null default value were required instead of optional

## 1.5.3
- bugfix: computed field returning a composite type was always null

## 1.5.4
- bugfix: once a query panics, all subsequent queries return a lock poisoned error.

## 1.5.6
- feature: add support for filtering on array column types using `contains`, `containedBy`, `overlaps`, `is`, `eq`


## master
