create or replace function graphql.build_schema_query(
    ast jsonb,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}'
)
    returns text
    language plpgsql
    stable
as $$
declare
    block_name text = graphql.slug();
    types_block_name text = graphql.slug();
begin
    return
        format('
            (
                select
                    jsonb_build_object(%s)
                from
                    graphql.field as %I
                where
                    parent_type = %L
                limit 1
            )',
            string_agg(
                format('%L, %s',
                    graphql.alias_or_name_literal(x.sel),
                    case graphql.name_literal(x.sel)
                        when 'description' then 'description'
                        when 'directives' then 'jsonb_build_array()' -- todo
                        when 'queryType' then format(
                            '(
                                select
                                    %s
                                from
                                    graphql.type %I
                                where
                                    %I.name = $v$Query$v$
                            )',
                            graphql.build_type_query_core_selects(
                                ast := x.sel,
                                block_name := types_block_name
                            ),
                            types_block_name,
                            types_block_name
                        )
                        when 'mutationType' then format(
                            '(
                                select
                                    %s
                                from
                                    graphql.type %I
                                where
                                    %I.name = $v$Mutation$v$
                            )',
                            graphql.build_type_query_core_selects(
                                ast := x.sel,
                                block_name := types_block_name
                            ),
                            types_block_name,
                            types_block_name
                        )
                        when 'subscriptionType' then 'null::text' -- todo
                        when 'types' then format(
                            '(
                                select
                                    jsonb_agg(%s order by %I.name)
                                from
                                    graphql.type %I
                            )',
                            graphql.build_type_query_core_selects(
                                ast := x.sel,
                                block_name := types_block_name
                            ),
                            types_block_name,
                            types_block_name
                        )
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
