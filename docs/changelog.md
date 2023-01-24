## [1.0.0]
- Initial release

## [1.0.1]
- feature: Add support for Postgres 15

## [1.0.2]
- bugfix: Correct inconsistent treatment of null literals

## [1.1.0]
- feature: Add support for Views, Materialized Views, and Foreign Tables
- feature: Add support for filtering on `is null` and `is not null`
- feature: User configurable page size
- bugfix: Remove requirement for `insert` permission on every column for inserts to succeed
- bugfix: `hasNextPage` and `hasPreviousPage` during reverse pagination were backwards
