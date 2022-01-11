create or replace function graphql.variable_definitions_sort(variable_definitions jsonb)
    returns jsonb
    immutable
    language sql
as $$
  -- Deterministically sort variable definitions
  select
        jsonb_agg(jae.f order by jae.f -> 'variable' -> 'name' ->> 'value' asc)
    from
        jsonb_array_elements(
            case jsonb_typeof(variable_definitions)
                when 'array' then variable_definitions
                else to_jsonb('{}'::text[])
            end
        ) jae(f)
$$;
