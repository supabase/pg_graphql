create function graphql.to_function_name(regproc)
    returns text
    language sql
    immutable
as
$$ select coalesce(nullif(split_part($1::text, '.', 2), ''), $1::text) $$;
