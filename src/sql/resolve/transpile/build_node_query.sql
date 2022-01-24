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
    nodeId text = graphql.arg_clause('nodeId', (ast -> 'arguments'), variable_definitions, type_.entity);
    result text;
begin
    return
        E'(\nselect\njsonb_build_object(\n'
        || string_agg(quote_literal(graphql.alias_or_name_literal(x.sel)) || E',\n' ||
            case
                when nf.column_name is not null then (quote_ident(block_name) || '.' || quote_ident(nf.column_name))
                when nf.name = '__typename' then quote_literal(type_.name)
                when nf.name = 'nodeId' then graphql.cursor_encoded_clause(type_.entity, block_name)
                when nf.local_columns is not null and nf_t.meta_kind = 'Connection' then graphql.build_connection_query(
                    ast := x.sel,
                    variable_definitions := variable_definitions,
                    variables := variables,
                    parent_type := field.type_,
                    parent_block_name := block_name
                )
                when nf.local_columns is not null and nf_t.meta_kind = 'Node' then graphql.build_node_query(
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
        %I as %s
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
    case
        when nodeId is null then 'true'
        else graphql.cursor_row_clause(type_.entity, block_name)
    end,
    case
        when nodeId is null then 'true'
        else nodeId
    end
    )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel)
        left join graphql.field nf
            on nf.parent_type = field.type_
            and graphql.name_literal(x.sel) = nf.name
        left join graphql.type nf_t
            on nf.type_ = nf_t.name
    where
        field.name = graphql.name_literal(ast)
        and $4 = field.parent_type;
end;
$$;
