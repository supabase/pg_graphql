import json

from sqlalchemy import func, select

# Cursor for ['public', 'account', 1]
ACCOUNT_CURSOR = "WyJwdWJsaWMiLCAiYWNjb3VudCIsIDJd"


def test_resolve_account_entrypoint(sess):
    query = """
{
  account(id: "WyJwdWJsaWMiLCAiYWNjb3VudCIsIDJd") {
    id
  }
}
"""
    (result,) = sess.execute(select([func.gql.dispatch(query)])).fetchone()
    print(json.dumps(result, indent=2))
    assert "data" in result
    assert "errors" in result
    assert result["errors"] == []
    assert result["data"] == {"account": {"id": 2}}


def test_resolve_account_entrypoint_with_named_operation(sess):
    query = """
query GetAccount($nodeId: ID!) {
  account(nodeId: $nodeId) {
    id
  }
}
"""
    (result,) = sess.execute(
        select(
            [
                func.gql.dispatch(
                    query, json.dumps({"nodeId": "WyJwdWJsaWMiLCAiYWNjb3VudCIsIDJd"})
                )
            ]
        )
    ).fetchone()
    print(json.dumps(result, indent=2))
    assert "data" in result
    assert "errors" in result
    assert result["errors"] == []
    assert result["data"] == {"account": {"id": 2}}


def test_resolve___Type(sess):
    query = """
{
  __type(name: "Account") {
    kind
    fields {
    	name
    }
  }
}
"""
    (result,) = sess.execute(select([func.gql.dispatch(query)])).fetchone()
    print(json.dumps(result, indent=2))
    assert "data" in result
    assert "errors" in result
    assert result["errors"] == []
    assert result["data"]["__type"]["kind"] == "OBJECT"
    fields = result["data"]["__type"]["fields"]
    assert len(fields) == 6
    assert "createdAt" in [x["name"] for x in fields]


def test_resolve___Schema(sess):
    query = """
query IntrospectionQuery {
  __schema {
    queryType {
      name
    }
    mutationType {
      name
    }
    types {
      kind
      name
    }
    directives {
      name
      description
      locations
    }
  }
}
"""
    (result,) = sess.execute(select([func.gql.dispatch(query)])).fetchone()
    print(json.dumps(result, indent=2))
    assert "data" in result
    assert result["errors"] == []
    assert result["data"]["__schema"]["queryType"]["name"] == "Query"
    assert result["data"]["__schema"]["mutationType"]["name"] == "Mutation"
    assert len(result["data"]["__schema"]["types"]) > 5


def test_resolve_connection_entrypoint(sess):
    query = """
{
  allAccounts {
    totalCount
    pageInfo{
        startCursor
        endCursor
        hasPreviousPage
        hasNextPage
    }
    edges {
      cursor
      node {
        id
        email
        createdAt
      }
    }
  }
}
"""

    (result,) = sess.execute(select([func.gql.dispatch(query)])).fetchone()
    print(json.dumps(result, indent=2))
    assert "data" in result
    assert "errors" in result
    assert result["errors"] == []
    data = result["data"]
    assert data["allAccounts"]["totalCount"] == 5
    edges = data["allAccounts"]["edges"]
    assert len(edges) == 5
    assert isinstance(edges[0]["cursor"], str)
    node = edges[0]["node"]
    assert isinstance(node, dict)
    assert isinstance(node["id"], int)
    assert isinstance(node["email"], str)
    assert isinstance(node["createdAt"], str)


def test_resolve_relationship_to_connection(sess):

    query = """
{
  allAccounts {
    totalCount
    pageInfo{
        startCursor
        endCursor
        hasPreviousPage
        hasNextPage
    }
    edges {
      cursor
      node {
        id
        email
        createdAt
        blogs {
          totalCount
          edges {
            cursor
            node {
              id
            }
          }
        }
      }
    }
  }
}
"""

    (result,) = sess.execute(select([func.gql.dispatch(query)])).fetchone()
    print(json.dumps(result, indent=2))
    assert "data" in result
    assert "errors" in result
    account = [
        x
        for x in result["data"]["allAccounts"]["edges"]
        if x["node"]["email"] == "aardvark@x.com"
    ][0]
    blogs = account["node"]["blogs"]
    print(blogs)
    assert blogs["totalCount"] == 3
    assert len(blogs["edges"]) == 3
    assert blogs["edges"][0]["node"]["id"]
    assert blogs["edges"][0]["cursor"]


def test_resolve_relationship_to_node(sess):

    query = """
{
  allBlogs {
    edges {
      node {
        ownerId
        owner {
          id
        }
      }
    }
  }
}
"""

    (result,) = sess.execute(select([func.gql.dispatch(query)])).fetchone()
    print(json.dumps(result, indent=2))
    assert "data" in result
    assert "errors" in result

    edges = result["data"]["allBlogs"]["edges"]
    assert len(edges) > 3

    for edge in edges:
        assert edge["node"]["ownerId"] == edge["node"]["owner"]["id"]


def test_resolve_fragment(sess):

    query = """
{
  allBlogs(first: 1) {
    edges {
      cursor
      node {
        ...BaseBlog
        createdAt
      }
    }
  }
}

fragment BaseBlog on Blog {
  name
  description
}
"""
    (result,) = sess.execute(select([func.gql.dispatch(query)])).fetchone()
    print(json.dumps(result, indent=2))
    assert "data" in result
    assert "errors" in result

    edges = result["data"]["allBlogs"]["edges"]
    assert len(edges) == 1
    node = edges[0]["node"]
    for key in ["name", "description", "createdAt"]:
        assert key in node
        assert node[key] is not None
