#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct GraphQLAstNode {
    _unused: [u8; 0],
}

extern "C" {
    #[doc = " Parse the given GraphQL source string, returning an AST. Returns"]
    #[doc = " NULL on error. Return value must be freed with"]
    #[doc = " graphql_node_free(). If NULL is returned and error is not NULL, an"]
    #[doc = " error message is placed in error and must be freed with"]
    #[doc = " graphql_error_free()."]
    pub fn graphql_parse_string(
        text: *const ::std::os::raw::c_char,
        error: *mut *const ::std::os::raw::c_char,
    ) -> *mut GraphQLAstNode;

    #[doc = " Serialize the given AST to JSON. The returned C string must be"]
    #[doc = " freed with free()."]
    pub fn graphql_ast_to_json(node: *const GraphQLAstNode) -> *const ::std::os::raw::c_char;

    #[doc = " Frees an error."]
    pub fn graphql_error_free(error: *const ::std::os::raw::c_char);

    pub fn graphql_node_free(node: *mut GraphQLAstNode);
}
