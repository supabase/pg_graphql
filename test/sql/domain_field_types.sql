begin;

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

  CREATE TABLE domain_test (
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
      field_timestamp domain_timestamp
  );

  INSERT INTO domain_test (field_int, field_smallint, field_bigint, field_numeric, field_real, field_double_precision, field_boolean, field_text, field_character, field_character_varying, field_date, field_time, field_timestamp)
  VALUES
      (42, 32767, 2165559898978,123.45, 3.14, 3.14159265359, true, 'Hello, world!', 'A', 'ABCD', '2022-01-01', '12:34:56', '2022-01-01 12:34:56'),
      (-123, -32768, -365989871454, -987.65, -2.71, -2.71828182846, false, 'Goodbye, world!', 'B', 'EFGH', '2022-02-02', '23:45:01', '2022-02-02 23:45:01');

  savepoint a;

  -- Check that a plain query resolves the base types and query filters work
  select  jsonb_pretty(
          graphql.resolve($$
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
          $$)
  );

  
  select jsonb_pretty(
    graphql.resolve($$
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
            }
          }
        }
      }
    $$)
  );

  -- Should probably test all of the filter but this is just a spot check
  select jsonb_pretty(
    graphql.resolve($$
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
      $$)
  );

  select jsonb_pretty(
    graphql.resolve($$
      {
        domainTestCollection(filter: {fieldBigint: {gt: 0}}) {
          edges {
            node {
              id
              fieldBigint
            }
          }
        }
      }
      $$)
  );

  select jsonb_pretty(
    graphql.resolve($$
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
      $$)
  );

  -- Check that insert mutation resolves the base types
  select  jsonb_pretty(
          graphql.resolve($$
            {
              __type(name: "DomainTestInsertInput") {
                inputFields {
                  name
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
          $$)
  );

  select jsonb_pretty(
    graphql.resolve($$
      mutation newDomainTest {
        insertIntoDomainTestCollection(objects: [{
          fieldInt: 42
          fieldSmallint: 32767
          fieldBigint: 2165559898978
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
        }]) {
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
          }
        }
      }
    $$)
  );

  rollback to savepoint a;

  -- TODO: Check that update mutation resolves the base types
  -- TODO: Check that delete mutation resolves the base types

end;