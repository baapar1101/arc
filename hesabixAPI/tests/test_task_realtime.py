from types import SimpleNamespace

from app.services import task_realtime_service as realtime


def test_build_task_realtime_event_is_minimal_and_tracks_internal_transition() -> None:
    payload = realtime.build_task_realtime_event(
        business_id=11,
        task_id=22,
        project_id=33,
        actor_user_id=44,
        event_type="task_updated",
        event_data={
            "project_id": {"from": 9, "to": 33},
            "title": {"from": "A", "to": "B"},
        },
    )

    assert payload["type"] == "task.realtime"
    assert payload["v"] == 1
    assert payload["business_id"] == 11
    assert payload["task_id"] == 22
    assert payload["project_id"] == 33
    assert payload["event"] == "task_updated"
    assert payload["_previous_project_id"] == 9
    assert payload["event_id"]

    public = realtime._public_payload(payload)
    assert public["task_id"] == 22
    assert public["project_id"] == 33
    assert "actor_user_id" not in public
    assert "data" not in public
    assert "_previous_project_id" not in public


def test_assignee_change_keeps_previous_ids_for_recipient_resolution() -> None:
    payload = realtime.build_task_realtime_event(
        business_id=1,
        task_id=2,
        project_id=None,
        actor_user_id=7,
        event_type="assignees_changed",
        event_data={"from": [4, 5, 5], "to": [6]},
    )

    assert payload["_previous_user_ids"] == [4, 5]
    assert "_previous_user_ids" not in realtime._public_payload(payload)


def test_queue_waits_for_after_commit(monkeypatch) -> None:
    session = SimpleNamespace(info={})
    task = SimpleNamespace(id=22, business_id=11, project_id=33)
    scheduled = []

    monkeypatch.setattr(
        realtime,
        "_schedule_committed_events",
        lambda events: scheduled.extend(events),
    )

    payload = realtime.queue_task_realtime_event(
        session,
        task=task,
        actor_user_id=44,
        event_type="task_moved",
        event_data={"target_status_id": 7},
    )

    assert scheduled == []
    assert session.info[realtime._SESSION_KEY] == [payload]

    realtime._task_realtime_after_commit(session)

    assert scheduled == [payload]
    assert realtime._SESSION_KEY not in session.info


def test_rollback_discards_queued_realtime_events(monkeypatch) -> None:
    session = SimpleNamespace(info={})
    task = SimpleNamespace(id=9, business_id=1, project_id=None)
    scheduled = []

    monkeypatch.setattr(
        realtime,
        "_schedule_committed_events",
        lambda events: scheduled.extend(events),
    )

    realtime.queue_task_realtime_event(
        session,
        task=task,
        actor_user_id=2,
        event_type="task_updated",
        event_data={"title": {"from": "a", "to": "b"}},
    )
    realtime._task_realtime_after_rollback(session)

    assert scheduled == []
    assert realtime._SESSION_KEY not in session.info


def test_public_payload_is_invalidation_not_domain_data() -> None:
    payload = realtime.build_task_realtime_event(
        business_id=1,
        task_id=2,
        project_id=None,
        actor_user_id=99,
        event_type="comment_added",
        event_data={"comment_body": "secret", "assignee_ids": [5, 6]},
    )

    public = realtime._public_payload(payload)
    assert public["event"] == "comment_added"
    assert public["business_id"] == 1
    assert public["task_id"] == 2
    assert "comment_body" not in str(public)
    assert "assignee_ids" not in str(public)
    assert "actor_user_id" not in public
