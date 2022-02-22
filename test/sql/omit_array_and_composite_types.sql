begin;

    /*
        Composite and array types are not currently supported as inputs
        - confirm composites are not allowed anywhere
        - confirm arrays are not allowed as input
    */

    create type complex as (r int, i int);

    create table something(
        id serial primary key,
        name varchar(255) not null,
        tags text[],
        comps complex
    );


    select
        name, parent_type, type_, is_not_null, is_array, is_arg
    from
        graphql.field
    where
        entity = 'something'::regclass
        and column_name is not null
    order by
        parent_type,
        name;

rollback;
