create function graphql.to_camel_case(text)
    returns text
    language sql
    immutable
as
$$
select
    string_agg(
        case
            when part_ix = 1 then part
            else initcap(part)
        end, '')
from
    unnest(string_to_array($1, '_')) with ordinality x(part, part_ix)
$$;
