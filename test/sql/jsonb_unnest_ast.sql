with doc(x) as (
    select (graphql.parse(
        $$
            {
              allAccounts(last: 2, before: "WyJhY2NvdW50IiwgM10=") {
                edges {
                  node {
                    nodeId
                    id
                  }
                }
              }
            }
        $$
    )).ast
)
select
    jkr.jpath,
    jkr.obj
from
    doc,
    graphql.jsonb_unnest_recursive_with_jsonpath(graphql.ast_pass_strip_loc(doc.x::jsonb)) jkr(jpath, obj)
where
    jkr.jpath::text not ilike '%."loc"%'
