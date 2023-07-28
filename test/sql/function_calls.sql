begin;

    savepoint a;
    -- Only volatilve functions appear on the mutation object

    create function add_smallints(a smallint, b smallint)
        returns smallint language sql volatile
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            addSmallints(a: 1, b: 2)
        }
    $$));

    create function add_ints(a int, b int)
        returns int language sql volatile
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            addInts(a: 2, b: 3)
        }
    $$));

    create function add_bigints(a bigint, b bigint)
        returns bigint language sql volatile
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            addBigints(a: 3, b: 4)
        }
    $$));

    create function add_reals(a real, b real)
        returns real language sql volatile
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            addReals(a: 4.5, b: 5.6)
        }
    $$));

    create function add_doubles(a double precision, b double precision)
        returns double precision language sql volatile
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            addDoubles(a: 7.8, b: 9.1)
        }
    $$));

    create function add_numerics(a numeric, b numeric)
        returns numeric language sql volatile
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            addNumerics(a: "11.12", b: "13.14")
        }
    $$));

    create function and_bools(a bool, b bool)
        returns bool language sql volatile
    as $$ select a and b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            andBools(a: true, b: false)
        }
    $$));

    create function uuid_identity(input uuid)
        returns uuid language sql volatile
    as $$ select input; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            uuidIdentity(input: "d3ef3a8c-2c72-11ee-b094-776acede7221")
        }
    $$));

    create function concat_text(a text, b text)
        returns text language sql volatile
    as $$ select a || b; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            concatText(a: "Hello ", b: "World")
        }
    $$));

    create function next_day(d date)
        returns date language sql volatile
    as $$ select d + interval '1 day'; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            nextDay(d: "2023-07-28")
        }
    $$));

    create function next_hour(t time)
        returns time language sql volatile
    as $$ select t + interval '1 hour'; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            nextHour(t: "10:20")
        }
    $$));

    set time zone 'Asia/Kolkata'; -- same as IST

    create function next_hour_with_timezone(t time with time zone)
        returns time with time zone language sql volatile
    as $$ select t + interval '1 hour'; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            nextHourWithTimezone(t: "10:20+05:30")
        }
    $$));

    create function next_minute(t timestamp)
        returns timestamp language sql volatile
    as $$ select t + interval '1 minute'; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            nextMinute(t: "2023-07-28 12:39:05")
        }
    $$));

    create function next_minute_with_timezone(t timestamptz)
        returns timestamptz language sql volatile
    as $$ select t + interval '1 minute'; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            nextMinuteWithTimezone(t: "2023-07-28 12:39:05+05:30")
        }
    $$));

    create function get_json_obj(input json, key text)
        returns json language sql volatile
    as $$ select input -> key; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            getJsonObj(input: "{\"a\": {\"b\": \"foo\"}}", key: "a")
        }
    $$));

    create function get_jsonb_obj(input jsonb, key text)
        returns jsonb language sql volatile
    as $$ select input -> key; $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            getJsonbObj(input: "{\"a\": {\"b\": \"foo\"}}", key: "a")
        }
    $$));

    create function concat_chars(a char(2), b char(3))
        returns char(5) language sql volatile
    as $$ select (a::char(2) || b::char(3))::char(5); $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            concatChars(a: "He", b: "llo")
        }
    $$));

    create function concat_varchars(a varchar(2), b varchar(3))
        returns varchar(5) language sql volatile
    as $$ select (a::varchar(2) || b::varchar(3))::varchar(5); $$;

    select jsonb_pretty(graphql.resolve($$
        mutation {
            concatVarchars(a: "He", b: "llo")
        }
    $$));

    rollback to savepoint a;

    -- Only stable and immutable functions appear on the query object

    create function add_smallints(a smallint, b smallint)
        returns smallint language sql stable
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            addSmallints(a: 1, b: 2)
        }
    $$));

    create function add_ints(a int, b int)
        returns int language sql immutable
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            addInts(a: 2, b: 3)
        }
    $$));

    create function add_bigints(a bigint, b bigint)
        returns bigint language sql stable
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            addBigints(a: 3, b: 4)
        }
    $$));

    create function add_reals(a real, b real)
        returns real language sql immutable
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            addReals(a: 4.5, b: 5.6)
        }
    $$));

    create function add_doubles(a double precision, b double precision)
        returns double precision language sql stable
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            addDoubles(a: 7.8, b: 9.1)
        }
    $$));

    create function add_numerics(a numeric, b numeric)
        returns numeric language sql immutable
    as $$ select a + b; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            addNumerics(a: "11.12", b: "13.14")
        }
    $$));

    create function and_bools(a bool, b bool)
        returns bool language sql stable
    as $$ select a and b; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            andBools(a: true, b: false)
        }
    $$));

    create function uuid_identity(input uuid)
        returns uuid language sql immutable
    as $$ select input; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            uuidIdentity(input: "d3ef3a8c-2c72-11ee-b094-776acede7221")
        }
    $$));

    create function concat_text(a text, b text)
        returns text language sql stable
    as $$ select a || b; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            concatText(a: "Hello ", b: "World")
        }
    $$));

    create function next_day(d date)
        returns date language sql immutable
    as $$ select d + interval '1 day'; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            nextDay(d: "2023-07-28")
        }
    $$));

    create function next_hour(t time)
        returns time language sql stable
    as $$ select t + interval '1 hour'; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            nextHour(t: "10:20")
        }
    $$));

    set time zone 'Asia/Kolkata'; -- same as IST

    create function next_hour_with_timezone(t time with time zone)
        returns time with time zone language sql immutable
    as $$ select t + interval '1 hour'; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            nextHourWithTimezone(t: "10:20+05:30")
        }
    $$));

    create function next_minute(t timestamp)
        returns timestamp language sql stable
    as $$ select t + interval '1 minute'; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            nextMinute(t: "2023-07-28 12:39:05")
        }
    $$));

    create function next_minute_with_timezone(t timestamptz)
        returns timestamptz language sql immutable
    as $$ select t + interval '1 minute'; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            nextMinuteWithTimezone(t: "2023-07-28 12:39:05+05:30")
        }
    $$));

    create function get_json_obj(input json, key text)
        returns json language sql stable
    as $$ select input -> key; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getJsonObj(input: "{\"a\": {\"b\": \"foo\"}}", key: "a")
        }
    $$));

    create function get_jsonb_obj(input jsonb, key text)
        returns jsonb language sql immutable
    as $$ select input -> key; $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            getJsonbObj(input: "{\"a\": {\"b\": \"foo\"}}", key: "a")
        }
    $$));

    create function concat_chars(a char(2), b char(3))
        returns char(5) language sql stable
    as $$ select (a::char(2) || b::char(3))::char(5); $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            concatChars(a: "He", b: "llo")
        }
    $$));

    create function concat_varchars(a varchar(2), b varchar(3))
        returns varchar(5) language sql immutable
    as $$ select (a::varchar(2) || b::varchar(3))::varchar(5); $$;

    select jsonb_pretty(graphql.resolve($$
        query {
            concatVarchars(a: "He", b: "llo")
        }
    $$));

rollback;
