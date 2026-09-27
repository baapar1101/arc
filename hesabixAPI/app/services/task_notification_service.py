"""Task/project notification adapter.

Task mutations enqueue RQ jobs when Redis is available. If Redis is disabled,
the request path falls back to in-app delivery only so external providers never
block task CRUD.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable, Optional

from sqlalchemy.orm import Session

from adapters.db.models.task_management import (
    Task,
    TaskActivity,
    TaskAssignee,
    TaskRelation,
    TaskReminder,
    TaskStatus,
)
from adapters.db.session import get_db_session
from app.core.queue import QUEUE_DEFAULT, get_queue_service
from app.services.notification_service import NotificationService

logger = logging.getLogger(__name__)
_TASK_CHANNELS = ("inapp", "email")


def _task_deep_link(task: Task) -> str:
    if task.project_id:
        return f"/business/{task.business_id}/tasks?project_id={task.project_id}"
    return f"/business/{task.business_id}/tasks"


def _task_context(
    task: Task,
    *,
    subject: str,
    message: str,
    **extra: Any,
) -> dict[str, Any]:
    deep_link = _task_deep_link(task)
    return {
        "subject": subject,
        "message": message,
        "business_id": task.business_id,
        "task_id": task.id,
        "task_title": task.title,
        "project_id": task.project_id,
        "deep_link": deep_link,
        "action_url": deep_link,
        **extra,
    }


def _recipient_ids(db: Session, task: Task) -> list[int]:
    ids = {
        int(row[0])
        for row in db.query(TaskAssignee.user_id).filter(
            TaskAssignee.business_id == task.business_id,
            TaskAssignee.task_id == task.id,
        ).all()
        if row[0]
    }
    if task.created_by_user_id:
        ids.add(int(task.created_by_user_id))
    return sorted(ids)


def deliver_task_notification_job(
    user_id: int,
    event_key: str,
    context: dict[str, Any],
    channels: Optional[list[str]] = None,
) -> bool:
    """RQ worker entry point."""
    with get_db_session() as db:
        return NotificationService(db).send(
            user_id=int(user_id),
            event_key=str(event_key),
            context=dict(context),
            preferred_channels=list(channels or _TASK_CHANNELS),
            broadcast_mode=True,
        )


def enqueue_task_notifications(
    db: Session,
    user_ids: Iterable[int],
    event_key: str,
    context: dict[str, Any],
    *,
    actor_user_id: Optional[int] = None,
) -> bool:
    recipients = sorted({
        int(value)
        for value in user_ids
        if value and (actor_user_id is None or int(value) != int(actor_user_id))
    })
    if not recipients:
        return False

    queue_service = get_queue_service()
    dispatched = False
    for user_id in recipients:
        queued = None
        if queue_service and queue_service.enabled:
            queued = queue_service.enqueue(
                deliver_task_notification_job,
                user_id,
                event_key,
                dict(context),
                list(_TASK_CHANNELS),
                queue_name=QUEUE_DEFAULT,
                timeout=120,
                result_ttl=3600,
            )
        if queued is not None:
            dispatched = True
            continue

        try:
            ok = NotificationService(db).send(
                user_id=user_id,
                event_key=event_key,
                context=dict(context),
                preferred_channels=["inapp"],
                broadcast_mode=False,
            )
            dispatched = bool(ok) or dispatched
        except Exception:
            logger.exception(
                "task notification fallback failed event=%s user=%s",
                event_key,
                user_id,
            )
    return dispatched


def notify_task_assigned(
    db: Session,
    task: Task,
    user_ids: Iterable[int],
    actor_user_id: Optional[int],
) -> bool:
    return enqueue_task_notifications(
        db,
        user_ids,
        "task.assigned",
        _task_context(
            task,
            subject="کار جدید به شما واگذار شد",
            message=f"کار «{task.title}» به شما واگذار شد.",
        ),
        actor_user_id=actor_user_id,
    )


def notify_task_comment(
    db: Session,
    task: Task,
    actor_user_id: int,
) -> bool:
    return enqueue_task_notifications(
        db,
        _recipient_ids(db, task),
        "task.comment_added",
        _task_context(
            task,
            subject="نظر جدید روی کار",
            message=f"یک نظر جدید روی «{task.title}» ثبت شد.",
        ),
        actor_user_id=actor_user_id,
    )


def notify_dependency_resolved(
    db: Session,
    completed_task: Task,
    actor_user_id: Optional[int],
) -> bool:
    relations = db.query(TaskRelation).filter(
        TaskRelation.business_id == completed_task.business_id,
        TaskRelation.task_id == completed_task.id,
        TaskRelation.relation_type == "blocks",
    ).all()
    dispatched = False
    for relation in relations:
        target = db.query(Task).filter(
            Task.id == relation.related_task_id,
            Task.business_id == completed_task.business_id,
            Task.deleted_at.is_(None),
        ).first()
        if not target or target.completed_at is not None:
            continue
        ok = enqueue_task_notifications(
            db,
            _recipient_ids(db, target),
            "task.dependency_resolved",
            _task_context(
                target,
                subject="وابستگی کار برطرف شد",
                message=(
                    f"کار مسدودکننده «{completed_task.title}» تکمیل شد؛ "
                    f"«{target.title}» می‌تواند ادامه پیدا کند."
                ),
                resolved_by_task_id=completed_task.id,
            ),
            actor_user_id=actor_user_id,
        )
        dispatched = ok or dispatched
    return dispatched


def notify_project_member_added(
    db: Session,
    *,
    business_id: int,
    project_id: int,
    project_name: str,
    user_id: int,
    actor_user_id: Optional[int],
) -> bool:
    if actor_user_id is not None and int(actor_user_id) == int(user_id):
        return False
    deep_link = f"/business/{business_id}/projects/{project_id}"
    return enqueue_task_notifications(
        db,
        [user_id],
        "task.project_member_added",
        {
            "subject": "عضویت در پروژه",
            "message": f"شما به پروژه «{project_name}» اضافه شدید.",
            "business_id": business_id,
            "project_id": project_id,
            "deep_link": deep_link,
            "action_url": deep_link,
        },
        actor_user_id=actor_user_id,
    )


def _has_marker(
    db: Session,
    task_id: int,
    business_id: int,
    event_type: str,
) -> bool:
    return db.query(TaskActivity.id).filter(
        TaskActivity.business_id == business_id,
        TaskActivity.task_id == task_id,
        TaskActivity.event_type == event_type,
    ).first() is not None


def _add_marker(
    db: Session,
    task: Task,
    event_type: str,
    event_data: Optional[dict[str, Any]] = None,
) -> None:
    db.add(TaskActivity(
        business_id=task.business_id,
        task_id=task.id,
        actor_user_id=None,
        event_type=event_type,
        event_data=event_data or {},
    ))


def process_task_notification_scan(
    db: Session,
    *,
    now: Optional[datetime] = None,
    limit: int = 200,
) -> dict[str, int]:
    now_utc = now or datetime.now(timezone.utc)
    if now_utc.tzinfo is None:
        now_utc = now_utc.replace(tzinfo=timezone.utc)
    due_soon_end = now_utc + timedelta(hours=24)
    counts = {"reminders": 0, "due_soon": 0, "overdue": 0}

    reminders = (
        db.query(TaskReminder)
        .filter(
            TaskReminder.sent_at.is_(None),
            TaskReminder.remind_at <= now_utc,
        )
        .order_by(TaskReminder.remind_at.asc(), TaskReminder.id.asc())
        .limit(max(1, min(int(limit), 500)))
        .all()
    )
    for reminder in reminders:
        task = db.query(Task).filter(
            Task.id == reminder.task_id,
            Task.business_id == reminder.business_id,
            Task.deleted_at.is_(None),
        ).first()
        if not task or task.completed_at is not None:
            reminder.sent_at = now_utc
            continue
        recipients = (
            [int(reminder.user_id)]
            if reminder.user_id
            else _recipient_ids(db, task)
        )
        dispatched = enqueue_task_notifications(
            db,
            recipients,
            "task.reminder",
            _task_context(
                task,
                subject="یادآور کار",
                message=f"یادآور برای «{task.title}».",
                reminder_id=reminder.id,
                remind_at=reminder.remind_at.isoformat(),
            ),
        )
        if dispatched:
            reminder.sent_at = now_utc
            _add_marker(
                db,
                task,
                "notification_reminder_dispatched",
                {"reminder_id": reminder.id},
            )
            counts["reminders"] += 1

    active_tasks = (
        db.query(Task)
        .outerjoin(TaskStatus, Task.status_id == TaskStatus.id)
        .filter(
            Task.deleted_at.is_(None),
            Task.completed_at.is_(None),
            Task.due_at.is_not(None),
            TaskStatus.category != "cancelled",
        )
        .order_by(Task.due_at.asc())
        .limit(max(1, min(int(limit), 500)))
        .all()
    )
    for task in active_tasks:
        due = task.due_at
        if due is None:
            continue
        if due.tzinfo is None:
            due = due.replace(tzinfo=timezone.utc)

        if now_utc <= due <= due_soon_end:
            marker = "notification_due_soon_dispatched"
            if not _has_marker(db, task.id, task.business_id, marker):
                dispatched = enqueue_task_notifications(
                    db,
                    _recipient_ids(db, task),
                    "task.due_soon",
                    _task_context(
                        task,
                        subject="سررسید کار نزدیک است",
                        message=f"کمتر از ۲۴ ساعت تا سررسید «{task.title}» باقی مانده است.",
                        due_at=due.isoformat(),
                    ),
                )
                if dispatched:
                    _add_marker(db, task, marker, {"due_at": due.isoformat()})
                    counts["due_soon"] += 1

        elif due < now_utc:
            marker = "notification_overdue_dispatched"
            if not _has_marker(db, task.id, task.business_id, marker):
                dispatched = enqueue_task_notifications(
                    db,
                    _recipient_ids(db, task),
                    "task.overdue",
                    _task_context(
                        task,
                        subject="کار از سررسید گذشته است",
                        message=f"سررسید «{task.title}» گذشته است.",
                        due_at=due.isoformat(),
                    ),
                )
                if dispatched:
                    _add_marker(db, task, marker, {"due_at": due.isoformat()})
                    counts["overdue"] += 1

    db.commit()
    return counts


async def task_notification_background_loop(interval_seconds: int = 300) -> None:
    def _scan() -> None:
        with get_db_session() as db:
            result = process_task_notification_scan(db)
            if any(result.values()):
                logger.info("task notification scan: %s", result)

    while True:
        try:
            await asyncio.to_thread(_scan)
        except Exception:
            logger.exception("task notification background scan failed")
        await asyncio.sleep(max(60, int(interval_seconds)))
