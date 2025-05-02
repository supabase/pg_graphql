-- Setup common test schema and table
drop schema if exists tests cascade;
create schema tests;
create table tests.posts (
    id serial primary key,
    title text,
    body text,
    views integer,
    created_at timestamp default now()
);

insert into tests.posts (title, body, views) values
    ('Post 1', 'Body 1', 100),
    ('Post 2', 'Body 2', 200),
    ('Post 3', 'Body 3', 50);


-- Test Case 1: Basic Count
select graphql.resolve($$
    query {
      testsPostsCollection {
        aggregate {
          count
        }
      }
    }
$$);


-- Test Case 2: Filtered Count
select graphql.resolve($$
    query {
      testsPostsCollection(filter: { views: { gt: 75 } }) {
        aggregate {
          count
        }
      }
    }
$$);


-- Test Case 3: Sum, Avg, Min, Max on 'views'
select graphql.resolve($$
    query {
        testsPostsCollection {
            aggregate {
                count
                sum {
                    views
                }
                avg {
                    views
                }
                min {
                    views
                }
                max {
                    views
                }
            }
        }
    }
$$);


-- Test Case 4: Aggregates with Filter
select graphql.resolve($$
    query {
        testsPostsCollection(filter: { views: { lt: 150 } }) {
            aggregate {
                count
                sum {
                    views
                }
                avg {
                    views
                }
                min {
                    views
                }
                max {
                    views
                }
            }
        }
    }
$$);


-- Test Case 5: Aggregates with Pagination (should ignore pagination)
select graphql.resolve($$
    query {
        testsPostsCollection(first: 1) {
            edges {
                node {
                    id
                    title
                }
            }
            aggregate {
                count
                sum {
                    views
                }
            }
        }
    }
$$);


-- Test Case 6: Aggregates on table with different numeric types
drop table if exists tests.numeric_types cascade;
create table tests.numeric_types (
    id serial primary key,
    int_val int,
    bigint_val bigint,
    float_val float,
    numeric_val numeric(10, 2)
);

insert into tests.numeric_types (int_val, bigint_val, float_val, numeric_val) values
    (10, 10000000000, 10.5, 100.50),
    (20, 20000000000, 20.5, 200.50),
    (30, 30000000000, 30.5, 300.50);

select graphql.resolve($$
    query {
        testsNumericTypesCollection {
            aggregate {
                count
                sum {
                    intVal
                    bigintVal
                    floatVal
                    numericVal
                }
                avg {
                    intVal
                    bigintVal
                    floatVal
                    numericVal
                }
                 min {
                    intVal
                    bigintVal
                    floatVal
                    numericVal
                }
                 max {
                    intVal
                    bigintVal
                    floatVal
                    numericVal
                }
            }
        }
    }
$$);

-- Test Case 7: Aggregates with empty result set
select graphql.resolve($$
    query {
        testsPostsCollection(filter: { views: { gt: 1000 } }) {
            aggregate {
                count
                sum {
                    views
                }
                 avg {
                    views
                }
                 min {
                    views
                }
                 max {
                    views
                }
            }
        }
    }
$$);

-- Test Case 8: Aggregates on table with null values
drop table if exists tests.posts_with_nulls cascade;
create table tests.posts_with_nulls (
    id serial primary key,
    views integer
);
insert into tests.posts_with_nulls(views) values (100), (null), (200);

select graphql.resolve($$
    query {
        testsPostsWithNullsCollection {
            aggregate {
                count
                sum {
                    views
                }
                avg {
                    views
                }
                min {
                    views
                }
                max {
                    views
                }
            }
        }
    }
$$); 