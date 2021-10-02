import json

from sqlalchemy import func, select


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
    assert isinstance(node["id"], str)
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
