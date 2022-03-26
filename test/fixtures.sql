create extension pg_graphql cascade;

comment on schema public is '@graphql({"inflect_names": true})';

-- Event triggers to watch for DDL and rebuild the schem
-- So we don't need to call `graphql.rebuild_schema()` manually
-- in each test
create event trigger graphql_watch_ddl
    on ddl_command_end
    execute procedure graphql.rebuild_on_ddl();

create event trigger graphql_watch_drop
    on sql_drop
    execute procedure graphql.rebuild_on_drop();
