create or replace function graphql.build_insert(
    ast jsonb,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}',
    parent_type text = null
)
    returns text
    language plpgsql
as $$
declare
    result text;
    entity_clause text = '';
    columns_clause text = '';
    values_clause text = '';
begin
    result = format(
        'insert into %I(%s) values (%s);',
        entity_clause,
        columns_clause,
        values_clause
    );

    raise exception '%s', ast;

    return result;
end;
$$;
