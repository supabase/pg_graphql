create or replace function graphql.resolve(
    query text = null,
    variables jsonb = '{}',
    "operationName" text = null,
    extensions jsonb = null
)
    returns jsonb
    volatile
    language plpgsql
as $$
declare
    ---------------------
    -- Always required --
    ---------------------
    parsed graphql.parse_result = graphql.parse(coalesce(query, ''));
    ast jsonb = parsed.ast;


    n_operation_defs int = jsonb_array_length(
        jsonb_path_query_array(
            ast,
            '$.definitions[*] ? (@.kind == "OperationDefinition")'
        )
    );

    -- AST for the operation part of the def, not e.g. fragments
    ast_operation jsonb = case
        when "operationName" is not null then jsonb_path_query_first(
            ast,
            '$.definitions[*] ? (@.kind == "OperationDefinition" && @.name.value == $op_name)',
            jsonb_build_object(
                'op_name',
                "operationName"
            )
        )
        when n_operation_defs = 1 then jsonb_path_query_first(
            ast,
            '$.definitions[*] ? (@.kind == "OperationDefinition")'
        )
        else null
    end;

    n_statements int = jsonb_array_length(ast_operation -> 'selectionSet' -> 'selections');

    variable_definitions jsonb = coalesce(graphql.variable_definitions_sort(ast_operation -> 'variableDefinitions'), '[]');

    -- Query or Mutation?
    operation graphql.meta_kind = (
        case (ast_operation ->> 'operation')
            when 'mutation' then 'Mutation'
            when 'query' then 'Query'
        end
    );

    prepared_statement_name text;

    q text;
    data_ jsonb;
    request_data jsonb;
    errors_ jsonb[] = case
        when parsed.error is not null then array[jsonb_build_object('message', parsed.error)]
        when ast_operation is null then array[jsonb_build_object('message', 'unknown operation')]
        else '{}'
    end;

    ---------------------
    -- If not in cache --
    ---------------------

    -- AST without location info ("loc" key)
    ast_statement jsonb;
    ast_locless jsonb;

    -- ast with fragments inlined
    fragment_definitions jsonb;
    ast_inlined jsonb;

    meta_kind graphql.meta_kind;
    field_meta_kind graphql.field_meta_kind;

    -- Exception stack
    error_message text;
begin


    if errors_ <> '{}' then
       -- If an error was encountered before execution begins, the data entry should not be present in the result.
       return jsonb_build_object(
        'errors', to_jsonb(errors_)
       );
    end if;

    begin

        -- Build query if not in cache
        for statement_ix in 0..(n_statements - 1) loop

            ast_statement = (
                 ast_operation -> 'selectionSet' -> 'selections' -> statement_ix
            );

            prepared_statement_name = (
                case
                    when operation = 'Query' then graphql.cache_key(current_user::regrole, ast_statement, variables)
                    -- If not a query (mutation) don't attempt to cache
                    else md5(format('%s%s%s',random(),random(),random()))
                end
            );

            if errors_ = '{}' and not graphql.prepared_statement_exists(prepared_statement_name) then

                    ast_locless = graphql.ast_pass_strip_loc(ast_statement);
                    fragment_definitions = graphql.ast_pass_strip_loc(
                        jsonb_path_query_array(ast, '$.definitions[*] ? (@.kind == "FragmentDefinition")')
                    );
                    -- Skip fragment inline when no fragments are present
                    ast_inlined = case
                        when fragment_definitions = '[]'::jsonb then ast_locless
                        else graphql.ast_pass_fragments(ast_locless, fragment_definitions)
                    end;

                    field_meta_kind = f.meta_kind
                        from
                            graphql.field f
                        where
                            f.parent_type = operation::text
                            and f.name = graphql.name_literal(ast_inlined);

                    if field_meta_kind is null then
                        perform graphql.exception_unknown_field(
                            graphql.name_literal(ast_inlined),
                            operation::text
                        );
                    end if;

                    q = case field_meta_kind
                        when 'Mutation.insert' then
                            graphql.build_insert(
                                ast := ast_inlined,
                                variable_definitions := variable_definitions,
                                variables := variables
                            )
                        when 'Mutation.delete' then
                            graphql.build_delete(
                                ast := ast_inlined,
                                variable_definitions := variable_definitions,
                                variables := variables
                            )
                        when 'Mutation.update' then
                            graphql.build_update(
                                ast := ast_inlined,
                                variable_definitions := variable_definitions,
                                variables := variables
                            )
                        when 'Query.collection' then
                                graphql.build_connection_query(
                                    ast := ast_inlined,
                                    variable_definitions := variable_definitions,
                                    variables := variables,
                                    parent_type :=  'Query',
                                    parent_block_name := null
                                )
                        when 'Query.heartbeat' then graphql.build_heartbeat_query(ast_inlined)
                        when '__Typename' then format(
                            $typename_stmt$ select to_jsonb(%L::text) $typename_stmt$,
                            (
                                select
                                    f.parent_type
                                from
                                    graphql.field f
                                where
                                    f.parent_type = operation::text
                                    and f.name = graphql.name_literal(ast_inlined)
                                limit 1
                            )
                        )
                    end;

                    if q is null and operation = 'Query' then

                        meta_kind = type_.meta_kind
                            from
                                graphql.field
                                join graphql.type type_
                                    on field.type_ = type_.name
                            where
                                field.parent_type = 'Query'
                                and field.name = graphql.name_literal(ast_inlined);

                        if meta_kind is null then
                            perform graphql.exception_unknown_field(
                                graphql.name_literal(ast_inlined),
                                'Query'
                            );
                        end if;

                        data_ = case meta_kind
                            when '__Schema' then
                                graphql."resolve___Schema"(
                                    ast := ast_inlined,
                                    variable_definitions := variable_definitions
                                )
                            when '__Type' then
                                jsonb_build_object(
                                    graphql.alias_or_name_literal(ast_statement),
                                    graphql."resolve___Type"(
                                        (
                                            select
                                                name
                                            from
                                                graphql.type type_
                                            where
                                                name = graphql.argument_value_by_name('name', ast_inlined)
                                        ),
                                        ast_inlined
                                    )
                                )
                            else null::jsonb
                        end;
                    end if;
            end if;

            if errors_ = '{}' and q is not null then
                execute graphql.prepared_statement_create_clause(prepared_statement_name, variable_definitions, q);
            end if;

            if errors_ = '{}' and data_ is null then
                -- Call prepared statement respecting passed values and variable definition defaults
                execute graphql.prepared_statement_execute_clause(prepared_statement_name, variable_definitions, variables) into data_;
                data_ = jsonb_build_object(
                    graphql.alias_or_name_literal(ast_statement),
                    data_
                );
            end if;

            -- Add data to final state
            request_data = case
                when request_data is null then data_
                else request_data || data_
            end;

            -- reset loop vars
            q = null;
            data_ = null;

        end loop;

    exception when others then
        get stacked diagnostics error_message = MESSAGE_TEXT;
        errors_ = errors_ || jsonb_build_object('message', error_message);
        -- Do no show partial or rolled back results
        request_data = null;
    end;


    return (
        -- If no errors were encountered during the requested operation, the errors entry should not be present in the result.
        jsonb_build_object('data', request_data)
        || case
           when errors_ <> '{}' then jsonb_build_object(
                'errors', to_jsonb(errors_),
                -- If an error was encountered during the execution that prevented a valid response, the data entry in the response should be null
                'data', null::text
            )
            else  '{}'
        end
    );
end
$$;
