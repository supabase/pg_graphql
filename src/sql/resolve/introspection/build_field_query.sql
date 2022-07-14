create or replace function graphql.build_field_query(
    ast jsonb,
    parent_block_name text,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}'
)
    returns text
    language plpgsql
    stable
as $$
declare
    block_name text = graphql.slug();
begin
    return
        format('
        (
            select
                %s
            from
                graphql.field gf
            where
                not gf.is_hidden_from_schema
                and gf.parent_type = %I
                and (
                    (gf.parent_arg_field_id is null and $3 is null)
                    or gf.parent_arg_field_id = $3
                )
            )',
            string_agg(
                format('%L, %s',
                    graphql.alias_or_name_literal(x.sel),
                    case graphql.name_literal(x.sel)
                        when 'description' then 'description'
                        when 'directives' then 'jsonb_build_array()' -- todo
                        when 'queryType' then '1' -- todo
                        when 'mutationType' then '1' -- todo
                        when 'subscriptionType' then '1' -- todo
                        when 'types' then format(
                            '(
                                select
                                    jsonb_agg(%s)
                                from
                                    graphql.type
                                where
                                    not is_hidden_from_schema
                            )',
                            graphql.build_type_query_core_selects(
                                ast := x.sel
                            )
                        )
                        when '' then '1' -- todo
                        else graphql.exception('Invalid field for type __Schema')
                    end
                ),
                ', '
            ),
            block_name,
            '__Schema'
        )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel);
end
$$;
