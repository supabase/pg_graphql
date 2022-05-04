#include "../submodules/libgraphqlparser/c/GraphQLParser.h"
#include "../submodules/libgraphqlparser/c/GraphQLAstNode.h"
#include "../submodules/libgraphqlparser/c/GraphQLAstToJSON.h"

/*
void parse_ast(char *query) {
// Read first argument as c string
    //char *query = text_to_cstring(PG_GETARG_TEXT_PP(0));
    struct GraphQLAstNode *node;

    const char *error = NULL;
    const char *ast = NULL;

    node = graphql_parse_string(query, &error);
    if (node != NULL) {
        ast = (char *) graphql_ast_to_json(node);
    }

    // clean up memory
    graphql_error_free(error);
    graphql_node_free(node);

    return ast;
}
*/

/*
void parse_graphql_to_json(
    char* query,
    //char* ast,
    //const char *error = NULL;
)
{
    char* ast;
    struct GraphQLAstNode *node;
    // Parse
    node = graphql_parse_string(query, &error);

    if (node == NULL) {
        ast = NULL;
    }
    else {
        ast = (char *) graphql_ast_to_json(node);
    }
    //graphql_error_free(error);
    graphql_node_free(node);

    return ast
}
*/
