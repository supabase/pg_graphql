create or replace function graphql.variable_literal(ast jsonb, variables jsonb)
    returns jsonb
    language sql
as $$
    with val_from_vars(val) as (
        select
            variables -> graphql.name_literal(ast)
    )
    select
        case val is null
            when true then graphql.exception('Variable value was not provided')::jsonb
            else val
        end
    from
        val_from_vars
$$;
