create or replace function graphql.build_update(
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

    field_rec graphql.field = f
        from
            graphql.field f
        where
            f.name = graphql.name_literal(ast) and f.meta_kind = 'Mutation.update';


    filter_arg jsonb = graphql.get_arg_by_name('filter',  graphql.jsonb_coalesce((ast -> 'arguments'), '[]'));
    where_clause text = graphql.where_clause(filter_arg, field_rec.entity, block_name, variables, variable_definitions);
    returning_clause text;
    at_most_clause text = graphql.arg_clause('atMost',  (ast -> 'arguments'), variable_definitions, field_rec.entity);

    arg_set graphql.field = field from graphql.field where parent_arg_field_id = field_rec.id and meta_kind = 'UpdateSetArg';
    allowed_columns graphql.field[] = array_agg(field) from graphql.field where parent_arg_field_id = arg_set.id and meta_kind = 'Column';
    set_arg_ix int = graphql.arg_index(arg_set.name, variable_definitions);
    set_arg jsonb = graphql.get_arg_by_name(arg_set.name, graphql.jsonb_coalesce(ast -> 'arguments', '[]'));
    set_clause text;
begin

    if graphql.is_variable(set_arg -> 'value') then
        -- `set` is variable
        select
            string_agg(
                format(
                    '%I = $%s::jsonb -> %L',
                    case
                        when ac.column_name is not null then ac.column_name
                        else graphql.exception_unknown_field(x.key_, f.type_)
                    end,
                    graphql.arg_index(
                        graphql.name_literal(set_arg -> 'value'),
                        variable_definitions
                    ),
                    x.key_
                ),
                ', '
            )
        from
            jsonb_each(variables -> graphql.name_literal(set_arg -> 'value')) x(key_, val)
            left join unnest(allowed_columns) ac
                on x.key_ = ac.name
        into
            set_clause;

    else
        -- Literals and Column Variables
        select
            string_agg(
                case
                    when graphql.is_variable(val -> 'value') then format(
                        '%I = $%s',
                        case
                            when ac.meta_kind = 'Column' then ac.column_name
                            else graphql.exception_unknown_field(graphql.name_literal(val), field_rec.type_)
                        end,
                        graphql.arg_index(
                            (val -> 'value' -> 'name' ->> 'value'),
                            variable_definitions
                        )
                    )
                    else format(
                        '%I = %L',
                        case
                            when ac.meta_kind = 'Column' then ac.column_name
                            else graphql.exception_unknown_field(graphql.name_literal(val), field_rec.type_)
                        end,
                        graphql.value_literal(val)
                    )
                end,
                ', '
            )
        from
            jsonb_array_elements(set_arg -> 'value' -> 'fields') arg_cols(val)
            left join unnest(allowed_columns) ac
                on graphql.name_literal(arg_cols.val) = ac.name
        into
            set_clause;

    end if;

    returning_clause = format(
        'jsonb_build_array(jsonb_build_object( %s ))',
        string_agg(
            format(
                '%L, %s',
                graphql.alias_or_name_literal(x.sel),
                case
                    when nf.column_name is not null then format('%I.%I', block_name, nf.column_name)
                    when nf.meta_kind = 'Function' then format('%I(%I)', nf.func, block_name)
                    when nf.name = '__typename' then format('%L', nf.type_)
                    when nf.local_columns is not null and nf.meta_kind = 'Relationship.toMany' then graphql.build_connection_query(
                        ast := x.sel,
                        variable_definitions := variable_definitions,
                        variables := variables,
                        parent_type := field_rec.type_,
                        parent_block_name := block_name
                    )
                    when nf.local_columns is not null and nf.meta_kind = 'Relationship.toOne' then graphql.build_node_query(
                        ast := x.sel,
                        variable_definitions := variable_definitions,
                        variables := variables,
                        parent_type := field_rec.type_,
                        parent_block_name := block_name
                    )
                    else graphql.exception_unknown_field(graphql.name_literal(x.sel), field_rec.type_)
                end
            ),
            ','
        )
    )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel)
        left join graphql.field nf
            on field_rec.type_ = nf.parent_type
            and graphql.name_literal(x.sel) = nf.name;


    result = format(
        -- todo: return empty list (vs null) on no matches
        'with updated as (
            update %I as %I
            set %s
            where %s
            returning *
        ),
        total(total_count) as (
            select
                count(*)
            from
                updated
        ),
        req(res) as (
            select
                %s
            from
                updated as %I
        ),
        wrapper(res) as (
            select
                case
                    when total.total_count > %s then graphql.exception($a$update impacts too many records$a$)::jsonb
                    when total.total_count = 0 then jsonb_build_array()
                    else req.res
                end
            from
                total
                left join req
                    on true
            limit 1
        )
        select
            res
        from
            wrapper;',
        field_rec.entity,
        block_name,
        set_clause,
        where_clause,
        coalesce(returning_clause, 'null'),
        block_name,
        at_most_clause
    );

    return result;
end;
$$;
