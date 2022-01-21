create or replace function graphql.resolve_field(field text, parent_type text, parent_arg_field_name text, ast jsonb)
    returns jsonb
    stable
    language plpgsql
as $$
declare
    field_rec graphql.field;
    field_recs graphql.field[];
begin
    -- todo can this conflict for input types?
    field_recs = array_agg(gf)
        from
            graphql.field gf
        where
            gf.name = $1
            and gf.parent_type = $2
            and coalesce(gf.parent_arg_field_name, '') = coalesce($3, '')
            limit 1;

    if array_length(field_recs, 1) > 1 then
        raise exception '% % %', $1, $2, $3;
    end if;

    field_rec = graphql.array_first(field_recs);

    if field_rec is null then
        raise exception '% % %', $1, $2, $3;

    end if;

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
                                        field_rec.name,
                                        x.sel
                                    )
                                    order by ga.name
                                ),
                                '[]'
                            )
                        from
                            graphql.field ga
                        where
                            ga.parent_arg_field_name = field_rec.name
                            and not ga.is_hidden_from_schema
                            and ga.is_arg
                            and ga.parent_type = field_rec.type_ -- todo double check this join
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
