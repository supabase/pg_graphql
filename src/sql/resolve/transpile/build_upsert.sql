create or replace function graphql.build_upsert(
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
            meta_kind = 'Mutation.upsert.one'
            and name = graphql.name_literal(ast);

    entity regclass = field_rec.entity;

    arg_object graphql.field = field from graphql.field where parent_arg_field_id = field_rec.id and meta_kind = 'ObjectArg';
    allowed_columns graphql.field[] = array_agg(field) from graphql.field where parent_arg_field_id = arg_object.id and meta_kind = 'Column';

    object_arg_ix int = graphql.arg_index(arg_object.name, variable_definitions);
    object_arg jsonb = graphql.get_arg_by_name(arg_object.name, graphql.jsonb_coalesce(ast -> 'arguments', '[]'));

    on_conflict_field graphql.field = field from graphql.field where parent_arg_field_id = field_rec.id and meta_kind = 'OnConflictArg';
    on_conflict_arg_ix int = graphql.arg_index(on_conflict_field.name, variable_definitions);
    on_conflict_arg jsonb = graphql.get_arg_by_name(on_conflict_field.name, graphql.jsonb_coalesce(ast -> 'arguments', '[]'));

    block_name text = graphql.slug();
    column_clause text;
    values_clause text;
    returning_clause text;
    result text;

    variable_val jsonb;
    variable_ix int;

    ast_seg jsonb;
    ast_working jsonb;

    on_conflict_clause text;
    on_conflict_conflict_clause text;
    on_conflict_update_clause text;
    arg_on_conflict_update_fields text[];

    selectable_cols graphql.enum_value[] = array_agg(ev)
        from
            graphql.type t
            join graphql.enum_value ev
                on t.name = ev.type_
        where
            t.entity = field_rec.entity
            and t.meta_kind = 'SelectableColumns';

    updatable_cols graphql.enum_value[] = array_agg(ev)
        from
            graphql.type t
            join graphql.enum_value ev
                on t.name = ev.type_
        where
            t.entity = field_rec.entity
            and t.meta_kind = 'UpdatableColumns';

    conflict_fields_ast jsonb;
    conflict_update_ast jsonb;
begin

    if graphql.is_variable(object_arg -> 'value') then
        -- `object` is variable
        select
            string_agg(format('%I', x.key_), ', ') as column_clause,
            string_agg(
                format(
                    '$%s::jsonb -> %L',
                    graphql.arg_index(
                        graphql.name_literal(object_arg -> 'value'),
                        variable_definitions
                    ),
                    x.key_
                ),
                ', '
            ) as values_clause
        from
            jsonb_each(variables -> graphql.name_literal(object_arg -> 'value')) x(key_, val)
            left join unnest(allowed_columns) ac
                on x.key_ = ac.name
        into
            column_clause, values_clause;

    else
        -- Literals and Column Variables
        select
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
    end if;

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


    if on_conflict_arg is null then
        on_conflict_clause = '';

    elsif graphql.is_variable(on_conflict_arg -> 'value') then
        -- `onConflict` is variable
        -- variable_value := graphql.variable_literal(on_conflict_arg -> 'value', variables);
        -- variable_ix := graphql.arg_index(graphql.name_literal(on_conflict_arg -> 'value'), variable_definitions);
        perform graphql.exception('variables not supported for on conflict clause');

    elsif not graphql.is_kind(on_conflict_arg -> 'value', 'ObjectValue') then
        --perform graphql.exception(on_conflict_arg -> 'value');
        -- Wrong type
        perform graphql.exception('Bad data for onConflict parameter');
    else
        -- Literals and Column Variables
        -- on_conflict_update_clause = 'id, "col2", xyz';
        arg_on_conflict_update_fields = array['temp'];


        /*
            onConflict.conflictFields
        */
        conflict_fields_ast = jsonb_path_query_first(
            on_conflict_arg,
            '$.value.fields ? ( @.name.value == $param_name )',
            '{"param_name": "conflictFields"}'
        );

        if graphql.is_variable(conflict_fields_ast) then
            perform graphql.exception('onConflict.conflictFields does not support variables');
        elsif not graphql.is_kind(conflict_fields_ast, 'ObjectField') or not (graphql.is_kind(conflict_fields_ast -> 'value', 'ListValue')) then
            perform graphql.exception('onConflict.conflictFields is invalid type');
        else

            select
                string_agg(
                    format(
                        '%I',
                        case
                            when sc1.column_name is not null then sc1.column_name
                            when sc2.column_name is not null then sc2.column_name
                            when true then graphql.exception(selectable_cols::text)
                            when graphql.is_variable(arg.obj) then graphql.exception('variable missing for onConflict.conflictFields')
                            else graphql.exception('invalid onConflict.conflictFields')
                        end
                    ),
                    ', '
                )
            from
                jsonb_array_elements(conflict_fields_ast -> 'value' -> 'values') arg(obj)
                -- literals
                left join unnest(selectable_cols) sc1
                    on graphql.is_literal(arg.obj)
                    and jsonb_typeof((arg.obj -> 'value')) = 'string'
                    and (arg.obj ->> 'value') = sc1.value
                -- variables
                left join unnest(selectable_cols) sc2
                    on graphql.is_variable(arg.obj)
                    and graphql.variable_literal(arg.obj, variables)::text = sc2.value
            into
                on_conflict_conflict_clause;

        end if;

        /*
            onConflict.updateFields
        */
        conflict_update_ast = jsonb_path_query_first(
            on_conflict_arg,
            '$.value.fields ? ( @.name.value == $param_name )',
            '{"param_name": "updateFields"}'
        );

        if graphql.is_variable(conflict_update_ast) then
            perform graphql.exception('onConflict.updateFields does not support variables');
        elsif not graphql.is_kind(conflict_update_ast, 'ObjectField') or not (graphql.is_kind(conflict_update_ast -> 'value', 'ListValue')) then
            perform graphql.exception('onConflict.updateFields is invalid type');
        else

            select
                string_agg(
                    format(
                        '%I = excluded.%I',
                        col.name,
                        col.name
                    ),
                    ', '
                )
            from
                jsonb_array_elements(conflict_update_ast -> 'value' -> 'values') arg(obj)
                -- literals
                left join unnest(updatable_cols) sc1
                    on graphql.is_literal(arg.obj)
                    and jsonb_typeof((arg.obj -> 'value')) = 'string'
                    and (arg.obj ->> 'value') = sc1.value
                -- variables
                left join unnest(updatable_cols) sc2
                    on graphql.is_variable(arg.obj)
                    and graphql.variable_literal(arg.obj, variables)::text = sc2.value,
                lateral (
                    select
                        case
                            when sc1.column_name is not null then sc1.column_name
                            when sc2.column_name is not null then sc2.column_name
                            when true then graphql.exception(selectable_cols::text)
                            when graphql.is_variable(arg.obj) then graphql.exception('variable missing for onConflict.updateFields')
                            else graphql.exception('invalid onConflict.updateFields')
                        end
                ) col(name)
            into
                on_conflict_update_clause;

        end if;

        if coalesce(on_conflict_update_clause, '') <> '' and coalesce(on_conflict_conflict_clause, '') <> '' then
            on_conflict_clause = format('on conflict ( %s ) do update set  %s', on_conflict_conflict_clause, on_conflict_update_clause);
        else
            perform graphql.exception('conflictColumns and updateColumns are required fields foronConflict parameter');
        end if;
    end if;


    result = format(
        'insert into %I as %I (%s) values (%s) %s returning %s;',
        entity,
        block_name,
        column_clause,
        values_clause,
        on_conflict_clause,
        coalesce(returning_clause, 'null')
    );
    return result;
end;
$$;
