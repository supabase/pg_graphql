/*
gson:Value is roughly a mirror of serde_json::Value
with added support for the concept of "Absent" so we
can differentiate between Null literals and values that
were not provided by the user.
*/
use std::collections::HashMap;

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Absent,
    Null,
    Number(Number),
    String(String),
    Boolean(bool),
    Array(Vec<Value>),
    Object(HashMap<String, Value>),
}

#[derive(Clone, Debug, PartialEq)]
pub enum Number {
    Integer(i64),
    Float(f64),
}
