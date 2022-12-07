use crate::sql_types::*;
use itertools::Itertools;
use lazy_static::lazy_static;
use regex::Regex;
use serde::Serialize;
use std::collections::HashMap;
use std::rc::Rc;

impl Context {
    fn inflect_names(&self, schema_oid: u32) -> bool {
        let schema = self.schemas.iter().find(|x| x.oid == schema_oid);
        schema.map(|s| s.directives.inflect_names).unwrap_or(false)
    }
}

fn to_base_type_name(
    table_name: &str,
    name_override: &Option<String>,
    inflect_names: bool,
) -> String {
    match name_override {
        Some(name) => return name.to_string(),
        None => (),
    };

    match inflect_names {
        false => table_name.to_string(),
        true => {
            let mut padded = "+".to_string();
            padded.push_str(table_name);

            // account_BY_email => Account_By_Email
            let casing: String = padded
                .chars()
                .zip(table_name.chars())
                .map(|(prev, cur)| match prev.is_alphanumeric() {
                    true => cur.to_string(),
                    false => cur.to_uppercase().to_string(),
                })
                .collect();

            str::replace(&casing, "_", "")
        }
    }
}

fn lowercase_first_letter(token: &str) -> String {
    token[0..1].to_lowercase() + &token[1..]
}

impl Table {
    fn graphql_base_type_name(&self) -> String {
        to_base_type_name(
            &self.name,
            &self.directives.name,
            self.directives.inflect_names,
        )
    }
}

impl Column {
    fn graphql_field_name(&self) -> String {
        if let Some(override_name) = &self.directives.name {
            return override_name.clone();
        }

        let base_type_name = to_base_type_name(
            &self.name,
            &self.directives.name,
            self.directives.inflect_names,
        );

        match self.directives.inflect_names {
            // Lowercase first letter
            // AccountByEmail => accountByEmail
            true => lowercase_first_letter(&base_type_name),
            false => base_type_name,
        }
    }
}

impl Function {
    fn graphql_field_name(&self) -> String {
        if let Some(override_name) = &self.directives.name {
            return override_name.clone();
        }

        // remove underscore prefix from function name before inflecting
        let trimmed_function_name = &self.name.strip_prefix('_').unwrap_or(&self.name);

        let base_type_name = to_base_type_name(
            trimmed_function_name,
            &self.directives.name,
            self.directives.inflect_names,
        );
        lowercase_first_letter(&base_type_name)
    }
}

impl Enum {
    fn graphql_base_type_name(&self, inflect_names: bool) -> String {
        to_base_type_name(&self.name, &self.directives.name, inflect_names)
    }
}

impl ForeignKey {
    fn graphql_field_name(&self, reverse_reference: bool) -> String {
        let mut table_ref: &ForeignKeyTableInfo = &self.referenced_table_meta;
        let mut name_override: &Option<String> = &self.directives.foreign_name;
        let mut is_unique: bool = true;
        let mut column_names: &Vec<String> = &self.local_table_meta.column_names;

        if reverse_reference {
            table_ref = &self.local_table_meta;
            name_override = &self.directives.local_name;
            is_unique = self.is_locally_unique;
            column_names = &self.referenced_table_meta.column_names;
        }

        let is_inflection_on = table_ref.directives.inflect_names;

        // If name is overridden, return immediately
        match name_override {
            Some(name) => return name.to_string(),
            None => (),
        }
        // "AccountHolder"
        let base_type_name = to_base_type_name(
            &table_ref.name,
            &table_ref.directives.name,
            is_inflection_on,
        );

        // "accountHolder"
        let base_type_as_field_name = lowercase_first_letter(&base_type_name);

        let singular_name = match &column_names[..] {
            [column_name] => match is_inflection_on {
                true => match column_name.strip_suffix("_id") {
                    Some(column_name_stripped) => {
                        let base = to_base_type_name(
                            column_name_stripped,
                            &None,
                            table_ref.directives.inflect_names,
                        );
                        lowercase_first_letter(&base)
                    }
                    None => base_type_as_field_name.clone(),
                },
                false => match column_name.strip_suffix("Id") {
                    Some(column_name_stripped) => {
                        let base = to_base_type_name(
                            column_name_stripped,
                            &None,
                            table_ref.directives.inflect_names,
                        );
                        lowercase_first_letter(&base)
                    }
                    None => base_type_as_field_name.clone(),
                },
            },
            _ => base_type_as_field_name.clone(),
        };

        match is_unique {
            true => singular_name,
            false => format!("{base_type_as_field_name}Collection"),
        }
    }
}

lazy_static! {
    static ref GRAPHQL_NAME_RE: Regex = Regex::new("^[_A-Za-z][_0-9A-Za-z]*$").unwrap();
}

fn is_valid_graphql_name(name: &str) -> bool {
    GRAPHQL_NAME_RE.is_match(name)
}

impl Table {
    fn graphql_select_types_are_valid(&self) -> bool {
        let check1 = is_valid_graphql_name(&self.graphql_base_type_name());
        let check2 = self.primary_key().is_some();
        // Any column is selectable
        let check3 = self.is_any_column_selectable();

        check1 && check2 && check3
    }

    fn graphql_insert_types_are_valid(&self) -> bool {
        let check1 = self.graphql_select_types_are_valid();
        let check2 = self.is_any_column_insertable();
        check1 && check2
    }

    fn graphql_update_types_are_valid(&self) -> bool {
        let check1 = self.graphql_select_types_are_valid();
        let check2 = self.is_any_column_updatable();
        check1 && check2
    }

    fn graphql_delete_types_are_valid(&self) -> bool {
        let check1 = self.graphql_select_types_are_valid();
        let check2 = self.permissions.is_deletable;
        check1 && check2
    }
}

pub trait ___Type {
    // kind: __TypeKind!
    fn kind(&self) -> __TypeKind;

    // name: String
    fn name(&self) -> Option<String> {
        None
    }

    // description: String
    fn description(&self) -> Option<String> {
        None
    }

    // # OBJECT and INTERFACE only
    // fields(includeDeprecated: Boolean = false): [__Field!]
    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        None
    }

    // # OBJECT only
    // interfaces: [__Type!]
    fn interfaces(&self) -> Option<Vec<__Type>> {
        None
    }

    // # INTERFACE and UNION only
    // possibleTypes: [__Type!]
    fn possible_types(&self) -> Option<Vec<__Type>> {
        None
    }

    // # ENUM only
    // enumValues(includeDeprecated: Boolean = false): [__EnumValue!]
    fn enum_values(&self, _include_deprecated: bool) -> Option<Vec<__EnumValue>> {
        Some(vec![])
    }

    // # INPUT_OBJECT only
    // inputFields: [__InputValue!]
    fn input_fields(&self) -> Option<Vec<__InputValue>> {
        None
    }

    // # NON_NULL and LIST only
    // ofType: __Type
    fn of_type(&self) -> Option<__Type> {
        None
    }

    fn field_map(&self) -> HashMap<String, __Field> {
        let mut hmap = HashMap::new();
        let fields = self.fields(true).unwrap_or_default();
        for field in fields {
            hmap.insert(field.name(), field);
        }
        hmap.insert(
            "__typename".to_string(),
            __Field {
                name_: "__typename".to_string(),
                description: None,
                type_: __Type::Scalar(Scalar::String),
                args: vec![],
                deprecation_reason: None,
                sql_type: None,
            },
        );
        hmap
    }

    fn input_field_map(&self) -> HashMap<String, __InputValue> {
        let mut hmap = HashMap::new();
        let fields = self.input_fields().unwrap_or_default();
        for field in fields {
            hmap.insert(field.name(), field);
        }
        hmap
    }
}

pub struct __Directive {}

pub struct __DirectiveLocation {}

pub trait ___Field {
    // name: String!
    fn name(&self) -> String;

    // description: String
    fn description(&self) -> Option<String>;

    // args: [__InputValue!]!
    fn args(&self) -> Vec<__InputValue>;

    // type: __Type!
    /// The literal introspection type, including type modifiers
    fn type_(&self) -> __Type;

    // isDeprecated: Boolean!
    fn is_deprecated(&self) -> bool {
        self.deprecation_reason().is_none()
    }

    // deprecationReason: String
    fn deprecation_reason(&self) -> Option<String> {
        None
    }

    fn arg_map(&self) -> HashMap<String, __InputValue> {
        let mut amap = HashMap::new();
        let args = self.args();
        for arg in args {
            amap.insert(arg.name_.clone(), arg.clone());
        }
        amap
    }
}

#[derive(Clone, Debug)]
pub enum NodeSQLType {
    Column(Column),
    NodeId(Vec<Column>),
    Function(Function),
}

#[derive(Clone, Debug)]
pub struct __Field {
    pub name_: String,
    pub description: Option<String>,
    pub type_: __Type,
    pub args: Vec<__InputValue>,
    pub deprecation_reason: Option<String>,

    // Only set for Node types
    pub sql_type: Option<NodeSQLType>,
}

impl __Field {
    pub fn get_arg(&self, name: &str) -> Option<__InputValue> {
        for arg in &self.args {
            if arg.name().as_str() == name {
                return Some(arg.clone());
            }
        }
        None
    }
}

impl ___Field for __Field {
    // name: String!
    fn name(&self) -> String {
        self.name_.clone()
    }

    // description: String
    fn description(&self) -> Option<String> {
        self.description.clone()
    }

    // args: [__InputValue!]!
    fn args(&self) -> Vec<__InputValue> {
        self.args.clone()
    }

    // type: __Type!
    /// The literal introspection type, including type modifiers
    fn type_(&self) -> __Type {
        self.type_.clone()
    }

    // isDeprecated: Boolean!
    fn is_deprecated(&self) -> bool {
        self.deprecation_reason().is_some()
    }

    // deprecationReason: String
    fn deprecation_reason(&self) -> Option<String> {
        self.deprecation_reason.clone()
    }
}

#[derive(Clone, Debug)]
pub struct __InputValue {
    pub name_: String,
    pub type_: __Type,
    pub description: Option<String>,
    pub default_value: Option<String>,
    pub sql_type: Option<NodeSQLType>,
}

impl __InputValue {
    // name: String!
    pub fn name(&self) -> String {
        self.name_.clone()
    }

    // description: String
    pub fn description(&self) -> Option<String> {
        self.description.clone()
    }

    // type: __Type!
    pub fn type_(&self) -> __Type {
        self.type_.clone()
    }

    // defaultValue: String
    pub fn default_value(&self) -> Option<String> {
        self.default_value.clone()
    }

    // isDeprecated: Boolean!
    pub fn is_deprecated(&self) -> bool {
        self.deprecation_reason().is_some()
    }

    // deprecationReason: String
    pub fn deprecation_reason(&self) -> Option<String> {
        None
    }
}

#[allow(non_camel_case_types, clippy::upper_case_acronyms)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum __TypeKind {
    SCALAR,
    OBJECT,
    INTERFACE,
    UNION,
    ENUM,
    INPUT_OBJECT,
    LIST,
    NON_NULL,
}

#[derive(Clone, Debug)]
pub struct __EnumValue {
    name: String,
    description: Option<String>,
    deprecation_reason: Option<String>,
}
impl __EnumValue {
    // name: String!
    pub fn name(&self) -> String {
        self.name.clone()
    }

    // description: String
    pub fn description(&self) -> Option<String> {
        self.description.clone()
    }

    // isDeprecated: Boolean!
    pub fn is_deprecated(&self) -> bool {
        self.deprecation_reason.is_some()
    }

    // deprecationReason: String
    pub fn deprecation_reason(&self) -> Option<String> {
        None
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum __Type {
    Scalar(Scalar),
    //Composite(Composite),
    // Query
    Query(QueryType),
    Connection(ConnectionType),
    Edge(EdgeType),
    Node(NodeType),
    Enum(EnumType),
    NodeInterface(NodeInterfaceType),
    // Mutation
    Mutation(MutationType),
    InsertInput(InsertInputType),
    InsertResponse(InsertResponseType),
    UpdateInput(UpdateInputType),
    UpdateResponse(UpdateResponseType),
    DeleteResponse(DeleteResponseType),
    OrderBy(OrderByType),
    OrderByEntity(OrderByEntityType),
    FilterType(FilterTypeType),
    FilterEntity(FilterEntityType),

    // Constant
    PageInfo(PageInfoType),
    // Introspection
    __TypeKind(__TypeKindType),
    __Schema(__SchemaType),
    __Type(__TypeType),
    __Field(__FieldType),
    __InputValue(__InputValueType),
    __EnumValue(__EnumValueType),
    __DirectiveLocation(__DirectiveLocationType),
    __Directive(__DirectiveType),
    // Modifiers
    List(ListType),
    NonNull(NonNullType),
}

impl ___Type for __Type {
    // kind: __TypeKind!
    fn kind(&self) -> __TypeKind {
        match self {
            Self::Scalar(x) => x.kind(),
            Self::Enum(x) => x.kind(),
            Self::Query(x) => x.kind(),
            Self::Mutation(x) => x.kind(),
            Self::Connection(x) => x.kind(),
            Self::Edge(x) => x.kind(),
            Self::Node(x) => x.kind(),
            Self::NodeInterface(x) => x.kind(),
            Self::InsertInput(x) => x.kind(),
            Self::InsertResponse(x) => x.kind(),
            Self::UpdateInput(x) => x.kind(),
            Self::UpdateResponse(x) => x.kind(),
            Self::DeleteResponse(x) => x.kind(),
            Self::FilterType(x) => x.kind(),
            Self::FilterEntity(x) => x.kind(),
            Self::OrderBy(x) => x.kind(),
            Self::OrderByEntity(x) => x.kind(),
            Self::PageInfo(x) => x.kind(),
            Self::__TypeKind(x) => x.kind(),
            Self::__Schema(x) => x.kind(),
            Self::__Type(x) => x.kind(),
            Self::__Field(x) => x.kind(),
            Self::__InputValue(x) => x.kind(),
            Self::__EnumValue(x) => x.kind(),
            Self::__DirectiveLocation(x) => x.kind(),
            Self::__Directive(x) => x.kind(),
            Self::List(x) => x.kind(),
            Self::NonNull(x) => x.kind(),
        }
    }

    // name: String
    fn name(&self) -> Option<String> {
        match self {
            Self::Scalar(x) => x.name(),
            Self::Enum(x) => x.name(),
            Self::Query(x) => x.name(),
            Self::Mutation(x) => x.name(),
            Self::Connection(x) => x.name(),
            Self::Edge(x) => x.name(),
            Self::Node(x) => x.name(),
            Self::NodeInterface(x) => x.name(),
            Self::InsertInput(x) => x.name(),
            Self::InsertResponse(x) => x.name(),
            Self::UpdateInput(x) => x.name(),
            Self::UpdateResponse(x) => x.name(),
            Self::DeleteResponse(x) => x.name(),
            Self::FilterType(x) => x.name(),
            Self::FilterEntity(x) => x.name(),
            Self::OrderBy(x) => x.name(),
            Self::OrderByEntity(x) => x.name(),
            Self::PageInfo(x) => x.name(),
            Self::__TypeKind(x) => x.name(),
            Self::__Schema(x) => x.name(),
            Self::__Type(x) => x.name(),
            Self::__Field(x) => x.name(),
            Self::__InputValue(x) => x.name(),
            Self::__EnumValue(x) => x.name(),
            Self::__DirectiveLocation(x) => x.name(),
            Self::__Directive(x) => x.name(),
            Self::List(x) => x.name(),
            Self::NonNull(x) => x.name(),
        }
    }

    // description: String
    fn description(&self) -> Option<String> {
        match self {
            Self::Scalar(x) => x.description(),
            Self::Enum(x) => x.description(),
            Self::Query(x) => x.description(),
            Self::Mutation(x) => x.description(),
            Self::Connection(x) => x.description(),
            Self::Edge(x) => x.description(),
            Self::Node(x) => x.description(),
            Self::NodeInterface(x) => x.description(),
            Self::InsertInput(x) => x.description(),
            Self::InsertResponse(x) => x.description(),
            Self::UpdateInput(x) => x.description(),
            Self::UpdateResponse(x) => x.description(),
            Self::DeleteResponse(x) => x.description(),
            Self::FilterType(x) => x.description(),
            Self::FilterEntity(x) => x.description(),
            Self::OrderBy(x) => x.description(),
            Self::OrderByEntity(x) => x.description(),
            Self::PageInfo(x) => x.description(),
            Self::__TypeKind(x) => x.description(),
            Self::__Schema(x) => x.description(),
            Self::__Type(x) => x.description(),
            Self::__Field(x) => x.description(),
            Self::__InputValue(x) => x.description(),
            Self::__EnumValue(x) => x.description(),
            Self::__DirectiveLocation(x) => x.description(),
            Self::__Directive(x) => x.description(),
            Self::List(x) => x.description(),
            Self::NonNull(x) => x.description(),
        }
    }

    // # OBJECT and INTERFACE only
    // fields(includeDeprecated: Boolean = false): [__Field!]
    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        match self {
            Self::Scalar(x) => x.fields(_include_deprecated),
            Self::Enum(x) => x.fields(_include_deprecated),
            Self::Query(x) => x.fields(_include_deprecated),
            Self::Mutation(x) => x.fields(_include_deprecated),
            Self::Connection(x) => x.fields(_include_deprecated),
            Self::Edge(x) => x.fields(_include_deprecated),
            Self::Node(x) => x.fields(_include_deprecated),
            Self::NodeInterface(x) => x.fields(_include_deprecated),
            Self::InsertInput(x) => x.fields(_include_deprecated),
            Self::InsertResponse(x) => x.fields(_include_deprecated),
            Self::UpdateInput(x) => x.fields(_include_deprecated),
            Self::UpdateResponse(x) => x.fields(_include_deprecated),
            Self::DeleteResponse(x) => x.fields(_include_deprecated),
            Self::FilterType(x) => x.fields(_include_deprecated),
            Self::FilterEntity(x) => x.fields(_include_deprecated),
            Self::OrderBy(x) => x.fields(_include_deprecated),
            Self::OrderByEntity(x) => x.fields(_include_deprecated),
            Self::PageInfo(x) => x.fields(_include_deprecated),
            Self::__TypeKind(x) => x.fields(_include_deprecated),
            Self::__Schema(x) => x.fields(_include_deprecated),
            Self::__Type(x) => x.fields(_include_deprecated),
            Self::__Field(x) => x.fields(_include_deprecated),
            Self::__InputValue(x) => x.fields(_include_deprecated),
            Self::__EnumValue(x) => x.fields(_include_deprecated),
            Self::__DirectiveLocation(x) => x.fields(_include_deprecated),
            Self::__Directive(x) => x.fields(_include_deprecated),
            Self::List(x) => x.fields(_include_deprecated),
            Self::NonNull(x) => x.fields(_include_deprecated),
        }
    }

    // # OBJECT only
    // interfaces: [__Type!]
    fn interfaces(&self) -> Option<Vec<__Type>> {
        match self {
            Self::Scalar(x) => x.interfaces(),
            Self::Enum(x) => x.interfaces(),
            Self::Query(x) => x.interfaces(),
            Self::Mutation(x) => x.interfaces(),
            Self::Connection(x) => x.interfaces(),
            Self::Edge(x) => x.interfaces(),
            Self::Node(x) => x.interfaces(),
            Self::NodeInterface(x) => x.interfaces(),
            Self::InsertInput(x) => x.interfaces(),
            Self::InsertResponse(x) => x.interfaces(),
            Self::UpdateInput(x) => x.interfaces(),
            Self::UpdateResponse(x) => x.interfaces(),
            Self::DeleteResponse(x) => x.interfaces(),
            Self::FilterType(x) => x.interfaces(),
            Self::FilterEntity(x) => x.interfaces(),
            Self::OrderBy(x) => x.interfaces(),
            Self::OrderByEntity(x) => x.interfaces(),
            Self::PageInfo(x) => x.interfaces(),
            Self::__TypeKind(x) => x.interfaces(),
            Self::__Schema(x) => x.interfaces(),
            Self::__Type(x) => x.interfaces(),
            Self::__Field(x) => x.interfaces(),
            Self::__InputValue(x) => x.interfaces(),
            Self::__EnumValue(x) => x.interfaces(),
            Self::__DirectiveLocation(x) => x.interfaces(),
            Self::__Directive(x) => x.interfaces(),
            Self::List(x) => x.interfaces(),
            Self::NonNull(x) => x.interfaces(),
        }
    }

    // # INTERFACE and UNION only
    // possibleTypes: [__Type!]
    fn possible_types(&self) -> Option<Vec<__Type>> {
        match self {
            Self::NodeInterface(x) => x.possible_types(),
            _ => None,
        }
    }

    // # ENUM only
    // enumValues(includeDeprecated: Boolean = false): [__EnumValue!]
    fn enum_values(&self, _include_deprecated: bool) -> Option<Vec<__EnumValue>> {
        match self {
            Self::Scalar(x) => x.enum_values(_include_deprecated),
            Self::Enum(x) => x.enum_values(_include_deprecated),
            Self::Query(x) => x.enum_values(_include_deprecated),
            Self::Mutation(x) => x.enum_values(_include_deprecated),
            Self::Connection(x) => x.enum_values(_include_deprecated),
            Self::Edge(x) => x.enum_values(_include_deprecated),
            Self::Node(x) => x.enum_values(_include_deprecated),
            Self::NodeInterface(x) => x.enum_values(_include_deprecated),
            Self::InsertInput(x) => x.enum_values(_include_deprecated),
            Self::InsertResponse(x) => x.enum_values(_include_deprecated),
            Self::UpdateInput(x) => x.enum_values(_include_deprecated),
            Self::UpdateResponse(x) => x.enum_values(_include_deprecated),
            Self::DeleteResponse(x) => x.enum_values(_include_deprecated),
            Self::FilterType(x) => x.enum_values(_include_deprecated),
            Self::FilterEntity(x) => x.enum_values(_include_deprecated),
            Self::OrderBy(x) => x.enum_values(_include_deprecated),
            Self::OrderByEntity(x) => x.enum_values(_include_deprecated),
            Self::PageInfo(x) => x.enum_values(_include_deprecated),
            Self::__TypeKind(x) => x.enum_values(_include_deprecated),
            Self::__Schema(x) => x.enum_values(_include_deprecated),
            Self::__Type(x) => x.enum_values(_include_deprecated),
            Self::__Field(x) => x.enum_values(_include_deprecated),
            Self::__InputValue(x) => x.enum_values(_include_deprecated),
            Self::__EnumValue(x) => x.enum_values(_include_deprecated),
            Self::__DirectiveLocation(x) => x.enum_values(_include_deprecated),
            Self::__Directive(x) => x.enum_values(_include_deprecated),
            Self::List(x) => x.enum_values(_include_deprecated),
            Self::NonNull(x) => x.enum_values(_include_deprecated),
        }
    }

    // # INPUT_OBJECT only
    // inputFields: [__InputValue!]
    fn input_fields(&self) -> Option<Vec<__InputValue>> {
        match self {
            Self::Scalar(x) => x.input_fields(),
            Self::Enum(x) => x.input_fields(),
            Self::Query(x) => x.input_fields(),
            Self::Mutation(x) => x.input_fields(),
            Self::Connection(x) => x.input_fields(),
            Self::Edge(x) => x.input_fields(),
            Self::Node(x) => x.input_fields(),
            Self::NodeInterface(x) => x.input_fields(),
            Self::InsertInput(x) => x.input_fields(),
            Self::InsertResponse(x) => x.input_fields(),
            Self::UpdateInput(x) => x.input_fields(),
            Self::UpdateResponse(x) => x.input_fields(),
            Self::DeleteResponse(x) => x.input_fields(),
            Self::FilterType(x) => x.input_fields(),
            Self::FilterEntity(x) => x.input_fields(),
            Self::OrderBy(x) => x.input_fields(),
            Self::OrderByEntity(x) => x.input_fields(),
            Self::PageInfo(x) => x.input_fields(),
            Self::__TypeKind(x) => x.input_fields(),
            Self::__Schema(x) => x.input_fields(),
            Self::__Type(x) => x.input_fields(),
            Self::__Field(x) => x.input_fields(),
            Self::__InputValue(x) => x.input_fields(),
            Self::__EnumValue(x) => x.input_fields(),
            Self::__DirectiveLocation(x) => x.input_fields(),
            Self::__Directive(x) => x.input_fields(),
            Self::List(x) => x.input_fields(),
            Self::NonNull(x) => x.input_fields(),
        }
    }

    // # NON_NULL and LIST only
    // ofType: __Type
    fn of_type(&self) -> Option<__Type> {
        match self {
            Self::List(x) => x.of_type(),
            Self::NonNull(x) => x.of_type(),
            _ => None,
        }
    }
}

impl __Type {
    /// Uwraps the List and NonNull modifiers to return a concrete __Type
    pub fn unmodified_type(&self) -> Self {
        match self {
            __Type::List(x) => x.type_.unmodified_type(),
            __Type::NonNull(x) => x.type_.unmodified_type(),
            _ => self.clone(),
        }
    }

    pub fn nullable_type(&self) -> Self {
        match self {
            __Type::NonNull(x) => (*x.type_).clone(),
            _ => self.clone(),
        }
    }
}

#[allow(clippy::upper_case_acronyms)]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Scalar {
    ID,
    Int,
    Float,
    String,
    Boolean,
    Date,
    Time,
    Datetime,
    BigInt,
    UUID,
    JSON,
    Cursor,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct __TypeKindType;
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct __SchemaType;
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct __TypeType;
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct __FieldType;
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct __InputValueType;
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct __EnumValueType;
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct __DirectiveLocationType;
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct __DirectiveType;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ListType {
    pub type_: Box<__Type>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NonNullType {
    pub type_: Box<__Type>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SchemaType {
    pub schema: Rc<__Schema>,
    //pub context: Context,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct QueryType {
    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MutationType {
    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct InsertInputType {
    pub table: Table,
    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UpdateInputType {
    pub table: Table,
    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct InsertResponseType {
    pub table: Table,
    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UpdateResponseType {
    pub table: Table,
    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DeleteResponseType {
    pub table: Table,
    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ConnectionType {
    pub table: Table,

    // If one is present, both should be present
    // could be improved
    pub fkey: Option<ForeignKey>,
    pub reverse_reference: Option<bool>,

    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EnumType {
    pub enum_: Enum,
    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OrderByType {}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OrderByEntityType {
    pub table: Table,
    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum FilterableType {
    Scalar(Scalar),
    Enum(EnumType),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FilterTypeType {
    pub entity: FilterableType,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FilterEntityType {
    pub table: Table,
    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EdgeType {
    pub table: Table,
    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NodeType {
    pub table: Table,

    // If one is present, both should be present
    // could be improved
    pub fkey: Option<ForeignKey>,
    pub reverse_reference: Option<bool>,

    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NodeInterfaceType {
    pub schema: Rc<__Schema>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PageInfoType;

impl ___Type for QueryType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some("Query".to_string())
    }

    fn description(&self) -> Option<String> {
        Some("The root type for querying data".to_string())
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        let mut f = vec![];

        let single_entrypoint = __Field {
            name_: "node".to_string(),
            type_: __Type::NodeInterface(NodeInterfaceType {
                schema: self.schema.clone(),
            }),
            args: vec![__InputValue {
                name_: "nodeId".to_string(),
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::Scalar(Scalar::ID)),
                }),
                description: Some("The record's `ID`".to_string()),
                default_value: None,
                sql_type: None,
            }],
            description: Some("Retrieve a record by its `ID`".to_string()),
            deprecation_reason: None,
            sql_type: None,
        };
        f.push(single_entrypoint);

        for schema in self.schema.context.schemas.iter() {
            for table in schema
                .tables
                .iter()
                .filter(|x| x.graphql_select_types_are_valid())
            {
                let collection_entrypoint = __Field {
                    name_: format!(
                        "{}Collection",
                        lowercase_first_letter(&table.graphql_base_type_name())
                    ),
                    type_: __Type::Connection(ConnectionType {
                        table: table.clone(),
                        fkey: None,
                        reverse_reference: None,
                        schema: self.schema.clone(),
                    }),
                    args: vec![
                        __InputValue {
                            name_: "first".to_string(),
                            type_: __Type::Scalar(Scalar::Int),
                            description: Some("Query the first `n` records in the collection".to_string()),
                            default_value: None,
                            sql_type: None,
                        },
                        __InputValue {
                            name_: "last".to_string(),
                            type_: __Type::Scalar(Scalar::Int),
                            description: Some("Query the last `n` records in the collection".to_string()),
                            default_value: None,
                            sql_type: None,
                        },
                        __InputValue {
                            name_: "before".to_string(),
                            type_: __Type::Scalar(Scalar::Cursor),
                            description: Some("Query values in the collection before the provided cursor".to_string()),
                            default_value: None,
                            sql_type: None,
                        },
                        __InputValue {
                            name_: "after".to_string(),
                            type_: __Type::Scalar(Scalar::Cursor),
                            description: Some("Query values in the collection after the provided cursor".to_string()),
                            default_value: None,
                            sql_type: None,
                        },
                        __InputValue {
                            name_: "filter".to_string(),
                            type_: __Type::FilterEntity(FilterEntityType {
                                table: table.clone(),
                                schema: self.schema.clone(),
                            }),
                            description: Some("Filters to apply to the results set when querying from the collection".to_string()),
                            default_value: None,
                            sql_type: None,
                        },
                        __InputValue {
                            name_: "orderBy".to_string(),
                            type_: __Type::List(ListType {
                                type_: Box::new(__Type::NonNull(NonNullType {
                                    type_: Box::new(__Type::OrderByEntity(
                                        OrderByEntityType {
                                            table: table.clone(),
                                            schema: self.schema.clone(),
                                        },
                                    )),
                                })),
                            }),
                            description: Some("Sort order to apply to the collection".to_string()),
                            default_value: None,
                            sql_type: None,
                        },
                    ],
                    description: Some(format!(
                        "A pagable collection of type `{}`",
                        table.graphql_base_type_name()
                    )),
                    deprecation_reason: None,
                    sql_type: None,
                };

                f.push(collection_entrypoint);
            }
        }

        // Default fields always preset
        f.extend(vec![
            __Field {
                name_: "__type".to_string(),
                type_: __Type::__Type(__TypeType),
                args: vec![__InputValue {
                    name_: "name".to_string(),
                    type_: __Type::Scalar(Scalar::String),
                    description: None,
                    default_value: None,
                    sql_type: None,
                }],
                description: None,
                deprecation_reason: None,
                sql_type: None,
            },
            __Field {
                name_: "__schema".to_string(),
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::__Schema(__SchemaType)),
                }),
                args: vec![],
                description: None,
                deprecation_reason: None,
                sql_type: None,
            },
        ]);

        f.sort_by_key(|a| a.name());
        Some(f)
    }
}

impl ___Type for MutationType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some("Mutation".to_string())
    }

    fn description(&self) -> Option<String> {
        Some("The root type for creating and mutating data".to_string())
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        let mut f = vec![];

        // TODO, filter to types in type map in case any were filtered out
        for schema in self.schema.context.schemas.iter() {
            for table in schema.tables.iter() {
                if table.graphql_insert_types_are_valid() {
                    f.push(__Field {
                        name_: format!("insertInto{}Collection", table.graphql_base_type_name()),
                        type_: __Type::InsertResponse(InsertResponseType {
                            table: table.clone(),
                            schema: self.schema.clone(),
                        }),
                        args: vec![__InputValue {
                            name_: "objects".to_string(),
                            type_: __Type::NonNull(NonNullType {
                                type_: Box::new(__Type::List(ListType {
                                    type_: Box::new(__Type::NonNull(NonNullType {
                                        type_: Box::new(__Type::InsertInput(InsertInputType {
                                            table: table.clone(),
                                            schema: self.schema.clone(),
                                        })),
                                    })),
                                })),
                            }),
                            description: None,
                            default_value: None,
                            sql_type: None,
                        }],
                        description: Some(format!(
                            "Adds one or more `{}` records to the collection",
                            table.graphql_base_type_name()
                        )),
                        deprecation_reason: None,
                        sql_type: None,
                    });
                }

                if table.graphql_update_types_are_valid() {
                    f.push(__Field {
                        name_: format!("update{}Collection", table.graphql_base_type_name()),
                        type_: __Type::NonNull(NonNullType {
                            type_: Box::new(__Type::UpdateResponse(UpdateResponseType {
                                table: table.clone(),
                                schema: self.schema.clone(),
                            })),
                        }),
                        args: vec![
                            __InputValue {
                                name_: "set".to_string(),
                                type_: __Type::NonNull(NonNullType {
                                    type_: Box::new(__Type::UpdateInput(UpdateInputType {
                                        table: table.clone(),
                                        schema: self.schema.clone(),
                                    })),
                                }),
                                description: Some("Fields that are set will be updated for all records matching the `filter`".to_string()),
                                default_value: None,
                                sql_type: None,
                            },
                            __InputValue {
                                name_: "filter".to_string(),
                                type_: __Type::FilterEntity(FilterEntityType {
                                    table: table.clone(),
                                    schema: self.schema.clone(),
                                }),
                                description: Some("Restricts the mutation's impact to records matching the criteria".to_string()),
                                default_value: None,
                                sql_type: None,
                            },
                            __InputValue {
                                name_: "atMost".to_string(),
                                type_: __Type::NonNull(NonNullType {
                                    type_: Box::new(__Type::Scalar(Scalar::Int)),
                                }),
                                description: Some("The maximum number of records in the collection permitted to be affected".to_string()),
                                default_value: Some("1".to_string()),
                                sql_type: None,
                            },
                        ],
                        description: Some(format!(
                            "Updates zero or more records in the `{}` collection",
                            table.graphql_base_type_name()
                        )),
                        deprecation_reason: None,
                        sql_type: None,
                    });
                }

                if table.graphql_delete_types_are_valid() {
                    f.push(__Field {
                        name_: format!("deleteFrom{}Collection", table.graphql_base_type_name()),
                        type_: __Type::NonNull(NonNullType {
                            type_: Box::new(__Type::DeleteResponse(DeleteResponseType {
                                table: table.clone(),
                                schema: self.schema.clone(),
                            })),
                        }),
                        args: vec![
                            __InputValue {
                                name_: "filter".to_string(),
                                type_: __Type::FilterEntity(FilterEntityType {
                                    table: table.clone(),
                                    schema: self.schema.clone(),
                                }),
                                description: Some(
                                    "Restricts the mutation's impact to records matching the criteria"
                                        .to_string(),
                                ),
                                default_value: None,
                                sql_type: None,
                            },
                            __InputValue {
                                name_: "atMost".to_string(),
                                type_: __Type::NonNull(NonNullType {
                                    type_: Box::new(__Type::Scalar(Scalar::Int)),
                                }),
                                description: Some("The maximum number of records in the collection permitted to be affected".to_string()),
                                default_value: Some("1".to_string()),
                                sql_type: None,
                            },
                        ],
                        description: Some(format!(
                            "Deletes zero or more records from the `{}` collection",
                            table.graphql_base_type_name()
                        )),
                        deprecation_reason: None,
                        sql_type: None,
                    })
                }
            }
        }
        f.sort_by_key(|a| a.name());
        Some(f)
    }
}

impl ___Type for Scalar {
    fn kind(&self) -> __TypeKind {
        __TypeKind::SCALAR
    }

    fn name(&self) -> Option<String> {
        Some(format!("{:?}", self))
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        None
    }
}

impl ___Type for EnumType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::ENUM
    }

    fn name(&self) -> Option<String> {
        let inflect_names = self.schema.context.inflect_names(self.enum_.schema_oid);
        Some(self.enum_.graphql_base_type_name(inflect_names))
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        None
    }

    fn enum_values(&self, _include_deprecated: bool) -> Option<Vec<__EnumValue>> {
        Some(
            self.enum_
                .values
                .iter()
                .map(|x| __EnumValue {
                    name: x.name.clone(),
                    description: None,
                    deprecation_reason: None,
                })
                .collect(),
        )
    }
}

impl ___Type for ConnectionType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some(format!("{}Connection", self.table.graphql_base_type_name()))
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        let mut fields = vec![
            __Field {
                name_: "edges".to_string(),
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::List(ListType {
                        type_: Box::new(__Type::NonNull(NonNullType {
                            type_: Box::new(__Type::Edge(EdgeType {
                                table: self.table.clone(),
                                schema: self.schema.clone(),
                            })),
                        })),
                    })),
                }),
                args: vec![],
                description: None,
                deprecation_reason: None,
                sql_type: None,
            },
            __Field {
                name_: "pageInfo".to_string(),
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::PageInfo(PageInfoType)),
                }),
                args: vec![],
                description: None,
                deprecation_reason: None,
                sql_type: None,
            },
        ];

        if let Some(total_count) = self.table.directives.total_count.as_ref() {
            if total_count.enabled {
                let total_count_field = __Field {
                    name_: "totalCount".to_string(),
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::Scalar(Scalar::Int)),
                    }),
                    args: vec![],
                    description: Some(
                        "The total number of records matching the `filter` criteria".to_string(),
                    ),
                    deprecation_reason: None,
                    sql_type: None,
                };
                fields.push(total_count_field);
            }
        }
        Some(fields)
    }
}

impl ___Type for NodeInterfaceType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::INTERFACE
    }

    fn name(&self) -> Option<String> {
        Some("Node".to_string())
    }

    fn possible_types(&self) -> Option<Vec<__Type>> {
        let node_interface_name = self.name().unwrap();

        let mut possible_types = vec![];

        for type_ in self.schema.types() {
            let type_interfaces: Vec<__Type> = type_.interfaces().unwrap_or(vec![]);
            let interface_names: Vec<String> =
                type_interfaces.iter().map(|x| x.name().unwrap()).collect();
            if interface_names.contains(&node_interface_name) {
                possible_types.push(type_)
            }
        }

        Some(possible_types)
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        Some(vec![__Field {
            name_: "nodeId".to_string(),
            type_: __Type::NonNull(NonNullType {
                type_: Box::new(__Type::Scalar(Scalar::ID)),
            }),
            args: vec![],
            description: Some("Retrieves a record by `ID`".to_string()),
            deprecation_reason: None,
            sql_type: None,
        }])
    }
}

impl ___Type for EdgeType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some(format!("{}Edge", self.table.graphql_base_type_name()))
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        Some(vec![
            __Field {
                name_: "cursor".to_string(),
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::Scalar(Scalar::String)),
                }),
                args: vec![],
                description: None,
                deprecation_reason: None,
                sql_type: None,
            },
            __Field {
                name_: "node".to_string(),
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::Node(NodeType {
                        table: self.table.clone(),
                        fkey: None,
                        reverse_reference: None,
                        schema: self.schema.clone(),
                    })),
                }),
                args: vec![],
                description: None,
                deprecation_reason: None,
                sql_type: None,
            },
        ])
    }
}

pub fn sql_type_to_graphql_type(type_oid: u32, type_name: &str, schema: &Rc<__Schema>) -> __Type {
    let mut type_w_list_mod = match type_oid {
        20 => __Type::Scalar(Scalar::BigInt),     // bigint "
        16 => __Type::Scalar(Scalar::Boolean),    // boolean "
        1082 => __Type::Scalar(Scalar::Date),     // date "
        1184 => __Type::Scalar(Scalar::Datetime), // timestamp with time zone "
        1114 => __Type::Scalar(Scalar::Datetime), // timestamp without time zone "
        701 => __Type::Scalar(Scalar::Float),     // double precision "
        23 => __Type::Scalar(Scalar::Int),        // integer "
        21 => __Type::Scalar(Scalar::Int),        // smallint "
        700 => __Type::Scalar(Scalar::Float),     // real "
        3802 => __Type::Scalar(Scalar::JSON),     // jsonb "
        114 => __Type::Scalar(Scalar::JSON),      // json "
        1083 => __Type::Scalar(Scalar::Time),     // time without time zone "
        2950 => __Type::Scalar(Scalar::UUID),     // uuid "
        25 => __Type::Scalar(Scalar::String),     // text "
        1009 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::String)),
        }), // text[] "
        1016 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::BigInt)),
        }), // bigint[] "
        1000 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::Boolean)),
        }), // boolean[] "
        1182 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::Date)),
        }), // date[] "
        1115 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::Datetime)),
        }), // timestamp without time zone[] "
        1185 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::Datetime)),
        }), // timestamp with time zone[] "
        1022 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::Float)),
        }), // double precision[] "
        1021 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::Float)),
        }), // real[] "
        1005 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::Int)),
        }), // smallint[] "
        1007 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::Int)),
        }), // integer[] "
        199 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::JSON)),
        }), // json[] "
        3807 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::JSON)),
        }), // jsonb[] "
        1183 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::Time)),
        }), // time without time zone[] "
        2951 => __Type::List(ListType {
            type_: Box::new(__Type::Scalar(Scalar::UUID)),
        }), // uuid[] "
        _ => match type_name.ends_with("[]") {
            true => __Type::List(ListType {
                type_: Box::new(__Type::Scalar(Scalar::String)),
            }),
            false => __Type::Scalar(Scalar::String),
        },
    };

    let enums: Vec<&Enum> = schema
        .context
        .enums
        .iter()
        .filter(|x| x.permissions.is_usable)
        .collect();

    for enum_ in enums {
        if enum_.oid == type_oid {
            type_w_list_mod = __Type::Enum(EnumType {
                enum_: enum_.clone(),
                schema: schema.clone(),
            })
        } else if format!("{}[]", enum_.name) == type_name
            || format!("\"{}\"[]", enum_.name) == type_name
        {
            type_w_list_mod = __Type::List(ListType {
                type_: Box::new(__Type::Enum(EnumType {
                    enum_: enum_.clone(),
                    schema: schema.clone(),
                })),
            })
        }
    }
    type_w_list_mod
}

pub fn sql_column_to_graphql_type(col: &Column, schema: &Rc<__Schema>) -> __Type {
    let type_w_list_mod = sql_type_to_graphql_type(col.type_oid, col.type_name.as_str(), schema);

    match col.is_not_null {
        true => __Type::NonNull(NonNullType {
            type_: Box::new(type_w_list_mod),
        }),
        _ => type_w_list_mod,
    }
}

impl ___Type for NodeType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some(self.table.graphql_base_type_name())
    }

    fn interfaces(&self) -> Option<Vec<__Type>> {
        let mut interfaces = vec![];

        if self.table.primary_key().is_some() {
            interfaces.push(__Type::NodeInterface(NodeInterfaceType {
                schema: self.schema.clone(),
            }))
        }

        match interfaces.is_empty() {
            false => Some(interfaces),
            true => None,
        }
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        let column_fields = self
            .table
            .columns
            .iter()
            .filter(|x| is_valid_graphql_name(&x.graphql_field_name()))
            .filter(|x| x.permissions.is_selectable)
            .filter(|x| !self.schema.context.is_composite(x.type_oid))
            .map(|col| __Field {
                name_: col.graphql_field_name(),
                type_: sql_column_to_graphql_type(col, &self.schema),
                args: vec![],
                description: None,
                deprecation_reason: None,
                sql_type: Some(NodeSQLType::Column(col.clone())),
            })
            .collect();

        // nodeId field
        let mut node_id_field: Vec<__Field> = vec![];

        if self.table.primary_key().is_some() {
            let node_id = __Field {
                name_: "nodeId".to_string(),
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::Scalar(Scalar::ID)),
                }),
                args: vec![],
                description: Some("Globally Unique Record Identifier".to_string()),
                deprecation_reason: None,
                sql_type: Some(NodeSQLType::NodeId(
                    self.table
                        .primary_key_columns()
                        .iter()
                        .map(|x| (*x).clone())
                        .collect::<Vec<Column>>(),
                )),
            };
            node_id_field.push(node_id);
        };

        // Functions require selecting an entire row. the whole table must be selectable
        // for functions to work
        let mut function_fields: Vec<__Field> = vec![];
        if self.table.permissions.is_selectable {
            function_fields = self
                .table
                .functions
                .iter()
                .filter(|x| is_valid_graphql_name(&x.graphql_field_name()))
                .filter(|x| x.permissions.is_executable)
                .map(|func| __Field {
                    name_: func.graphql_field_name(),
                    type_: sql_type_to_graphql_type(
                        func.type_oid,
                        func.type_name.as_str(),
                        &self.schema,
                    ),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: Some(NodeSQLType::Function(func.clone())),
                })
                .collect();
        }

        let mut relation_fields: Vec<__Field> = vec![];

        for fkey in self
            .table
            .foreign_keys
            .iter()
            .filter(|x| x.permissions.is_selectable)
        {
            let reverse_reference = false;
            let foreign_table: Option<&Table> = self
                .schema
                .context
                .schemas
                .iter()
                .flat_map(|x| x.tables.iter())
                .find(|x| x.oid == fkey.referenced_table_meta.oid);
            // this should never happen but if there is an unhandled edge case panic-ing here
            // would block
            if foreign_table.is_none() {
                continue;
            }
            let foreign_table = foreign_table.unwrap();
            if !foreign_table.graphql_select_types_are_valid() {
                continue;
            }

            let relation_field = __Field {
                name_: fkey.graphql_field_name(reverse_reference),
                // XXX: column nullability ignored for NonNull type to match pg_graphql
                type_: __Type::Node(NodeType {
                    table: foreign_table.clone(),
                    fkey: Some(fkey.clone()),
                    reverse_reference: Some(reverse_reference),
                    schema: self.schema.clone(),
                }),
                args: vec![],
                description: None,
                deprecation_reason: None,
                sql_type: None,
            };
            relation_fields.push(relation_field);
        }

        for fkey in self
            .schema
            .context
            .schemas
            .iter()
            .flat_map(|schema| schema.tables.iter())
            .flat_map(|tab| tab.foreign_keys.iter())
            .filter(|x| x.permissions.is_selectable)
            // inbound references
            .filter(|x| x.referenced_table_meta.oid == self.table.oid)
        {
            let reverse_reference = true;
            let foreign_table: Option<&Table> = self
                .schema
                .context
                .schemas
                .iter()
                .flat_map(|x| x.tables.iter())
                .find(|x| x.oid == fkey.local_table_meta.oid);
            // this should never happen but if there is an unhandled edge case panic-ing here
            // would block
            if foreign_table.is_none() {
                continue;
            }
            let foreign_table = foreign_table.unwrap();
            if !foreign_table.graphql_select_types_are_valid() {
                continue;
            }

            let relation_field = match fkey.is_locally_unique {
                false => {
                    __Field {
                        name_: fkey.graphql_field_name(reverse_reference),
                        // XXX: column nullability ignored for NonNull type to match pg_graphql
                        type_: __Type::Connection(ConnectionType {
                                table: foreign_table.clone(),
                                fkey: Some(fkey.clone()),
                                reverse_reference: Some(reverse_reference),
                                schema: self.schema.clone(),
                            }),
                        args: vec![
                            __InputValue {
                                name_: "first".to_string(),
                                type_: __Type::Scalar(Scalar::Int),
                                description: Some("Query the first `n` records in the collection".to_string()),
                                default_value: None,
                                sql_type: None,
                            },
                            __InputValue {
                                name_: "last".to_string(),
                                type_: __Type::Scalar(Scalar::Int),
                                description: Some("Query the last `n` records in the collection".to_string()),
                                default_value: None,
                                sql_type: None,
                            },
                            __InputValue {
                                name_: "before".to_string(),
                                type_: __Type::Scalar(Scalar::Cursor),
                                description: Some("Query values in the collection before the provided cursor".to_string()),
                                default_value: None,
                                sql_type: None,
                            },
                            __InputValue {
                                name_: "after".to_string(),
                                type_: __Type::Scalar(Scalar::Cursor),
                                description: Some("Query values in the collection after the provided cursor".to_string()),
                                default_value: None,
                                sql_type: None,
                            },
                            __InputValue {
                                name_: "filter".to_string(),
                                type_: __Type::FilterEntity(FilterEntityType {
                                    table: foreign_table.clone(),
                                    schema: self.schema.clone(),
                                }),
                                description: Some("Filters to apply to the results set when querying from the collection".to_string()),
                                default_value: None,
                                sql_type: None,
                            },
                            __InputValue {
                                name_: "orderBy".to_string(),
                                type_: __Type::List(ListType {
                                    type_: Box::new(__Type::NonNull(NonNullType {
                                        type_: Box::new(__Type::OrderByEntity(
                                            OrderByEntityType {
                                                table: foreign_table.clone(),
                                                schema: self.schema.clone(),
                                            },
                                        )),
                                    })),
                                }),
                                description: Some("Sort order to apply to the collection".to_string()),
                                default_value: None,
                                sql_type: None,
                            },
                        ],
                        description: None,
                        deprecation_reason: None,
                        sql_type: None,
                    }
                }
                true => {
                    __Field {
                        name_: fkey.graphql_field_name(reverse_reference),
                        // XXX: column nullability ignored for NonNull type to match pg_graphql
                        type_: __Type::Node(NodeType {
                            table: foreign_table.clone(),
                            fkey: Some(fkey.clone()),
                            reverse_reference: Some(reverse_reference),
                            schema: self.schema.clone(),
                        }),
                        args: vec![],
                        description: None,
                        deprecation_reason: None,
                        sql_type: None,
                    }
                }
            };
            relation_fields.push(relation_field);
        }

        Some(
            vec![
                node_id_field,
                column_fields,
                relation_fields,
                function_fields,
            ]
            .into_iter()
            .flatten()
            //.sorted_by(|a, b| a.name().cmp(&b.name()))
            .collect(),
        )
    }
}

impl ___Type for PageInfoType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some("PageInfo".to_string())
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        Some(vec![
            __Field {
                name_: "endCursor".to_string(),
                type_: __Type::Scalar(Scalar::String),
                args: vec![],
                description: None,
                deprecation_reason: None,
                sql_type: None,
            },
            __Field {
                name_: "hasNextPage".to_string(),
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::Scalar(Scalar::Boolean)),
                }),
                args: vec![],
                description: None,
                deprecation_reason: None,
                sql_type: None,
            },
            __Field {
                name_: "hasPreviousPage".to_string(),
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::Scalar(Scalar::Boolean)),
                }),
                args: vec![],
                description: None,
                deprecation_reason: None,
                sql_type: None,
            },
            __Field {
                name_: "startCursor".to_string(),
                type_: __Type::Scalar(Scalar::String),
                args: vec![],
                description: None,
                deprecation_reason: None,
                sql_type: None,
            },
        ])
    }
}

impl ___Type for __TypeKindType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::ENUM
    }

    fn name(&self) -> Option<String> {
        Some("__TypeKind".to_string())
    }

    fn description(&self) -> Option<String> {
        Some("An enum describing what kind of type a given `__Type` is.".to_string())
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        None
    }

    fn enum_values(&self, _include_deprecated: bool) -> Option<Vec<__EnumValue>> {
        Some(vec![
            __EnumValue {
                name: format!("{:?}", __TypeKind::SCALAR),
                description: None,
                deprecation_reason: None,
            },
            __EnumValue {
                name: format!("{:?}", __TypeKind::OBJECT),
                description: None,
                deprecation_reason: None,
            },
            __EnumValue {
                name: format!("{:?}", __TypeKind::INTERFACE),
                description: None,
                deprecation_reason: None,
            },
            __EnumValue {
                name: format!("{:?}", __TypeKind::UNION),
                description: None,
                deprecation_reason: None,
            },
            __EnumValue {
                name: format!("{:?}", __TypeKind::ENUM),
                description: None,
                deprecation_reason: None,
            },
            __EnumValue {
                name: format!("{:?}", __TypeKind::INPUT_OBJECT),
                description: None,
                deprecation_reason: None,
            },
            __EnumValue {
                name: format!("{:?}", __TypeKind::LIST),
                description: None,
                deprecation_reason: None,
            },
            __EnumValue {
                name: format!("{:?}", __TypeKind::NON_NULL),
                description: None,
                deprecation_reason: None,
            },
        ])
    }
}

impl ___Type for __DirectiveLocationType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::ENUM
    }

    fn name(&self) -> Option<String> {
        Some("__DirectiveLocation".to_string())
    }

    fn description(&self) -> Option<String> {
        Some("A Directive can be adjacent to many parts of the GraphQL language, a __DirectiveLocation describes one such possible adjacencies.".to_string())
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        None
    }

    fn enum_values(&self, _include_deprecated: bool) -> Option<Vec<__EnumValue>> {
        Some(vec![
            __EnumValue {
                name: "QUERY".to_string(),
                description: Some("Location adjacent to a query operation.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "MUTATION".to_string(),
                description: Some("Location adjacent to a mutation operation.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "SUBSCRIPTION".to_string(),
                description: Some("Location adjacent to a subscription operation.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "FIELD".to_string(),
                description: Some("Location adjacent to a field.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "FRAGMENT_DEFINITION".to_string(),
                description: Some("Location adjacent to a fragment definition.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "FRAGMENT_SPREAD".to_string(),
                description: Some("Location adjacent to a fragment spread.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "INLINE_FRAGMENT".to_string(),
                description: Some("Location adjacent to an inline fragment.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "VARIABLE_DEFINITION".to_string(),
                description: Some("Location adjacent to a variable definition.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "SCHEMA".to_string(),
                description: Some("Location adjacent to a schema definition.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "SCALAR".to_string(),
                description: Some("Location adjacent to a scalar definition.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "OBJECT".to_string(),
                description: Some("Location adjacent to an object type definition.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "FIELD_DEFINITION".to_string(),
                description: Some("Location adjacent to a field definition.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "ARGUMENT_DEFINITION".to_string(),
                description: Some("Location adjacent to an argument definition.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "INTERFACE".to_string(),
                description: Some("Location adjacent to an interface definition.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "UNION".to_string(),
                description: Some("Location adjacent to a union definition.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "ENUM".to_string(),
                description: Some("Location adjacent to an enum definition.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "ENUM_VALUE".to_string(),
                description: Some("Location adjacent to an enum value definition.".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "INPUT_OBJECT".to_string(),
                description: Some(
                    "Location adjacent to an input object type definition.".to_string(),
                ),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "INPUT_FIELD_DEFINITION".to_string(),
                description: Some(
                    "Location adjacent to an input object field definition.".to_string(),
                ),
                deprecation_reason: None,
            },
        ])
    }
}

// __Type::NonNull(NonNullType{ type_: Box::new( __Type::List(ListType { type_: Box::new(__Type::NonNull( NonNullType { type_: Box::new(__Type::__Type) } ) )}))})

impl ___Type for __SchemaType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some("__Schema".to_string())
    }

    fn description(&self) -> Option<String> {
        Some("A GraphQL Schema defines the capabilities of a GraphQL server. It exposes all available types and directives on the server, as well as the entry points for query, mutation, and subscription operations.".to_string())
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        Some(
            vec![
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::List(ListType {
                            type_: Box::new(__Type::NonNull(NonNullType {
                                type_: Box::new(__Type::__Type(__TypeType {})),
                            })),
                        })),
                    }),
                    name_: "types".to_string(),
                    args: vec![],
                    description: Some("A list of all types supported by this server.".to_string()),
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::NonNull(NonNullType {
                            type_: Box::new(__Type::__Type(__TypeType {})),
                    }),
                    name_: "queryType".to_string(),
                    args: vec![],
                    description: Some("The type that query operations will be rooted at.".to_string()),
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::__Type(__TypeType {}),
                    name_: "mutationType".to_string(),
                    args: vec![],
                    description: Some("If this server supports mutation, the type that mutation operations will be rooted at.".to_string()),
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::__Type(__TypeType {}),

                    name_: "subscriptionType".to_string(),
                    args: vec![],
                    description: Some("If this server support subscription, the type that subscription operations will be rooted at.".to_string()),
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::List(ListType {
                            type_: Box::new(__Type::NonNull(NonNullType {
                                type_: Box::new(__Type::__Directive(__DirectiveType {})),
                            })),
                        })),
                    }),
                    name_: "directives".to_string(),
                    args: vec![__InputValue {
                        name_: "includeDeprecated".to_string(),
                        type_: __Type::Scalar(Scalar::Boolean),
                        description: None,
                        default_value: Some("false".to_string()),
                        sql_type: None,
                    }],
                    description: Some(
                        "A list of all directives supported by this server.".to_string(),
                    ),
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::Scalar(Scalar::String),
                    name_: "description".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },

            ]
            .into_iter()
            .sorted_by(|a, b| a.name().cmp(&b.name()))
            .collect(),
        )
    }
}

impl ___Type for __InputValueType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some("__InputValue".to_string())
    }

    fn description(&self) -> Option<String> {
        Some(
            "Arguments provided to Fields or Directives and the input fields of an InputObject are represented as Input Values which describe their type and optionally a default value."
                .to_string(),
        )
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        Some(
            vec![
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::Scalar(Scalar::String)),
                    }),
                    name_: "name".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::Scalar(Scalar::String),
                    name_: "description".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::__Type(__TypeType)),
                    }),
                    name_: "type".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::Scalar(Scalar::String),
                    name_: "defaultValue".to_string(),
                    args: vec![],
                    description: Some("A GraphQL-formatted string representing the default value for this input value.".to_string()),
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::Scalar(Scalar::Boolean)),
                    }),
                    name_: "isDeprecated".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::Scalar(Scalar::String),
                    name_: "deprecationReason".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
            ]
            .into_iter()
            .sorted_by(|a, b| a.name().cmp(&b.name()))
            .collect(),
        )
    }
}

impl ___Type for __TypeType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some("__Type".to_string())
    }

    fn description(&self) -> Option<String> {
        Some("The fundamental unit of any GraphQL Schema is the type. There are many kinds of types in GraphQL as represented by the `__TypeKind` enum.\\n\\nDepending on the kind of a type, certain fields describe information about that type. Scalar types provide no information beyond a name, description and optional `specifiedByURL`, while Enum types provide their values. Object and Interface types provide the fields they describe. Abstract types, Union and Interface, provide the Object types possible at runtime. List and NonNull types compose other types ".to_string())
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        Some(
            vec![
                __Field {
                    type_: __Type::Scalar(Scalar::String),
                    name_: "name".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::Scalar(Scalar::String),
                    name_: "description".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::__TypeKind(__TypeKindType)),
                    }),
                    name_: "kind".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::List(ListType {
                        type_: Box::new(__Type::NonNull(NonNullType {
                            type_: Box::new(__Type::__InputValue(__InputValueType)),
                        })),
                    }),
                    name_: "inputFields".to_string(),
                    args: vec![__InputValue {
                        name_: "includeDeprecated".to_string(),
                        type_: __Type::Scalar(Scalar::Boolean),
                        description: None,
                        default_value: Some("false".to_string()),
                        sql_type: None,
                    }],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::List(ListType {
                        type_: Box::new(__Type::NonNull(NonNullType {
                            type_: Box::new(__Type::__Type(__TypeType)),
                        })),
                    }),
                    name_: "interfaces".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::List(ListType {
                        type_: Box::new(__Type::NonNull(NonNullType {
                            type_: Box::new(__Type::__Type(__TypeType)),
                        })),
                    }),
                    name_: "possibleTypes".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                // Declared as nullable list in introspection but GraphiQL query fails
                // if null value is returned
                __Field {
                    type_: __Type::List(ListType {
                        type_: Box::new(__Type::NonNull(NonNullType {
                            type_: Box::new(__Type::__EnumValue(__EnumValueType {})),
                        })),
                    }),
                    name_: "enumValues".to_string(),
                    args: vec![__InputValue {
                        name_: "includeDeprecated".to_string(),
                        type_: __Type::Scalar(Scalar::Boolean),
                        description: None,
                        default_value: Some("false".to_string()),
                        sql_type: None,
                    }],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::List(ListType {
                        type_: Box::new(__Type::NonNull(NonNullType {
                            type_: Box::new(__Type::__Field(__FieldType {})),
                        })),
                    }),
                    name_: "fields".to_string(),
                    args: vec![__InputValue {
                        name_: "includeDeprecated".to_string(),
                        type_: __Type::Scalar(Scalar::Boolean),
                        description: None,
                        default_value: Some("false".to_string()),
                        sql_type: None,
                    }],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::__Type(__TypeType),
                    name_: "ofType".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::Scalar(Scalar::String),
                    name_: "specifiedByURL".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
            ]
            .into_iter()
            .sorted_by(|a, b| a.name().cmp(&b.name()))
            .collect(),
        )
    }
}

impl ___Type for __FieldType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some("__Field".to_string())
    }

    fn description(&self) -> Option<String> {
        Some("Object and Interface types are described by a list of Fields, each of which has a name, potentially a list of arguments, and a return type.".to_string())
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        Some(
            vec![
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::Scalar(Scalar::String)),
                    }),
                    name_: "name".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::Scalar(Scalar::String),
                    name_: "description".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::List(ListType {
                            type_: Box::new(__Type::NonNull(NonNullType {
                                type_: Box::new(__Type::__InputValue(__InputValueType)),
                            })),
                        })),
                    }),
                    name_: "args".to_string(),
                    args: vec![__InputValue {
                        name_: "includeDeprecated".to_string(),
                        type_: __Type::Scalar(Scalar::Boolean),
                        description: None,
                        default_value: Some("false".to_string()),
                        sql_type: None,
                    }],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::__Type(__TypeType)),
                    }),
                    name_: "type".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::Scalar(Scalar::Boolean)),
                    }),
                    name_: "isDeprecated".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::Scalar(Scalar::String),
                    name_: "deprecationReason".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
            ]
            .into_iter()
            .sorted_by(|a, b| a.name().cmp(&b.name()))
            .collect(),
        )
    }
}

impl ___Type for __EnumValueType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some("__EnumValue".to_string())
    }

    fn description(&self) -> Option<String> {
        Some("One possible value for a given Enum. Enum values are unique values, not a placeholder for a string or numeric value. However an Enum value is returned in a JSON response as a string.".to_string())
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        Some(
            vec![
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::Scalar(Scalar::String)),
                    }),
                    name_: "name".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::Scalar(Scalar::String),
                    name_: "description".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::Scalar(Scalar::Boolean)),
                    }),
                    name_: "isDeprecated".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::Scalar(Scalar::String),
                    name_: "deprecationReason".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
            ]
            .into_iter()
            .sorted_by(|a, b| a.name().cmp(&b.name()))
            .collect(),
        )
    }
}

impl ___Type for __DirectiveType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some("__Directive".to_string())
    }

    fn description(&self) -> Option<String> {
        Some("A Directive provides a way to describe alternate runtime execution and type validation behavior in a GraphQL document.\\n\\nIn some cases, you need to provide options to alter GraphQL execution behavior in ways field arguments will not suffice, such as conditionally including or skipping a field. Directives provide this by describing additional information to the executor.".to_string())
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        Some(
            vec![
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::Scalar(Scalar::String)),
                    }),
                    name_: "name".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::Scalar(Scalar::String),
                    name_: "description".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::Scalar(Scalar::Boolean)),
                    }),
                    name_: "isRepeatable".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::List(ListType {
                            type_: Box::new(__Type::NonNull(NonNullType {
                                type_: Box::new(__Type::__DirectiveLocation(
                                    __DirectiveLocationType,
                                )),
                            })),
                        })),
                    }),
                    name_: "locations".to_string(),
                    args: vec![],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
                __Field {
                    type_: __Type::NonNull(NonNullType {
                        type_: Box::new(__Type::List(ListType {
                            type_: Box::new(__Type::NonNull(NonNullType {
                                type_: Box::new(__Type::__InputValue(__InputValueType)),
                            })),
                        })),
                    }),
                    name_: "args".to_string(),
                    args: vec![__InputValue {
                        name_: "includeDeprecated".to_string(),
                        type_: __Type::Scalar(Scalar::Boolean),
                        description: None,
                        default_value: Some("false".to_string()),
                        sql_type: None,
                    }],
                    description: None,
                    deprecation_reason: None,
                    sql_type: None,
                },
            ]
            .into_iter()
            .sorted_by(|a, b| a.name().cmp(&b.name()))
            .collect(),
        )
    }
}

impl ___Type for ListType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::LIST
    }

    fn name(&self) -> Option<String> {
        None
    }

    fn of_type(&self) -> Option<__Type> {
        Some((*(self.type_)).clone())
    }
}

impl ___Type for NonNullType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::NON_NULL
    }

    fn name(&self) -> Option<String> {
        None
    }

    fn of_type(&self) -> Option<__Type> {
        Some((*(self.type_)).clone())
    }
}

impl ___Type for InsertInputType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::INPUT_OBJECT
    }

    fn name(&self) -> Option<String> {
        Some(format!(
            "{}InsertInput",
            self.table.graphql_base_type_name()
        ))
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        None
    }

    fn input_fields(&self) -> Option<Vec<__InputValue>> {
        Some(
            self.table
                .columns
                .iter()
                .filter(|x| x.permissions.is_insertable)
                .filter(|x| !x.is_generated)
                .filter(|x| !x.is_serial)
                .filter(|x| !self.schema.context.is_composite(x.type_oid))
                // TODO: not composite
                .map(|col| __InputValue {
                    name_: col.graphql_field_name(),
                    // If triggers are involved, we can't detect if a field is non-null. Default
                    // all fields to non-null and let postgres errors handle it.
                    type_: sql_column_to_graphql_type(col, &self.schema).nullable_type(),
                    description: None,
                    default_value: None,
                    sql_type: Some(NodeSQLType::Column(col.clone())),
                })
                .collect(),
        )
    }
}

impl ___Type for InsertResponseType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some(format!(
            "{}InsertResponse",
            self.table.graphql_base_type_name()
        ))
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        Some(vec![
            __Field {
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::Scalar(Scalar::Int)),
                }),
                name_: "affectedCount".to_string(),
                args: vec![],
                description: Some("Count of the records impacted by the mutation".to_string()),
                deprecation_reason: None,
                sql_type: None,
            },
            __Field {
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::List(ListType {
                        type_: Box::new(__Type::NonNull(NonNullType {
                            type_: Box::new(__Type::Node(NodeType {
                                table: self.table.clone(),
                                fkey: None,
                                reverse_reference: None,
                                schema: self.schema.clone(),
                            })),
                        })),
                    })),
                }),
                name_: "records".to_string(),
                args: vec![],
                description: Some("Array of records impacted by the mutation".to_string()),
                deprecation_reason: None,
                sql_type: None,
            },
        ])
    }
}

impl ___Type for UpdateInputType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::INPUT_OBJECT
    }

    fn name(&self) -> Option<String> {
        Some(format!(
            "{}UpdateInput",
            self.table.graphql_base_type_name()
        ))
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        None
    }

    fn input_fields(&self) -> Option<Vec<__InputValue>> {
        Some(
            self.table
                .columns
                .iter()
                .filter(|x| x.permissions.is_updatable)
                .filter(|x| !x.is_generated)
                .filter(|x| !x.is_serial)
                .filter(|x| !self.schema.context.is_composite(x.type_oid))
                .map(|col| __InputValue {
                    name_: col.graphql_field_name(),
                    // TODO: handle possible array inputs
                    type_: sql_column_to_graphql_type(col, &self.schema).nullable_type(),
                    description: None,
                    default_value: None,
                    sql_type: Some(NodeSQLType::Column(col.clone())),
                })
                .collect(),
        )
    }
}

impl ___Type for UpdateResponseType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some(format!(
            "{}UpdateResponse",
            self.table.graphql_base_type_name()
        ))
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        Some(vec![
            __Field {
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::Scalar(Scalar::Int)),
                }),
                name_: "affectedCount".to_string(),
                args: vec![],
                description: Some("Count of the records impacted by the mutation".to_string()),
                deprecation_reason: None,
                sql_type: None,
            },
            __Field {
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::List(ListType {
                        type_: Box::new(__Type::NonNull(NonNullType {
                            type_: Box::new(__Type::Node(NodeType {
                                table: self.table.clone(),
                                fkey: None,
                                reverse_reference: None,
                                schema: self.schema.clone(),
                            })),
                        })),
                    })),
                }),
                name_: "records".to_string(),
                args: vec![],
                description: Some("Array of records impacted by the mutation".to_string()),
                deprecation_reason: None,
                sql_type: None,
            },
        ])
    }
}

impl ___Type for DeleteResponseType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::OBJECT
    }

    fn name(&self) -> Option<String> {
        Some(format!(
            "{}DeleteResponse",
            self.table.graphql_base_type_name()
        ))
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        Some(vec![
            __Field {
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::Scalar(Scalar::Int)),
                }),
                name_: "affectedCount".to_string(),
                args: vec![],
                description: Some("Count of the records impacted by the mutation".to_string()),
                deprecation_reason: None,
                sql_type: None,
            },
            __Field {
                type_: __Type::NonNull(NonNullType {
                    type_: Box::new(__Type::List(ListType {
                        type_: Box::new(__Type::NonNull(NonNullType {
                            type_: Box::new(__Type::Node(NodeType {
                                table: self.table.clone(),
                                fkey: None,
                                reverse_reference: None,
                                schema: self.schema.clone(),
                            })),
                        })),
                    })),
                }),
                name_: "records".to_string(),
                args: vec![],
                description: Some("Array of records impacted by the mutation".to_string()),
                deprecation_reason: None,
                sql_type: None,
            },
        ])
    }
}

impl ___Type for FilterTypeType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::INPUT_OBJECT
    }

    fn name(&self) -> Option<String> {
        match &self.entity {
            FilterableType::Scalar(s) => Some(format!("{}Filter", s.name().unwrap())),
            FilterableType::Enum(e) => Some(format!("{}Filter", e.name().unwrap())),
        }
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        None
    }

    fn description(&self) -> Option<String> {
        Some(format!(
            "Boolean expression comparing fields on type \"{}\"",
            match &self.entity {
                FilterableType::Scalar(s) => s.name().unwrap(),
                FilterableType::Enum(e) => e.name().unwrap(),
            }
        ))
    }

    fn input_fields(&self) -> Option<Vec<__InputValue>> {
        let mut infields: Vec<__InputValue> = match &self.entity {
            FilterableType::Scalar(scalar) => {
                let mut scalar_infields = vec![__InputValue {
                    name_: "eq".to_string(),
                    type_: __Type::Scalar(scalar.clone()),
                    description: None,
                    default_value: None,
                    sql_type: None,
                }];

                match scalar {
                    // IDFilter only supports equality
                    Scalar::ID => (),
                    // UUIDs are not ordered
                    Scalar::UUID => {
                        scalar_infields.extend(vec![
                            __InputValue {
                                name_: "neq".to_string(),
                                type_: __Type::Scalar(scalar.clone()),
                                description: None,
                                default_value: None,
                                sql_type: None,
                            },
                            __InputValue {
                                name_: "in".to_string(),
                                type_: __Type::List(ListType {
                                    type_: Box::new(__Type::NonNull(NonNullType {
                                        type_: Box::new(__Type::Scalar(scalar.clone())),
                                    })),
                                }),
                                description: None,
                                default_value: None,
                                sql_type: None,
                            },
                        ]);
                    }
                    _ => scalar_infields.extend(vec![
                        __InputValue {
                            name_: "neq".to_string(),
                            type_: __Type::Scalar(scalar.clone()),
                            description: None,
                            default_value: None,
                            sql_type: None,
                        },
                        __InputValue {
                            name_: "in".to_string(),
                            type_: __Type::List(ListType {
                                type_: Box::new(__Type::NonNull(NonNullType {
                                    type_: Box::new(__Type::Scalar(scalar.clone())),
                                })),
                            }),
                            description: None,
                            default_value: None,
                            sql_type: None,
                        },
                        __InputValue {
                            name_: "gt".to_string(),
                            type_: __Type::Scalar(scalar.clone()),
                            description: None,
                            default_value: None,
                            sql_type: None,
                        },
                        __InputValue {
                            name_: "gte".to_string(),
                            type_: __Type::Scalar(scalar.clone()),
                            description: None,
                            default_value: None,
                            sql_type: None,
                        },
                        __InputValue {
                            name_: "lt".to_string(),
                            type_: __Type::Scalar(scalar.clone()),
                            description: None,
                            default_value: None,
                            sql_type: None,
                        },
                        __InputValue {
                            name_: "lte".to_string(),
                            type_: __Type::Scalar(scalar.clone()),
                            description: None,
                            default_value: None,
                            sql_type: None,
                        },
                    ]),
                };
                scalar_infields
            }
            FilterableType::Enum(enum_) => {
                vec![
                    __InputValue {
                        name_: "eq".to_string(),
                        type_: __Type::Enum(enum_.clone()),
                        description: None,
                        default_value: None,
                        sql_type: None,
                    },
                    __InputValue {
                        name_: "neq".to_string(),
                        type_: __Type::Enum(enum_.clone()),
                        description: None,
                        default_value: None,
                        sql_type: None,
                    },
                    __InputValue {
                        name_: "in".to_string(),
                        type_: __Type::List(ListType {
                            type_: Box::new(__Type::NonNull(NonNullType {
                                type_: Box::new(__Type::Enum(enum_.clone())),
                            })),
                        }),
                        description: None,
                        default_value: None,
                        sql_type: None,
                    },
                ]
            }
        };

        infields.sort_by_key(|a| a.name());
        Some(infields)
    }
}

impl ___Type for FilterEntityType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::INPUT_OBJECT
    }

    fn name(&self) -> Option<String> {
        Some(format!("{}Filter", self.table.graphql_base_type_name()))
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        None
    }

    fn input_fields(&self) -> Option<Vec<__InputValue>> {
        let mut f: Vec<__InputValue> = self
            .table
            .columns
            .iter()
            .filter(|x| is_valid_graphql_name(&x.graphql_field_name()))
            .filter(|x| x.permissions.is_selectable)
            // No filtering on arrays
            .filter(|x| !x.type_name.ends_with("[]"))
            // No filtering on composites
            .filter(|x| !self.schema.context.is_composite(x.type_oid))
            // No filtering on json/b. they do not support = or <>
            .filter(|x| !vec!["json", "jsonb"].contains(&x.type_name.as_ref()))
            .filter_map(|col| {
                // Should be a scalar
                let utype = sql_column_to_graphql_type(col, &self.schema).unmodified_type();

                match utype {
                    __Type::Scalar(s) => Some(__InputValue {
                        name_: col.graphql_field_name(),
                        type_: __Type::FilterType(FilterTypeType {
                            entity: FilterableType::Scalar(s),
                        }),
                        description: None,
                        default_value: None,
                        sql_type: Some(NodeSQLType::Column(col.clone())),
                    }),
                    // ERROR HERE
                    __Type::Enum(s) => Some(__InputValue {
                        name_: col.graphql_field_name(),
                        type_: __Type::FilterType(FilterTypeType {
                            entity: FilterableType::Enum(s),
                        }),
                        description: None,
                        default_value: None,
                        sql_type: Some(NodeSQLType::Column(col.clone())),
                    }),
                    _ => None,
                }
            })
            .collect();

        if self.table.primary_key().is_some() {
            let pkey_cols = self
                .table
                .primary_key_columns()
                .into_iter()
                .cloned()
                .collect();

            f.push(__InputValue {
                name_: "nodeId".to_string(),
                type_: __Type::FilterType(FilterTypeType {
                    entity: FilterableType::Scalar(Scalar::ID),
                }),
                description: None,
                default_value: None,
                sql_type: Some(NodeSQLType::NodeId(pkey_cols)),
            });
        }

        Some(f)
    }
}

impl ___Type for OrderByType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::ENUM
    }

    fn name(&self) -> Option<String> {
        Some("OrderByDirection".to_string())
    }

    fn description(&self) -> Option<String> {
        Some("Defines a per-field sorting order".to_string())
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        None
    }

    fn enum_values(&self, _include_deprecated: bool) -> Option<Vec<__EnumValue>> {
        Some(vec![
            __EnumValue {
                name: "AscNullsFirst".to_string(),
                description: Some("Ascending order, nulls first".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "AscNullsLast".to_string(),
                description: Some("Ascending order, nulls last".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "DescNullsFirst".to_string(),
                description: Some("Descending order, nulls first".to_string()),
                deprecation_reason: None,
            },
            __EnumValue {
                name: "DescNullsLast".to_string(),
                description: Some("Descending order, nulls last".to_string()),
                deprecation_reason: None,
            },
        ])
    }
}

impl ___Type for OrderByEntityType {
    fn kind(&self) -> __TypeKind {
        __TypeKind::INPUT_OBJECT
    }

    fn name(&self) -> Option<String> {
        Some(format!("{}OrderBy", self.table.graphql_base_type_name()))
    }

    fn fields(&self, _include_deprecated: bool) -> Option<Vec<__Field>> {
        None
    }

    fn input_fields(&self) -> Option<Vec<__InputValue>> {
        Some(
            self.table
                .columns
                .iter()
                .filter(|x| is_valid_graphql_name(&x.graphql_field_name()))
                .filter(|x| x.permissions.is_selectable)
                // No filtering on arrays
                .filter(|x| !x.type_name.ends_with("[]"))
                // No filtering on composites
                .filter(|x| !self.schema.context.is_composite(x.type_oid))
                // No filtering on json/b. they do not support = or <>
                .filter(|x| !vec!["json", "jsonb"].contains(&x.type_name.as_ref()))
                // TODO  filter out arrays, json and composites
                .map(|col| __InputValue {
                    name_: col.graphql_field_name(),
                    type_: __Type::OrderBy(OrderByType {}),
                    description: None,
                    default_value: None,
                    sql_type: Some(NodeSQLType::Column(col.clone())),
                })
                .collect(),
        )
    }
}

#[derive(Serialize)]
pub struct ErrorMessage {
    pub message: String,
}

use super::omit::Omit;

#[derive(Serialize)]
pub struct GraphQLResponse {
    #[serde(skip_serializing_if = "Omit::is_omit")]
    pub data: Omit<serde_json::Value>,

    #[serde(skip_serializing_if = "Omit::is_omit")]
    pub errors: Omit<Vec<ErrorMessage>>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct __Schema {
    pub context: Context,
}

impl __Schema {
    // types: [__Type!]!
    pub fn types(&self) -> Vec<__Type> {
        // This is certainly not the right way to do this
        let schema_rc = Rc::new(self.clone());

        let mut types_: Vec<__Type> = vec![
            __Type::__TypeKind(__TypeKindType),
            __Type::__Schema(__SchemaType),
            __Type::__Type(__TypeType),
            __Type::__Field(__FieldType),
            __Type::__InputValue(__InputValueType),
            __Type::__EnumValue(__EnumValueType),
            __Type::__DirectiveLocation(__DirectiveLocationType),
            __Type::__Directive(__DirectiveType),
            __Type::PageInfo(PageInfoType),
            __Type::Scalar(Scalar::ID),
            __Type::Scalar(Scalar::Int),
            __Type::Scalar(Scalar::Float),
            __Type::Scalar(Scalar::String),
            __Type::Scalar(Scalar::Boolean),
            __Type::Scalar(Scalar::Date),
            __Type::Scalar(Scalar::Time),
            __Type::Scalar(Scalar::Datetime),
            __Type::Scalar(Scalar::BigInt),
            __Type::Scalar(Scalar::UUID),
            __Type::Scalar(Scalar::JSON),
            __Type::Scalar(Scalar::Cursor),
            __Type::OrderBy(OrderByType {}),
            __Type::FilterType(FilterTypeType {
                entity: FilterableType::Scalar(Scalar::ID),
            }),
            __Type::FilterType(FilterTypeType {
                entity: FilterableType::Scalar(Scalar::Int),
            }),
            __Type::FilterType(FilterTypeType {
                entity: FilterableType::Scalar(Scalar::Float),
            }),
            __Type::FilterType(FilterTypeType {
                entity: FilterableType::Scalar(Scalar::String),
            }),
            __Type::FilterType(FilterTypeType {
                entity: FilterableType::Scalar(Scalar::Boolean),
            }),
            __Type::FilterType(FilterTypeType {
                entity: FilterableType::Scalar(Scalar::Date),
            }),
            __Type::FilterType(FilterTypeType {
                entity: FilterableType::Scalar(Scalar::Time),
            }),
            __Type::FilterType(FilterTypeType {
                entity: FilterableType::Scalar(Scalar::Datetime),
            }),
            __Type::FilterType(FilterTypeType {
                entity: FilterableType::Scalar(Scalar::BigInt),
            }),
            __Type::FilterType(FilterTypeType {
                entity: FilterableType::Scalar(Scalar::UUID),
            }),
            __Type::Query(QueryType {
                schema: schema_rc.clone(),
            }),
            __Type::NodeInterface(NodeInterfaceType {
                schema: schema_rc.clone(),
            }),
        ];

        if self.mutations_exist() {
            types_.push(__Type::Mutation(MutationType {
                schema: schema_rc.clone(),
            }));
        }

        for schema in self.context.schemas.iter() {
            for table in schema
                .tables
                .iter()
                .filter(|x| x.graphql_select_types_are_valid())
            {
                types_.push(__Type::Node(NodeType {
                    table: table.clone(),
                    fkey: None,
                    reverse_reference: None,
                    schema: schema_rc.clone(),
                }));
                types_.push(__Type::Edge(EdgeType {
                    table: table.clone(),
                    schema: schema_rc.clone(),
                }));
                types_.push(__Type::Connection(ConnectionType {
                    table: table.clone(),
                    fkey: None,
                    reverse_reference: None,
                    schema: schema_rc.clone(),
                }));

                types_.push(__Type::FilterEntity(FilterEntityType {
                    table: table.clone(),
                    schema: schema_rc.clone(),
                }));

                types_.push(__Type::OrderByEntity(OrderByEntityType {
                    table: table.clone(),
                    schema: schema_rc.clone(),
                }));

                if table.graphql_insert_types_are_valid() {
                    types_.push(__Type::InsertInput(InsertInputType {
                        table: table.clone(),
                        schema: schema_rc.clone(),
                    }));
                    types_.push(__Type::InsertResponse(InsertResponseType {
                        table: table.clone(),
                        schema: schema_rc.clone(),
                    }));
                }

                if table.graphql_update_types_are_valid() {
                    types_.push(__Type::UpdateInput(UpdateInputType {
                        table: table.clone(),
                        schema: schema_rc.clone(),
                    }));
                    types_.push(__Type::UpdateResponse(UpdateResponseType {
                        table: table.clone(),
                        schema: schema_rc.clone(),
                    }));
                }

                if table.graphql_delete_types_are_valid() {
                    types_.push(__Type::DeleteResponse(DeleteResponseType {
                        table: table.clone(),
                        schema: schema_rc.clone(),
                    }));
                }
            }

            for enum_ in self
                .context
                .enums
                .iter()
                .filter(|x| x.permissions.is_usable)
            {
                let enum_type = EnumType {
                    enum_: enum_.clone(),
                    schema: schema_rc.clone(),
                };

                types_.push(__Type::Enum(enum_type.clone()));

                let enum_filter = __Type::FilterType(FilterTypeType {
                    entity: FilterableType::Enum(enum_type.clone()),
                });

                types_.push(__Type::Enum(enum_type));
                types_.push(enum_filter);
            }
        }

        types_.sort_by_key(|a| a.name());
        types_
    }

    pub fn type_map(&self) -> HashMap<String, __Type> {
        let tmap: HashMap<String, __Type> = self
            .types()
            .into_iter()
            .filter(|x| x.name().is_some())
            .map(|x| (x.name().unwrap(), x))
            .collect();
        tmap
    }

    pub fn mutations_exist(&self) -> bool {
        self.context
            .schemas
            .iter()
            .flat_map(|x| x.tables.iter())
            .filter(|x| x.graphql_select_types_are_valid())
            .any(|x| {
                x.permissions.is_selectable
                    && (x.permissions.is_insertable
                        || x.permissions.is_updatable
                        || x.permissions.is_deletable)
            })
    }

    // queryType: __Type!
    #[allow(dead_code)]
    pub fn query_type(&self) -> __Type {
        __Type::Query(QueryType {
            //schema: Rc::new(*self),
            schema: Rc::new(self.clone()),
        })
    }

    // mutationType: __Type
    #[allow(dead_code)]
    pub fn mutation_type(&self) -> Option<__Type> {
        let mutation = MutationType {
            //schema: Rc::new(*self),
            schema: Rc::new(self.clone()),
        };

        match mutation.fields(true).unwrap_or_default().len() {
            0 => None,
            _ => Some(__Type::Mutation(mutation)),
        }
    }

    // subscriptionType: __Type
    #[allow(dead_code)]
    pub fn subscription_type(&self) -> Option<__Type> {
        None
    }

    // directives: [__Directive!]!
    #[allow(dead_code)]
    pub fn directives(&self) -> Vec<__Directive> {
        vec![]
    }
}

#[cfg(any(test, feature = "pg_test"))]
#[pgx::pg_schema]
mod tests {
    use crate::graphql::*;
    use pgx::*;

    #[pg_test]
    fn test_load_graphql_schema() {
        let config = load_sql_config();
        let context = load_sql_context(&config);
        let graphql_schema = __Schema { context };
        let query_type = graphql_schema.query_type();
        assert_eq!(query_type.name(), Some("Query".to_string()));
    }
}
