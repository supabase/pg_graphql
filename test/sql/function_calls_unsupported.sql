begin;
    -- These following tests are there to just document
    -- the current behaviour and any limitations. Do not
    -- assume that just because they pass it the expected
    -- behaviour.

    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    insert into public.account(email)
    values
        ('aardvark@x.com'),
        ('bat@x.com'),
        ('cat@x.com');

    -- functions returning record are not supported yet
    -- currently they do return the fields from the returned record
    -- but do not return nodeId and __typename fields
    -- Their schema queries also return a type of scalar
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

    -- overloaded functions are also not supported yet
    -- some of the simpler cases can work, but not
    -- everything works.
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

    -- functions without names are not supported yet
    -- we will need to generate synthetic names like arg1, arg2 etc.
    -- for these to be supported
    create function no_arg_name(int)
        returns int language sql immutable
    as $$ select 42; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            noArgName
        }
    $$));

    select jsonb_pretty(graphql.resolve($$
        query {
            noArgName(arg0: 1)
        }
    $$));

    -- function names which clash with other fields like
    -- table collections are not handled yet.
    create function accountCollection()
        returns account language sql stable
    as $$ select id, email from account; $$;

    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection {
                edges {
                    node {
                        id
                        email
                    }
                }
            }
        }
        $$)
    );

    select graphql.resolve($$
        mutation {
            insertIntoAccountCollection(objects: [
                { email: "foo@barsley.com" },
                { email: "bar@foosworth.com" }
            ]) {
                affectedCount
                records {
                    id
                }
            }
        }
    $$);

rollback;
