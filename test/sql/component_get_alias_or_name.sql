select gql.alias_or_name($$
    {
        "kind": "Field",
        "name": {"kind": "Name", "value": "hello"},
        "alias": {"kind": "Name", "value": "hello_alias"},
        "arguments": null,
        "directives": null,
        "selectionSet": null
    }
$$::jsonb);


select gql.alias_or_name($$
    {
        "kind": "Field",
        "name": {"kind": "Name", "value": "hello"},
        "alias": null,
        "arguments": null,
        "directives": null,
        "selectionSet": null
    }
$$::jsonb);
