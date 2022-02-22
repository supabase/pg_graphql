create or replace function graphql.build_node_query(
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
    block_name text = graphql.slug();
    field graphql.field = gf from graphql.field gf where gf.name = graphql.name_literal(ast) and gf.parent_type = $4;
    type_ graphql.type = gt from graphql.type gt where gt.name = field.type_;
    result text;
begin
    return
        E'(\nselect\njsonb_build_object(\n'
        || string_agg(quote_literal(graphql.alias_or_name_literal(x.sel)) || E',\n' ||
            case
                when nf.column_name is not null and nf.column_type = 'bigint'::regtype then format('(%I.%I)::text', block_name, nf.column_name)
                when nf.column_name is not null then format('%I.%I', block_name, nf.column_name)
                when nf.meta_kind = 'Function' then format('%I(%I)', nf.func, block_name)
                when nf.name = '__typename' then quote_literal(type_.name)
                when nf.local_columns is not null and nf.meta_kind = 'Relationship.toMany' then graphql.build_connection_query(
                    ast := x.sel,
                    variable_definitions := variable_definitions,
                    variables := variables,
                    parent_type := field.type_,
                    parent_block_name := block_name
                )
                when nf.local_columns is not null and nf.meta_kind = 'Relationship.toOne' then graphql.build_node_query(
                    ast := x.sel,
                    variable_definitions := variable_definitions,
                    variables := variables,
                    parent_type := field.type_,
                    parent_block_name := block_name
                )
                else graphql.exception_unknown_field(graphql.name_literal(x.sel), field.type_)
            end,
            E',\n'
        )
        || ')'
        || format('
    from
        %s as %s
    where
        true
        -- join clause
        and %s
        -- filter clause
        and %s = %s
    limit 1
)
',
    type_.entity,
    quote_ident(block_name),
    coalesce(graphql.join_clause(field.local_columns, block_name, field.foreign_columns, parent_block_name), 'true'),
    'true',
    'true'
    )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel)
        left join graphql.field nf
            on nf.parent_type = field.type_
            and graphql.name_literal(x.sel) = nf.name
    where
        field.name = graphql.name_literal(ast)
        and $4 = field.parent_type;
end;
$$;
