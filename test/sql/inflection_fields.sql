begin;
    create view f as
        select
            distinct name
        from
            graphql.field
        where
            column_name in ('id', 'name_with_underscore')
        order by
            name;

    create table account (
        id int primary key,
        name_with_underscore text
    );

    -- Inflection off, Overrides: off
    comment on schema public is e'@graphql({"inflect_names": false})';
    select * from f;

    savepoint a;

    -- Inflection off, Overrides: on
    comment on column account.id is e'@graphql({"name": "IddD"})';
    comment on column account.name_with_underscore is e'@graphql({"name": "nAMe"})';
    select * from f;

    rollback to savepoint a;

    -- Inflection on, Overrides: off
    comment on schema public is e'@graphql({"inflect_names": true})';
    select * from f;

    -- Inflection on, Overrides: on
    comment on column account.id is e'@graphql({"name": "IddD"})';
    comment on column account.name_with_underscore is e'@graphql({"name": "nAMe"})';
    select * from f;

rollback;
