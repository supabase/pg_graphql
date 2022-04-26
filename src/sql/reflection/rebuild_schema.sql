-- Is updated every time the schema changes
create sequence if not exists graphql.seq_schema_version as int cycle;

-- Tracks the most recently built schema version
-- Contains 1 row
create table graphql.schema_version(ver int primary key);
insert into graphql.schema_version(ver) values (nextval('graphql.seq_schema_version') - 1);

create or replace function graphql.get_built_schema_version()
    returns int
    security definer
    language sql
as $$
    select ver from graphql.schema_version limit 1;
$$;

create or replace function graphql.rebuild_schema()
    returns void
    security definer
    language plpgsql
as $$
declare
    cur_schema_version int = last_value from graphql.seq_schema_version;
    built_schema_version int = graphql.get_built_schema_version();
begin
    if built_schema_version <> cur_schema_version then
        -- Lock the row to avoid concurrent access
        built_schema_version = ver from graphql.schema_version for update;

        -- Recheck condition now that we have aquired a row lock to avoid racing & stacking requests
        if built_schema_version <> cur_schema_version then
            truncate table graphql._field;
            delete from graphql._type;
            refresh materialized view graphql.entity with data;
            refresh materialized view graphql.entity_column with data;
            refresh materialized view graphql.entity_unique_columns with data;
            refresh materialized view graphql.relationship with data;
            perform graphql.rebuild_types();
            perform graphql.rebuild_fields();
            truncate table graphql.introspection_query_cache;

            -- Update the stored schema version value
            update graphql.schema_version set ver = cur_schema_version;

        end if;
    end if;
end;
$$;

create or replace function graphql.rebuild_on_ddl()
    returns event_trigger
    language plpgsql
as $$
declare
    cmd record;
begin
    for cmd IN select * FROM pg_event_trigger_ddl_commands()
    loop
        if cmd.command_tag in (
            'CREATE SCHEMA',
            'ALTER SCHEMA',
            'CREATE TABLE',
            'CREATE TABLE AS',
            'SELECT INTO',
            'ALTER TABLE',
            'CREATE FOREIGN TABLE',
            'ALTER FOREIGN TABLE'
            'CREATE VIEW',
            'ALTER VIEW',
            'CREATE MATERIALIZED VIEW',
            'ALTER MATERIALIZED VIEW',
            'CREATE FUNCTION',
            'ALTER FUNCTION',
            'CREATE TRIGGER',
            'CREATE TYPE',
            'CREATE RULE',
            'GRANT',
            'REVOKE',
            'COMMENT'
        )
        and cmd.schema_name is distinct from 'pg_temp'
        then
            perform nextval('graphql.seq_schema_version');
        end if;
    end loop;
end;
$$;


create or replace function graphql.rebuild_on_drop()
    returns event_trigger
    language plpgsql
as $$
declare
    obj record;
begin
    for obj IN SELECT * FROM pg_event_trigger_dropped_objects()
        loop
            if obj.object_type IN (
                'schema',
                'table',
                'foreign table',
                'view',
                'materialized view',
                'function',
                'trigger',
                'type',
                'rule'
            )
            and obj.is_temporary IS false
            then
                perform nextval('graphql.seq_schema_version');
            end if;
    end loop;
end;
$$;

select graphql.rebuild_schema();


-- On DDL event, increment the schema version number
create event trigger graphql_watch_ddl
    on ddl_command_end
    execute procedure graphql.rebuild_on_ddl();

create event trigger graphql_watch_drop
    on sql_drop
    execute procedure graphql.rebuild_on_drop();
