create table graphql._type (
    id serial primary key,
    type_kind graphql.type_kind not null,
    meta_kind graphql.meta_kind not null,
    is_builtin bool not null default false,
    entity regclass,
    graphql_type_id int references graphql._type(id),
    enum regtype,
    description text,
    unique (meta_kind, entity),
    check (entity is null or graphql_type_id is null)
);


create or replace function graphql.inflect_type_default(text)
    returns text
    language sql
    immutable
as $$
    select replace(initcap($1), '_', '');
$$;


create function graphql.type_name(rec graphql._type, dialect text = 'default')
    returns text
    immutable
    language sql
as $$
    select
        case
            when (rec).is_builtin then rec.meta_kind::text
            when dialect = 'default' then
                case rec.meta_kind
                    when 'Node'         then graphql.inflect_type_default(graphql.to_table_name(rec.entity))
                    when 'Edge'         then format('%sEdge',       graphql.inflect_type_default(graphql.to_table_name(rec.entity)))
                    when 'Connection'   then format('%sConnection', graphql.inflect_type_default(graphql.to_table_name(rec.entity)))
                    when 'OrderBy'      then format('%sOrderBy',    graphql.inflect_type_default(graphql.to_table_name(rec.entity)))
                    when 'FilterEntity' then format('%sFilter',     graphql.inflect_type_default(graphql.to_table_name(rec.entity)))
                    when 'FilterType'   then format('%sFilter',     graphql.type_name(rec.graphql_type_id))
                    when 'OrderByDirection' then rec.meta_kind::text
                    when 'PageInfo'     then rec.meta_kind::text
                    when 'Cursor'       then rec.meta_kind::text
                    when 'Query'        then rec.meta_kind::text
                    when 'Mutation'     then rec.meta_kind::text
                    when 'Enum'         then graphql.inflect_type_default(graphql.to_type_name(rec.enum))
                    else                graphql.exception('could not determine type name')
                end
            else graphql.exception('unknown dialect')
        end
$$;

create function graphql.type_name(type_id int, dialect text = 'default')
    returns text
    immutable
    language sql
as $$
    select
        graphql.type_name(rec, $2)
    from
        graphql._type rec
    where
        id = $1;
$$;



create index ix_graphql_type_name_dialect_default on graphql._type(
    graphql.type_name(rec := _type, dialect := 'default'::text)
);
