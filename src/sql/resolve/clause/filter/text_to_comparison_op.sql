create or replace function graphql.text_to_comparison_op(text)
    returns graphql.comparison_op
    language sql
    immutable
    as
$$
    select
        case $1
            when 'eq' then '='
            when 'lt' then '<'
            when 'lte' then '<='
            when 'neq' then '<>'
            when 'gte' then '>='
            when 'gt' then '>'
            when 'like' then 'like'
            when 'ilike' then 'ilike'
            else graphql.exception('Invalid comaprison operator')
        end::graphql.comparison_op
$$;
