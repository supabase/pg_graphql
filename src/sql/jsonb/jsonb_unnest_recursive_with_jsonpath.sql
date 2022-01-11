create or replace function graphql.jsonb_unnest_recursive_with_jsonpath(obj jsonb)
    returns table(jpath jsonpath, obj jsonb)
     language sql
as $$
/*
Recursively unrolls a jsonb object and arrays to scalars

    select
        *
    from
        graphql.jsonb_keys_recursive('{"id": [1, 2]}'::jsonb)


    | jpath   |       obj      |
    |---------|----------------|
    | $       | {"id": [1, 2]} |
    | $.id    | [1, 2]         |
    | $.id[0] | 1              |
    | $.id[1] | 2              |

*/
    with recursive _tree as (
        select
            obj,
            '$' as path_

        union all
        (
            with typed_values as (
                select
                    jsonb_typeof(obj) as typeof,
                    obj,
                    path_
                from
                    _tree
            )
            select
                v.val_,
                path_ || '.' || key_
            from
                typed_values,
                lateral jsonb_each(obj) v(key_, val_)
            where
                typeof = 'object'

            union all

            select
                elem,
                path_ || '[' || (elem_ix - 1 )::text || ']'
            from
                typed_values,
                lateral jsonb_array_elements(obj) with ordinality z(elem, elem_ix)
            where
                typeof = 'array'
      )
    )

    select
        path_::jsonpath,
        obj
    from
        _tree
    order by
        path_::text;
$$;
