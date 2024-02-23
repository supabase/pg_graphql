use std::collections::HashMap;

#[derive(PartialEq, Eq, Debug)]
pub struct Field {
    name: String,
    alias: Option<String>,
    children: Vec<Field>,
}

impl Field {
    pub fn response_key(&self) -> &str {
        self.alias.as_ref().unwrap_or(&self.name)
    }
}

pub fn merge_fields(fields: Vec<Field>) -> Result<Vec<Field>, String> {
    let mut merged: HashMap<String, Field> = HashMap::with_capacity(fields.len());
    for current_field in fields {
        let response_key = current_field.response_key().to_string();
        match merged.get_mut(&response_key) {
            Some(existing_field) => {
                if current_field.name != existing_field.name {
                    return Err(format!(
                        "Field {} and {} are different",
                        current_field.name, existing_field.name
                    ));
                }
                let existing_field = merged
                    .remove(&response_key)
                    .expect("failed to remove existing field");
                let mut child_fields = vec![];
                child_fields.extend(current_field.children);
                child_fields.extend(existing_field.children);
                let merged_children = merge_fields(child_fields)?;
                let new_field = Field {
                    name: existing_field.name,
                    alias: existing_field.alias,
                    children: merged_children,
                };
                merged.insert(response_key, new_field);
            }
            None => {
                merged.insert(response_key, current_field);
            }
        }
    }

    let merged_vec: Vec<Field> = merged.drain().map(|(_, f)| f).collect();

    Ok(merged_vec)
}

#[cfg(test)]
mod tests {
    use super::{merge_fields, Field};

    #[test]
    fn merge_fields_no_fields_test() {
        let fields = vec![];
        let merged_fields = merge_fields(fields);
        assert!(merged_fields.is_ok());
        let merged_fields = merged_fields.unwrap();
        let expected_fields = vec![];
        assert_eq_unordered(merged_fields, expected_fields);
    }

    #[test]
    fn merge_fields_single_field_test() {
        let fields = vec![Field {
            name: "a".to_string(),
            alias: None,
            children: vec![],
        }];
        let merged_fields = merge_fields(fields);
        assert!(merged_fields.is_ok());
        let merged_fields = merged_fields.unwrap();
        let expected_fields = vec![Field {
            name: "a".to_string(),
            alias: None,
            children: vec![],
        }];
        assert_eq_unordered(merged_fields, expected_fields);
    }

    #[test]
    fn merge_fields_two_distinct_fields_test() {
        let fields = vec![
            Field {
                name: "a".to_string(),
                alias: None,
                children: vec![],
            },
            Field {
                name: "b".to_string(),
                alias: None,
                children: vec![],
            },
        ];
        let merged_fields = merge_fields(fields);
        assert!(merged_fields.is_ok());
        let merged_fields = merged_fields.unwrap();
        let expected_fields = vec![
            Field {
                name: "a".to_string(),
                alias: None,
                children: vec![],
            },
            Field {
                name: "b".to_string(),
                alias: None,
                children: vec![],
            },
        ];
        assert_eq_unordered(merged_fields, expected_fields);
    }

    #[test]
    fn merge_fields_two_same_fields_test() {
        let fields = vec![
            Field {
                name: "a".to_string(),
                alias: None,
                children: vec![],
            },
            Field {
                name: "a".to_string(),
                alias: None,
                children: vec![],
            },
        ];
        let merged_fields = merge_fields(fields);
        assert!(merged_fields.is_ok());
        let merged_fields = merged_fields.unwrap();
        let expected_fields = vec![Field {
            name: "a".to_string(),
            alias: None,
            children: vec![],
        }];
        assert_eq_unordered(merged_fields, expected_fields);
    }

    #[test]
    fn merge_fields_two_same_fields_with_children_test() {
        let fields = vec![
            Field {
                name: "a".to_string(),
                alias: None,
                children: vec![Field {
                    name: "b".to_string(),
                    alias: None,
                    children: vec![{
                        Field {
                            name: "d".to_string(),
                            alias: None,
                            children: vec![Field {
                                name: "e".to_string(),
                                alias: None,
                                children: vec![],
                            }],
                        }
                    }],
                }],
            },
            Field {
                name: "a".to_string(),
                alias: None,
                children: vec![
                    Field {
                        name: "b".to_string(),
                        alias: None,
                        children: vec![{
                            Field {
                                name: "d".to_string(),
                                alias: None,
                                children: vec![Field {
                                    name: "f".to_string(),
                                    alias: None,
                                    children: vec![],
                                }],
                            }
                        }],
                    },
                    Field {
                        name: "c".to_string(),
                        alias: None,
                        children: vec![],
                    },
                ],
            },
        ];
        let merged_fields = merge_fields(fields);
        assert!(merged_fields.is_ok());
        let merged_fields = merged_fields.unwrap();
        let expected_fields = vec![Field {
            name: "a".to_string(),
            alias: None,
            children: vec![
                Field {
                    name: "b".to_string(),
                    alias: None,
                    children: vec![Field {
                        name: "d".to_string(),
                        alias: None,
                        children: vec![
                            Field {
                                name: "e".to_string(),
                                alias: None,
                                children: vec![],
                            },
                            Field {
                                name: "f".to_string(),
                                alias: None,
                                children: vec![],
                            },
                        ],
                    }],
                },
                Field {
                    name: "c".to_string(),
                    alias: None,
                    children: vec![],
                },
            ],
        }];
        assert_eq_unordered(merged_fields, expected_fields);
    }

    #[test]
    fn merge_fields_alias_no_conflict_test() {
        let fields = vec![
            Field {
                name: "a".to_string(),
                alias: None,
                children: vec![],
            },
            Field {
                name: "a".to_string(),
                alias: Some("b".to_string()),
                children: vec![],
            },
        ];
        let merged_fields = merge_fields(fields);
        assert!(merged_fields.is_ok());
        let merged_fields = merged_fields.unwrap();
        let expected_fields = vec![
            Field {
                name: "a".to_string(),
                alias: None,
                children: vec![],
            },
            Field {
                name: "a".to_string(),
                alias: Some("b".to_string()),
                children: vec![],
            },
        ];
        assert_eq_unordered(merged_fields, expected_fields);
    }

    #[test]
    fn merge_fields_alias_conflict_test() {
        let fields = vec![
            Field {
                name: "a".to_string(),
                alias: None,
                children: vec![],
            },
            Field {
                name: "b".to_string(),
                alias: Some("a".to_string()),
                children: vec![],
            },
        ];
        let merged_fields = merge_fields(fields);
        assert_eq!(
            merged_fields,
            Err("Field b and a are different".to_string())
        );
    }

    fn assert_eq_unordered(mut first: Vec<Field>, mut second: Vec<Field>) {
        sort_fields(&mut first);
        sort_fields(&mut second);
        assert_eq!(first, second);
    }

    fn sort_fields(fields: &mut Vec<Field>) {
        fields.sort_by_key(|f| f.response_key().to_string());
        for field in fields {
            sort_fields(&mut field.children);
        }
    }
}
