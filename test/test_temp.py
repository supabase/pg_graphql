from sqlalchemy import text, func, select


def test_select_one(sess):

    (one,) = sess.execute(text(
        """
        select 1; 
    """
    )).fetchone()

    assert one == 1


def test_select_sql_to_ast(sess):

    (ast,) = sess.execute(text(
        """
        select gql.sql_to_ast('select 1') 
    """
    )).fetchone()

    assert 'RAWSTMT' in ast


def test_parse(sess):

    query = """
    query {
      account {
        name
      }
    }
    """

    (ast,) = sess.execute(select([func.gql.parse(query)])).fetchone()

    print(ast)
    assert False



