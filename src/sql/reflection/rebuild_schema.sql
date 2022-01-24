create or replace function graphql.rebuild_schema()
    returns void
    language plpgsql
as $$
begin
    truncate table graphql._field;
    delete from graphql._type;
    refresh materialized view graphql.entity with data;
    perform graphql.rebuild_types();
    perform graphql.rebuild_fields();
    refresh materialized view graphql.enum_value with data;
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
            'COMMENT'
        )
        and cmd.schema_name is distinct from 'pg_temp'
        then
            perform graphql.rebuild_schema();
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
            'rule',
        )
        and obj.is_temporary IS false
        then
            perform graphql.rebuild_schema();
        end if
    end loop;
end;
$$;


create event trigger graphql_watch_ddl
    on ddl_command_end
    execute procedure graphql.rebuild_on_ddl();

create event trigger graphql_watch_drop
    on sql_drop
    execute procedure graphql.rebuild_on_ddl();
