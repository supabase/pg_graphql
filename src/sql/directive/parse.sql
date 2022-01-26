create function graphql.comment_directive(comment_ text)
    returns jsonb
    language sql
as $$
    /*
    comment on column public.account.name is '@graphql.name: myField'
    */
    select
        (
            regexp_matches(
                comment_,
                '@graphql\((.+?)\)',
                'g'
            )
        )[1]::jsonb
$$;


create function graphql.comment(regclass)
    returns text
    language sql
as $$
    select pg_catalog.obj_description($1::oid, 'pg_class')
$$;


create function graphql.comment(regtype)
    returns text
    language sql
as $$
    select pg_catalog.obj_description($1::oid, 'pg_type')
$$;

create function graphql.comment(regproc)
    returns text
    language sql
as $$
    select pg_catalog.obj_description($1::oid, 'pg_proc')
$$;


create function graphql.comment(regclass, column_name text)
    returns text
    language sql
as $$
    select
        pg_catalog.col_description($1::oid, attnum)
    from
        pg_attribute
    where
        attrelid = $1::oid
        and attname = column_name::name
        and attnum > 0
        and not attisdropped
$$;


create function graphql.comment_directive_name(regclass, column_name text)
    returns text
    language sql
as $$
    select graphql.comment_directive(graphql.comment($1, column_name)) ->> 'name'
$$;


create function graphql.comment_directive_name(regclass)
    returns text
    language sql
as $$
    select graphql.comment_directive(graphql.comment($1)) ->> 'name'
$$;


create function graphql.comment_directive_name(regtype)
    returns text
    language sql
as $$
    select graphql.comment_directive(graphql.comment($1)) ->> 'name'
$$;

create function graphql.comment_directive_name(regproc)
    returns text
    language sql
as $$
    select graphql.comment_directive(graphql.comment($1)) ->> 'name'
$$;
