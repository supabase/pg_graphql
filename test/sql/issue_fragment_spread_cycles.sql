begin;

    -- example from the reported issue
    select graphql.resolve($$
        query {
            ...A
        }

        fragment A on Query {
            __typename
            ...B
        }

        fragment B on Query {
            __typename
            ...A
        }
    $$);

    -- example from graphql spec
    select graphql.resolve($$
    {
        dog {
            ...nameFragment
        }
    }

    fragment nameFragment on Dog {
        name
        ...barkVolumeFragment
    }

    fragment barkVolumeFragment on Dog {
        barkVolume
        ...nameFragment
    }
    $$);

    -- example from dockerfile
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
        status blog_post_status not null,
        created_at timestamp not null
    );

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

    comment on schema public is '@graphql({"inflect_names": true})';

    select graphql.resolve($$
    {
        blogCollection {
            edges {
                node {
                    ... blogFragment
                }
            }
        }
    }

    fragment blogFragment on Blog {
        owner {
            ... accountFragment
        }
    }

    fragment accountFragment on Account {
        blogCollection {
            edges {
                node {
                    ... blogFragment
                }
            }
        }
    }
    $$);

    select graphql.resolve($$
    {
        blogCollection {
            edges {
                node {
                    ... blogFragment
                }
            }
        }
    }

    fragment blogFragment on Blog {
        owner {
            blogCollection {
                edges {
                    node {
                        ... blogFragment
                    }
                }
            }
        }
    }
    $$);

    select graphql.resolve($$
    {
        blogCollection {
            edges {
                node {
                    id
                }
            }
        }
    }

    fragment blogFragment on Blog {
        owner {
            blogCollection {
                edges {
                    node {
                        ... blogFragment
                    }
                }
            }
        }
    }
    $$);

    -- test that a recursion limit of 50 is good enough for most queries
    select graphql.resolve($$
    {
        blogCollection {
            edges {
                node {
                    ... blogFragment
                }
            }
        }
    }

    fragment blogFragment on Blog {
        owner {
            blogCollection {
                edges {
                    node {
                        owner {
                            blogCollection {
                                edges {
                                    node {
                                        owner {
                                            blogCollection {
                                                edges {
                                                    node {
                                                        owner {
                                                            blogCollection {
                                                                edges {
                                                                    node {
                                                                        owner {
                                                                            blogCollection {
                                                                                edges {
                                                                                    node {
                                                                                        owner {
                                                                                            blogCollection {
                                                                                                edges {
                                                                                                    node {
                                                                                                        id
                                                                                                    }
                                                                                                }
                                                                                            }
                                                                                        }
                                                                                    }
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    $$);

rollback;
