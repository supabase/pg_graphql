create or replace function graphql."resolve___Type"(
    type_ text,
    ast jsonb,
    is_array_not_null bool = false,
    is_array bool = false,
    is_not_null bool = false
)
    returns jsonb
    stable
    language plpgsql
as $$
declare
begin
       return
        coalesce(
            jsonb_object_agg(
                fa.field_alias,
                case
                    when selection_name = 'name' and not has_modifiers then to_jsonb(gt.name::text)
                    when selection_name = 'description' and not has_modifiers then to_jsonb(gt.description::text)
                    when selection_name = 'specifiedByURL' and not has_modifiers then to_jsonb(null::text)
                    when selection_name = 'kind' then (
                        case
                            when is_array_not_null then to_jsonb('NON_NULL'::text)
                            when is_array then to_jsonb('LIST'::text)
                            when is_not_null then to_jsonb('NON_NULL'::text)
                            else to_jsonb(gt.type_kind::text)
                        end
                    )
                    when selection_name = 'fields' and not has_modifiers then (
                        select
                            jsonb_agg(graphql.resolve_field(f.name, f.parent_type, null, x.sel) order by f.name)
                        from
                            graphql.field f
                        where
                            f.parent_type = gt.name
                            and not f.is_hidden_from_schema
                            and gt.type_kind = 'OBJECT'
                            and not f.is_arg
                            --and gt.type_kind not in ('SCALAR', 'ENUM', 'INPUT_OBJECT')
                    )
                    when selection_name = 'interfaces' and not has_modifiers then (
                        case
                            -- Scalars get null, objects get an empty list. This is a poor implementation
                            -- when gt.meta_kind not in ('Interface', 'BUILTIN', 'CURSOR') then '[]'::jsonb
                            when gt.type_kind = 'SCALAR' then to_jsonb(null::text)
                            when gt.type_kind = 'INTERFACE' then to_jsonb(null::text)
                            when gt.meta_kind = 'Cursor' then to_jsonb(null::text)
                            else '[]'::jsonb
                        end
                    )
                    when selection_name = 'possibleTypes' and not has_modifiers then to_jsonb(null::text)
                    when selection_name = 'enumValues' then graphql."resolve_enumValues"(gt.name, x.sel)
                    when selection_name = 'inputFields' and not has_modifiers then (
                        select
                            jsonb_agg(graphql.resolve_field(f.name, f.parent_type, f.parent_arg_field_id, x.sel) order by f.name)
                        from
                            graphql.field f
                        where
                            f.parent_type = gt.name
                            and not f.is_hidden_from_schema
                            and gt.type_kind = 'INPUT_OBJECT'
                    )
                    when selection_name = 'ofType' then (
                        case
                            -- NON_NULL(LIST(...))
                            when is_array_not_null is true then graphql."resolve___Type"(type_, x.sel, is_array_not_null := false, is_array := is_array, is_not_null := is_not_null)
                            -- LIST(...)
                            when is_array then graphql."resolve___Type"(type_, x.sel, is_array_not_null := false, is_array := false, is_not_null := is_not_null)
                            -- NON_NULL(...)
                            when is_not_null then graphql."resolve___Type"(type_, x.sel, is_array_not_null := false, is_array := false, is_not_null := false)
                            -- TYPE
                            else null
                        end
                    )
                    else null
                end
            ),
            'null'::jsonb
        )
    from
        graphql.type gt
        join jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel)
            on true,
        lateral (
            select
                graphql.alias_or_name_literal(x.sel) field_alias,
                graphql.name_literal(x.sel) as selection_name
        ) fa,
        lateral (
            select (coalesce(is_array_not_null, false) or is_array or is_not_null) as has_modifiers
        ) hm
    where
        gt.name = type_;
end;
$$;
