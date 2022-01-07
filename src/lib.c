// clang-format off
#include "postgres.h"
#include "funcapi.h"
// clang-format on
#include "graphqlparser/c/GraphQLParser.h"
#include "graphqlparser/c/GraphQLAstToJSON.h"
#include "graphqlparser/c/GraphQLAstNode.h"
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


PG_FUNCTION_INFO_V1(parse);

Datum
parse(PG_FUNCTION_ARGS) {
	// Read first argument as c string
    char *query = text_to_cstring(PG_GETARG_TEXT_PP(0));
	struct GraphQLAstNode *node;
    const char *error = NULL;


	// Description of the composite type we're returning
    TupleDesc   tupdesc;
	// Heap allocated tuple we will return
	HeapTuple   rettuple;
    char        *values[2];

	// Define the structure of the composite type
	// 2 attributes
	tupdesc = CreateTemplateTupleDesc(2);
	// definition of attr 1
	TupleDescInitEntry(tupdesc, (AttrNumber) 1, "ast", TEXTOID, -1, 0);
	// definition of attr 2
	TupleDescInitEntry(tupdesc, (AttrNumber) 2, "error", TEXTOID, -1, 0);

	// Values for the output
	// Parse
    node = graphql_parse_string(query, &error);
	if (node == NULL) {
		values[0] = NULL;
	}
	else {
		values[0] = (char *) graphql_ast_to_json(node);
	}
	values[1] = (char *) error;

	// convert values into a heap allocated tuple with the description we defined
	rettuple = BuildTupleFromCStrings(TupleDescGetAttInMetadata(tupdesc), values);

    // clean up memory
	graphql_error_free(error);
	graphql_node_free(node);

	// return the heap tuple as datum
    PG_RETURN_DATUM( HeapTupleGetDatum( rettuple ) );
}
