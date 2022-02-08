create or replace function graphql."resolve_enumValues"(type_ text, ast jsonb)
    returns jsonb
    stable
    language sql
as $$
    -- todo: remove overselection
    select
        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'name', value::text,
                    'description', null::text,
                    'isDeprecated', false,
                    'deprecationReason', null
                )
            ),
            jsonb_build_array()
        )
    from
        graphql.enum_value ev where ev.type_ = $1;
$$;
