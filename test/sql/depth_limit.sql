begin;
    -- Regression test for the "Unbounded Direct GraphQL Selection Depth"
    -- DoS: graphql.resolve() had no limit on selection depth for directly
    -- nested selections (i.e. no fragments required). A query that
    -- alternates a to-one relationship (owner) and a to-many relationship
    -- (blogCollection) could be nested arbitrarily deep, causing exponential
    -- SQL join / JSON response growth (see MAX_SELECTION_DEPTH in
    -- src/resolve.rs). Compare with test/sql/issue_fragment_spread_cycles.sql,
    -- which covers the same style of runaway recursion when reached via
    -- fragment spreads.
    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    create table blog(
        id serial primary key,
        owner_id integer not null references account(id) on delete cascade,
        name varchar(255) not null
    );

    comment on schema public is '@graphql({"inflect_names": true})';

    insert into account(email) values ('a@x.com');
    insert into blog(owner_id, name) values ((select id from account limit 1), 'blog 1');

    -- queries with depth limit within MAX_SELECTION_DEPTH succeed.
    select graphql.resolve($$
    {
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
            }
        }
    }
    $$);

    -- queries with depth limit beyond MAX_SELECTION_DEPTH are rejected .
    select graphql.resolve($$
    {
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
