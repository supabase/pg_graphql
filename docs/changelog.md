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
- rename enum variants with comment directive `@graphql({"mappings": "sql-value": "graphql_value""})`
- bugfix: query with more than 50 fields fails
- bugfix: @skip and @include directives missing from introspection schema
- feature: Support for `and`, `or` and `not` operators in filters

## master
