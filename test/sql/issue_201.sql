begin;
    /*
    When the extension is installed via
        create extension pg_graphql with schema xyz;

    The initial build runs with search_path = 'xyz';

    While names are being inflected, we check if the inflect_names comment
    directive is active. The bug was that we checked in `current_schema`
    rather than the schema associated with the entity being named

    This test confirms that inflection rules are pulled from the owning schema
    rather than the search path.
    */

    comment on schema public is '@graphql({"inflect_names": true})';

    create schema xyz;

    create table account_holder(
        id serial primary key,
        email_address varchar(255) not null
    );

    drop extension pg_graphql;
    create extension pg_graphql with schema xyz;

    select name from graphql.type where name ilike 'a%';
    select name from graphql.field where parent_type ilike 'AccountHolder%' and name ilike 'email%';

rollback;
