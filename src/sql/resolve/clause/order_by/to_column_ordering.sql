create or replace function graphql.to_column_orders(
    order_by_arg jsonb, -- Ex: [{"id": "AscNullsLast"}, {"name": "DescNullsFirst"}]
    entity regclass,
    variables jsonb default '{}'
)
    returns graphql.column_order_w_type[]
    language plpgsql
    immutable
    as
$$
declare
    pkey_ordering graphql.column_order_w_type[] = array_agg(
            (column_name, 'asc', false, y.column_type)::graphql.column_order_w_type
        )
        from
            unnest(graphql.primary_key_columns(entity)) with ordinality x(column_name, ix)
            join unnest(graphql.primary_key_types(entity)) with ordinality y(column_type, ix)
                on x.ix = y.ix;
begin

    -- No order by clause was specified
    if order_by_arg is null then
        return pkey_ordering;
    end if;

    return array_agg(
        (
            case
                when f.column_name is null then graphql.exception(
                    'Invalid list entry field name for order clause'
                )
                when f.column_name is not null then f.column_name
                else graphql.exception_unknown_field(x.key_, t.name)
            end,
            case when x.val_ like 'Asc%' then 'asc' else 'desc' end, -- asc or desc
            case when x.val_ like '%First' then true else false end, -- nulls_first?
            f.column_type
        )::graphql.column_order_w_type
    ) || pkey_ordering
    from
        jsonb_array_elements(order_by_arg) jae(obj),
        lateral (
            select
                case jsonb_typeof(jae.obj)
                    when 'object' then ''
                    else graphql.exception('Invalid order clause')
                end
        ) _validate_elem_is_object, -- unused
        lateral (
            select
                jet.key_,
                case
                    when jet.val_ in (
                        'AscNullsFirst',
                        'AscNullsLast',
                        'DescNullsFirst',
                        'DescNullsLast'
                    ) then jet.val_
                    else graphql.exception('Invalid order clause')
                end as val_
            from
                jsonb_each_text( jae.obj )  jet(key_, val_)
        ) x
        join graphql.type t
            on t.entity = $2
            and t.meta_kind = 'Node'
        left join graphql.field f
            on t.name = f.parent_type
            and f.name = x.key_;
end;
$$;
