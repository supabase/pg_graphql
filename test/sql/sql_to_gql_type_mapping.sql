/*
Monitor if the SQL -> GQL type map changes
*/
select
    pt.typname sql_type,
    graphql.sql_type_to_graphql_type(pt.typname) as graphql_type
from
    pg_type pt
    join pg_namespace pn
        on pt.typnamespace = pn.oid
where
    substring(pt.typname, 1, 1) <> '_'
    and pt.typname not like '%[]'
    and pt.typname not like 'pg_%'
    and pt.typname not like 'view_%'
    and pt.typname not like 'any%'
    and pt.typname not like 'sql_%'
    and pt.typname not like 'foreign_%'
    and pt.typname not like 'role_%'
    and pt.typname not like 'account%'
    and pt.typname not like 'blog%'
    and pt.typname not like 'collation%'
    and pt.typname not like 'cardinal%'
    and pt.typname not like 'reg%' -- e.g. regclass, regrole
    and pt.typname not like 'table%'
    and pt.typname not like 'trigger%'
    and pt.typname not like 'column%'
    and pt.typname not like 'check%'
    and pn.nspname <> 'graphql'
order by
    graphql.sql_type_to_graphql_type(pt.typname) = 'String',
    graphql.sql_type_to_graphql_type(pt.typname),
    pt.typname
