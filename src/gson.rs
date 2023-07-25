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

pub fn json_to_gson(val: &serde_json::Value) -> Result<Value, String> {
    use serde_json::Value as JsonValue;

    let v = match val {
        JsonValue::Null => Value::Null,
        JsonValue::Bool(x) => Value::Boolean(x.to_owned()),
        JsonValue::String(x) => Value::String(x.to_owned()),
        JsonValue::Array(x) => {
            let mut arr = vec![];
            for jelem in x {
                let gelem = json_to_gson(jelem)?;
                arr.push(gelem);
            }
            Value::Array(arr)
        }
        JsonValue::Number(x) => {
            let val: Option<i64> = x.as_i64();
            match val {
                Some(num) => {
                    let i_val = Number::Integer(num);
                    Value::Number(i_val)
                }
                None => {
                    let f_val: f64 = x
                        .as_f64()
                        .ok_or("Failed to handle numeric user input".to_string())?;
                    Value::Number(Number::Float(f_val))
                }
            }
        }
        JsonValue::Object(kv) => {
            let mut hmap = HashMap::new();
            for (key, v) in kv.iter() {
                let gson_val = json_to_gson(v)?;
                hmap.insert(key.to_owned(), gson_val);
            }
            Value::Object(hmap)
        }
    };
    Ok(v)
}

pub fn gson_to_json(val: &Value) -> Result<serde_json::Value, String> {
    use serde_json::Value as JsonValue;

    let v = match val {
        Value::Absent => {
            return Err("Encounterd `Absent` value while transforming between GraphQL intermediate object notation and JSON".to_string())
        },
        Value::Null => JsonValue::Null,
        Value::Boolean(x) => JsonValue::Bool(x.to_owned()),
        Value::String(x) => JsonValue::String(x.to_owned()),
        Value::Array(x) => {
            let mut arr = vec![];
            for gelem in x {
                let jelem = gson_to_json(gelem)?;
                arr.push(jelem);
            }
            JsonValue::Array(arr)
        }
        Value::Number(x) => match x {
            Number::Integer(y) => serde_json::json!(y),
            Number::Float(y) => serde_json::json!(y),
        },
        Value::Object(kv) => {
            let mut hmap = serde_json::Map::new();
            for (key, v) in kv.iter() {
                let json_val = gson_to_json(v)?;
                hmap.insert(key.to_owned(), json_val);
            }
            JsonValue::Object(hmap)
        }
    };
    Ok(v)
}
