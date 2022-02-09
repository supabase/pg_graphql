create or replace function graphql.order_by_clause(
    order_by_arg jsonb,
    entity regclass,
    alias_name text,
    reverse bool default false,
    variables jsonb default '{}'
)
    returns text
    language plpgsql
    immutable
    as
$$
declare
    claues text;
    variable_value jsonb;
begin
    -- No order by clause was specified
    if order_by_arg is null then
        return graphql.primary_key_clause(entity, alias_name) || case when reverse then ' desc' else ' asc' end;
        -- todo handle no primary key
    end if;

    if (order_by_arg -> 'value' ->> 'kind') = 'Variable' then

        -- Expect [{"fieldName", "DescNullsFirst"}]
        variable_value = variables -> (order_by_arg -> 'value' -> 'name' ->> 'value');

        if jsonb_typeof(variable_value) <> 'array' or jsonb_array_length(variable_value) = 0 then
            return graphql.exception('Invalid value for ordering variable');
        end if;

        -- name of the variable
        return string_agg(
            format(
                '%I.%I %s',
                alias_name,
                case
                    when f.column_name is null then graphql.exception('Invalid list entry field name for order clause')
                    when f.column_name is not null then f.column_name
                    else graphql.exception_unknown_field(x.key_, t.name)
                end,
                graphql.order_by_enum_to_clause(val_)
            ),
            ', '
        )
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
                string_agg(
                    format(
                        '%I.%I %s',
                        alias_name,
                        case
                            when f.column_name is not null then f.column_name
                            else graphql.exception('Invalid order clause')
                        end,
                        graphql.order_by_enum_to_clause(norm.direction_val)
                    ),
                    ', '
                    order by norm.ix asc
                )
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
