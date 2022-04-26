begin;
    create view t as
        select
            distinct name
        from
            graphql.type
        where
            entity is not null
        order by
            name;

    create table blog_post(
        id int primary key,
        author_id int
    );

    savepoint a;

    -- Inflection off, Overrides: off
    comment on schema public is e'@graphql({"inflect_names": false})';
    select graphql.rebuild_schema();
    select * from t;

    -- Inflection off, Overrides: on
    comment on table blog_post is e'@graphql({"name": "BlogZZZ"})';
    select graphql.rebuild_schema();
    select * from t;

    rollback to savepoint a;

    -- Inflection on, Overrides: off
    comment on schema public is e'@graphql({"inflect_names": true})';
    select graphql.rebuild_schema();
    select name from graphql.type where entity is not null order by entity, name;

    -- Inflection on, Overrides: on
    comment on table blog_post is e'@graphql({"name": "BlogZZZ"})';
    select graphql.rebuild_schema();
    select name from graphql.type where entity is not null order by entity, name;

rollback;
