create or replace function graphql.arg_to_jsonb(
    arg jsonb, -- has
    variables jsonb default '{}'
)
    returns jsonb
    language sql
    immutable
    as
$$
    select
        case arg ->> 'kind'
            when 'Argument'     then graphql.arg_to_jsonb(arg -> 'value', variables)
            when 'IntValue'     then to_jsonb((arg ->> 'value')::int)
            when 'FloatValue'   then to_jsonb((arg ->> 'value')::float)
            when 'BooleanValue' then to_jsonb((arg ->> 'value')::bool)
            when 'StringValue'  then to_jsonb(arg ->> 'value')
            when 'EnumValue'    then to_jsonb(arg ->> 'value')
            when 'ListValue'    then (
                select
                    jsonb_agg(
                        graphql.arg_to_jsonb(je.x, variables)
                    )
                from
                    jsonb_array_elements((arg -> 'values')) je(x)
            )
            when 'ObjectField'  then (
                jsonb_build_object(
                    arg -> 'name' -> 'value',
                    graphql.arg_to_jsonb(arg -> 'value', variables)
                )
            )
            when 'ObjectValue'  then (
                select
                    jsonb_object_agg(
                        je.elem -> 'name' ->> 'value',
                        graphql.arg_to_jsonb(je.elem -> 'value', variables)
                    )
                from
                    jsonb_array_elements((arg -> 'fields')) je(elem)
            )
            when 'Variable'     then (
                case
                    -- null value should be treated as missing in all cases.
                    when jsonb_typeof((variables -> (arg -> 'name' ->> 'value'))) = 'null' then null
                    else (variables -> (arg -> 'name' ->> 'value'))
                end
            )
        else (
            case
                when arg is null then null
                else  graphql.exception('unhandled argument kind')::jsonb
            end
        )
        end;
$$;


create or replace function graphql.arg_coerce_list(arg jsonb)
returns jsonb
    language sql
    immutable
    as
$$
    -- Wraps jsonb value with a list if its not already a list
    -- If null, returns null
    select
        case
            when jsonb_typeof(arg) is null then arg -- sql null
            when jsonb_typeof(arg) = 'null' then null-- json null
            when jsonb_typeof(arg) = 'array' then arg
            else jsonb_build_array(arg)
        end;
$$;
