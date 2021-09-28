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
