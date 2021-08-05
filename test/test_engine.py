def test_connect(sess):
    (x,) = sess.execute("select 1").fetchone()
    assert x == 1
