from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from zoneinfo import ZoneInfo

import pytest

import app.services.task_management_service as service
from adapters.db.models.task_management import (
    Task,
    TaskActivity,
    TaskAssignee,
    TaskLabelLink,
    TaskReminder,
)
from app.core.responses import ApiError


def _task(
    *,
    start_at: datetime | None = None,
    due_at: datetime | None = None,
    timezone_name: str = "UTC",
    rule: str = "FREQ=DAILY",
    end_at: datetime | None = None,
) -> Task:
    return Task(
        id=10,
        business_id=1,
        status_id=1,
        title="Recurring task",
        priority="normal",
        start_at=start_at,
        due_at=due_at,
        recurrence_rule=rule,
        recurrence_timezone=timezone_name,
        recurrence_end_at=end_at,
    )


@pytest.mark.parametrize(
    ("timezone_name", "anchor_utc", "expected_next_utc"),
    [
        (
            "Europe/London",
            datetime(2026, 3, 28, 9, 0, tzinfo=timezone.utc),
            datetime(2026, 3, 29, 8, 0, tzinfo=timezone.utc),
        ),
        (
            "Europe/London",
            datetime(2026, 10, 24, 8, 0, tzinfo=timezone.utc),
            datetime(2026, 10, 25, 9, 0, tzinfo=timezone.utc),
        ),
        (
            "America/New_York",
            datetime(2026, 3, 7, 14, 0, tzinfo=timezone.utc),
            datetime(2026, 3, 8, 13, 0, tzinfo=timezone.utc),
        ),
        (
            "America/New_York",
            datetime(2026, 10, 31, 13, 0, tzinfo=timezone.utc),
            datetime(2026, 11, 1, 14, 0, tzinfo=timezone.utc),
        ),
    ],
)
def test_daily_recurrence_preserves_local_clock_across_dst(
    timezone_name: str,
    anchor_utc: datetime,
    expected_next_utc: datetime,
) -> None:
    task = _task(due_at=anchor_utc, timezone_name=timezone_name)

    next_start, next_due = service._next_recurrence_dates(task)

    assert next_start is None
    assert next_due == expected_next_utc
    assert next_due.astimezone(ZoneInfo(timezone_name)).hour == 9


def test_start_and_due_duration_is_preserved_across_dst() -> None:
    task = _task(
        start_at=datetime(2026, 3, 28, 8, 0, tzinfo=timezone.utc),
        due_at=datetime(2026, 3, 28, 9, 0, tzinfo=timezone.utc),
        timezone_name="Europe/London",
    )

    next_start, next_due = service._next_recurrence_dates(task)

    assert next_start == datetime(2026, 3, 29, 7, 0, tzinfo=timezone.utc)
    assert next_due == datetime(2026, 3, 29, 8, 0, tzinfo=timezone.utc)
    assert next_due - next_start == timedelta(hours=1)
    london = ZoneInfo("Europe/London")
    assert next_start.astimezone(london).hour == 8
    assert next_due.astimezone(london).hour == 9


def test_recurrence_end_at_is_inclusive() -> None:
    task = _task(
        due_at=datetime(2026, 3, 28, 9, 0, tzinfo=timezone.utc),
        timezone_name="Europe/London",
        end_at=datetime(2026, 3, 29, 8, 0, tzinfo=timezone.utc),
    )
    assert service._next_recurrence_dates(task)[1] == task.recurrence_end_at

    task.recurrence_end_at = datetime(
        2026,
        3,
        29,
        7,
        59,
        59,
        tzinfo=timezone.utc,
    )
    assert service._next_recurrence_dates(task) == (None, None)


def test_normalize_recurrence_uses_business_timezone(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        service,
        "resolve_display_timezone_name",
        lambda _business_id: "Europe/London",
    )

    rule, timezone_name, end_at = service._normalize_recurrence(
        1,
        "RRULE:FREQ=WEEKLY;BYDAY=MO,WE",
        None,
        None,
    )

    assert rule == "FREQ=WEEKLY;BYDAY=MO,WE"
    assert timezone_name == "Europe/London"
    assert end_at is None


@pytest.mark.parametrize(
    "rule",
    [
        "BYDAY=MO",
        "FREQ=DAILY;COUNT=3",
        "FREQ=DAILY;UNTIL=20261231T000000Z",
        "FREQ=NOT_A_FREQUENCY",
    ],
)
def test_invalid_or_noncanonical_rrules_are_rejected(rule: str) -> None:
    with pytest.raises(ApiError):
        service._normalize_recurrence(1, rule, "UTC", None)


def test_invalid_recurrence_timezone_is_rejected() -> None:
    with pytest.raises(ApiError):
        service._normalize_recurrence(
            1,
            "FREQ=DAILY",
            "Mars/Olympus_Mons",
            None,
        )


class _ReminderQuery:
    def __init__(self, reminders: list[TaskReminder]) -> None:
        self.reminders = reminders

    def filter(self, *_args):
        return self

    def all(self) -> list[TaskReminder]:
        return self.reminders


class _ReminderDb:
    def __init__(self, reminders: list[TaskReminder]) -> None:
        self.reminders = reminders
        self.deleted: list[TaskReminder] = []

    def query(self, model):
        assert model is TaskReminder
        return _ReminderQuery(self.reminders)

    def delete(self, reminder: TaskReminder) -> None:
        self.deleted.append(reminder)


def test_relative_reminders_follow_rescheduled_task_dates() -> None:
    due_reminder = TaskReminder(
        id=1,
        business_id=1,
        task_id=10,
        user_id=7,
        remind_at=datetime(2026, 4, 1, tzinfo=timezone.utc),
        relative_to="due",
        offset_minutes=60,
    )
    start_reminder = TaskReminder(
        id=2,
        business_id=1,
        task_id=10,
        user_id=7,
        remind_at=datetime(2026, 4, 1, tzinfo=timezone.utc),
        relative_to="start",
        offset_minutes=30,
    )
    db = _ReminderDb([due_reminder, start_reminder])
    task = _task(
        start_at=datetime(2026, 4, 10, 8, 0, tzinfo=timezone.utc),
        due_at=datetime(2026, 4, 10, 10, 0, tzinfo=timezone.utc),
    )

    service._sync_relative_reminders(db, task)

    assert start_reminder.remind_at == datetime(
        2026,
        4,
        10,
        7,
        30,
        tzinfo=timezone.utc,
    )
    assert due_reminder.remind_at == datetime(
        2026,
        4,
        10,
        9,
        0,
        tzinfo=timezone.utc,
    )
    assert db.deleted == []


def test_relative_reminder_is_removed_when_anchor_date_is_removed() -> None:
    reminder = TaskReminder(
        id=3,
        business_id=1,
        task_id=10,
        user_id=7,
        remind_at=datetime(2026, 4, 1, tzinfo=timezone.utc),
        relative_to="start",
        offset_minutes=15,
    )
    db = _ReminderDb([reminder])
    task = _task(start_at=None, due_at=None)

    service._sync_relative_reminders(db, task)

    assert db.deleted == [reminder]


class _FakeQuery:
    def __init__(self, db: "_FakeDb", model) -> None:
        self.db = db
        self.model = model

    def filter(self, *_args):
        return self

    def order_by(self, *_args):
        return self

    def first(self):
        if self.model is TaskActivity:
            return self.db.recurrence_events[-1] if self.db.recurrence_events else None
        return None

    def all(self):
        if self.model in {TaskAssignee, TaskLabelLink}:
            return []
        return []


class _FakeDb:
    def __init__(self) -> None:
        self.tasks: dict[int, Task] = {}
        self.recurrence_events: list[SimpleNamespace] = []
        self.next_id = 500

    def query(self, model):
        return _FakeQuery(self, model)

    def add(self, obj) -> None:
        if isinstance(obj, Task):
            if obj.id is None:
                obj.id = self.next_id
                self.next_id += 1
            self.tasks[int(obj.id)] = obj

    def flush(self) -> None:
        return None


class _FakeTaskRepository:
    def __init__(self, db: _FakeDb) -> None:
        self.db = db

    def next_sort_order(self, _business_id: int, _project_id: int | None) -> int:
        return 1000

    def get_by_id(self, task_id: int, _business_id: int) -> Task | None:
        return self.db.tasks.get(task_id)


def test_next_recurring_task_creation_is_idempotent(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    db = _FakeDb()
    source = _task(
        due_at=datetime(2026, 5, 1, 9, 0, tzinfo=timezone.utc),
        timezone_name="UTC",
    )
    source.completed_at = datetime(2026, 5, 1, 10, 0, tzinfo=timezone.utc)

    monkeypatch.setattr(service, "TaskRepository", _FakeTaskRepository)
    monkeypatch.setattr(
        service,
        "_default_status",
        lambda _db, _business_id: SimpleNamespace(id=7),
    )

    def _record_activity(
        _db,
        *,
        task,
        actor_user_id,
        event_type,
        event_data=None,
    ) -> None:
        del task, actor_user_id
        if event_type == "recurrence_next_created":
            db.recurrence_events.append(
                SimpleNamespace(
                    event_type=event_type,
                    event_data=event_data or {},
                )
            )

    monkeypatch.setattr(service, "_record_activity", _record_activity)

    first = service._ensure_next_recurring_task(db, source, actor_user_id=99)
    second = service._ensure_next_recurring_task(db, source, actor_user_id=99)

    assert first is not None
    assert second is first
    assert first.id == 500
    assert len(db.tasks) == 1
    assert len(db.recurrence_events) == 1
    assert db.recurrence_events[0].event_data["next_task_id"] == first.id
