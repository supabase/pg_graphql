begin;

    savepoint a;

    create function public.uid()
    returns uuid stable language sql as
    $$
      select 'adfc9433-b00e-4072-bbe5-5ae23a76e15d'::uuid
    $$;

    create function public.get_user_id(p_user_id uuid default public.uid())
    returns uuid stable language sql as
    $$
        select p_user_id;
    $$;

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
                        defaultValue
                        type {
                            name
                            kind
                            ofType {
                              name
                              kind
                            }
                        }
                    }
                }
            }
        }
    } $$));

    select jsonb_pretty(graphql.resolve($$
    query {
      userId: getUserId(
        pUserId: "34f45987-bb41-4111-967c-bd462ea41d52"
      )
    }
    $$));

    select jsonb_pretty(graphql.resolve($$
    query {
      userId: getUserId
    }
    $$));

    rollback to savepoint a;

    create function public.uid()
    returns text stable language sql as
    $$
      select 'adfc9433-b00e-4072-bbe5-5ae23a76e15d'
    $$;

    create function public.get_user_id(p_user_id text default public.uid())
    returns text stable language sql as
    $$
        select p_user_id;
    $$;

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
                        defaultValue
                        type {
                            name
                            kind
                            ofType {
                              name
                              kind
                            }
                        }
                    }
                }
            }
        }
    } $$));

    select jsonb_pretty(graphql.resolve($$
    query {
      userId: getUserId(
        pUserId: "34f45987-bb41-4111-967c-bd462ea41d52"
      )
    }
    $$));

    select jsonb_pretty(graphql.resolve($$
    query {
      userId: getUserId
    }
    $$));

    rollback to savepoint a;

    create function public.add_nums(a int default 1 + 1, b int default 2 + 2)
    returns int stable language sql as
    $$
        select a + b;
    $$;

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
                        defaultValue
                        type {
                            name
                            kind
                            ofType {
                              name
                              kind
                            }
                        }
                    }
                }
            }
        }
    } $$));

    select jsonb_pretty(graphql.resolve($$
    query {
      addNums(a: 1, b: 2)
    }
    $$));

    select jsonb_pretty(graphql.resolve($$
    query {
      addNums
    }
    $$));
rollback;
