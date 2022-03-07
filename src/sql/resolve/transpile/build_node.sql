create or replace function graphql.build_node_query(
    ast jsonb,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}',
    parent_type text = null,
    parent_block_name text = null
)
    returns text
    language sql
    stable
as $$
    select
        format('
            (
                select
                    jsonb_build_object(%s)
                from
                    %s as %I
                where
                    true
                    -- join clause
                    and %s
                    -- filter clause
                    and %s = %s
                limit 1
            )',
            string_agg(
                format('%L, %s',
                    graphql.alias_or_name_literal(x.sel),
                    case
                        when nf.column_name is not null and nf.column_type = 'bigint'::regtype then format('(%I.%I)::text', block_name, nf.column_name)
                        when nf.column_name is not null then format('%I.%I', block_name, nf.column_name)
                        when nf.meta_kind = 'Function' then format('%s(%I)', nf.func, block_name)
                        when nf.name = '__typename' then format('%L', (c.type_).name)
                        when nf.local_columns is not null and nf.meta_kind = 'Relationship.toMany' then graphql.build_connection_query(
                            ast := x.sel,
                            variable_definitions := variable_definitions,
                            variables := variables,
                            parent_type := (c.field).type_,
                            parent_block_name := block_name
                        )
                        when nf.local_columns is not null and nf.meta_kind = 'Relationship.toOne' then graphql.build_node_query(
                            ast := x.sel,
                            variable_definitions := variable_definitions,
                            variables := variables,
                            parent_type := (c.field).type_,
                            parent_block_name := block_name
                        )
                        else graphql.exception_unknown_field(graphql.name_literal(x.sel), (c.field).type_)
                    end
                ),
                ', '
            ),
            (c.type_).entity,
            c.block_name,
            coalesce(graphql.join_clause((c.field).local_columns, block_name, (c.field).foreign_columns, parent_block_name), 'true'),
            'true',
            'true'
    )
    from
        (
            -- Define constants
            select
                graphql.slug(),
                gf,
                gt
            from
                graphql.field gf
                join graphql.type gt
                    on gt.name = gf.type_
            where
                gf.name = graphql.name_literal(ast)
                and gf.parent_type = $4
        ) c(block_name, field, type_)
        join jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel)
            on true
        left join graphql.field nf
            on nf.parent_type = (c.field).type_
            and graphql.name_literal(x.sel) = nf.name
    where
        (c.field).name = graphql.name_literal(ast)
        and $4 = (c.field).parent_type
    group by
        c.block_name,
        c.field,
        c.type_
$$;
