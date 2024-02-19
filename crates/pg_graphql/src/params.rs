use pgrx::{prelude::pg_sys, IntoDatum, PgBuiltInOids, PgOid};

pub struct ParamContext {
    pub params: Vec<(PgOid, Option<pg_sys::Datum>)>,
}

impl ParamContext {
    // Pushes a parameter into the context and returns a SQL clause to reference it
    //fn clause_for(&mut self, param: (PgOid, Option<pg_sys::Datum>)) -> String {
    pub fn clause_for(
        &mut self,
        value: &serde_json::Value,
        type_name: &str,
    ) -> Result<String, String> {
        let type_oid = match type_name.ends_with("[]") {
            true => PgOid::BuiltIn(PgBuiltInOids::TEXTARRAYOID),
            false => PgOid::BuiltIn(PgBuiltInOids::TEXTOID),
        };

        let val_datum = json_to_text_datum(value)?;
        self.params.push((type_oid, val_datum));
        Ok(format!("(${}::{})", self.params.len(), type_name))
    }
}

pub fn json_to_text_datum(val: &serde_json::Value) -> Result<Option<pg_sys::Datum>, String> {
    use serde_json::Value;
    let null: Option<i32> = None;
    match val {
        Value::Null => Ok(null.into_datum()),
        Value::Bool(x) => Ok(x.to_string().into_datum()),
        Value::String(x) => Ok(x.into_datum()),
        Value::Number(x) => Ok(x.to_string().into_datum()),
        Value::Array(xarr) => {
            let mut inner_vals: Vec<Option<String>> = vec![];
            for elem in xarr {
                let str_elem = match elem {
                    Value::Null => None,
                    Value::Bool(x) => Some(x.to_string()),
                    Value::String(x) => Some(x.to_string()),
                    Value::Number(x) => Some(x.to_string()),
                    Value::Array(_) => {
                        return Err("Unexpected array in input value array".to_string());
                    }
                    Value::Object(_) => {
                        return Err("Unexpected object in input value array".to_string());
                    }
                };
                inner_vals.push(str_elem);
            }
            Ok(inner_vals.into_datum())
        }
        // Should this ever happen? json input is escaped so it would be a string.
        Value::Object(_) => Err("Unexpected object in input value".to_string()),
    }
}
