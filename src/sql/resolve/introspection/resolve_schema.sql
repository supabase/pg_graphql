create or replace function graphql."resolve___Schema"(
    ast jsonb,
    variable_definitions jsonb = '[]'
)
    returns jsonb
    stable
    language plpgsql
    as $$
declare
    node_fields jsonb = jsonb_path_query(ast, '$.selectionSet.selections');
    node_field jsonb;
    node_field_rec graphql.field;
    agg jsonb = '{}';
begin
    --field_rec = "field" from graphql.field where parent_type = '__Schema' and name = field_name;

    for node_field in select * from jsonb_array_elements(node_fields) loop
        node_field_rec = "field" from graphql.field where parent_type = '__Schema' and name = graphql.name_literal(node_field);

        if graphql.name_literal(node_field) = 'description' then
            agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), node_field_rec.description);
        elsif node_field_rec.type_ = '__Directive' then
            -- TODO
            agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), '[]'::jsonb);

        elsif node_field_rec.name = 'queryType' then
            agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), graphql."resolve_queryType"(node_field));

        elsif node_field_rec.name = 'mutationType' then
            agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), 'null'::jsonb);

        elsif node_field_rec.name = 'subscriptionType' then
            agg = agg || jsonb_build_object(graphql.alias_or_name_literal(node_field), null);

        elsif node_field_rec.name = 'types' then
            agg = agg || (
                with uq as (
                    select
                        distinct gt.name
                    from
                        graphql.type gt
                        -- Filter out object types with no fields
                        join (select distinct parent_type from graphql.field) gf
                            on gt.name = gf.parent_type
                            or gt.type_kind not in ('OBJECT', 'INPUT_OBJECT')
                )
                select
                    jsonb_build_object(
                        graphql.alias_or_name_literal(node_field),
                        jsonb_agg(graphql."resolve___Type"(uq.name, node_field) order by uq.name)
                    )
                from uq
            );

        elsif node_field_rec.type_ = '__Type' and not node_field_rec.is_array then
            agg = agg || graphql."resolve___Type"(
                node_field_rec.type_,
                node_field,
                node_field_rec.is_array_not_null,
                node_field_rec.is_array,
                node_field_rec.is_not_null
            );

        else
            raise 'Invalid field for type __Schema: "%"', graphql.name_literal(node_field);
        end if;
    end loop;

    return jsonb_build_object(graphql.alias_or_name_literal(ast), agg);
end
$$;
