create or replace function graphql."resolve_queryType"(ast jsonb)
    returns jsonb
    stable
    language sql
as $$
    select
        coalesce(
            jsonb_object_agg(
                fa.field_alias,
                case
                    when selection_name = 'name' then 'Query'
                    when selection_name = 'description' then null
                    else graphql.exception_unknown_field(selection_name, 'Query')
                end
            ),
            'null'::jsonb
        )
    from
        jsonb_path_query(ast, '$.selectionSet.selections') selections,
        lateral( select sel from jsonb_array_elements(selections) s(sel) ) x(sel),
        lateral (
            select
                graphql.alias_or_name_literal(x.sel) field_alias,
                graphql.name_literal(x.sel) as selection_name
        ) fa
$$;
