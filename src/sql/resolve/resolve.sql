create type graphql.operation as enum ('query', 'mutation');


create or replace function graphql.resolve(stmt text, variables jsonb = '{}')
    returns jsonb
    volatile
    strict
    language plpgsql
as $$
declare
    ---------------------
    -- Always required --
    ---------------------
    parsed graphql.parse_result = graphql.parse(stmt);
    ast jsonb = parsed.ast;
    variable_definitions jsonb = coalesce(graphql.variable_definitions_sort(ast -> 'definitions' -> 0 -> 'variableDefinitions'), '[]');

    prepared_statement_name text = graphql.cache_key(current_user::regrole, ast, variables);

    q text;
    data_ jsonb;
    errors_ text[] = case when parsed.error is null then '{}' else array[parsed.error] end;

    operation graphql.operation;

    ---------------------
    -- If not in cache --
    ---------------------

    -- AST without location info ("loc" key)
    ast_locless jsonb;

    -- ast with fragments inlined
    fragment_definitions jsonb;
    ast_inlined jsonb;
    ast_operation jsonb;

    meta_kind graphql.meta_kind;
    field_meta_kind graphql.field_meta_kind;

    -- Exception stack
    error_message text;
begin
    -- Build query if not in cache
    if errors_ = '{}' and not graphql.prepared_statement_exists(prepared_statement_name) then

        begin

            ast_locless = graphql.ast_pass_strip_loc(ast);
            fragment_definitions = jsonb_path_query_array(ast_locless, '$.definitions[*] ? (@.kind == "FragmentDefinition")');
            -- Skip fragment inline when no fragments are present
            ast_inlined = case
                when fragment_definitions = '[]'::jsonb then ast_locless
                else graphql.ast_pass_fragments(ast_locless, fragment_definitions)
            end;

            -- Query or Mutation?
            operation = ast_inlined -> 'definitions' -> 0 ->> 'operation';
            ast_operation = ast_inlined -> 'definitions' -> 0 -> 'selectionSet' -> 'selections' -> 0;

            if operation = 'mutation' then
                field_meta_kind = f.meta_kind
                    from
                        graphql.field f
                    where
                        f.parent_type = 'Mutation'
                        and f.name = graphql.name_literal(ast_operation);

                q = case field_meta_kind
                    when 'Mutation.upsert.one' then
                        graphql.build_upsert(
                            ast := ast_operation,
                            variable_definitions := variable_definitions,
                            variables := variables
                        )
                    else graphql.exception(field_meta_kind::text) --null::text
                end;

            elsif operation = 'query' then

                meta_kind = type_.meta_kind
                    from
                        graphql.field
                        join graphql.type type_
                            on field.type_ = type_.name
                    where
                        field.parent_type = 'Query'
                        and field.name = graphql.name_literal(ast_operation);

                q = case meta_kind
                    when 'Connection' then
                        graphql.build_connection_query(
                            ast := ast_operation,
                            variable_definitions := variable_definitions,
                            variables := variables,
                            parent_type :=  'Query',
                            parent_block_name := null
                        )
                    when 'Node' then
                        graphql.build_node_query(
                            ast := ast_operation,
                            variable_definitions := variable_definitions,
                            variables := variables,
                            parent_type := 'Query',
                            parent_block_name := null
                        )
                    else null::text
                end;

                data_ = case meta_kind
                    when '__Schema' then
                        graphql."resolve___Schema"(
                            ast := ast_operation,
                            variable_definitions := variable_definitions
                        )
                    when '__Type' then
                        jsonb_build_object(
                            graphql.name_literal(ast_operation),
                            graphql."resolve___Type"(
                                (
                                    select
                                        name
                                    from
                                        graphql.type type_
                                    where
                                        name = graphql.argument_value_by_name('name', ast_operation)
                                ),
                                ast_operation
                            )
                        )
                    else null::jsonb
                end;
            end if;

        /*
        exception when others then
            -- https://stackoverflow.com/questions/56595217/get-error-message-from-error-code-postgresql
            get stacked diagnostics error_message = MESSAGE_TEXT;
            errors_ = errors_ || error_message;
        */
        end;

    end if;

    if errors_ = '{}' and q is not null then
        execute graphql.prepared_statement_create_clause(prepared_statement_name, variable_definitions, q);
    end if;

    if errors_ = '{}' and data_ is null then
        begin
            -- Call prepared statement respecting passed values and variable definition defaults
            execute graphql.prepared_statement_execute_clause(prepared_statement_name, variable_definitions, variables) into data_;
            data_ = jsonb_build_object(
                graphql.alias_or_name_literal(ast -> 'definitions' -> 0 -> 'selectionSet' -> 'selections' -> 0),
                data_
            );
        exception when others then
            -- https://stackoverflow.com/questions/56595217/get-error-message-from-error-code-postgresql
            get stacked diagnostics error_message = MESSAGE_TEXT;
            errors_ = errors_ || error_message;
        end;
    end if;

    return jsonb_build_object(
        'data', data_,
        'errors', to_jsonb(errors_)
    );
end
$$;
