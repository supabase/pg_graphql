create or replace function graphql.build_field_on_type_query(
    ast jsonb,
    type_block_name text,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}',
    is_input_fields bool = false
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
                    jsonb_agg(jsonb_build_object(%s) order by %I.column_attribute_num, %I.name)
                from
                    graphql.field %I
                where
                    not %I.is_hidden_from_schema
                    and %I.parent_type =  %I.name
                    -- Toggle between fields and input fields
                    and case %L::bool
                        when false then %I.type_kind = $v$OBJECT$v$ and not %I.is_arg
                        else %I.type_kind = $v$INPUT_OBJECT$v$
                    end
                    and (
                        %I.meta_kind <> $v$Query.heartbeat$v$
                        or (
                            %I.meta_kind = $v$Query.heartbeat$v$
                            and not exists(
                                select
                                    1
                                from
                                    graphql.field gf
                                where
                                    gf.parent_type = $v$Query$v$
                                    and not gf.is_hidden_from_schema
                                    and gf.meta_kind <> $v$Query.heartbeat$v$
                            )
                        )
                    )
            )',
            string_agg(
                format('%L, %s',
                    graphql.alias_or_name_literal(x.sel),
                    case graphql.name_literal(x.sel)
                        when 'name' then 'name'
                        when 'description' then 'description'
                        when 'isDeprecated' then 'false'
                        when 'deprecationReason' then 'null'
                        when 'defaultValue' then 'default_value'
                        when 'type' then graphql.build_type_query_in_field_context(
                            ast:= x.sel,
                            field_block_name := block_name
                        )
                        when 'args' then graphql.build_args_on_field_query(
                            ast := x.sel,
                            field_block_name := block_name
                        )
                        else graphql.exception_unknown_field(graphql.name_literal(x.sel), '__Field')
                    end
                ),
                ', '
            ),
            block_name,
            block_name,
            block_name,
            block_name,
            block_name,
            type_block_name,
            is_input_fields,
            type_block_name,
            block_name,
            type_block_name,
            block_name,
            block_name
        )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel);
end
$$;



create or replace function graphql.build_args_on_field_query(
    ast jsonb,
    field_block_name text,
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
                    coalesce(
                        jsonb_agg(
                            jsonb_build_object(%s)
                             order by
                                %I.column_attribute_num,
                                case %I.name
                                    when $v$first$v$ then 80
                                    when $v$last$v$ then 81
                                    when $v$before$v$ then 82
                                    when $v$after$v$ then 83
                                    when $v$filter$v$ then 95
                                    when $v$orderBy$v$ then 96
                                    when $v$atMost$v$ then 97
                                    else 0
                                end,
                                %I.name
                            ),
                            $v$[]$v$
                        )
                from
                    graphql.field %I
                where
                    not %I.is_hidden_from_schema
                    and %I.parent_arg_field_id =  %I.id
            )',
            string_agg(
                format('%L, %s',
                    graphql.alias_or_name_literal(x.sel),
                    case graphql.name_literal(x.sel)
                        when 'name' then 'name'
                        when 'description' then 'description'
                        when 'isDeprecated' then 'false'
                        when 'deprecationReason' then 'null'
                        when 'defaultValue' then 'default_value'
                        when 'type' then graphql.build_type_query_in_field_context(
                            ast:= x.sel,
                            field_block_name := block_name
                        )
                        when 'args' then graphql.build_args_on_field_query(
                            ast := x.sel,
                            field_block_name := block_name
                        )
                        else graphql.exception_unknown_field(graphql.name_literal(x.sel), '__Field')
                    end
                ),
                ', '
            ),
            block_name,
            block_name,
            block_name,
            block_name,
            block_name,
            block_name,
            field_block_name
        )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel);
end
$$;
