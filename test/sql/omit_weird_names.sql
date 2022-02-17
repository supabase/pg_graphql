begin;

    savepoint a;

    create table "@xyz"( id int primary key);
    select name from graphql.type where entity = '"@xyz"'::regclass;

    rollback to savepoint a;

    create table xyz( "! q" int primary key);
    select name from graphql.field where entity = 'xyz'::regclass and meta_kind = 'Column';

    rollback to savepoint a;

rollback;
