create function graphql.ast_pass_strip_loc(body jsonb)
returns jsonb
language sql
immutable
as $$
/*
Remove a 'loc' key from a jsonb object by name
*/
select
    regexp_replace(
        body::text,
        '"loc":\s*\{\s*("end"|"start")\s*:\s*\{\s*("line"|"column")\s*:\s*\d+,\s*("line"|"column")\s*:\s*\d+\s*},\s*("end"|"start")\s*:\s*\{\s*("line"|"column")\s*:\s*\d+,\s*("line"|"column")\s*:\s*\d+\s*}\s*},'::text,
        '',
        'g'
    )::jsonb
$$;
