begin;
    -- functions in this file are not supported yet

    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    insert into public.account(email)
    values
        ('aardvark@x.com'),
        ('bat@x.com'),
        ('cat@x.com');

    -- functions which return a record
    create function returns_record()
        returns record language sql stable
    as $$ select id, email from account; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsRecord {
                id
                email
                nodeId
                __typename
            }
        }
    $$));

    -- functions which accept a table tuple type
    create function accepts_table_tuple_type(rec public.account)
        returns int
        immutable
        language sql
    as $$
        select 1;
    $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            acceptsTableTupleType
        }
    $$));

    -- overloaded functions
    create function an_overloaded_function()
        returns int language sql stable
    as $$ select 1; $$;

    create function an_overloaded_function(a int)
        returns int language sql stable
    as $$ select 2; $$;

    create function an_overloaded_function(a text)
        returns int language sql stable
    as $$ select 2; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            anOverloadedFunction
        }
    $$));

    select jsonb_pretty(graphql.resolve($$
        query {
            anOverloadedFunction (a: 1)
        }
    $$));

    select jsonb_pretty(graphql.resolve($$
        query {
            anOverloadedFunction (a: "some text")
        }
    $$));

    -- functions without arg names
    create function no_arg_name(int)
        returns int language sql immutable
    as $$ select 42; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            noArgName
        }
    $$));

    -- variadic functions
    create function variadic_func(variadic int[])
        returns int language sql immutable
    as $$ select 42; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            variadicFunc
        }
    $$));

    -- functions returning void
    create function void_returning_func(variadic int[])
        returns void language sql immutable
    as $$ $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            voidReturningFunc
        }
    $$));

    -- function returning type not on search path
    create schema dev;
    create table dev.book(
        id int primary key
    );
    insert into dev.book values (1);

    create function "returnsBook"()
        returns dev.book
        stable
        language sql
    as $$
        select db from dev.book db limit 1;
    $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsBook
        }
    $$));

    -- function accepting type not on search path
    create type dev.invisible as enum ('ONLY');

    create function "badInputArg"(val dev.invisible)
        returns int
        stable
        language sql
    as $$
        select 1;
    $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            badInputArg
        }
    $$));


    -- function returning enum
    create type "Algorithm" as enum ('aead-ietf');
    comment on type "Algorithm" is '@graphql({"mappings": {"aead-ietf": "AEAD_IETF"}})';

    create function return_algorithm()
        returns "Algorithm" language sql volatile
    as $$ select 'aead-ietf'::"Algorithm"; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            returnAlgorithm
        }
    $$));

    create function accept_algorithm(e "Algorithm")
        returns int language sql stable
    as $$ select 0; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            acceptAlgorithm(e: "AEAD_IETF")
        }
    $$));

    select jsonb_pretty(graphql.resolve($$
    query IntrospectionQuery {
        __schema {
            queryType {
                fields {
                    name
                    description
                    type {
                        kind
                    }
                    args {
                        name
                        type {
                            name
                        }
                    }
                }
            }
        }
    } $$));
rollback;
