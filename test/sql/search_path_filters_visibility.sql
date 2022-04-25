begin;

    create table public.foo(
        id serial primary key
    );

    create schema other;

    create table other.bar(
        id serial primary key
    );

    select graphql.rebuild_schema();

    -- public.foo is visible, other.bar is not
    select
        name
    from
        graphql.type
    where
        entity is not null
        and meta_kind = 'Node';


    -- switch search path to other
    set search_path = other;
    -- other.bar is visible, public.foo is not is not
    select
        name
    from
        graphql.type
    where
        entity is not null
        and meta_kind = 'Node';

rollback;
