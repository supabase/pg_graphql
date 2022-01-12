create or replace function graphql.arg_clause(name text, arguments jsonb, variable_definitions jsonb, entity regclass)
    returns text
    immutable
    language plpgsql
as $$
declare
    arg jsonb = graphql.get_arg_by_name(name, graphql.jsonb_coalesce(arguments, '[]'));

    is_opaque boolean = name in ('nodeId', 'before', 'after');

    res text;

    cast_to text = case
        when name in ('first', 'last') then 'int'
        else 'text'
    end;

begin
    if arg is null then
        return null;

    elsif graphql.is_variable(arg -> 'value') and is_opaque then
        return graphql.cursor_clause_for_variable(entity, graphql.arg_index(name, variable_definitions));

    elsif is_opaque then
        return graphql.cursor_clause_for_literal(arg -> 'value' ->> 'value');


    -- Order by

    -- Non-special variable
    elsif graphql.is_variable(arg -> 'value') then
        return '$' || graphql.arg_index(name, variable_definitions)::text || '::' || cast_to;

    -- Non-special literal
    else
        return format('%L::%s', (arg -> 'value' ->> 'value'), cast_to);
    end if;
end
$$;
