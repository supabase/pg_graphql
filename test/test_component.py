import json

from sqlalchemy import func, select, text


def test_get_name(sess):

    selection = json.dumps({
      "kind": "Field",
      "name": {
        "kind": "Name",
        "value": "hello"
      },
      "alias": None,
      "arguments": None,
      "directives": None,
      "selectionSet": None
    })

    (result,) = sess.execute(select([func.gql.get_name(selection)])).fetchone()

    assert result == "hello"


def test_get_alias(sess):

    selection = json.dumps({
      "kind": "Field",
      "name": {
        "kind": "Name",
        "value": "hello"
      },
      "alias": {
        "kind": "Name",
        "value": "hello_alias"
      },
      "arguments": None,
      "directives": None,
      "selectionSet": None
    })

    (result,) = sess.execute(select([func.gql.get_alias(selection)])).fetchone()

    assert result == "hello_alias"


def test_get_alias_defaults_to_name(sess):

    selection = json.dumps({
      "kind": "Field",
      "name": {
        "kind": "Name",
        "value": "hello"
      },
      "alias": None,
      "arguments": None,
      "directives": None,
      "selectionSet": None
    })

    (result,) = sess.execute(select([func.gql.get_alias(selection)])).fetchone()

    assert result == "hello"
