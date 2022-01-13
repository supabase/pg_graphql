create or replace function graphql.inflect_type_default(text)
    returns text
    language sql
    immutable
as $$
    select replace(initcap($1), '_', '');
$$;


create function graphql.type_name(rec graphql.__type, dialect text = 'default')
    returns text
    language sql
    immutable
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
                    when 'FilterType'   then format('%sFilter',     rec.graphql_type)
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


create index ix_graphql_type_name_dialect_default on graphql.__type(
    graphql.type_name(rec := __type, dialect := 'default'::text)
);
