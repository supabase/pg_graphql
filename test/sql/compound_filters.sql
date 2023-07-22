begin;

    create table account(
        id serial primary key,
        email varchar(255) not null,
        created_at timestamp not null
    );

    insert into public.account(email, created_at)
    values
        ('aardvark@x.com', now()),
        ('bat@x.com', now()),
        ('cat@x.com', now()),
        ('dog@x.com', now()),
        ('elephant@x.com', now());

    -- AND filter
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

    -- empty AND filter
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

    -- OR filter
    select jsonb_pretty(
        graphql.resolve($$
        {
            accountCollection(filter: {OR: [{id: {eq: 3}}, {id: {eq: 5}}]}) {
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

    -- empty OR filter
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
