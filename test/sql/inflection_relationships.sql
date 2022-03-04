begin;
    create view r as
        select
            distinct name
        from
            graphql.field
        where
            local_columns is not null
        order by
            name;

    create table account (
        id int primary key,
        name_with_underscore text
    );

    create table blog_post(
        id int primary key,
        author_id  int,
        account_no  int,

        constraint fkey_author_id foreign key (author_id) references account(id),
        constraint fkey_author_no foreign key (account_no) references account(id)
    );

    savepoint a;

    -- Inflection off, Overrides: off
    comment on schema public is e'@graphql({"inflect_names": false})';
    select * from r;

    savepoint a;

    -- Inflection off, Overrides: on
    comment on constraint fkey_author_id
        on blog_post
        is E'@graphql({"foreign_name": "ownerOO", "local_name": "Blogzzz"})';
    comment on constraint fkey_author_no
        on blog_post
        is E'@graphql({"foreign_name": "accountNO", "local_name": "NOblogz"})';
    select * from r;

    rollback to savepoint a;

    -- Inflection on, Overrides: off
    comment on schema public is e'@graphql({"inflect_names": true})';
    select * from r;

    -- Inflection on, Overrides: on
    comment on constraint fkey_author_id
        on blog_post
        is E'@graphql({"foreign_name": "ownerOO", "local_name": "Blogzzz"})';
    comment on constraint fkey_author_no
        on blog_post
        is E'@graphql({"foreign_name": "accountNO", "local_name": "NOblogz"})';
    select * from r;

rollback;
