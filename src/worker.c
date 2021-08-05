// clang-format off
#include "postgres.h"
// clang-format on
#include "graphqlparser/c/GraphQLParser.h"
#include "tcop/utility.h"
#include "miscadmin.h"
#include "utils/varlena.h"
#include "utils/acl.h"

#include "parser/parser.h"
#include "utils/builtins.h"
#include "nodes/print.h"

#define PG13_GTE (PG_VERSION_NUM >= 130000)

// required macro for extension libraries to work
PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(sql_to_ast);

Datum sql_to_ast(PG_FUNCTION_ARGS) {
    // Read argument 0 from the sql function call as text
    // and convert to a c string
    char *query = text_to_cstring(PG_GETARG_TEXT_PP(0));
    List *tree;
    char *tree_str;
    char *tree_str_pretty;
    text *t;

    // List of AST node as c structs
    tree = raw_parser(query);
    // Compact stringified AST
    tree_str = nodeToString(tree);
    // Stringified AST with space for readability
    tree_str_pretty = pretty_format_node_dump(tree_str);
    // Convert back to a postgres text type
    t = cstring_to_text(tree_str_pretty);

    pfree(tree);
    pfree(tree_str);
    pfree(tree_str_pretty);

    // Return the text from the sql function
    PG_RETURN_TEXT_P(t);
}

PG_FUNCTION_INFO_V1(parse);

Datum parse(PG_FUNCTION_ARGS) {
    // Read argument 0 from the sql function call as text
    // and convert to a c string
    char *query = text_to_cstring(PG_GETARG_TEXT_PP(0));
    const char **error;
    text *t;
    struct GraphQLAstNode *node;

    // Parse
    node = graphql_parse_string(query, error);

    t = cstring_to_text(query);

    // Return the text from the sql function
    PG_RETURN_TEXT_P(t);
}
