/// GraphQL field and argument name constants used throughout the codebase
///
/// This module centralizes all magic strings to prevent typos and make refactoring easier.

/// GraphQL introspection field names
pub mod introspection {
    pub const TYPENAME: &str = "__typename";
    pub const TYPE: &str = "__type";
    pub const SCHEMA: &str = "__schema";
}

/// Connection-related field names
pub mod connection {
    pub const EDGES: &str = "edges";
    pub const NODE: &str = "node";
    pub const PAGE_INFO: &str = "pageInfo";
    pub const TOTAL_COUNT: &str = "totalCount";
    pub const CURSOR: &str = "cursor";
}

/// Mutation result field names
pub mod mutation {
    pub const RECORDS: &str = "records";
    pub const AFFECTED_COUNT: &str = "affectedCount";
}

/// Pagination argument names
pub mod pagination {
    pub const FIRST: &str = "first";
    pub const LAST: &str = "last";
    pub const BEFORE: &str = "before";
    pub const AFTER: &str = "after";
    pub const OFFSET: &str = "offset";
}

/// Query argument names
pub mod args {
    pub const FILTER: &str = "filter";
    pub const ORDER_BY: &str = "orderBy";
    pub const OBJECTS: &str = "objects";
    pub const SET: &str = "set";
    pub const AT_MOST: &str = "atMost";
    pub const AT: &str = "at";
    pub const DELETE_USING_NODE_ID: &str = "deleteUsingNodeId";
    pub const NODE_ID: &str = "nodeId";
    pub const NAME: &str = "name";
}

/// Aggregate function field names
pub mod aggregate {
    pub const COUNT: &str = "count";
    pub const SUM: &str = "sum";
    pub const AVG: &str = "avg";
    pub const MIN: &str = "min";
    pub const MAX: &str = "max";
}

/// PageInfo field names
pub mod page_info {
    pub const HAS_NEXT_PAGE: &str = "hasNextPage";
    pub const HAS_PREVIOUS_PAGE: &str = "hasPreviousPage";
    pub const START_CURSOR: &str = "startCursor";
    pub const END_CURSOR: &str = "endCursor";
}
