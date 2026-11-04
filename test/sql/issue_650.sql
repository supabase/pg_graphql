begin;

    create table test_table (
        id serial primary key,
        name text not null,
        description text
    );

    comment on schema public is e'@graphql({"introspection": true})';

    -- baseline: a non-empty search_path resolves fine
    set local search_path to public;
    select graphql.resolve('{ __typename }');

    -- an empty search_path should also resolve, with no visible schemas
    set local search_path to '';
    select graphql.resolve('{ __typename }');

rollback;
