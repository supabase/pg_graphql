create or replace function graphql.to_column_orders(
    order_by_arg jsonb,
    entity regclass,
    variables jsonb default '{}'
)
    returns graphql.column_order_w_type[]
    language plpgsql
    immutable
    as
$$
declare
    pkey_ordering graphql.column_order_w_type[] = array_agg((column_name, 'asc', false, y.column_type))
        from
            unnest(graphql.primary_key_columns(entity)) with ordinality x(column_name, ix)
            join unnest(graphql.primary_key_types(entity)) with ordinality y(column_type, ix)
                on x.ix = y.ix;
    claues text;
    variable_value jsonb;

    variable_ordering graphql.column_order_w_type[];
begin
    -- No order by clause was specified
    if order_by_arg is null then
        return pkey_ordering;

    elsif (order_by_arg -> 'value' ->> 'kind') = 'Variable' then
        -- Expect [{"fieldName", "DescNullsFirst"}]
        variable_value = variables -> (order_by_arg -> 'value' -> 'name' ->> 'value');

        if jsonb_typeof(variable_value) <> 'array' or jsonb_array_length(variable_value) = 0 then
            return graphql.exception('Invalid value for ordering variable');
        end if;

        return array_agg(
            (
                case
                    when f.column_name is null then graphql.exception('Invalid list entry field name for order clause')
                    when f.column_name is not null then f.column_name
                    else graphql.exception_unknown_field(x.key_, t.name)
                end,
                case when x.val_ like 'Asc%' then 'asc' else 'desc' end, -- asc or desc
                case when x.val_ like '%First' then true else false end, -- nulls_first?
                f.column_type
            )::graphql.column_order_w_type
        ) || pkey_ordering
        from
            jsonb_array_elements(variable_value) jae(obj),
            lateral (
                select
                    jet.key_,
                    jet.val_
                from
                    jsonb_each_text( jae.obj )  jet(key_, val_)
            ) x
            join graphql.type t
                on t.entity = $2
                and t.meta_kind = 'Node'
            left join graphql.field f
                on t.name = f.parent_type
                and f.name = x.key_;

    elsif (order_by_arg -> 'value' ->> 'kind') = 'ListValue' then
        return (
            with obs as (
                select
                    *
                from
                    jsonb_array_elements( order_by_arg -> 'value' -> 'values') with ordinality oba(sel, ix)
            ),
            norm as (
                -- Literal
                select
                    ext.field_name,
                    ext.direction_val,
                    obs.ix,
                    case
                        when field_name is null then graphql.exception('Invalid order clause')
                        when direction_val is null then graphql.exception('Invalid order clause')
                        else null
                    end as errors
                from
                    obs,
                    lateral (
                        select
                            graphql.name_literal(sel -> 'fields' -> 0) field_name,
                            graphql.value_literal(sel -> 'fields' -> 0) direction_val
                    ) ext
                where
                    not graphql.is_variable(obs.sel)
                union all
                -- Variable
                select
                    v.field_name,
                    v.direction_val,
                    obs.ix,
                    case
                        when v.field_name is null then graphql.exception('Invalid order clause')
                        when v.direction_val is null then graphql.exception('Invalid order clause')
                        else null
                    end as errors
                from
                    obs,
                    lateral (
                        select
                            field_name,
                            direction_val
                        from
                            jsonb_each_text(
                                case jsonb_typeof(variables -> graphql.name_literal(obs.sel))
                                    when 'object' then variables -> graphql.name_literal(obs.sel)
                                    else graphql.exception('Invalid order clause')::jsonb
                                end
                            ) jv(field_name, direction_val)
                        ) v
                where
                    graphql.is_variable(obs.sel)
            )
            select
                array_agg(
                    (
                        f.column_name,
                        case when norm.direction_val like 'Asc%' then 'asc' else 'desc' end, -- asc or desc
                        case when norm.direction_val like 'First%' then true else false end, -- nulls_first?
                        f.column_type
                    )::graphql.column_order_w_type
                    order by norm.ix asc
                ) || pkey_ordering
            from
                norm
                join graphql.type t
                    on t.entity = $2
                    and t.meta_kind = 'Node'
                left join graphql.field f
                    on t.name = f.parent_type
                    and f.name = norm.field_name
        );

    else
        return graphql.exception('Invalid type for order clause');
    end if;
end;
$$;
