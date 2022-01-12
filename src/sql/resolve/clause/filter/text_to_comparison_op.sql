create or replace function graphql.text_to_comparison_op(text)
    returns graphql.comparison_op
    language sql
    immutable
    as
$$
    select
        case $1
            when 'eq' then '='
            else graphql.exception('Invalid comaprison operator')
        end::graphql.comparison_op
$$;
