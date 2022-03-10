/*
Monitor if the SQL -> GQL type map changes
*/
select
    pt.oid::regtype,
    graphql.sql_type_to_graphql_type(pt.oid::regtype) as graphql_type
from
    pg_type pt
    join pg_namespace pn
        on pt.typnamespace = pn.oid
where
    pt.typname not like '\_%'
    and graphql.sql_type_to_graphql_type(pt.oid::regtype) <> 'String'
    or pt.typname similar to '(text|varchar|char)'
order by
    graphql.sql_type_to_graphql_type(pt.oid::regtype),
    pt.typname
