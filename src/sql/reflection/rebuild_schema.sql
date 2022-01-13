create or replace function graphql.rebuild_schema() returns event_trigger
  language plpgsql
as $$
begin
    if tg_tag = 'REFRESH MATERIALIZED VIEW' then
        return;
    end if;

    refresh materialized view graphql.entity with data;
    perform graphql.rebuild_types();
    refresh materialized view graphql._field_output with data;
    refresh materialized view graphql._field_arg with data;
    refresh materialized view graphql.enum_value with data;
end;
$$;


create event trigger graphql_watch
    on ddl_command_end
    execute procedure graphql.rebuild_schema();
