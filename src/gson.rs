use std::collections::HashMap;

pub enum Value {
    Absent,
    Null,
    Number(Number),
    String(String),
    Boolean(bool),
    Array(Vec<Value>),
    Object(HashMap<String, Value>),
}

pub enum Number {
    Integer(i64),
    Float(f64),
}
