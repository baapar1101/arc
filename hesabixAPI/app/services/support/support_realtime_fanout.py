"""Redis pub/sub fan-out for support ticket WebSocket events across workers."""

from __future__ import annotations

import asyncio
import json
import logging
import os
import threading
import uuid
from typing import Any, Dict, List, Optional

import redis
from redis.exceptions import RedisError

from app.core.queue import load_redis_settings_from_configuration

logger = logging.getLogger(__name__)

CHANNEL = "hesabix:support:ws_fanout"

_fanout_listen_thread: Optional[threading.Thread] = None
_main_loop_holder: Dict[str, Any] = {"loop": None}
_fanout_worker_sid_lock = threading.Lock()
_fanout_worker_sid: Optional[str] = None


def _fanout_process_sid() -> str:
    global _fanout_worker_sid
    if _fanout_worker_sid is None:
        with _fanout_worker_sid_lock:
            if _fanout_worker_sid is None:
                _fanout_worker_sid = f"w{os.getpid()}:{uuid.uuid4().hex[:12]}"
    return _fanout_worker_sid


def _set_main_loop(loop: asyncio.AbstractEventLoop) -> None:
    _main_loop_holder["loop"] = loop


def _publish_raw(envelope: Dict[str, Any]) -> None:
    from app.core.cache import get_redis_client

    client = get_redis_client()
    if client is None:
        raise RedisError("no redis client")
    raw = json.dumps(envelope, separators=(",", ":"), default=str)
    client.publish(CHANNEL, raw)


async def broadcast_support_cross_worker(
    recipient_user_ids: List[int],
    ticket_id: Optional[int],
    payload: Dict[str, Any],
) -> None:
    from app.services.support.support_realtime import support_realtime_manager

    await support_realtime_manager.deliver_support_event(recipient_user_ids, ticket_id, payload)
    if not load_redis_settings_from_configuration()[0]:
        return
    env = {
        "v": 1,
        "uids": [int(u) for u in recipient_user_ids],
        "ticket_id": ticket_id,
        "p": payload,
        "s": _fanout_process_sid(),
    }
    try:
        await asyncio.to_thread(_publish_raw, env)
    except (RedisError, OSError, TypeError, ValueError):
        logger.debug("support fanout publish failed", exc_info=True)


def _schedule_deliver(envelope: Dict[str, Any]) -> None:
    loop = _main_loop_holder.get("loop")
    if loop is None or loop.is_closed():
        return

    async def _run() -> None:
        from app.services.support.support_realtime import support_realtime_manager

        if envelope.get("v") != 1:
            return
        sender_sid = envelope.get("s")
        if isinstance(sender_sid, str) and sender_sid and sender_sid == _fanout_process_sid():
            return
        uids = envelope.get("uids")
        ticket_id = envelope.get("ticket_id")
        pl = envelope.get("p")
        if not isinstance(pl, dict) or not isinstance(uids, list):
            return
        try:
            tid = int(ticket_id) if ticket_id is not None else None
            await support_realtime_manager.deliver_support_event([int(u) for u in uids], tid, pl)
        except Exception:
            logger.debug("support fanout local deliver failed", exc_info=True)

    try:
        asyncio.run_coroutine_threadsafe(_run(), loop)
    except RuntimeError:
        logger.debug("support fanout could not schedule on main loop")


def _fanout_listen_loop() -> None:
    redis_enabled, host, port, db_num, pwd = load_redis_settings_from_configuration()
    if not redis_enabled:
        return
    try:
        r = redis.Redis(
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
        r.ping()
    except Exception:
        logger.exception("support fanout subscriber: redis connect failed")
        return

    pubsub = r.pubsub(ignore_subscribe_messages=True)
    try:
        pubsub.subscribe(CHANNEL)
        logger.info("Support WS fan-out subscriber subscribed to %s", CHANNEL)
    except Exception:
        logger.exception("support fanout subscribe failed")
        try:
            pubsub.close()
        except Exception:
            pass
        try:
            r.close()
        except Exception:
            pass
        return

    try:
        for msg in pubsub.listen():
            if msg is None or msg.get("type") != "message":
                continue
            raw = msg.get("data")
            if isinstance(raw, bytes):
                raw = raw.decode("utf-8", errors="replace")
            if not raw or not isinstance(raw, str):
                continue
            try:
                envelope = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if isinstance(envelope, dict):
                _schedule_deliver(envelope)
    except RedisError:
        logger.warning("support fanout subscriber redis stopped", exc_info=True)
    except Exception:
        logger.exception("support fanout subscriber died")
    finally:
        try:
            pubsub.unsubscribe(CHANNEL)
            pubsub.close()
        except Exception:
            pass
        try:
            r.close()
        except Exception:
            pass


def start_support_fanout_subscriber(loop: asyncio.AbstractEventLoop) -> None:
    global _fanout_listen_thread
    _set_main_loop(loop)

    if _fanout_listen_thread is not None and _fanout_listen_thread.is_alive():
        return

    if not load_redis_settings_from_configuration()[0]:
        logger.info(
            "Support WS: Redis disabled — realtime events only reach sockets on the same API worker."
        )
        return

    def _runner() -> None:
        while True:
            _fanout_listen_loop()
            try:
                threading.Event().wait(timeout=5.0)
            except KeyboardInterrupt:
                break

    thread = threading.Thread(target=_runner, name="support_ws_fanout", daemon=True)
    thread.start()
    _fanout_listen_thread = thread
