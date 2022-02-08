create or replace function graphql.resolve_field(field text, parent_type text, parent_arg_field_id integer, ast jsonb)
    returns jsonb
    stable
    language plpgsql
as $$
declare
    field_rec graphql.field;
    field_recs graphql.field[];
begin
    field_recs = array_agg(gf)
        from
            graphql.field gf
        where
            gf.name = $1
            and gf.parent_type = $2
            and (
                (gf.parent_arg_field_id is null and $3 is null)
                or gf.parent_arg_field_id = $3
            )
            limit 1;

    field_rec = graphql.array_first(field_recs);

    return
        coalesce(
            jsonb_object_agg(
                fa.field_alias,
                case
                    when selection_name = 'name' then to_jsonb(field_rec.name)
                    when selection_name = 'description' then to_jsonb(field_rec.description)
                    when selection_name = 'isDeprecated' then to_jsonb(false) -- todo
                    when selection_name = 'deprecationReason' then to_jsonb(null::text) -- todo
                    when selection_name = 'type' then graphql."resolve___Type"(
                                                            field_rec.type_,
                                                            x.sel,
                                                            field_rec.is_array_not_null,
                                                            field_rec.is_array,
                                                            field_rec.is_not_null
                    )
                    when selection_name = 'args' then (
                        select
                            coalesce(
                                jsonb_agg(
                                    graphql.resolve_field(
                                        ga.name,
                                        field_rec.type_,
                                        field_rec.id,
                                        x.sel
                                    )
                                    order by
                                        ga.column_attribute_num,
                                        case ga.name
                                            when 'first' then 80
                                            when 'last' then 81
                                            when 'before' then 82
                                            when 'after' then 83
                                            when 'after' then 83
                                            when 'filter' then 95
                                            when 'orderBy' then 96
                                            when 'atMost' then 97
                                            else 0
                                        end,
                                        ga.name
                                ),
                                '[]'
                            )
                        from
                            graphql.field ga
                        where
                            ga.parent_arg_field_id = field_rec.id
                            and not ga.is_hidden_from_schema
                            and ga.is_arg
                            and ga.parent_type = field_rec.type_
                    )
                    -- INPUT_OBJECT types only
                    when selection_name = 'defaultValue' then to_jsonb(field_rec.default_value)
                    else graphql.exception_unknown_field(selection_name, field_rec.type_)::jsonb
                end
            ),
            'null'::jsonb
        )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel),
        lateral (
            select
                graphql.alias_or_name_literal(x.sel) field_alias,
                graphql.name_literal(x.sel) as selection_name
        ) fa;
end;
$$;
