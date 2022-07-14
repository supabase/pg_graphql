create table graphql._type (
    id serial primary key,
    type_kind graphql.type_kind not null,
    meta_kind graphql.meta_kind not null,
    is_builtin bool not null default false,
    constant_name text,
    name text not null,
    entity regclass,
    graphql_type_id int references graphql._type(id),
    enum regtype,
    description text,
    unique (meta_kind, entity),
    check (entity is null or graphql_type_id is null)
);

create index ix_graphql_type_name on graphql._type(name);
create index ix_graphql_type_type_kind on graphql._type(type_kind);
create index ix_graphql_type_meta_kind on graphql._type(meta_kind);
create index ix_graphql_type_graphql_type_id on graphql._type(graphql_type_id);
create index ix_graphql_type_name_regex on graphql._type ( (name ~ '^[_A-Za-z][_0-9A-Za-z]*$' ));


create or replace function graphql.inflect_type_default(text)
    returns text
    language sql
    immutable
as $$
    select replace(initcap($1), '_', '');
$$;


create function graphql.type_name(rec graphql._type)
    returns text
    immutable
    language sql
as $$
    with name_override as (
        select
            case
                when rec.entity is not null then coalesce(
                    -- Explicit name has firts priority
                    graphql.comment_directive_name(rec.entity),
                    -- When the schema has "inflect_names: true then inflect. otherwise, use table name
                    case graphql.comment_directive_inflect_names(current_schema::regnamespace)
                        when true then graphql.inflect_type_default(graphql.to_table_name(rec.entity))
                        else graphql.to_table_name(rec.entity)
                    end
                )
                else null
            end as base_type_name
    )
    select
        case
            when (rec).is_builtin then rec.meta_kind::text
            when rec.meta_kind='Node'         then base_type_name
            when rec.meta_kind='InsertNode'   then format('%sInsertInput',base_type_name)
            when rec.meta_kind='UpdateNode'   then format('%sUpdateInput',base_type_name)
            when rec.meta_kind='UpdateNodeResponse' then format('%sUpdateResponse',base_type_name)
            when rec.meta_kind='InsertNodeResponse' then format('%sInsertResponse',base_type_name)
            when rec.meta_kind='DeleteNodeResponse' then format('%sDeleteResponse',base_type_name)
            when rec.meta_kind='Edge'         then format('%sEdge',       base_type_name)
            when rec.meta_kind='Connection'   then format('%sConnection', base_type_name)
            when rec.meta_kind='OrderBy'      then format('%sOrderBy',    base_type_name)
            when rec.meta_kind='FilterEntity' then format('%sFilter',     base_type_name)
            when rec.meta_kind='FilterType'        then format('%sFilter',     graphql.type_name(rec.graphql_type_id))
            when rec.meta_kind='OrderByDirection'  then rec.meta_kind::text
            when rec.meta_kind='PageInfo'     then rec.meta_kind::text
            when rec.meta_kind='Cursor'       then rec.meta_kind::text
            when rec.meta_kind='Query'        then rec.meta_kind::text
            when rec.meta_kind='Mutation'     then rec.meta_kind::text
            when rec.meta_kind='Enum'         then coalesce(
                graphql.comment_directive_name(rec.enum),
                graphql.inflect_type_default(graphql.to_type_name(rec.enum))
            )
            else graphql.exception('could not determine type name')
        end
    from
        name_override
$$;

create function graphql.type_name(type_id int)
    returns text
    immutable
    language sql
as $$
    select
        graphql.type_name(rec)
    from
        graphql._type rec
    where
        id = $1;
$$;

create function graphql.type_name(regclass, graphql.meta_kind)
    returns text
    immutable
    language sql
as $$
    select
        graphql.type_name(rec)
    from
        graphql._type rec
    where
        entity = $1
        and meta_kind = $2
$$;

create function graphql.set_type_name()
    returns trigger
    language plpgsql
as $$
begin
    new.name = coalesce(
        new.constant_name,
        graphql.type_name(new)
    );
    return new;
end;
$$;

create trigger on_insert_set_name
    before insert on graphql._type
    for each row execute procedure graphql.set_type_name();
