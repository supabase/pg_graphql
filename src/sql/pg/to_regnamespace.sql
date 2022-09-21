create function graphql.to_regnamespace(regclass)
    returns regnamespace
    language sql
    set search_path to ''
    immutable
as
$$ select (parse_ident($1::text))[1]::regnamespace $$;


create function graphql.to_regnamespace(regproc)
    returns regnamespace
    language sql
    set search_path to ''
    immutable
as
$$ select (parse_ident($1::text))[1]::regnamespace $$;
