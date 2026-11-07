"""Real Session events; only the external stock-push boundary is replaced."""

from copy import deepcopy

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column

from app.services import woocommerce_stock_push_hook as hook


class Base(DeclarativeBase):
    pass


class CommitMarker(Base):
    __tablename__ = "stock_push_test_markers"

    id: Mapped[int] = mapped_column(primary_key=True)


@pytest.fixture
def harness(monkeypatch):
    delivered = []
    monkeypatch.setattr(hook, "_execute_stock_push", lambda payload: delivered.append(deepcopy(payload)))
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    try:
        with Session(engine) as session:
            session.execute(text("select 1"))
            yield session, delivered
    finally:
        engine.dispose()


def schedule(session, number):
    hook.schedule_woocommerce_stock_push_after_warehouse_post(
        session, business_id=1, warehouse_document_id=number, product_ids=[number],
    )


def delivered_ids(delivered):
    return [payload["warehouse_document_id"] for payload in delivered]


def test_root_commit_is_the_first_dispatch_boundary(harness):
    session, delivered = harness
    session.add(CommitMarker(id=1))
    schedule(session, 1)
    session.flush()
    assert delivered == []
    session.commit()
    assert delivered_ids(delivered) == [1]
    assert session.get(CommitMarker, 1) is not None


def test_nested_commits_wait_for_root(harness):
    session, delivered = harness
    schedule(session, 1)
    with session.begin_nested():
        schedule(session, 2)
        with session.begin_nested():
            schedule(session, 3)
    assert delivered == []
    session.commit()
    assert delivered_ids(delivered) == [1, 2, 3]


def test_nested_rollback_keeps_outer_payload(harness):
    session, delivered = harness
    schedule(session, 1)
    child = session.begin_nested()
    schedule(session, 2)
    child.rollback()
    assert delivered == []
    session.commit()
    assert delivered_ids(delivered) == [1]


def test_parent_rollback_discards_committed_descendant(harness):
    session, delivered = harness
    schedule(session, 1)
    parent = session.begin_nested()
    schedule(session, 2)
    with session.begin_nested():
        schedule(session, 3)
    parent.rollback()
    assert delivered == []
    session.commit()
    assert delivered_ids(delivered) == [1]


def test_root_rollback_never_dispatches(harness):
    session, delivered = harness
    schedule(session, 1)
    session.rollback()
    assert delivered == []


def test_root_rollback_then_session_reuse(harness):
    session, delivered = harness
    schedule(session, 1)
    session.rollback()
    session.execute(text("select 1"))
    schedule(session, 2)
    session.commit()
    assert delivered_ids(delivered) == [2]


def test_root_close_then_session_reuse_discards_stale_payload(harness):
    session, delivered = harness
    schedule(session, 1)
    session.close()
    session.execute(text("select 1"))
    schedule(session, 2)
    session.commit()
    assert delivered_ids(delivered) == [2]


def test_savepoint_close_discards_only_inner_payload(harness):
    session, delivered = harness
    schedule(session, 1)
    child = session.begin_nested()
    schedule(session, 2)
    child.close()
    session.commit()
    assert delivered_ids(delivered) == [1]


def test_committed_savepoint_then_root_rollback_never_dispatches(harness):
    session, delivered = harness
    with session.begin_nested():
        schedule(session, 1)
    assert delivered == []
    session.rollback()
    assert delivered == []


def test_reused_session_dispatches_once_per_root_commit(harness):
    session, delivered = harness
    for number in range(1, 6):
        session.execute(text("select 1"))
        schedule(session, number)
        session.commit()
    assert delivered_ids(delivered) == [1, 2, 3, 4, 5]


@pytest.mark.parametrize("product_ids,extra_info", [
    ([], None), ([0, -1], None), ([1], {"arcwoc_origin": "wc_stock_push"}),
])
def test_empty_and_loop_origin_are_not_dispatched(harness, product_ids, extra_info):
    session, delivered = harness
    hook.schedule_woocommerce_stock_push_after_warehouse_post(
        session, business_id=1, warehouse_document_id=1,
        product_ids=product_ids, extra_info=extra_info,
    )
    session.commit()
    assert delivered == []


def test_failed_commit_drops_queue_before_session_reuse(harness):
    session, delivered = harness
    session.add_all([CommitMarker(id=1), CommitMarker(id=1)])
    schedule(session, 1)
    with pytest.raises(IntegrityError):
        session.commit()
    session.rollback()
    assert delivered == []
    session.add(CommitMarker(id=2))
    schedule(session, 2)
    session.commit()
    assert delivered_ids(delivered) == [2]
    assert session.get(CommitMarker, 1) is None


def test_push_failure_does_not_undo_commit_or_stop_other_payloads(harness, monkeypatch, caplog):
    session, delivered = harness

    def send(payload):
        if payload["warehouse_document_id"] == 1:
            raise RuntimeError("simulated external push failure")
        delivered.append(deepcopy(payload))

    monkeypatch.setattr(hook, "_execute_stock_push", send)
    session.add(CommitMarker(id=1))
    schedule(session, 1)
    schedule(session, 2)
    session.commit()
    assert session.get(CommitMarker, 1) is not None
    assert delivered_ids(delivered) == [2]
    assert "woocommerce_stock_push_failed" in caplog.text
