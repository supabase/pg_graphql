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

## master
- feature: `String` type filters support `regex`, `iregex`
- feature: computed relationships via functions returning setof
