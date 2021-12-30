with doc(x) as (
    select '{"id": {"eq": "DescNullsFirst"}, "x": [1, {"f": ["a"]},3]}'::jsonb
)
select
    jkr.jpath,
    jkr.obj,
    jsonb_path_query(doc.x, jpath::jsonpath),
    -- Should always be true
    jkr.obj = jsonb_path_query(doc.x, jpath::jsonpath) is_equal
from
    doc,
    graphql.jsonb_unnest_recursive_with_jsonpath(doc.x) jkr(jpath, obj)
