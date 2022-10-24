create or replace function graphql.exception(message text)
    returns text
    language plpgsql
as $$
begin
    raise exception using errcode='22000', message=message;
end;
$$;

create or replace function graphql.sequential_executor(prepared_statement_names text[])
    returns jsonb
    language plpgsql
    volatile
as $$
declare
    res jsonb[] = array[]::jsonb[];
    res_element jsonb;
    error_message text;
    errors_ text[] = array[]::text[];
    prepared_statement_name text;
    statement_parameters text[];
begin
    begin
        for ix IN 1 .. array_upper(prepared_statement_names, 1) loop
             -- Disallow whitespace. Prepared statement names only.
            if prepared_statement_names[ix] ~ '\s' then
                perform graphql.exception('Internal Error: Invalid input to sequential executor');
            end if;

            execute format('execute %s', prepared_statement_names[ix]) into res_element;
            res := res || res_element;
        end loop;
    exception when others then
        get stacked diagnostics error_message = MESSAGE_TEXT;
        errors_ = errors_ || error_message;
        -- Do no show partial or rolled back results
        res = null;
    end;

    -- Dellocate the prepared statements to limit build up
    for ix IN 1 .. array_upper(prepared_statement_names, 1) loop
        execute format('deallocate %s', prepared_statement_names[ix]);
    end loop;

    return jsonb_build_object(
        'statement_results', res,
        'errors',  errors_
    );

end
$$;
