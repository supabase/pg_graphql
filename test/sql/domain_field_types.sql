begin;

comment on schema public is e'@graphql({"inflect_names": true, "resolve_base_type": true})';

CREATE DOMAIN domain_int AS int;

CREATE DOMAIN domain_smallint AS smallint;

CREATE DOMAIN domain_bigint AS bigint;

CREATE DOMAIN domain_numeric AS numeric;

CREATE DOMAIN domain_real AS real;

CREATE DOMAIN domain_double_precision AS double precision;

CREATE DOMAIN domain_boolean AS boolean;

CREATE DOMAIN domain_text AS text;

CREATE DOMAIN domain_character AS character;

CREATE DOMAIN domain_character_varying AS character varying;

CREATE DOMAIN domain_date AS date;

CREATE DOMAIN domain_time AS time;

CREATE DOMAIN domain_timestamp AS timestamp;

CREATE DOMAIN domain_jsonb AS jsonb;

CREATE DOMAIN domain_json AS json;

CREATE TABLE
  domain_test (
    id SERIAL PRIMARY KEY,
    field_int domain_int,
    field_smallint domain_smallint,
    field_bigint domain_bigint,
    field_numeric domain_numeric,
    field_real domain_real,
    field_double_precision domain_double_precision,
    field_boolean domain_boolean,
    field_text domain_text,
    field_character domain_character,
    field_character_varying domain_character_varying,
    field_date domain_date,
    field_time domain_time,
    field_timestamp domain_timestamp,
    field_jsonb domain_jsonb,
    field_json domain_json
  );

INSERT INTO
  domain_test (
    field_int,
    field_smallint,
    field_bigint,
    field_numeric,
    field_real,
    field_double_precision,
    field_boolean,
    field_text,
    field_character,
    field_character_varying,
    field_date,
    field_time,
    field_timestamp,
    field_jsonb,
    field_json
  )
VALUES
  (
    42,
    32767,
    2165559898978,
    123.45,
    3.14,
    3.14159265359,
    true,
    'Hello, world!',
    'A',
    'ABCD',
    '2022-01-01',
    '12:34:56',
    '2022-01-01 12:34:56',
    '{"a": 1}',
    '{"b": 2}'
  ),
  (
    -123,
    -32768,
    -365989871454,
    -987.65,
    -2.71,
    -2.71828182846,
    false,
    'Goodbye, world!',
    'B',
    'EFGH',
    '2022-02-02',
    '23:45:01',
    '2022-02-02 23:45:01',
    '{"c": -3}',
    '{"d": -4}'
  );

savepoint a;

-- Check that a plain query resolves the base types
select
  graphql.resolve (
    $$
      {
        __type(name: "DomainTest") {
          kind
          fields {
              name
              type {
                  name
                  kind
              }
          }
        }
      }
    $$
  );

select
  graphql.resolve (
    $$
      {
        domainTestCollection {
          edges {
            node {
              id
              fieldInt
              fieldSmallint
              fieldBigint
              fieldNumeric
              fieldReal
              fieldDoublePrecision
              fieldBoolean
              fieldText
              fieldCharacter
              fieldCharacterVarying
              fieldDate
              fieldTime
              fieldTimestamp
              fieldJsonb
              fieldJson
            }
          }
        }
      }
    $$
  );

-- Get the filter types, specifically shouldn't see json and jsonb types as they aren't supported yet
select graphql.resolve(
  $$
  {
    __type(name: "DomainTestFilter"){
      inputFields{
        name
        type{
          name
        }
      }
    }
  }
  $$
);

-- Should probably test all of the filters but this is just a spot check
select
    graphql.resolve (
      $$
      {
        domainTestCollection(filter: {fieldInt: {gt: 41}}) {
          edges {
            node {
              id
              fieldInt
            }
          }
        }
      }
      $$
    );

select
  graphql.resolve (
    $$
    {
      domainTestCollection(filter: {fieldBigint: {gt: "2165559898977"}}){
        edges{
          node{
            id
            fieldBigint
          }
        }
      }
    }
    $$
  );

select
    graphql.resolve (
      $$
      {
        domainTestCollection(filter: {fieldNumeric: {gt: "0"}}) {
          edges {
            node {
              id
              fieldNumeric
            }
          }
        }
      }
      $$
    );

select
  graphql.resolve (
    $$
    {
      domainTestCollection(filter: {fieldText: {startsWith: "Hello"}}){
        edges{
          node{
            id
            fieldText
          }
        }
      }
    }
    $$
  );

-- Insert types and mutation
select
    graphql.resolve (
    $$
    {
      __type(name: "DomainTestInsertInput") {
        inputFields {
          name
          type {
            name
            kind
          }
        }
      }
    }
    $$
    );

select
  graphql.resolve (
    $$
      mutation newDomainTest {
        insertIntoDomainTestCollection(objects: [{
          fieldInt: 42
          fieldSmallint: 32767
          fieldBigint: "2165559898978"
          fieldNumeric: "123.45"
          fieldReal: 3.14
          fieldDoublePrecision: 3.141592
          fieldBoolean: true
          fieldText: "Hello, world!"
          fieldCharacter: "A"
          fieldCharacterVarying: "ABCD"
          fieldDate: "2022-01-01"
          fieldTime: "12:34:56"
          fieldTimestamp: "2022-01-01 12:34:56"
          fieldJsonb: "{\"c\": -3}",
          fieldJson: "{\"d\": 12}"
        }]) {
          affectedCount
          records {
            id
            fieldInt
            fieldSmallint
            fieldBigint
            fieldNumeric
            fieldReal
            fieldDoublePrecision
            fieldBoolean
            fieldText
            fieldCharacter
            fieldCharacterVarying
            fieldDate
            fieldTime
            fieldTimestamp
            fieldJsonb
            fieldJson
          }
        }
      }
    $$
  );

rollback to savepoint a;

-- Update types and mutation

select
    graphql.resolve (
      $$
      {
        __type(name: "DomainTestUpdateInput") {
          inputFields {
            name
            type {
              name
              kind
            }
          }
        }
      }
      $$
  );

select
    graphql.resolve (
      $$
    mutation updateDomainTest {
      updateDomainTestCollection(
        set: {
          fieldInt: 43
          fieldSmallint: 32766
          fieldBigint: 2165559898977
          fieldNumeric: "123.46"
          fieldReal: 3.15
          fieldDoublePrecision: 3.141593
          fieldBoolean: false
          fieldText: "Hello, world!!"
          fieldCharacter: "B"
          fieldCharacterVarying: "ABCDE"
          fieldDate: "2022-01-02"
          fieldTime: "12:34:57"
          fieldTimestamp: "2022-01-02 12:34:57",
          fieldJsonb: "{\"c\": -3}",
          fieldJson: "{\"d\": 12}"
        }
        filter: {
          id: {eq: 1}
        }
      ) {
        affectedCount
        records {
          id
          fieldInt
          fieldSmallint
          fieldBigint
          fieldNumeric
          fieldReal
          fieldDoublePrecision
          fieldBoolean
          fieldText
          fieldCharacter
          fieldCharacterVarying
          fieldDate
          fieldTime
          fieldTimestamp
          fieldJsonb
          fieldJson
        }
      }
    }
    $$
    );

rollback to savepoint a;

-- Delete mutation, more a canary in a coal mine than anything else as the types are the same as the select

select graphql.resolve(
  $$
  mutation deleteDomainTest {
    deleteDomainTestCollection(
      filter: {
        id: {eq: 1}
      }
    ) {
      affectedCount
      records {
        id
        fieldInt
        fieldSmallint
        fieldBigint
        fieldNumeric
        fieldReal
        fieldDoublePrecision
        fieldBoolean
        fieldText
        fieldCharacter
        fieldCharacterVarying
        fieldDate
        fieldTime
        fieldTimestamp
        fieldJsonb
        fieldJson
      }
    }
  }
  $$
);
rollback;
