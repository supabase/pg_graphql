create or replace function graphql.arg_index(arg_name text, variable_definitions jsonb)
    returns int
    immutable
    strict
    language sql
as $$
    select
        ar.idx
    from
        jsonb_array_elements(variable_definitions) with ordinality ar(elem, idx)
    where
        graphql.name_literal(elem -> 'variable') = $1
$$;
