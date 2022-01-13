create function graphql.to_type_name(regtype)
    returns text
    language sql
    immutable
as
$$ select coalesce(nullif(split_part($1::text, '.', 2), ''), $1::text) $$;
