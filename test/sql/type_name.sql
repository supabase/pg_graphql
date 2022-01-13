begin;
    create table account(id int primary key);
    create type post_status as enum ('published', 'unpublished');

    select
        (rec).type_kind,
        (rec).meta_kind,
        (rec).is_builtin,
        (rec).entity,
        (rec).graphql_type,
        graphql.type_name(rec) type_name
    from
        graphql.__type rec;

rollback;
