create or replace function graphql.resolve_mutation_type(ast jsonb)
    returns jsonb
    stable
    language sql
as $$
    select
        -- check mutations exist
        case exists(select 1 from graphql.field where parent_type = 'Mutation' and not is_hidden_from_schema)
            when true then (
                select
                    coalesce(
                        jsonb_object_agg(
                            fa.field_alias,
                            case
                                when selection_name = 'name' then 'Mutation'
                                when selection_name = 'description' then null
                                else graphql.exception_unknown_field(selection_name, 'Mutation')
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
        )
    end
$$;
