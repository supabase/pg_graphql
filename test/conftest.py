# pylint: disable=redefined-outer-name,no-member
import json
import os
import subprocess
import time
from pathlib import Path

import pytest
import sqlalchemy
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session

CONTAINER_NAME = "pg_graphql_test_db"
PORT = 5402


@pytest.fixture(scope="session")
def dockerize_database():

    # Skip if we're using github actions CI
    if not "GITHUB_SHA" in os.environ:
        subprocess.call(
            ["docker-compose", "-f", "docker-compose.tests.yml", "up", "-d"]
        )
        # Wait for postgres to become healthy
        for _ in range(10):
            out = subprocess.check_output(["docker", "inspect", CONTAINER_NAME])
            container_info = json.loads(out)
            container_health_status = container_info[0]["State"]["Health"]["Status"]
            if container_health_status == "healthy":
                time.sleep(1)
                break
            else:
                time.sleep(1)
        else:
            raise Exception("Container never became healthy")
        yield
        subprocess.call(
            ["docker-compose", "-f", "docker-compose.tests.yml", "down", "-v"]
        )
        return
    yield


@pytest.fixture(scope="session")
def engine(dockerize_database):
    eng = create_engine(f"postgresql://postgres:password@localhost:5402/gqldb")

    path = Path("test/setup.sql")
    contents = path.read_text()
    with eng.connect() as conn:
        conn.execute(text(contents))
        conn.execute(text("commit"))

    yield eng
    eng.dispose()


@pytest.fixture(scope="function")
def sess(engine):
    conn = engine.connect()

    # Begin a transaction directly against the connection
    transaction = conn.begin()

    # Bind a session to the top level transaction
    _session = Session(bind=conn)

    # Start a savepoint that we can rollback to in the transaction
    _session.begin_nested()

    @sqlalchemy.event.listens_for(_session, "after_transaction_end")
    def restart_savepoint(sess, trans):
        """Register event listener to clean up the sqla objects of a session after a transaction ends"""
        if trans.nested and not trans._parent.nested:
            # Expire all objects registered against the session
            sess.expire_all()
            sess.begin_nested()

    yield _session
    # Close the session object
    _session.close()

    # Rollback to the savepoint, eliminating everything that happend to the _session
    # while it was yielded, cleaning up any newly committed objects
    transaction.rollback()

    # Close the connection
    conn.close()
