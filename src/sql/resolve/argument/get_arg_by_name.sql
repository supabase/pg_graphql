create or replace function graphql.get_arg_by_name(name text, arguments jsonb)
    returns jsonb
    immutable
    strict
    language sql
as $$
    select
        ar.elem
    from
        jsonb_array_elements(arguments) ar(elem)
    where
        graphql.name_literal(elem) = $1
$$;
