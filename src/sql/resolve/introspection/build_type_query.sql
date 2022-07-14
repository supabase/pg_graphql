create or replace function graphql.build_type_query_core_selects(
    ast jsonb
)
    returns text
    language sql
    immutable
as $$
    select format(
        'jsonb_build_object(%s)',
        string_agg(
            format('%L, %s',
                graphql.alias_or_name_literal(x.sel),
                case graphql.name_literal(x.sel)
                    when 'name' then 'name'
                    when 'description' then 'description'
                    when 'specifiedByURL' then 'null::text'
                    when 'kind' then 'type_kind::text'
                    when 'fields' then 'null' -- todo
                    when 'interfaces' then format('
                        case
                            when type_kind = %L then to_jsonb(null::text)
                            when type_kind = %L then to_jsonb(null::text)
                            when meta_kind = %L then to_jsonb(null::text)
                            else jsonb_build_array()
                        end',
                        'SCALAR',
                        'INTERFACE',
                        'Cursor'
                    )
                    when 'possibleTypes' then 'null'
                    when 'enumValues' then 'null' --todo
                    when 'inputFields' then 'null' --todo
                    when 'ofType' then 'null'
                    else graphql.exception('Invalid field for type __Type')
                end
            ),
            ', '
        )
    )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel);
$$;

/*

create or replace function graphql.build_type_query_wrapper_selects(
    ast jsonb,
    kind text, -- NON_NULL or LIST
    of_type_selects text
)
    returns text
    language sql
    immutable
as $$
    select format(
        'jsonb_build_object(%s)',
        string_agg(
            format('%L, %s',
                graphql.alias_or_name_literal(x.sel),
                case graphql.name_literal(x.sel)
                    when 'kind' then format('%L', kind)
                    when 'ofType' then of_type_selects
                    when 'name' then 'null'
                    when 'description' then 'null'
                    when 'specifiedByURL' then 'null'
                    when 'fields' then 'null'
                    when 'interfaces' then 'null'
                    when 'possibleTypes' then 'null'
                    when 'enumValues' then 'null'
                    else graphql.exception('Invalid field for type __Type')
                end
            ),
            ', '
        )
    )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel);

$$;



create or replace function graphql.build_type_query_in_field_context(
    ast jsonb,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}',
)
    returns text
    language plpgsql
    stable
as $$
declare
    block_name text = graphql.slug();

    of_type_ast jsonb = jsonb_path_query(ast, '$.selectionSet.selections[*] ? (@.name.value == "ofKind")') -> 0;
    of_type_of_type_ast jsonb = jsonb_path_query(of_type_ast, '$.selectionSet.selections[*] ? (@.name.value == "ofKind")') -> 0;
    of_type_of_type_of_type_ast jsonb = jsonb_path_query(of_type_of_type_ast, '$.selectionSet.selections[*] ? (@.name.value == "ofKind")') -> 0;

begin

    return
        format('
            (
                select
                    case
                        when is_array_not_null and is_array and is_not_null then %s
                        when is_array and is_not_null then %s
                        when is_not_null then %s
                        when is_array then %s
                        else %s
                    end
                from
                    graphql.type as %I
                where
                    not is_hidden_from_schema
            )',
            graphql.build_type_query_wrapper_selects(
                ast,
                $a$NON_NULL$a$,
                graphql.build_type_query_wrapper_selects(
                    of_type_ast,
                    $a$LIST$a$,
                    graphql.build_type_query_wrapper_selects(
                        of_type_of_type_ast,
                        $a$NON_NULL$a$,
                        graphql.build_type_query_core_selects(
                            of_type_of_type_of_type_ast
                        )
                    )
                )
            ),
            graphql.build_type_query_wrapper_selects(
                ast,
                $a$LIST$a$,
                graphql.build_type_query_wrapper_selects(
                    of_type_ast,
                    $a$NON_NULL$a$,
                    graphql.build_type_query_core_selects(
                        of_type_of_type_ast
                    )
                )
            ),
            graphql.build_type_query_wrapper_selects(
                ast,
                $a$NON_NULL$a$,
                graphql.build_type_query_core_selects(
                    of_type_ast
                )
            ),
            graphql.build_type_query_wrapper_selects(
                ast,
                $a$LIST$a$,
                graphql.build_type_query_core_selects(
                    of_type_ast
                )
            ),
            graphql.build_type_query_core_selects(
                ast
            ),
            block_name
        );
end
$$;
*/
