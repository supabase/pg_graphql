begin;
    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    comment on column public.account.email is E'@graphql({"name": "emailAddress"})';

    select
        name
    from
        graphql.field
    where
        entity = 'public.account'::regclass
        and column_name = 'email'
        and meta_kind = 'Column';

rollback;
