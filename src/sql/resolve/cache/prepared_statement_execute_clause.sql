create or replace function graphql.prepared_statement_execute_clause(statement_name text, variable_definitions jsonb, variables jsonb)
    returns text
    immutable
    language sql
as $$
   select
        case count(1)
            when 0 then format('execute %I', statement_name)
            else
                format('execute %I (', statement_name)
                || string_agg(format('%L', coalesce(var.val, def ->> 'defaultValue')), ',' order by def_idx)
                || ')'
        end
    from
        jsonb_array_elements(variable_definitions) with ordinality d(def, def_idx)
        left join jsonb_each_text(variables) var(key_, val)
            on graphql.name_literal(def -> 'variable') = var.key_
$$;
