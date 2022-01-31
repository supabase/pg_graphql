create or replace function graphql.build_insert(
    ast jsonb,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}',
    parent_type text = null
)
    returns text
    language plpgsql
as $$
declare
    field_rec graphql.field = field
        from graphql.field
        where
            meta_kind = 'Mutation.insert.one'
            and name = graphql.name_literal(ast);

    entity regclass = field_rec.entity;

    arg_object graphql.field = field from graphql.field where parent_arg_field_id = field_rec.id and meta_kind = 'ObjectArg';
    allowed_columns graphql.field[] = array_agg(field) from graphql.field where parent_arg_field_id = arg_object.id and meta_kind = 'Column';

    object_arg_ix int = graphql.arg_index(arg_object.name, variable_definitions);
    object_arg jsonb = graphql.get_arg_by_name(arg_object.name, graphql.jsonb_coalesce(ast -> 'arguments', '[]'));

    block_name text = graphql.slug();
    column_clause text;
    values_clause text;
    returning_clause text;
    result text;
begin

    if graphql.is_variable(object_arg) then
        return graphql.exception('Variable for arg "object" not yet supported');
    end if;

    select
        -- Column Clause
        string_agg(
            format(
                '%I',
                case
                    when ac.meta_kind = 'Column' then ac.column_name
                    else graphql.exception_unknown_field(graphql.name_literal(val), field_rec.type_)
                end
            ),
            ', '
        ) as column_clause,
        -- Values Clause
        string_agg(
            case
                when graphql.is_variable(val -> 'value') then format(
                    '$%s',
                    graphql.arg_index(
                        (val -> 'value' -> 'name' ->> 'value'),
                        variable_definitions
                    )
                )
                else format('%L', graphql.value_literal(val))
            end,
            ', '
        ) as values_clause
    from
        jsonb_array_elements(object_arg -> 'value' -> 'fields') arg_cols(val)
        left join unnest(allowed_columns) ac
            on graphql.name_literal(arg_cols.val) = ac.name
    into
        column_clause, values_clause;

    returning_clause = format(
        'jsonb_build_object( %s )',
        string_agg(
            format(
                '%L, %s',
                graphql.alias_or_name_literal(x.sel),
                case
                    when nf.column_name is not null then format('%I.%I', block_name, nf.column_name)
                    when nf.meta_kind = 'Function' then format('%I(%I)', nf.func, block_name)
                    when nf.name = '__typename' then format('%L', nf.type_)
                    when nf.name = 'nodeId' then graphql.cursor_encoded_clause(field_rec.entity, block_name)
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
        'insert into %I as %I (%s) values (%s) returning %s;',
        entity,
        block_name,
        column_clause,
        values_clause,
        coalesce(returning_clause, 'null')
    );

    return result;
end;
$$;
