create function graphql.sql_type_to_graphql_type(regtype)
    returns text
    language sql
as
$$
    select
        case $1
            when 'smallint'          ::regtype then 'Int'
            when 'smallint[]'        ::regtype then 'Int'

            when 'integer'           ::regtype then 'Int'
            when 'integer[]'         ::regtype then 'Int'

            when 'bigint'            ::regtype then 'BigInt'
            when 'bigint[]'          ::regtype then 'BigInt'

            when 'boolean'           ::regtype then 'Boolean'
            when 'boolean[]'         ::regtype then 'Boolean'

            when 'real'              ::regtype then 'Float'
            when 'real[]'            ::regtype then 'Float'

            when 'double precision'  ::regtype then 'Float'
            when 'double precision[]'::regtype then 'Float'

            when 'json'              ::regtype  then 'JSON'
            when 'json[]'            ::regtype  then 'JSON'

            when 'jsonb'             ::regtype  then 'JSON'
            when 'jsonb[]'           ::regtype  then 'JSON'

            when 'uuid'              ::regtype  then 'UUID'
            when 'uuid[]'            ::regtype  then 'UUID'

            when 'date'              ::regtype  then 'Date'
            when 'date[]'            ::regtype  then 'Date'

            when 'time'              ::regtype  then 'Time'
            when 'time[]'            ::regtype  then 'Time'

            when 'timestamp'         ::regtype then 'Datetime'
            when 'timestamp[]'       ::regtype then 'Datetime'

            when 'timestamptz'       ::regtype then 'Datetime'
            when 'timestamptz[]'     ::regtype then 'Datetime'
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
        graphql.type_id(graphql.sql_type_to_graphql_type($1))
$$;
