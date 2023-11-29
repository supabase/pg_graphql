begin;

    savepoint a;
    --query tests

    -- functions accepting arrays
    create function get_smallint_array_item(arr smallint[], i int)
        returns smallint language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getSmallintArrayItem(arr: [1, 2, 3], i: 1)
        }
    $$));

    create function get_int_array_item(arr int[], i int)
        returns int language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getIntArrayItem(arr: [1, 2, 3], i: 2)
        }
    $$));

    create function get_bigint_array_item(arr bigint[], i int)
        returns bigint language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getBigintArrayItem(arr: ["1", "2", "3"], i: 3)
        }
    $$));

    create function get_real_array_item(arr real[], i int)
        returns real language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getRealArrayItem(arr: [1.1, 2.2, 3.3], i: 1)
        }
    $$));

    create function get_double_array_item(arr double precision[], i int)
        returns double precision language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getDoubleArrayItem(arr: [1.1, 2.2, 3.3], i: 2)
        }
    $$));

    create function get_numeric_array_item(arr numeric[], i int)
        returns numeric language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getNumericArrayItem(arr: ["1.1", "2.2", "3.3"], i: 3)
        }
    $$));

    create function get_bool_array_item(arr bool[], i int)
        returns bool language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getBoolArrayItem(arr: [true, false], i: 1)
        }
    $$));

    create function get_uuid_array_item(arr uuid[], i int)
        returns uuid language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getUuidArrayItem(arr: ["e8dc3a9a-2c72-11ee-b094-776acede6790", "d3ef3a8c-2c72-11ee-b094-776acede7221"], i: 2)
        }
    $$));

    create function get_text_array_item(arr text[], i int)
        returns text language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getTextArrayItem(arr: ["hello", "world"], i: 1)
        }
    $$));

    create function get_json_array_item(arr json[], i int)
        returns json language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getJsonArrayItem(arr: ["{\"hello\": \"world\"}", "{\"bye\": \"world\"}"], i: 2)
        }
    $$));

    create function get_jsonb_array_item(arr jsonb[], i int)
        returns jsonb language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getJsonbArrayItem(arr: ["{\"hello\": \"world\"}", "{\"bye\": \"world\"}"], i: 1)
        }
    $$));

    create function get_date_array_item(arr date[], i int)
        returns date language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getDateArrayItem(arr: ["2023-11-22", "2023-11-23", "2023-11-24"], i: 3)
        }
    $$));

    create function get_time_array_item(arr time[], i int)
        returns time language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getTimeArrayItem(arr: ["5:05", "5:06", "5:07"], i: 1)
        }
    $$));

    create function get_timestamp_array_item(arr timestamp[], i int)
        returns timestamp language sql stable
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getTimestampArrayItem(arr: ["2023-07-28 12:39:05", "2023-08-28 12:39:05", "2023-09-28 12:39:05"], i: 2)
        }
    $$));

    -- functions returning arrays
    create function returns_smallint_array()
        returns smallint[] language sql stable
    as $$ select '{1, 2, 3}'::smallint[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsSmallintArray
        }
    $$));

    create function returns_int_array()
        returns int[] language sql stable
    as $$ select '{1, 2, 3}'::int[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsIntArray
        }
    $$));

    create function returns_bigint_array()
        returns bigint[] language sql stable
    as $$ select '{1, 2, 3}'::bigint[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsBigintArray
        }
    $$));

    create function returns_real_array()
        returns real[] language sql stable
    as $$ select '{1.1, 2.2, 3.3}'::real[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsRealArray
        }
    $$));

    create function returns_double_array()
        returns double precision[] language sql stable
    as $$ select '{1.1, 2.2, 3.3}'::double precision[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsDoubleArray
        }
    $$));

    create function returns_numeric_array()
        returns numeric[] language sql stable
    as $$ select '{1.1, 2.2, 3.3}'::numeric[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsNumericArray
        }
    $$));

    create function returns_bool_array()
        returns bool[] language sql stable
    as $$ select '{true, false}'::bool[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsBoolArray
        }
    $$));

    create function returns_uuid_array()
        returns uuid[] language sql stable
    as $$ select '{"e8dc3a9a-2c72-11ee-b094-776acede6790", "d3ef3a8c-2c72-11ee-b094-776acede7221"}'::uuid[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsUuidArray
        }
    $$));

    create function returns_text_array()
        returns text[] language sql stable
    as $$ select '{"hello", "world"}'::text[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsTextArray
        }
    $$));

    create function returns_json_array()
        returns json[] language sql stable
    as $$ select array[json_build_object('hello', 'world'), json_build_object('bye', 'world')]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsJsonArray
        }
    $$));

    create function returns_jsonb_array()
        returns jsonb[] language sql stable
    as $$ select array[jsonb_build_object('hello', 'world'), jsonb_build_object('bye', 'world')]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsJsonbArray
        }
    $$));

    create function returns_date_array()
        returns date[] language sql stable
    as $$ select '{"2023-11-22", "2023-11-23", "2023-11-24"}'::date[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsDateArray
        }
    $$));

    create function returns_time_array()
        returns time[] language sql stable
    as $$ select '{"5:05", "5:06", "5:07"}'::time[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsTimeArray
        }
    $$));

    create function returns_timestamp_array()
        returns timestamp[] language sql stable
    as $$ select '{"2023-07-28 12:39:05", "2023-08-28 12:39:05", "2023-09-28 12:39:05"}'::timestamp[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsTimestampArray
        }
    $$));

    select jsonb_pretty(graphql.resolve($$
    query IntrospectionQuery {
        __schema {
            queryType {
                fields {
                    name
                    description
                    type {
                        kind
                        name
                        ofType {
                            kind
                            name
                            ofType {
                                kind
                                name
                            }
                        }
                    }
                    args {
                        name
                        type {
                            kind
                            name
                            ofType {
                                kind
                                name
                                ofType {
                                    kind
                                    name
                                }
                            }
                        }
                    }
                }
            }
        }
    } $$));

    rollback to savepoint a;

    --mutation tests

    -- functions accepting arrays
    create function get_smallint_array_item(arr smallint[], i int)
        returns smallint language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getSmallintArrayItem(arr: [1, 2, 3], i: 1)
        }
    $$));

    create function get_int_array_item(arr int[], i int)
        returns int language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getIntArrayItem(arr: [1, 2, 3], i: 2)
        }
    $$));

    create function get_bigint_array_item(arr bigint[], i int)
        returns bigint language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getBigintArrayItem(arr: ["1", "2", "3"], i: 3)
        }
    $$));

    create function get_real_array_item(arr real[], i int)
        returns real language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getRealArrayItem(arr: [1.1, 2.2, 3.3], i: 1)
        }
    $$));

    create function get_double_array_item(arr double precision[], i int)
        returns double precision language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getDoubleArrayItem(arr: [1.1, 2.2, 3.3], i: 2)
        }
    $$));

    create function get_numeric_array_item(arr numeric[], i int)
        returns numeric language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getNumericArrayItem(arr: ["1.1", "2.2", "3.3"], i: 3)
        }
    $$));

    create function get_bool_array_item(arr bool[], i int)
        returns bool language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getBoolArrayItem(arr: [true, false], i: 1)
        }
    $$));

    create function get_uuid_array_item(arr uuid[], i int)
        returns uuid language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getUuidArrayItem(arr: ["e8dc3a9a-2c72-11ee-b094-776acede6790", "d3ef3a8c-2c72-11ee-b094-776acede7221"], i: 2)
        }
    $$));

    create function get_text_array_item(arr text[], i int)
        returns text language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getTextArrayItem(arr: ["hello", "world"], i: 1)
        }
    $$));

    create function get_json_array_item(arr json[], i int)
        returns json language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getJsonArrayItem(arr: ["{\"hello\": \"world\"}", "{\"bye\": \"world\"}"], i: 2)
        }
    $$));

    create function get_jsonb_array_item(arr jsonb[], i int)
        returns jsonb language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getJsonbArrayItem(arr: ["{\"hello\": \"world\"}", "{\"bye\": \"world\"}"], i: 1)
        }
    $$));

    create function get_date_array_item(arr date[], i int)
        returns date language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getDateArrayItem(arr: ["2023-11-22", "2023-11-23", "2023-11-24"], i: 3)
        }
    $$));

    create function get_time_array_item(arr time[], i int)
        returns time language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getTimeArrayItem(arr: ["5:05", "5:06", "5:07"], i: 1)
        }
    $$));

    create function get_timestamp_array_item(arr timestamp[], i int)
        returns timestamp language sql volatile
    as $$ select arr[i]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getTimestampArrayItem(arr: ["2023-07-28 12:39:05", "2023-08-28 12:39:05", "2023-09-28 12:39:05"], i: 2)
        }
    $$));

    -- functions returning arrays
    create function returns_smallint_array()
        returns smallint[] language sql volatile
    as $$ select '{1, 2, 3}'::smallint[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsSmallintArray
        }
    $$));

    create function returns_int_array()
        returns int[] language sql volatile
    as $$ select '{1, 2, 3}'::int[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsIntArray
        }
    $$));

    create function returns_bigint_array()
        returns bigint[] language sql volatile
    as $$ select '{1, 2, 3}'::bigint[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsBigintArray
        }
    $$));

    create function returns_real_array()
        returns real[] language sql volatile
    as $$ select '{1.1, 2.2, 3.3}'::real[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsRealArray
        }
    $$));

    create function returns_double_array()
        returns double precision[] language sql volatile
    as $$ select '{1.1, 2.2, 3.3}'::double precision[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsDoubleArray
        }
    $$));

    create function returns_numeric_array()
        returns numeric[] language sql volatile
    as $$ select '{1.1, 2.2, 3.3}'::numeric[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsNumericArray
        }
    $$));

    create function returns_bool_array()
        returns bool[] language sql volatile
    as $$ select '{true, false}'::bool[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsBoolArray
        }
    $$));

    create function returns_uuid_array()
        returns uuid[] language sql volatile
    as $$ select '{"e8dc3a9a-2c72-11ee-b094-776acede6790", "d3ef3a8c-2c72-11ee-b094-776acede7221"}'::uuid[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsUuidArray
        }
    $$));

    create function returns_text_array()
        returns text[] language sql volatile
    as $$ select '{"hello", "world"}'::text[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsTextArray
        }
    $$));

    create function returns_json_array()
        returns json[] language sql volatile
    as $$ select array[json_build_object('hello', 'world'), json_build_object('bye', 'world')]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsJsonArray
        }
    $$));

    create function returns_jsonb_array()
        returns jsonb[] language sql volatile
    as $$ select array[jsonb_build_object('hello', 'world'), jsonb_build_object('bye', 'world')]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsJsonbArray
        }
    $$));

    create function returns_date_array()
        returns date[] language sql volatile
    as $$ select '{"2023-11-22", "2023-11-23", "2023-11-24"}'::date[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsDateArray
        }
    $$));

    create function returns_time_array()
        returns time[] language sql volatile
    as $$ select '{"5:05", "5:06", "5:07"}'::time[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsTimeArray
        }
    $$));

    create function returns_timestamp_array()
        returns timestamp[] language sql volatile
    as $$ select '{"2023-07-28 12:39:05", "2023-08-28 12:39:05", "2023-09-28 12:39:05"}'::timestamp[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsTimestampArray
        }
    $$));

    select jsonb_pretty(graphql.resolve($$
    query IntrospectionQuery {
        __schema {
            mutationType {
                fields {
                    name
                    description
                    type {
                        kind
                        name
                        ofType {
                            kind
                            name
                            ofType {
                                kind
                                name
                            }
                        }
                    }
                    args {
                        name
                        type {
                            kind
                            name
                            ofType {
                                kind
                                name
                                ofType {
                                    kind
                                    name
                                }
                            }
                        }
                    }
                }
            }
        }
    } $$));

    rollback to savepoint a;

    -- array args with default values are not yet supported
    create function return_input_array(arr smallint[] = '{4, 2}'::smallint[])
        returns smallint[] language sql stable
    as $$ select arr; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnInputArray
        }
    $$));

    -- composite type arrays are not supported
    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    create function returns_account_array()
        returns Account[] language sql stable
    as $$ select '{"(1, \"a@example.com\")", "(2, \"b@example.com\")"}'::Account[]; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            returnsAccountArray {
                id
            }
        }
    $$));

rollback;
