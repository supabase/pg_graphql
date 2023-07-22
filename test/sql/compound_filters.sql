begin;

    CREATE TYPE plan AS ENUM ('free', 'pro', 'enterprise');

    create table account(
        id serial primary key,
        email varchar(255) not null,
        plan plan not null
    );

    insert into public.account(email, plan)
    values
        ('aardvark@x.com', 'free'),
        ('bat@x.com', 'pro'),
        ('cat@x.com', 'enterprise'),
        ('dog@x.com', 'free'),
        ('elephant@x.com', 'pro');

    -- AND filter zero expressions
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {AND: []}) {
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

    -- AND filter one expression
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {AND: [{id: {eq: 1}}]}) {
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

    -- AND filter two expressions
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {AND: [{id: {eq: 1}}, {email: {eq: "aardvark@x.com"}}]}) {
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

    -- AND filter three expressions
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {AND: [{id: {eq: 1}}, {email: {eq: "aardvark@x.com"}}, {plan: {eq: "free"}}]}) {
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

    -- OR filter zero expressions
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {OR: []}) {
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

    -- OR filter one expression
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {OR: [{id: {eq: 1}}]}) {
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

    -- OR filter two expressions
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {OR: [{id: {eq: 3}}, {email: {eq: "elephant@x.com"}}]}) {
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

    -- OR filter three expressions
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {OR: [{id: {eq: 1}}, {email: {eq: "bat@x.com"}}, {plan: {eq: "enterprise"}}]}) {
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

    -- NOT filter
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {NOT: {id: {eq: 3}}}) {
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

    -- empty NOT filter
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {NOT: {}}) {
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

    -- Nested filters
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(
                filter: {
                OR: [
                    { id: { eq: 3 } }
                    { id: { eq: 5 } }
                    { AND: [{ id: { eq: 1 } }, { email: { eq: "aardvark@x.com" } }] }
                ]
                }
            ) {
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

    -- Nested filters
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(
                filter: {
                AND: [
                    { id: { gt: 0 } }
                    { id: { lt: 4 } }
                    { OR: [{email: { eq: "bat@x.com" }}, {email: { eq: "cat@x.com" }}] }
                ]
                }
            ) {
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

    -- Nested filters
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(
                filter: {
                AND: [
                    { id: { gt: 0 } }
                    { id: { lt: 4 } }
                    { OR: [{NOT: {email: { eq: "bat@x.com" }}}, {email: { eq: "cat@x.com" }}] }
                ]
                }
            ) {
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

rollback;
