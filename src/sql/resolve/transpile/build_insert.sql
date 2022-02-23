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
            meta_kind = 'Mutation.insert'
            and name = graphql.name_literal(ast);

    entity regclass = field_rec.entity;

    arg_object graphql.field = field from graphql.field where parent_arg_field_id = field_rec.id and meta_kind = 'ObjectsArg';
    allowed_columns graphql.field[] = array_agg(field) from graphql.field where parent_arg_field_id = arg_object.id and meta_kind = 'Column';

    object_arg jsonb = graphql.get_arg_by_name(arg_object.name, graphql.jsonb_coalesce(ast -> 'arguments', '[]'));

    block_name text = graphql.slug();
    column_clause text;
    values_clause text;
    returning_clause text;
    result text;

    values_var jsonb; -- value for `objects` from variables
    values_all_field_keys text[]; -- all field keys referenced in values_var
begin
    if object_arg is null then
       perform graphql.exception_required_argument('objects');
    end if;

    if graphql.is_variable(object_arg -> 'value') then
        values_var = variables -> graphql.name_literal(object_arg -> 'value');

    elsif (object_arg -> 'value' ->> 'kind') = 'ListValue' then
        -- Literals and Column Variables
        select
            jsonb_agg(
                case
                    when graphql.is_variable(row_.ast) then (
                        case
                            when jsonb_typeof(variables -> (graphql.name_literal(row_.ast))) <> 'object' then graphql.exception('Invalid value for objects record')::jsonb
                            else variables -> (graphql.name_literal(row_.ast))
                        end
                    )
                    when row_.ast ->> 'kind' = 'ObjectValue' then (
                        select
                            jsonb_object_agg(
                                graphql.name_literal(rec_vals.ast),
                                case
                                    when graphql.is_variable(rec_vals.ast -> 'value') then (variables ->> (graphql.name_literal(rec_vals.ast -> 'value')))
                                    else graphql.value_literal(rec_vals.ast)
                                end
                            )
                        from
                            jsonb_array_elements(row_.ast -> 'fields') rec_vals(ast)
                    )
                    else graphql.exception('Invalid value for objects record')::jsonb
                end
            )
        from
            jsonb_array_elements(object_arg -> 'value' -> 'values') row_(ast) -- one per "record" of data
        into
            values_var;

        -- Handle empty list input
        values_var = coalesce(values_var, jsonb_build_array());
    else
        perform graphql.exception('Invalid value for objects record')::jsonb;
    end if;

    -- Confirm values is a list
    if not jsonb_typeof(values_var) = 'array' then
        perform graphql.exception('Invalid value for objects. Expected list');
    end if;

    -- Confirm each element of values is an object
    perform (
        select
            string_agg(
                case jsonb_typeof(x.elem)
                    when 'object' then 'irrelevant'
                    else graphql.exception('Invalid value for objects. Expected list of objects')
                end,
                ','
            )
        from
            jsonb_array_elements(values_var) x(elem)
    );

    if not jsonb_array_length(values_var) > 0 then
        perform graphql.exception('At least one record must be provided to objects');
    end if;

    values_all_field_keys = (
        select
            array_agg(distinct y.key_)
        from
            jsonb_array_elements(values_var) x(elem),
            jsonb_each(x.elem) y(key_, val_)
    );

    -- Confirm all keys are valid field names
    select
        string_agg(
            case
                when ac.name is not null then format('%I', ac.column_name)
                else graphql.exception_unknown_field(vfk.field_name)
            end,
            ','
            order by vfk.field_name asc
        )
    from
        unnest(values_all_field_keys) vfk(field_name)
        left join unnest(allowed_columns) ac
            on vfk.field_name = ac.name
    into
        column_clause;

    -- At this point all field keys are known safe
    with value_rows(r) as (
        select
            format(
                format(
                    '(%s)',
                    string_agg(
                        format(
                            '%s',
                            case
                                when row_col.field_val is null then 'default'
                                else format('%L', row_col.field_val)
                            end
                        ),
                        ', '
                        order by vfk.field_name asc
                    )
                )
            )
        from
            jsonb_array_elements(values_var) with ordinality row_(elem, ix),
            unnest(values_all_field_keys) vfk(field_name)
            left join jsonb_each_text(row_.elem) row_col(field_name, field_val)
                on vfk.field_name = row_col.field_name
        group by
            row_.ix
    )
    select
        string_agg(r, ', ')
    from
        value_rows
    into
        values_clause;

    returning_clause = (
        select
            format(
                'jsonb_build_object( %s )',
                string_agg(
                    case
                        when top_fields.name = '__typename' then format(
                            '%L, %L',
                            graphql.alias_or_name_literal(top.sel),
                            top_fields.type_
                        )
                        when top_fields.name = 'affectedCount' then format(
                            '%L, %s',
                            graphql.alias_or_name_literal(top.sel),
                            'count(1)'
                        )
                        when top_fields.name = 'records' then (
                            select
                                format(
                                    '%L, coalesce(jsonb_agg(jsonb_build_object( %s )), jsonb_build_array())',
                                    graphql.alias_or_name_literal(top.sel),
                                    string_agg(
                                        format(
                                            '%L, %s',
                                            graphql.alias_or_name_literal(x.sel),
                                            case
                                                when nf.column_name is not null and nf.column_type = 'bigint'::regtype then format('(%I.%I)::text', block_name, nf.column_name)
                                                when nf.column_name is not null then format('%I.%I', block_name, nf.column_name)
                                                when nf.meta_kind = 'Function' then format('%I(%I)', nf.func, block_name)
                                                when nf.name = '__typename' then format('%L', nf.type_)
                                                when nf.local_columns is not null and nf.meta_kind = 'Relationship.toMany' then graphql.build_connection_query(
                                                    ast := x.sel,
                                                    variable_definitions := variable_definitions,
                                                    variables := variables,
                                                    parent_type := top_fields.type_,
                                                    parent_block_name := block_name
                                                )
                                                when nf.local_columns is not null and nf.meta_kind = 'Relationship.toOne' then graphql.build_node_query(
                                                    ast := x.sel,
                                                    variable_definitions := variable_definitions,
                                                    variables := variables,
                                                    parent_type := top_fields.type_,
                                                    parent_block_name := block_name
                                                )
                                                else graphql.exception_unknown_field(graphql.name_literal(x.sel))
                                            end
                                        ),
                                        ','
                                    )
                                )
                            from
                                lateral jsonb_array_elements(top.sel -> 'selectionSet' -> 'selections') x(sel)
                                left join graphql.field nf
                                    on top_fields.type_ = nf.parent_type
                                    and graphql.name_literal(x.sel) = nf.name
                            where
                                graphql.name_literal(top.sel) = 'records'
                        )
                        else graphql.exception_unknown_field(graphql.name_literal(top.sel), field_rec.type_)
                    end,
                    ', '
                )
            )
        from
            jsonb_array_elements(ast -> 'selectionSet' -> 'selections') top(sel)
            left join graphql.field top_fields
                on field_rec.type_ = top_fields.parent_type
                and graphql.name_literal(top.sel) = top_fields.name
    );

    result = format(
        'with affected as (
            insert into %s(%s)
            values %s
            returning *
        )
        select
            %s
        from
            affected as %I;
        ',
        field_rec.entity,
        column_clause,
        values_clause,
        coalesce(returning_clause, 'null'),
        block_name
    );

    return result;
end;
$$;
