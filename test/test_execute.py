import json

from sqlalchemy import func, select, text


def setup_data(sess) -> None:

    sess.execute(
        text(
            """
    create table "book"(
        id integer primary key,
        title text
    );

    insert into "book"(id, title)
    values
        (1, 'book 1'),
        (2, 'book 2'),
        (3, 'book 3');
        """
        )
    )
    sess.flush()


def test_execute_simple(sess):
    """Smoke test to see if queries work at all"""
    setup_data(sess)

    query = """
    query {
      book(id: 2) {
        title
      }
    }
    """

    (result,) = sess.execute(select([func.gql.execute(query)])).fetchone()

    assert result == {"data": {"book": {"title": "book 2"}}}


def test_execute_multi_column(sess):
    """Select multiple columns"""
    setup_data(sess)

    query = """
    query {
      book(id: 2) {
        id
        title
      }
    }
    """

    (result,) = sess.execute(select([func.gql.execute(query)])).fetchone()

    assert result["data"]["book"] == {"id": 2, "title": "book 2"}


def test_execute_filter_by_id(sess):
    """Filter table to a record by id"""
    setup_data(sess)

    query = """
    query {
      book(id: 2) {
        id
        title
      }
    }
    """

    (result,) = sess.execute(select([func.gql.execute(query)])).fetchone()

    assert result["data"]["book"] == {"id": 2, "title": "book 2"}


def test_execute_filter_by_title(sess):
    """Filter table to a record by title"""
    setup_data(sess)

    query = """
    query {
      book(title: "book 1") {
        id
        title
      }
    }
    """

    (result,) = sess.execute(select([func.gql.execute(query)])).fetchone()

    assert result["data"]["book"] == {"id": 1, "title": "book 1"}


def test_execute_alias_field_name(sess):
    """Alias id field to book_id"""
    setup_data(sess)

    query = """
    query {
      book(id: 2) {
        book_id: id
      }
    }
    """

    (result,) = sess.execute(select([func.gql.execute(query)])).fetchone()

    assert result["data"]["book"] == {"book_id": 2}


def test_execute_alias_operation_name(sess):
    """Alias book query operation to xXx"""
    setup_data(sess)

    query = """
    query {
      xXx: book(id: 2) {
        book_id: id
      }
    }
    """

    (result,) = sess.execute(select([func.gql.execute(query)])).fetchone()

    assert result["data"] == {"xXx": {"book_id": 2}}
