create function graphql.sql_type_to_graphql_type(sql_type text)
    returns text
    language sql
as
$$
    -- SQL type from pg_catalog.format_type
    select
        case
            when sql_type like 'int%' then 'Int' -- unsafe for int8
            when sql_type like 'bool%' then 'Boolean'
            when sql_type like 'float%' then 'Float'
            when sql_type like 'numeric%' then 'Float' -- unsafe
            when sql_type = 'json' then 'JSON'
            when sql_type = 'jsonb' then 'JSON'
            when sql_type like 'json%' then 'JSON'
            when sql_type = 'uuid' then 'UUID'
            when sql_type = 'daterange' then 'String'
            when sql_type like 'date%' then 'DateTime'
            when sql_type like 'timestamp%' then 'DateTime'
            when sql_type like 'time%' then 'DateTime'
            --when sql_type = 'inet' then 'InternetAddress'
            --when sql_type = 'cidr' then 'InternetAddress'
            --when sql_type = 'macaddr' then 'MACAddress'
        else 'String'
    end;
$$;




create function graphql.type_id(regtype)
    returns int
    immutable
    language sql
as
$$
    select
        graphql.type_id(
            graphql.sql_type_to_graphql_type(
                -- strip trailing [] for array types
                regexp_replace(
                    pg_catalog.format_type($1, null),
                    '\[\]$',
                    ''
                )
            )
        )
$$;
