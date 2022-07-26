create or replace function graphql.build_enum_values_query(
    ast jsonb,
    type_block_name text
)
    returns text
    language plpgsql
    stable
as $$
declare
begin
    return
        format('
            (
                select
                    coalesce(
                        jsonb_agg(
                            jsonb_build_object(%s)
                        ),
                        jsonb_build_array()
                    )
                from
                    graphql.enum_value ev
                where
                    ev.type_ = %I.name
            )',
            string_agg(
                format('%L, %s',
                    graphql.alias_or_name_literal(x.sel),
                    case graphql.name_literal(x.sel)
                        when 'name' then 'ev.value'
                        when 'description' then 'ev.description'
                        when 'isDeprecated' then 'false'
                        when 'deprecationReason' then 'null'
                        else graphql.exception('Invalid field for type __EnumValue')
                    end
                ),
                ', '
            ),
            type_block_name
        )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel);
end
$$;
