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
    result text;
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
    field_row graphql.field = f from graphql.field f where f.name = graphql.name_literal(ast) and f.parent_type = $4;
    first_ text = graphql.arg_clause('first',  (ast -> 'arguments'), variable_definitions, entity);
    last_ text = graphql.arg_clause('last',   (ast -> 'arguments'), variable_definitions, entity);
    before_ text = graphql.arg_clause('before', (ast -> 'arguments'), variable_definitions, entity);
    after_ text = graphql.arg_clause('after',  (ast -> 'arguments'), variable_definitions, entity);

    order_by_arg jsonb = graphql.get_arg_by_name('orderBy',  graphql.jsonb_coalesce((ast -> 'arguments'), '[]'));
    filter_arg jsonb = graphql.get_arg_by_name('filter',  graphql.jsonb_coalesce((ast -> 'arguments'), '[]'));

begin
    with clauses as (
        select
            (
                array_remove(
                    array_agg(
                        case
                            when graphql.name_literal(root.sel) = 'totalCount' then
                                format(
                                    '%L, coalesce(min(%I.%I), 0)',
                                    graphql.alias_or_name_literal(root.sel),
                                    block_name,
                                    '__total_count'
                                )
                            else null::text
                        end
                    ),
                    null
                )
            )[1] as total_count_clause,
            (
                array_remove(
                    array_agg(
                        case
                            when graphql.name_literal(root.sel) = '__typename' then
                                format(
                                    '%L, %L',
                                    graphql.alias_or_name_literal(root.sel),
                                    field_row.type_
                                )
                            else null::text
                        end
                    ),
                    null
                )
            )[1] as typename_clause,
            (
                array_remove(
                    array_agg(
                        case
                            when graphql.name_literal(root.sel) = 'pageInfo' then
                                format(
                                    '%L, jsonb_build_object(%s)',
                                    graphql.alias_or_name_literal(root.sel),
                                    (
                                        select
                                            string_agg(
                                                format(
                                                    '%L, %s',
                                                    graphql.alias_or_name_literal(pi.sel),
                                                    case graphql.name_literal(pi.sel)
                                                        when '__typename' then (select quote_literal(name) from graphql.type where meta_kind = 'PageInfo')
                                                        when 'startCursor' then format('graphql.array_first(array_agg(%I.__cursor))', block_name)
                                                        when 'endCursor' then format('graphql.array_last(array_agg(%I.__cursor))', block_name)
                                                        when 'hasNextPage' then format('graphql.array_last(array_agg(%I.__cursor)) <> graphql.array_first(array_agg(%I.__last_cursor))', block_name, block_name)
                                                        when 'hasPreviousPage' then format('graphql.array_first(array_agg(%I.__cursor)) <> graphql.array_first(array_agg(%I.__first_cursor))', block_name, block_name)
                                                        else graphql.exception_unknown_field(graphql.name_literal(pi.sel), 'PageInfo')

                                                    end
                                                )
                                                , E','
                                            )
                                        from
                                            jsonb_array_elements(root.sel -> 'selectionSet' -> 'selections') pi(sel)
                                    )
                                )
                            else null::text
                        end
                    ),
                    null
                )
            )[1] as page_info_clause,


            (
                array_remove(
                    array_agg(
                        case
                            when graphql.name_literal(root.sel) = 'edges' then
                                format(
                                    '%L, coalesce(jsonb_agg(%s %s), jsonb_build_array())',
                                    graphql.alias_or_name_literal(root.sel),
                                    (
                                        select
                                            coalesce(
                                                string_agg(
                                                    case graphql.name_literal(ec.sel)
                                                        when 'cursor' then format('jsonb_build_object(%L, %I.%I)', graphql.alias_or_name_literal(ec.sel), block_name, '__cursor')
                                                        when '__typename' then format('jsonb_build_object(%L, %L)', graphql.alias_or_name_literal(ec.sel), gf_e.type_)
                                                        else graphql.exception_unknown_field(graphql.name_literal(ec.sel), gf_e.type_)
                                                    end,
                                                    '||'
                                                ),
                                                'jsonb_build_object()'
                                            )
                                        from
                                            jsonb_array_elements(root.sel -> 'selectionSet' -> 'selections') ec(sel)
                                            join graphql.field gf_e -- edge field
                                                on gf_e.parent_type = field_row.type_
                                                and gf_e.name = 'edges'
                                        where
                                            graphql.name_literal(root.sel) = 'edges'
                                            and graphql.name_literal(ec.sel) <> 'node'
                                    ),
                                    (
                                        select
                                            format(
                                                '|| jsonb_build_object(%L, jsonb_build_object(%s))',
                                                graphql.alias_or_name_literal(e.sel),
                                                    string_agg(
                                                        format(
                                                            '%L, %s',
                                                            graphql.alias_or_name_literal(n.sel),
                                                            case
                                                                when gf_s.name = '__typename' then quote_literal(gf_n.type_)
                                                                when gf_s.column_name is not null then format('%I.%I', block_name, gf_s.column_name)
                                                                when gf_s.local_columns is not null and gf_st.meta_kind = 'Node' then
                                                                    graphql.build_node_query(
                                                                        ast := n.sel,
                                                                        variable_definitions := variable_definitions,
                                                                        variables := variables,
                                                                        parent_type := gf_n.type_,
                                                                        parent_block_name := block_name
                                                                    )
                                                                when gf_s.local_columns is not null and gf_st.meta_kind = 'Connection' then
                                                                    graphql.build_connection_query(
                                                                        ast := n.sel,
                                                                        variable_definitions := variable_definitions,
                                                                        variables := variables,
                                                                        parent_type := gf_n.type_,
                                                                        parent_block_name := block_name
                                                                    )
                                                                when gf_s.name = 'nodeId' then format('%I.%I', block_name, '__cursor')
                                                                else graphql.exception_unknown_field(graphql.name_literal(n.sel), gf_n.type_)
                                                            end
                                                        ),
                                                        E','
                                                    )
                                            )
                                        from
                                            jsonb_array_elements(root.sel -> 'selectionSet' -> 'selections') e(sel), -- node (0 or 1)
                                            lateral jsonb_array_elements(e.sel -> 'selectionSet' -> 'selections') n(sel) -- node selection
                                            join graphql.field gf_e -- edge field
                                                on field_row.type_ = gf_e.parent_type
                                                and gf_e.name = 'edges'
                                            join graphql.field gf_n -- node field
                                                on gf_e.type_ = gf_n.parent_type
                                                and gf_n.name = 'node'
                                            left join graphql.field gf_s -- node selections
                                                on gf_n.type_ = gf_s.parent_type
                                                and graphql.name_literal(n.sel) = gf_s.name
                                            left join graphql.type gf_st
                                                on gf_s.type_ = gf_st.name
                                        where
                                            graphql.name_literal(e.sel) = 'node'
                                        group by
                                            e.sel
                                )
                            )
                        else null::text
                    end
                ),
                null
            )
        )[1] as edges_clause,

        -- Error handling for unknown fields at top level
        (
            array_agg(
                case
                    when graphql.name_literal(root.sel) not in ('pageInfo', 'edges', 'totalCount', '__typename') then graphql.exception_unknown_field(graphql.name_literal(root.sel), field_row.type_)
                    else null::text
                end
            )
        ) as error_handler

        from
            jsonb_array_elements((ast -> 'selectionSet' -> 'selections')) root(sel)
    )
    select
        format('
    (
        with xyz as (
            select
                count(*) over () __total_count,
                first_value(%s) over (order by %s range between unbounded preceding and current row)::text as __first_cursor,
                last_value(%s) over (order by %s range between current row and unbounded following)::text as __last_cursor,
                %s::text as __cursor,
                %s -- all allowed columns
            from
                %I as %s
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
            limit %s
        )
        select
            -- total count
            jsonb_build_object(
            %s
            )
            -- page info
            || jsonb_build_object(
            %s
            )
            -- edges
            || jsonb_build_object(
            %s
            )
            -- __typename
            || jsonb_build_object(
            %s
            )
        from
        (
            select
                *
            from
                xyz
            order by
                %s
        ) as %s
    )',
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
                        string_agg(format('%I.%I', block_name, column_name), ', '),
                        '1'
                    )
                from
                    graphql.field f
                    join graphql.type t
                        on f.parent_type = t.name
                where
                    f.column_name is not null
                    and t.entity = ent
                    and t.meta_kind = 'Node'
            ),
            -- from
            entity,
            quote_ident(block_name),
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
            -- limit: max 20
            least(coalesce(first_, last_), '30'),
            -- JSON selects
            coalesce(clauses.total_count_clause, ''),
            coalesce(clauses.page_info_clause, ''),
            coalesce(clauses.edges_clause, ''),
            coalesce(clauses.typename_clause, ''),
            -- final order by
            graphql.order_by_clause(order_by_arg, entity, 'xyz', false, variables),
            -- block name
            quote_ident(block_name)
        )
        from clauses
        into result;

    return result;
end;
$$;
