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
        ('aardvark@x.com', now()),
        ('bat@x.com', now()),
        ('cat@x.com', now()),
        ('dog@x.com', now()),
        ('elephant@x.com', now());

    insert into blog(owner_id, name, description, created_at)
    values
        ((select id from account where email ilike 'a%'), 'A: Blog 1', 'a desc1', now()),
        ((select id from account where email ilike 'a%'), 'A: Blog 2', 'a desc2', now()),
        ((select id from account where email ilike 'a%'), 'A: Blog 3', 'a desc3', now()),
        ((select id from account where email ilike 'b%'), 'B: Blog 3', 'b desc1', now());

    insert into blog_post (blog_id, title, body, tags, status, created_at)
    values
        ((SELECT id FROM blog WHERE name = 'A: Blog 1'), 'Post 1 in A Blog 1', 'Content for post 1 in A Blog 1', '{"tech", "update"}', 'RELEASED', NOW()),
        ((SELECT id FROM blog WHERE name = 'A: Blog 1'), 'Post 2 in A Blog 1', 'Content for post 2 in A Blog 1', '{"announcement", "tech"}', 'PENDING', NOW()),
        ((SELECT id FROM blog WHERE name = 'A: Blog 2'), 'Post 1 in A Blog 2', 'Content for post 1 in A Blog 2', '{"personal"}', 'RELEASED', NOW()),
        ((SELECT id FROM blog WHERE name = 'A: Blog 2'), 'Post 2 in A Blog 2', 'Content for post 2 in A Blog 2', '{"update"}', 'RELEASED', NOW()),
        ((SELECT id FROM blog WHERE name = 'A: Blog 3'), 'Post 1 in A Blog 3', 'Content for post 1 in A Blog 3', '{"travel", "adventure"}', 'PENDING', NOW()),
        ((SELECT id FROM blog WHERE name = 'B: Blog 3'), 'Post 1 in B Blog 3', 'Content for post 1 in B Blog 3', '{"tech", "review"}', 'RELEASED', NOW()),
        ((SELECT id FROM blog WHERE name = 'B: Blog 3'), 'Post 2 in B Blog 3', 'Content for post 2 in B Blog 3', '{"coding", "tutorial"}', 'PENDING', NOW());


    comment on table blog_post is e'@graphql({"totalCount": {"enabled": true}})';

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