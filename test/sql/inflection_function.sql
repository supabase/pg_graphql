begin;
    create view f as
        select
            distinct name
        from
            graphql.field
        where
            func is not null
        order by
            name;

    create table account (
        id int primary key
    );

    create function _full_name(rec public.account)
        returns text
        immutable
        strict
        language sql
    as $$
        select 'Foo';
    $$;

    -- Inflection off, Overrides: off
    comment on schema public is e'@graphql({"inflect_names": false})';
    select graphql.rebuild_schema();
    select * from f;

    savepoint a;

    -- Inflection off, Overrides: on
    comment on function public._full_name(public.account) is E'@graphql({"name": "wholeName"})';
    select graphql.rebuild_schema();
    select * from f;

    rollback to savepoint a;

    -- Inflection on, Overrides: off
    comment on schema public is e'@graphql({"inflect_names": true})';
    select graphql.rebuild_schema();
    select * from f;

    -- Inflection on, Overrides: on
    comment on function public._full_name(public.account) is E'@graphql({"name": "WholeName"})';
    select graphql.rebuild_schema();
    select * from f;

rollback;
