import json

from sqlalchemy import func, select


def test_parse(sess):

    query = """
    query {
      account(id: 1) {
        name
      }
    }
    """

    (full_ast,) = sess.execute(select([func.gql.parse(query)])).fetchone()
    (ast,) = sess.execute(
        select([func.gql._recursive_strip_key(json.dumps(full_ast, indent=2))])
    ).fetchone()

    with open("example.json", "w") as f:
        f.write(json.dumps(ast, indent=2))

    assert ast == {
        "kind": "Document",
        "definitions": [
            {
                "kind": "OperationDefinition",
                "name": None,
                "operation": "query",
                "directives": None,
                "selectionSet": {
                    "kind": "SelectionSet",
                    "selections": [
                        {
                            "kind": "Field",
                            "name": {"kind": "Name", "value": "account"},
                            "alias": None,
                            "arguments": [
                                {
                                    "kind": "Argument",
                                    "name": {"kind": "Name", "value": "id"},
                                    "value": {"kind": "IntValue", "value": "1"},
                                }
                            ],
                            "directives": None,
                            "selectionSet": {
                                "kind": "SelectionSet",
                                "selections": [
                                    {
                                        "kind": "Field",
                                        "name": {"kind": "Name", "value": "name"},
                                        "alias": None,
                                        "arguments": None,
                                        "directives": None,
                                        "selectionSet": None,
                                    }
                                ],
                            },
                        }
                    ],
                },
                "variableDefinitions": None,
            }
        ],
    }
