"""Task-domain realtime events over the existing notifications WebSocket.

Task mutations queue lightweight invalidation events while a SQLAlchemy
transaction is open. The events are delivered only after commit. Clients use
those events to reconcile authoritative state through the normal REST APIs.

The existing /ws/notifications connection is user-scoped. We therefore fan out
one task event to the active members of the owning business. Redis pub/sub is
used when enabled so REST mutations and WebSocket connections may live on
different API workers.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import threading
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, Optional

import redis
from redis.exceptions import RedisError
from sqlalchemy import event
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.business_permission import BusinessPermission
from adapters.db.models.task_management import Task, TaskAssignee
from adapters.db.models.user import User
from adapters.db.session import get_db_session
from app.core.auth_dependency import AuthContext
from app.core.business_membership import membership_is_active
from app.core.queue import load_redis_settings_from_configuration
from app.core.task_project_permissions import task_visibility_scope
from app.services.realtime import realtime_manager

logger = logging.getLogger(__name__)

_CHANNEL = "hesabix:task:ws_fanout"
_SESSION_KEY = "_hesabix_task_realtime_events"

_fanout_listen_thread: Optional[threading.Thread] = None
_main_loop_holder: Dict[str, Any] = {"loop": None}
_worker_sid_lock = threading.Lock()
_worker_sid: Optional[str] = None


def _process_sid() -> str:
    global _worker_sid
    if _worker_sid is None:
        with _worker_sid_lock:
            if _worker_sid is None:
                _worker_sid = f"w{os.getpid()}:{uuid.uuid4().hex[:12]}"
    return _worker_sid


def _json_safe(value: Any) -> Any:
    return json.loads(json.dumps(value, default=str))


def build_task_realtime_event(
    *,
    business_id: int,
    task_id: int,
    project_id: Optional[int],
    actor_user_id: Optional[int],
    event_type: str,
    event_data: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    data = _json_safe(event_data or {})
    previous_project_id = None
    project_change = data.get("project_id")
    if isinstance(project_change, dict):
        raw_previous = project_change.get("from")
        if raw_previous is not None:
            try:
                previous_project_id = int(raw_previous)
            except (TypeError, ValueError):
                previous_project_id = None

    previous_user_ids: list[int] = []
    if str(event_type) == "assignees_changed":
        raw_from = data.get("from")
        if isinstance(raw_from, list):
            for value in raw_from:
                try:
                    uid = int(value)
                except (TypeError, ValueError):
                    continue
                if uid > 0 and uid not in previous_user_ids:
                    previous_user_ids.append(uid)

    # Internal fields prefixed with "_" are used only for recipient resolution
    # and are removed before the WebSocket payload is sent.
    del actor_user_id
    return {
        "type": "task.realtime",
        "v": 1,
        "event_id": uuid.uuid4().hex,
        "event": str(event_type),
        "business_id": int(business_id),
        "task_id": int(task_id),
        "project_id": int(project_id) if project_id is not None else None,
        "_previous_project_id": previous_project_id,
        "_previous_user_ids": previous_user_ids,
        "emitted_at": datetime.now(timezone.utc).isoformat(),
    }


def queue_task_realtime_event(
    db: Session,
    *,
    task: Any,
    actor_user_id: Optional[int],
    event_type: str,
    event_data: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    payload = build_task_realtime_event(
        business_id=int(task.business_id),
        task_id=int(task.id),
        project_id=int(task.project_id) if task.project_id is not None else None,
        actor_user_id=actor_user_id,
        event_type=event_type,
        event_data=event_data,
    )
    db.info.setdefault(_SESSION_KEY, []).append(payload)
    return payload


def _active_business_users(db: Session, business_id: int) -> list[User]:
    business = db.get(Business, int(business_id))
    if not business or getattr(business, "deleted_at", None) is not None:
        return []

    user_ids: list[int] = [int(business.owner_id)]
    rows = (
        db.query(BusinessPermission)
        .filter(BusinessPermission.business_id == int(business_id))
        .all()
    )
    for row in rows:
        if not membership_is_active(row):
            continue
        uid = int(row.user_id)
        if uid not in user_ids:
            user_ids.append(uid)

    users = (
        db.query(User)
        .filter(User.id.in_(user_ids), User.is_active.is_(True))
        .all()
    )
    by_id = {int(user.id): user for user in users}
    return [by_id[uid] for uid in user_ids if uid in by_id]


def _public_payload(payload: dict[str, Any]) -> dict[str, Any]:
    return {
        key: payload.get(key)
        for key in (
            "type",
            "v",
            "event_id",
            "event",
            "business_id",
            "task_id",
            "project_id",
            "emitted_at",
        )
    }


def _task_recipient_ids(
    db: Session,
    payload: dict[str, Any],
) -> list[int]:
    business_id = int(payload.get("business_id") or 0)
    task_id = int(payload.get("task_id") or 0)
    if business_id <= 0 or task_id <= 0:
        return []

    task = (
        db.query(Task)
        .filter(
            Task.id == task_id,
            Task.business_id == business_id,
        )
        .first()
    )
    if task is None:
        return []

    previous_project_id = payload.get("_previous_project_id")
    try:
        previous_project_id = (
            int(previous_project_id)
            if previous_project_id is not None
            else None
        )
    except (TypeError, ValueError):
        previous_project_id = None

    previous_user_ids = {
        int(value)
        for value in (payload.get("_previous_user_ids") or [])
        if value
    }
    current_assignee_ids = {
        int(row[0])
        for row in db.query(TaskAssignee.user_id)
        .filter(
            TaskAssignee.business_id == business_id,
            TaskAssignee.task_id == task_id,
        )
        .all()
    }

    recipients: list[int] = []
    for user in _active_business_users(db, business_id):
        user_id = int(user.id)
        ctx = AuthContext(
            user=user,
            api_key_id=0,
            business_id=business_id,
            db=db,
        )
        visible_project_ids, visible_user_id = task_visibility_scope(
            ctx,
            db,
            business_id,
        )
        if visible_project_ids is None:
            recipients.append(user_id)
            continue

        current_project_id = (
            int(task.project_id) if task.project_id is not None else None
        )
        if (
            current_project_id is not None
            and current_project_id in visible_project_ids
        ):
            recipients.append(user_id)
            continue
        if (
            previous_project_id is not None
            and previous_project_id in visible_project_ids
        ):
            recipients.append(user_id)
            continue

        personal_transition = (
            current_project_id is None or previous_project_id is None
        )
        if personal_transition and visible_user_id == user_id:
            if (
                task.created_by_user_id == user_id
                or user_id in current_assignee_ids
                or user_id in previous_user_ids
            ):
                recipients.append(user_id)

    return sorted(set(recipients))


async def _deliver_local(user_ids: Iterable[int], payload: dict[str, Any]) -> None:
    for user_id in set(int(value) for value in user_ids if value):
        try:
            await realtime_manager.send_to_user(user_id, payload)
        except Exception:
            logger.debug(
                "task realtime local delivery failed user=%s event=%s",
                user_id,
                payload.get("event_id"),
                exc_info=True,
            )


def _publish_raw(envelope: dict[str, Any]) -> None:
    from app.core.cache import get_redis_client

    client = get_redis_client()
    if client is None:
        raise RedisError("no redis client")
    client.publish(
        _CHANNEL,
        json.dumps(envelope, separators=(",", ":"), default=str),
    )


async def broadcast_task_cross_worker(
    user_ids: Iterable[int],
    payload: dict[str, Any],
) -> None:
    recipients = sorted(set(int(value) for value in user_ids if value))
    if not recipients:
        return

    await _deliver_local(recipients, payload)
    if not load_redis_settings_from_configuration()[0]:
        return

    envelope = {
        "v": 1,
        "uids": recipients,
        "p": payload,
        "s": _process_sid(),
    }
    try:
        await asyncio.to_thread(_publish_raw, envelope)
    except (RedisError, OSError, TypeError, ValueError):
        logger.debug("task realtime fanout publish failed", exc_info=True)


async def _broadcast_committed_events(events: list[dict[str, Any]]) -> None:
    try:
        with get_db_session() as db:
            for payload in events:
                recipients = _task_recipient_ids(db, payload)
                if not recipients:
                    continue
                await broadcast_task_cross_worker(
                    recipients,
                    _public_payload(payload),
                )
    except Exception:
        logger.exception("task realtime committed-event broadcast failed")


def _schedule_committed_events(events: list[dict[str, Any]]) -> None:
    if not events:
        return
    safe_events = [_json_safe(item) for item in events]
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        def _runner() -> None:
            try:
                asyncio.run(_broadcast_committed_events(safe_events))
            except Exception:
                logger.debug("task realtime background runner failed", exc_info=True)

        threading.Thread(
            target=_runner,
            name="task_realtime_after_commit",
            daemon=True,
        ).start()
        return

    loop.create_task(_broadcast_committed_events(safe_events))


@event.listens_for(Session, "after_commit")
def _task_realtime_after_commit(session: Session) -> None:
    queued = list(session.info.pop(_SESSION_KEY, []) or [])
    if queued:
        _schedule_committed_events(queued)


@event.listens_for(Session, "after_rollback")
def _task_realtime_after_rollback(session: Session) -> None:
    session.info.pop(_SESSION_KEY, None)


def _set_main_loop(loop: asyncio.AbstractEventLoop) -> None:
    _main_loop_holder["loop"] = loop


def _schedule_fanout_delivery(envelope: dict[str, Any]) -> None:
    loop = _main_loop_holder.get("loop")
    if loop is None or loop.is_closed():
        return

    async def _run() -> None:
        if envelope.get("v") != 1:
            return
        if envelope.get("s") == _process_sid():
            return
        uids = envelope.get("uids")
        payload = envelope.get("p")
        if not isinstance(uids, list) or not isinstance(payload, dict):
            return
        await _deliver_local([int(value) for value in uids], payload)

    try:
        asyncio.run_coroutine_threadsafe(_run(), loop)
    except RuntimeError:
        logger.debug("task realtime fanout could not schedule on main loop")


def _fanout_listen_loop() -> None:
    redis_enabled, host, port, db_num, pwd = load_redis_settings_from_configuration()
    if not redis_enabled:
        return

    try:
        client = redis.Redis(
            host=host,
            port=int(port),
            db=int(db_num),
            password=pwd,
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=None,
            retry_on_timeout=True,
            health_check_interval=30,
        )
        client.ping()
    except Exception:
        logger.exception("task realtime fanout subscriber: redis connect failed")
        return

    pubsub = client.pubsub(ignore_subscribe_messages=True)
    try:
        pubsub.subscribe(_CHANNEL)
        logger.info("Task WS fan-out subscriber subscribed to %s", _CHANNEL)
        for msg in pubsub.listen():
            if msg is None or msg.get("type") != "message":
                continue
            raw = msg.get("data")
            if isinstance(raw, bytes):
                raw = raw.decode("utf-8", errors="replace")
            if not isinstance(raw, str) or not raw:
                continue
            try:
                envelope = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if isinstance(envelope, dict):
                _schedule_fanout_delivery(envelope)
    except RedisError:
        logger.warning("task realtime fanout redis subscriber stopped", exc_info=True)
    except Exception:
        logger.exception("task realtime fanout subscriber died")
    finally:
        try:
            pubsub.unsubscribe(_CHANNEL)
            pubsub.close()
        except Exception:
            pass
        try:
            client.close()
        except Exception:
            pass


def start_task_realtime_fanout_subscriber(
    loop: asyncio.AbstractEventLoop,
) -> None:
    global _fanout_listen_thread
    _set_main_loop(loop)

    if _fanout_listen_thread is not None and _fanout_listen_thread.is_alive():
        return

    if not load_redis_settings_from_configuration()[0]:
        logger.info(
            "Task WS: Redis disabled — task realtime events reach sockets "
            "connected to the same API worker only."
        )
        return

    def _runner() -> None:
        while True:
            _fanout_listen_loop()
            threading.Event().wait(timeout=5.0)

    thread = threading.Thread(
        target=_runner,
        name="task_ws_fanout",
        daemon=True,
    )
    thread.start()
    _fanout_listen_thread = thread
