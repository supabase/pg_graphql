begin;

    create table account(
        id serial primary key,
        email varchar(255) not null,
        created_at timestamp not null
    );


    create table blog(
        id serial primary key,
        owner_id integer not null references account(id) on delete cascade,
        name varchar(255) not null,
        description varchar(255),
        created_at timestamp not null
    );


    create type blog_post_status as enum ('PENDING', 'RELEASED');


    create table blog_post(
        id uuid not null default gen_random_uuid() primary key,
        blog_id integer not null references blog(id) on delete cascade,
        title varchar(255) not null,
        body varchar(10000),
        tags TEXT[],
        status blog_post_status not null,
        created_at timestamp not null
    );


    -- 5 Accounts
    insert into public.account(email, created_at)
    values
        ('aardvark@x.com', '2025-04-27 12:00:00'),
        ('bat@x.com', '2025-04-28 12:00:00'),
        ('cat@x.com', '2025-04-29 12:00:00'),
        ('dog@x.com', '2025-04-30 12:00:00'),
        ('elephant@x.com', '2025-05-01 12:00:00');

    insert into blog(owner_id, name, description, created_at)
    values
        ((select id from account where email ilike 'a%'), 'A: Blog 1', 'a desc1', '2025-04-22 12:00:00'),
        ((select id from account where email ilike 'a%'), 'A: Blog 2', 'a desc2', '2025-04-23 12:00:00'),
        ((select id from account where email ilike 'a%'), 'A: Blog 3', 'a desc3', '2025-04-24 12:00:00'),
        ((select id from account where email ilike 'b%'), 'B: Blog 3', 'b desc1', '2025-04-25 12:00:00');

    insert into blog_post (blog_id, title, body, tags, status, created_at)
    values
        ((SELECT id FROM blog WHERE name = 'A: Blog 1'), 'Post 1 in A Blog 1', 'Content for post 1 in A Blog 1', '{"tech", "update"}', 'RELEASED', '2025-04-02 12:00:00'),
        ((SELECT id FROM blog WHERE name = 'A: Blog 1'), 'Post 2 in A Blog 1', 'Content for post 2 in A Blog 1', '{"announcement", "tech"}', 'PENDING', '2025-04-07 12:00:00'),
        ((SELECT id FROM blog WHERE name = 'A: Blog 2'), 'Post 1 in A Blog 2', 'Content for post 1 in A Blog 2', '{"personal"}', 'RELEASED', '2025-04-12 12:00:00'),
        ((SELECT id FROM blog WHERE name = 'A: Blog 2'), 'Post 2 in A Blog 2', 'Content for post 2 in A Blog 2', '{"update"}', 'RELEASED', '2025-04-17 12:00:00'),
        ((SELECT id FROM blog WHERE name = 'A: Blog 3'), 'Post 1 in A Blog 3', 'Content for post 1 in A Blog 3', '{"travel", "adventure"}', 'PENDING', '2025-04-22 12:00:00'),
        ((SELECT id FROM blog WHERE name = 'B: Blog 3'), 'Post 1 in B Blog 3', 'Content for post 1 in B Blog 3', '{"tech", "review"}', 'RELEASED', '2025-04-27 12:00:00'),
        ((SELECT id FROM blog WHERE name = 'B: Blog 3'), 'Post 2 in B Blog 3', 'Content for post 2 in B Blog 3', '{"coding", "tutorial"}', 'PENDING', '2025-05-02 12:00:00');

    comment on table account is e'@graphql({"totalCount": {"enabled": true}, "aggregate": {"enabled": true}})';
    comment on table blog is e'@graphql({"totalCount": {"enabled": true}, "aggregate": {"enabled": true}})';
    comment on table blog_post is e'@graphql({"totalCount": {"enabled": true}, "aggregate": {"enabled": true}})';

    -- Test Case 1: Basic Count on accountCollection
    select graphql.resolve($$
        query {
            accountCollection {
                aggregate {
                    count
                }
            }
        }
    $$);


    -- Test Case 2: Filtered Count on accountCollection
    select graphql.resolve($$
        query {
            accountCollection(filter: { id: { gt: 3 } }) {
                aggregate {
                    count
                }
            }
        }
    $$);


    -- Test Case 3: Sum, Avg, Min, Max on blogCollection.id
    select graphql.resolve($$
        query {
            blogCollection {
                aggregate {
                    count
                    sum {
                        id
                    }
                    avg {
                        id
                    }
                    min {
                        id
                    }
                    max {
                        id
                    }
                }
            }
        }
    $$);


    -- Test Case 4: Aggregates with Filter on blogCollection.id
    select graphql.resolve($$
        query {
            blogCollection(filter: { ownerId: { lt: 2 } }) {
                aggregate {
                    count
                    sum {
                        id
                    }
                    avg {
                        id
                    }
                    min {
                        id
                    }
                    max {
                        id
                    }
                }
            }
        }
    $$);


    -- Test Case 5: Aggregates with Pagination on blogCollection (should ignore pagination for aggregates)
    select graphql.resolve($$
        query {
            blogCollection(first: 1) {
                edges {
                    node {
                        id
                        name
                    }
                }
                aggregate {
                    count
                    sum {
                        id
                    }
                }
            }
        }
    $$);


    -- Test Case 7: Aggregates with empty result set on accountCollection
    select graphql.resolve($$
        query {
            accountCollection(filter: { id: { gt: 1000 } }) {
                aggregate {
                    count
                    sum {
                        id
                    }
                    avg {
                        id
                    }
                    min {
                        id
                    }
                    max {
                        id
                    }
                }
            }
        }
    $$);

    -- Test Case 8: Aggregates on table with null values (using blog.description)
    -- Count where description is not null
    select graphql.resolve($$
        query {
            blogCollection(filter: { description: { is: NOT_NULL }}) {
                aggregate {
                    count
                }
            }
        }
    $$);
    -- Count where description is null
    select graphql.resolve($$
        query {
            blogCollection(filter: { description: { is: NULL }}) {
                aggregate {
                    count
                }
            }
        }
    $$);

    -- Test Case 9: Basic Count on blogPostCollection
    select graphql.resolve($$
        query {
            blogPostCollection {
                aggregate {
                    count
                }
            }
        }
    $$);

    -- Test Case 10: Min/Max on non-numeric fields (string, datetime)
    select graphql.resolve($$
        query {
            blogCollection {
                aggregate {
                    min {
                        name
                        description
                        createdAt
                    }
                    max {
                        name
                        description
                        createdAt
                    }
                }
            }
        }
    $$);

    -- Test Case 11: Aggregation with relationships (nested queries)
    select graphql.resolve($$
        query {
            accountCollection {
                edges {
                    node {
                        email
                        blogCollection {
                            aggregate {
                                count
                                sum {
                                    id
                                }
                            }
                        }
                    }
                }
            }
        }
    $$);

    -- Test Case 12: Combination of aggregates in a complex query
    select graphql.resolve($$
        query {
            blogCollection {
                edges {
                    node {
                        name
                        blogPostCollection {
                            aggregate {
                                count
                                min {
                                    createdAt
                                }
                                max {
                                    createdAt
                                }
                            }
                        }
                    }
                }
                aggregate {
                    count
                    min {
                        id
                        createdAt
                    }
                    max {
                        id
                        createdAt
                    }
                    sum {
                        id
                    }
                    avg {
                        id
                    }
                }
            }
        }
    $$);

    -- Test Case 13: Complex filters with aggregates using AND/OR/NOT
    select graphql.resolve($$
        query {
            blogPostCollection(
                filter: {
                    or: [
                        {status: {eq: RELEASED}},
                        {title: {startsWith: "Post"}}
                    ]
                }
            ) {
                aggregate {
                    count
                }
            }
        }
    $$);

    select graphql.resolve($$
        query {
            blogPostCollection(
                filter: {
                    and: [
                        {status: {eq: PENDING}},
                        {not: {blogId: {eq: 4}}}
                    ]
                }
            ) {
                aggregate {
                    count
                }
            }
        }
    $$);

    -- Test Case 14: Array field aggregation (on tags array)
    select graphql.resolve($$
        query {
            blogPostCollection(
                filter: {
                    tags: {contains: "tech"}
                }
            ) {
                aggregate {
                    count
                }
            }
        }
    $$);

    -- Test Case 15: UUID field aggregation
    -- This test verifies that UUID fields are intentionally excluded from min/max aggregation.
    -- UUIDs don't have a meaningful natural ordering for aggregation purposes, so they're explicitly
    -- excluded from the list of types that can be aggregated with min/max.
    select graphql.resolve($$
        query {
            blogPostCollection {
                aggregate {
                    min {
                        id
                    }
                    max {
                        id
                    }
                }
            }
        }
    $$);

    -- Test Case 16: Edge case - Empty result set with aggregates
    select graphql.resolve($$
        query {
            blogPostCollection(
                filter: {
                    title: {eq: "This title does not exist"}
                }
            ) {
                aggregate {
                    count
                    min {
                        createdAt
                    }
                    max {
                        createdAt
                    }
                }
            }
        }
    $$);

    -- Test Case 17: Filtering on aggregate results (verify all posts with RELEASED status)
    select graphql.resolve($$
        query {
            blogPostCollection(
                filter: {status: {eq: RELEASED}}
            ) {
                aggregate {
                    count
                }
            }
        }
    $$);

    -- Test Case 18: Aggregates on filtered relationships
    select graphql.resolve($$
        query {
            blogCollection {
                edges {
                    node {
                        name
                        blogPostCollection(
                            filter: {status: {eq: RELEASED}}
                        ) {
                            aggregate {
                                count
                            }
                        }
                    }
                }
            }
        }
    $$);


    -- Test Case 19: aliases test case
    select graphql.resolve($$
        query {
            blogCollection {
                agg: aggregate {
                    cnt: count
                    total: sum {
                        identifier: id
                    }
                    average: avg {
                        identifier: id
                    }
                    minimum: min {
                        identifier: id
                    }
                    maximum: max {
                        identifier: id
                    }
                }
            }
        }
    $$);

rollback;
