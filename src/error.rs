use graphql_parser::query::ParseError as GraphQLParseError;
use thiserror::Error;

/// Central error type for all pg_graphql operations.
/// This replaces string-based error handling with strongly-typed variants.
#[derive(Debug, Error)]
pub enum GraphQLError {
    /// GraphQL query parsing errors
    #[error("Parse error: {0}")]
    Parse(#[from] GraphQLParseError),

    /// Field resolution errors
    #[error("Field not found: {field} on type {type_name}")]
    FieldNotFound { field: String, type_name: String },

    /// General operation errors with context
    #[error("{context}: {message}")]
    Operation { context: String, message: String },
}

impl GraphQLError {
    /// Creates a field not found error
    pub fn field_not_found(field: impl Into<String>, type_name: impl Into<String>) -> Self {
        Self::FieldNotFound {
            field: field.into(),
            type_name: type_name.into(),
        }
    }

    /// Creates a validation error
    pub fn validation(message: impl Into<String>) -> Self {
        Self::Operation {
            context: "Validation error".to_string(),
            message: message.into(),
        }
    }

    /// Creates a schema error
    pub fn schema(message: impl Into<String>) -> Self {
        Self::Operation {
            context: "Schema error".to_string(),
            message: message.into(),
        }
    }

    /// Creates a type error
    pub fn type_error(message: impl Into<String>) -> Self {
        Self::Operation {
            context: "Type error".to_string(),
            message: message.into(),
        }
    }

    /// Creates an argument error
    pub fn argument(message: impl Into<String>) -> Self {
        Self::Operation {
            context: "Argument error".to_string(),
            message: message.into(),
        }
    }

    /// Creates a SQL generation error
    pub fn sql_generation(message: impl Into<String>) -> Self {
        Self::Operation {
            context: "SQL generation error".to_string(),
            message: message.into(),
        }
    }

    /// Creates a SQL execution error
    pub fn sql_execution(message: impl Into<String>) -> Self {
        Self::Operation {
            context: "SQL execution error".to_string(),
            message: message.into(),
        }
    }

    /// Creates an authorization error
    pub fn authorization(message: impl Into<String>) -> Self {
        Self::Operation {
            context: "Authorization error".to_string(),
            message: message.into(),
        }
    }

    /// Creates an internal error
    pub fn internal(message: impl Into<String>) -> Self {
        Self::Operation {
            context: "Internal error".to_string(),
            message: message.into(),
        }
    }

    /// Creates an unsupported operation error
    pub fn unsupported_operation(operation: impl Into<String>) -> Self {
        Self::Operation {
            context: "Operation not supported".to_string(),
            message: operation.into(),
        }
    }

    /// Creates a configuration error
    pub fn configuration(message: impl Into<String>) -> Self {
        Self::Operation {
            context: "Configuration error".to_string(),
            message: message.into(),
        }
    }
}

/// Type alias for Results that use GraphQLError
pub type GraphQLResult<T> = Result<T, GraphQLError>;
