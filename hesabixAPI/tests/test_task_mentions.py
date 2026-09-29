from types import SimpleNamespace

import pytest

from adapters.api.v1.schema_models.task_management import (
    TaskCommentCreateRequest,
    TaskCommentUpdateRequest,
)
from adapters.db.models.task_management import TaskCommentMention
from app.core.responses import ApiError
from app.services import task_management_service as task_service
from app.services import task_notification_service as notifications


def test_comment_mention_model_has_expected_foreign_keys() -> None:
    table = TaskCommentMention.__table__
    assert {fk.target_fullname for fk in table.c.comment_id.foreign_keys} == {
        "task_comments.id"
    }
    assert {fk.target_fullname for fk in table.c.task_id.foreign_keys} == {
        "tasks.id"
    }
    assert {fk.target_fullname for fk in table.c.user_id.foreign_keys} == {
        "users.id"
    }
    assert any(
        constraint.name == "uq_task_comment_mentions_comment_user"
        for constraint in table.constraints
    )


def test_comment_request_schemas_carry_explicit_mention_ids() -> None:
    created = TaskCommentCreateRequest(
        body="Please review",
        mention_user_ids=[2, 3],
    )
    updated = TaskCommentUpdateRequest(
        body="Updated",
        mention_user_ids=[4],
    )
    untouched = TaskCommentUpdateRequest(body="Body only")

    assert created.mention_user_ids == [2, 3]
    assert updated.mention_user_ids == [4]
    assert untouched.mention_user_ids is None


def test_mention_id_normalization_deduplicates_and_excludes_actor() -> None:
    result = task_service._normalize_comment_mention_ids(
        [2, 2, 1, 3, 0, -1],
        actor_user_id=1,
    )
    assert result == [2, 3]


def test_mention_id_normalization_caps_comment_mentions() -> None:
    with pytest.raises(ApiError):
        task_service._normalize_comment_mention_ids(
            list(range(2, 28)),
            actor_user_id=1,
        )


def test_task_mentioned_uses_dedicated_event_and_comment_context(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured = {}

    def _capture(db, user_ids, event_key, context, *, actor_user_id=None):
        del db
        captured.update(
            user_ids=list(user_ids),
            event_key=event_key,
            context=context,
            actor_user_id=actor_user_id,
        )
        return True

    monkeypatch.setattr(
        notifications,
        "enqueue_task_notifications",
        _capture,
    )
    task = SimpleNamespace(
        id=9,
        business_id=1,
        project_id=4,
        title="Review invoice",
    )

    assert notifications.notify_task_mentioned(
        object(),
        task,
        [7, 8],
        actor_user_id=7,
        comment_id=22,
    )

    assert captured["event_key"] == "task.mentioned"
    assert captured["user_ids"] == [7, 8]
    assert captured["actor_user_id"] == 7
    assert captured["context"]["comment_id"] == 22
    assert captured["context"]["task_id"] == 9


def test_comment_notification_excludes_explicit_mentions(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured = {}

    monkeypatch.setattr(
        notifications,
        "_recipient_ids",
        lambda _db, _task: [2, 3, 4],
    )

    def _capture(db, user_ids, event_key, context, *, actor_user_id=None):
        del db, context
        captured.update(
            user_ids=list(user_ids),
            event_key=event_key,
            actor_user_id=actor_user_id,
        )
        return True

    monkeypatch.setattr(
        notifications,
        "enqueue_task_notifications",
        _capture,
    )
    task = SimpleNamespace(
        id=10,
        business_id=1,
        project_id=None,
        title="Call customer",
    )

    notifications.notify_task_comment(
        object(),
        task,
        actor_user_id=2,
        exclude_user_ids=[3],
    )

    assert captured["event_key"] == "task.comment_added"
    assert captured["user_ids"] == [2, 4]
    assert captured["actor_user_id"] == 2
