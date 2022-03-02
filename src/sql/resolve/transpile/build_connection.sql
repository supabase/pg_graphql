create or replace function graphql.build_connection_query(
    ast jsonb,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}',
    parent_type text = null,
    parent_block_name text = null
)
    returns text
    language plpgsql
as $$
declare
    block_name text = graphql.slug();
    entity regclass = t.entity
        from
            graphql.field f
            join graphql.type t
                on f.type_ = t.name
        where
            f.name = graphql.name_literal(ast)
            and f.parent_type = $4;

    ent alias for entity;

    arguments jsonb = graphql.jsonb_coalesce((ast -> 'arguments'), '[]');

    field_row graphql.field = f from graphql.field f where f.name = graphql.name_literal(ast) and f.parent_type = $4;
    first_ text = graphql.arg_clause(
        'first',
        arguments,
        variable_definitions,
        entity
    );
    last_ text = graphql.arg_clause('last',   arguments, variable_definitions, entity);
    before_ text = graphql.arg_clause('before', arguments, variable_definitions, entity);
    after_ text = graphql.arg_clause('after',  arguments, variable_definitions, entity);

    order_by_arg jsonb = graphql.get_arg_by_name('orderBy',  arguments);
    filter_arg jsonb = graphql.get_arg_by_name('filter',  arguments);

    total_count_ast jsonb = jsonb_path_query_first(
        ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "totalCount"}'
    );

    __typename_ast jsonb = jsonb_path_query_first(
        ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "__typename"}'
    );

    page_info_ast jsonb = jsonb_path_query_first(
        ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "pageInfo"}'
    );

    edges_ast jsonb = jsonb_path_query_first(
        ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "edges"}'
    );

    cursor_ast jsonb = jsonb_path_query_first(
        edges_ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "cursor"}'
    );

    node_ast jsonb = jsonb_path_query_first(
        edges_ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "node"}'
    );

    __typename_clause text;
    total_count_clause text;
    page_info_clause text;
    node_clause text;
    edges_clause text;

    result text;
begin
    if first_ is not null and last_ is not null then
        perform graphql.exception('only one of "first" and "last" may be provided');
    elsif before_ is not null and after_ is not null then
        perform graphql.exception('only one of "before" and "after" may be provided');
    elsif first_ is not null and before_ is not null then
        perform graphql.exception('"first" may only be used with "after"');
    elsif last_ is not null and after_ is not null then
        perform graphql.exception('"last" may only be used with "before"');
    end if;

    __typename_clause = format(
        '%L, %L',
        graphql.alias_or_name_literal(__typename_ast),
        field_row.type_
    ) where __typename_ast is not null;

    total_count_clause = format(
        '%L, coalesce(min(%I.%I), 0)',
        graphql.alias_or_name_literal(total_count_ast),
        block_name,
        '__total_count'
    ) where total_count_ast is not null;

    page_info_clause = case
        when page_info_ast is null then null
        else (
            select
                format(
                '%L, jsonb_build_object(%s)',
                graphql.alias_or_name_literal(page_info_ast),
                string_agg(
                    format(
                        '%L, %s',
                        graphql.alias_or_name_literal(pi.sel),
                        case graphql.name_literal(pi.sel)
                            when '__typename' then format('%L', pit.name)
                            when 'startCursor' then format('graphql.array_first(array_agg(%I.__cursor))', block_name)
                            when 'endCursor' then format('graphql.array_last(array_agg(%I.__cursor))', block_name)
                            when 'hasNextPage' then format(
                                'coalesce(bool_and(%I.__has_next_page), false)',
                                block_name
                            )
                            when 'hasPreviousPage' then format(
                                'coalesce(bool_and(%s), false)',
                                case
                                    when first_ is not null and after_ is not null then 'true'
                                    when last_ is not null and before_ is not null then 'true'
                                    else 'false'
                                end
                            )
                            else graphql.exception_unknown_field(graphql.name_literal(pi.sel), 'PageInfo')
                        end
                    ),
                    ','
                )
            )
        from
            jsonb_array_elements(page_info_ast -> 'selectionSet' -> 'selections') pi(sel)
            join graphql.type pit
                on true
        where
            pit.meta_kind = 'PageInfo'
        )
    end;


    node_clause = case
        when node_ast is null then null
        else (
            select
                format(
                    'jsonb_build_object(%s)',
                    string_agg(
                        format(
                            '%L, %s',
                            graphql.alias_or_name_literal(n.sel),
                            case
                                when gf_s.name = '__typename' then format('%L', gt.name)
                                when gf_s.column_name is not null and gf_s.column_type = 'bigint'::regtype then format(
                                    '(%I.%I)::text',
                                    block_name,
                                    gf_s.column_name
                                )
                                when gf_s.column_name is not null then format('%I.%I', block_name, gf_s.column_name)
                                when gf_s.local_columns is not null and gf_s.meta_kind = 'Relationship.toOne' then
                                    graphql.build_node_query(
                                        ast := n.sel,
                                        variable_definitions := variable_definitions,
                                        variables := variables,
                                        parent_type := gt.name,
                                        parent_block_name := block_name
                                    )
                                when gf_s.local_columns is not null and gf_s.meta_kind = 'Relationship.toMany' then
                                    graphql.build_connection_query(
                                        ast := n.sel,
                                        variable_definitions := variable_definitions,
                                        variables := variables,
                                        parent_type := gt.name,
                                        parent_block_name := block_name
                                    )
                                when gf_s.meta_kind = 'Function' then format('%I.%I', block_name, gf_s.func)
                                else graphql.exception_unknown_field(graphql.name_literal(n.sel), gt.name)
                            end
                        ),
                        ','
                    )
                )
                from
                    jsonb_array_elements(node_ast -> 'selectionSet' -> 'selections') n(sel) -- node selection
                    join graphql.type gt -- return type of node
                        on true
                    left join graphql.field gf_s -- node selections
                        on gt.name = gf_s.parent_type
                        and graphql.name_literal(n.sel) = gf_s.name
                where
                    gt.meta_kind = 'Node'
                    and gt.entity = ent
                    and not coalesce(gf_s.is_arg, false)
        )
    end;

    edges_clause = case
        when edges_ast is null then null
        else (
            select
                format(
                    '%L, coalesce(jsonb_agg(jsonb_build_object(%s)), jsonb_build_array())',
                    graphql.alias_or_name_literal(edges_ast),
                    string_agg(
                        format(
                            '%L, %s',
                            graphql.alias_or_name_literal(ec.sel),
                            case graphql.name_literal(ec.sel)
                                when 'cursor' then format('%I.%I', block_name, '__cursor')
                                when '__typename' then format('%L', gf_e.type_)
                                when 'node' then node_clause
                                else graphql.exception_unknown_field(graphql.name_literal(ec.sel), gf_e.type_)
                            end
                        ),
                        E',\n'
                    )
                )
                from
                    jsonb_array_elements(edges_ast -> 'selectionSet' -> 'selections') ec(sel)
                    join graphql.field gf_e -- edge field
                        on gf_e.parent_type = field_row.type_
                        and gf_e.name = 'edges'
        )
    end;

    -- Error out on invalid top level selections
    perform case
                when (
                    graphql.name_literal(root.sel)
                    not in ('pageInfo', 'edges', 'totalCount', '__typename')
                ) then graphql.exception_unknown_field(graphql.name_literal(root.sel), field_row.type_)
                else null::text
            end
        from
            jsonb_array_elements((ast -> 'selectionSet' -> 'selections')) root(sel);

    select
        format('
    (
        with xyz_tot as (
            select
                count(1) as __total_count
            from
                %s as %I
            where
                %s
                -- join clause
                and %s
                -- where clause
                and %s
        ),
        -- might contain 1 extra row
        xyz_maybe_extra as (
            select
                first_value(%s) over (order by %s range between unbounded preceding and current row)::text as __first_cursor,
                last_value(%s) over (order by %s range between current row and unbounded following)::text as __last_cursor,
                %s::text as __cursor,
                %s -- all requested columns
            from
                %s as %I
            where
                true
                --pagination_clause
                and %s %s %s
                -- join clause
                and %s
                -- where clause
                and %s
            order by
                %s
            limit
                least(%s, 30) + 1
        ),
        xyz_has_next_page as (
            select
                count(1) > least(%s, 30) as __has_next_page
            from
                xyz_maybe_extra
        ),
        xyz as (
            select
                *
            from
                xyz_maybe_extra as %I
            order by
                %s
            limit
                least(%s, 30)
        )
        select
            jsonb_build_object(%s)
        from
        (
            select
                *
            from
                xyz,
                xyz_tot,
                xyz_has_next_page
            order by
                %s
        ) as %I
    )',
            -- total from
            entity,
            block_name,
            -- total count only computed if requested
            case
                when total_count_ast is null then 'false'
                else 'true'
            end,
            -- total join clause
            coalesce(graphql.join_clause(field_row.local_columns, block_name, field_row.foreign_columns, parent_block_name), 'true'),
            -- total where
            graphql.where_clause(filter_arg, entity, block_name, variables, variable_definitions),
            -- __first_cursor
            graphql.cursor_encoded_clause(entity, block_name),
            graphql.order_by_clause(order_by_arg, entity, block_name, false, variables),
            -- __last_cursor
            graphql.cursor_encoded_clause(entity, block_name),
            graphql.order_by_clause(order_by_arg, entity, block_name, false, variables),
            -- __cursor
            graphql.cursor_encoded_clause(entity, block_name),
            -- enumerate columns
            (
                select
                    coalesce(
                        string_agg(
                            case f.meta_kind
                                when 'Column' then format('%I.%I', block_name, column_name)
                                when 'Function' then format('%I(%I) as %I', f.func, block_name, f.func)
                                else graphql.exception('Unexpected meta_kind in select')
                            end,
                            ', '
                        )
                    )
                from
                    graphql.field f
                    join graphql.type t
                        on f.parent_type = t.name
                where
                    f.meta_kind in ('Column', 'Function') --(f.column_name is not null or f.func is not null)
                    and t.entity = ent
                    and t.meta_kind = 'Node'
            ),
            -- from
            entity,
            block_name,
            -- pagination
            case when coalesce(after_, before_) is null then 'true' else graphql.cursor_row_clause(entity, block_name) end,
            case when after_ is not null then '>' when before_ is not null then '<' else '=' end,
            case when coalesce(after_, before_) is null then 'true' else coalesce(after_, before_) end,
            -- join
            coalesce(graphql.join_clause(field_row.local_columns, block_name, field_row.foreign_columns, parent_block_name), 'true'),
            -- where
            graphql.where_clause(filter_arg, entity, block_name, variables, variable_definitions),
            -- order
            case
                when last_ is not null then graphql.order_by_clause(order_by_arg, entity, block_name, true, variables)
                else graphql.order_by_clause(order_by_arg, entity, block_name, false, variables)
            end,
            -- limit
            coalesce(first_, last_, '30'),
            -- xyz_has_next_page limit
            coalesce(first_, last_, '30'),
            -- xyz
            block_name,
            case
                when last_ is not null then graphql.order_by_clause(order_by_arg, entity, block_name, true, variables)
                else graphql.order_by_clause(order_by_arg, entity, block_name, false, variables)
            end,
            coalesce(first_, last_, '30'),
            -- JSON selects
            concat_ws(', ', total_count_clause, page_info_clause, __typename_clause, edges_clause),
            -- final order by
            graphql.order_by_clause(order_by_arg, entity, 'xyz', false, variables),
            -- block name
            block_name
        )
        into result;

    return result;
end;
$$;
