begin;

    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    insert into public.account(email)
    values
        ('aardvark@x.com'),
        ('bat@x.com'),
        ('cat@x.com');

    -- `or` with only an empty entry is ignored
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {or: [{}]}) {
                edges { node { id } }
            }
        }
        $$)
    );

    -- `and` with only an empty entry is ignored
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {and: [{}]}) {
                edges { node { id } }
            }
        }
        $$)
    );

    -- an `or` entry whose only operator comes from an omitted variable is ignored
    select jsonb_pretty(
        graphql.resolve($$
        query AccountsByEmail($email: String) {
            accountCollection(filter: {or: [{email: {eq: $email}}]}) {
                edges { node { id } }
            }
        }
        $$,
        variables := '{}'
        )
    );

    -- empty entries next to a real one still leave the real one in place
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {or: [{}, {id: {eq: 2}}]}) {
                edges { node { id } }
            }
        }
        $$)
    );

    -- nested: `not` around an `or` of empty entries is ignored
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {not: {or: [{}]}}) {
                edges { node { id } }
            }
        }
        $$)
    );

    -- same on a mutation filter: nothing is filtered out, so every row is updated
    select jsonb_pretty(
        graphql.resolve($$
        mutation {
            updateAccountCollection(set: {email: "x@x.com"}, filter: {or: [{}]}, atMost: 10) {
                affectedCount
            }
        }
        $$)
    );

rollback;
