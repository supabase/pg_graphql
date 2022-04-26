begin;
    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    comment on table public.account is E'@graphql({"name": "UserAccount"})';

    select graphql.rebuild_schema();

    select name from graphql.type where entity = 'public.account'::regclass order by name;

rollback;
