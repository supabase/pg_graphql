create or replace function graphql.prepared_statement_create_clause(statement_name text, variable_definitions jsonb, query_ text)
    returns text
    immutable
    language sql
as $$
    -- Create Prepared Statement
    select format(
        'prepare %I %s as %s',
        statement_name,
        case jsonb_array_length(variable_definitions)
            when 0 then ''
            else (select '(' || string_agg('text', ', ') || ')' from jsonb_array_elements(variable_definitions) jae(vd))
        end,
        query_
    )
$$;
