create or replace function graphql.exception_required_argument(arg_name text)
    returns text
    language plpgsql
as $$
begin
    raise exception using errcode='22000', message=format('Argument %L is required', arg_name);
end;
$$;
