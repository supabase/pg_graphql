// clang-format off
#include "postgres.h"
#include "funcapi.h"
// clang-format on
#include "graphqlparser/c/GraphQLParser.h"
#include "graphqlparser/c/GraphQLAstToJSON.h"
#include "tcop/utility.h"
#include "miscadmin.h"
#include "utils/varlena.h"
#include "utils/acl.h"

#include "parser/parser.h"
#include "utils/builtins.h"
#include "nodes/print.h"

#include "fmgr.h"
#include "catalog/pg_type.h"

#define PG13_GTE (PG_VERSION_NUM >= 130000)

// required macro for extension libraries to work
PG_MODULE_MAGIC;


PG_FUNCTION_INFO_V1(_parse);

Datum _parse(PG_FUNCTION_ARGS) {
    // Read argument 0 from the sql function call as text
    // and convert to a c string
    char *query = text_to_cstring(PG_GETARG_TEXT_PP(0));
    const char **error;
    struct GraphQLAstNode *node;
    const char *json;
    text *t;

    // TODO error handling
    // TODO free memory

    // Parse
    node = graphql_parse_string(query, error);

    json = graphql_ast_to_json(node);

    t = cstring_to_text(json);
    // t = cstring_to_text(error);

    // Return the text from the sql function
    PG_RETURN_TEXT_P(t);
}


PG_FUNCTION_INFO_V1(test_parse);

Datum
test_parse(PG_FUNCTION_ARGS) {
    TupleDesc   tupdesc;
	HeapTuple   rettuple;
    char		*values[2];

	tupdesc = CreateTemplateTupleDesc(2);
	TupleDescInitEntry(tupdesc, (AttrNumber) 1, "ast", TEXTOID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 2, "errors", TEXTOID, -1, 0);

	values[0] = "hello";
	values[1] = "world";

	rettuple = BuildTupleFromCStrings(TupleDescGetAttInMetadata(tupdesc), values);



    PG_RETURN_DATUM( HeapTupleGetDatum( rettuple ) );
}
