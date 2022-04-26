begin;

    savepoint a;

    create table account(
        id serial primary key
    );

    select graphql.rebuild_schema();

    -- Should be visible because it has a primary ky
    select * from graphql.entity;

    rollback to savepoint a;

    create table account(
        id serial
    );

    -- Should NOT be visible because it does not have a primary ky
    select * from graphql.entity;

rollback;
