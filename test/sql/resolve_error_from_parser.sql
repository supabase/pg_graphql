-- Platform specific diffs so we have to test the properties here rather than exact response
with d(val) as (
  select graphql.resolve($$
  { { {
      shouldFail
    }
  }
  $$)::json
)

select
  (
    json_typeof(val -> 'errors') = 'array'
    and json_array_length(val -> 'errors') = 1
  ) as is_valid
from d;
