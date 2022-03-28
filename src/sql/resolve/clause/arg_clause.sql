create or replace function graphql.arg_clause(name text, arguments jsonb, variable_definitions jsonb, entity regclass, default_value text = null)
    returns text
    immutable
    language plpgsql
as $$
declare
    arg jsonb = graphql.get_arg_by_name(name, graphql.jsonb_coalesce(arguments, '[]'));

    res text;

    cast_to regtype = case
        when name in ('first', 'last', 'atMost') then 'int'
        else 'text'
    end;

    var_ix int;
    var_name text;

begin
    if arg is null then
        return default_value;

    elsif graphql.is_variable(arg -> 'value') then

        -- variable name (if its a variable)
        var_name = graphql.name_literal(arg -> 'value');
        -- variable index (if its a variable)
        var_ix   = graphql.arg_index(var_name, variable_definitions);

        if var_ix is null then
            perform graphql.exception(format("unknown variable %s", var_name));
        end if;

        return format(
            '$%s::%s',
            var_ix,
            cast_to
        );

    -- Non-special literal
    else
        return
            format(
                '%L::%s',
                graphql.value_literal(arg),
                cast_to
            );
    end if;
end
$$;
