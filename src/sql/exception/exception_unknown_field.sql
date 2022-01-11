create or replace function graphql.exception_unknown_field(field_name text, type_name text)
    returns text
    language plpgsql
as $$
begin
    raise exception using errcode='22000', message=format('Unknown field %L on type %L', field_name, type_name);
end;
$$;
