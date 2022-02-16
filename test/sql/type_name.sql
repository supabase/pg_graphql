begin;
    create table account(id int primary key);
    create type post_status as enum ('published', 'unpublished');

    select
        (rec).type_kind,
        (rec).meta_kind,
        (rec).is_builtin,
        (rec).entity,
        (rec).graphql_type_id,
        graphql.type_name(rec) type_name
    from
        graphql._type rec
    order by
        (rec).entity,
        (rec).type_kind,
        graphql.type_name(rec);

rollback;
