import json

from sqlalchemy import func, select


def test_get_name(sess):

    selection = json.dumps(
        {
            "kind": "Field",
            "name": {"kind": "Name", "value": "hello"},
            "alias": None,
            "arguments": None,
            "directives": None,
            "selectionSet": None,
        }
    )

    (result,) = sess.execute(select([func.gql.name(selection)])).fetchone()

    assert result == "hello"


def test_get_alias_or_name_w_alias(sess):

    selection = json.dumps(
        {
            "kind": "Field",
            "name": {"kind": "Name", "value": "hello"},
            "alias": {"kind": "Name", "value": "hello_alias"},
            "arguments": None,
            "directives": None,
            "selectionSet": None,
        }
    )

    (result,) = sess.execute(select([func.gql.alias_or_name(selection)])).fetchone()

    assert result == "hello_alias"


def test_get_alias_or_name_wo_alias(sess):

    selection = json.dumps(
        {
            "kind": "Field",
            "name": {"kind": "Name", "value": "hello"},
            "alias": None,
            "arguments": None,
            "directives": None,
            "selectionSet": None,
        }
    )

    (result,) = sess.execute(select([func.gql.alias_or_name(selection)])).fetchone()

    assert result == "hello"
