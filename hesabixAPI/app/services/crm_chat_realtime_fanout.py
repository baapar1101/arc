# noqa: D100
"""
Pub/Sub روی Redis برای پخش پیام وب‌سوکت چت CRM بین چند worker (uvicorn -w).

بدون این لایه، اتاق مکالمه فقط در حافظهٔ همان فرایند است؛ عامل در worker A پیام می‌فرستد
ولی بازدیدکننده روی worker B اتصال دارد → تایپ/ورود عامل هرگز به ویجیت نمی‌رسد،
در حالی که «اکو»ٔ تایپ بازدیدکننده ممکن است روی همان worker به خودش برگردد.
"""
from __future__ import annotations

import asyncio
import json
import logging
import threading
from typing import Any, Dict, Optional

import redis
from redis.exceptions import RedisError

from app.core.queue import load_redis_settings_from_configuration

logger = logging.getLogger(__name__)

CHANNEL = "hesabix:crm_chat:ws_fanout"

_fanout_listen_thread: Optional[threading.Thread] = None
_main_loop_holder: Dict[str, Any] = {"loop": None}


def _set_main_loop(loop: asyncio.AbstractEventLoop) -> None:
	_main_loop_holder["loop"] = loop


def _publish_raw(envelope: Dict[str, Any]) -> None:
	from app.core.cache import get_redis_client

	client = get_redis_client()
	if client is None:
		raise RedisError("no redis client")
	raw = json.dumps(envelope, separators=(",", ":"), default=str)
	client.publish(CHANNEL, raw)


async def _fanout_publish(conversation_id: Optional[int], business_id: Optional[int], payload: Dict[str, Any]) -> bool:
	"""در صورت موفقیت پیام را فقط از طریق Redis می‌فرستیم (subscriberها به سوکت‌ها می‌رسانند)."""
	if conversation_id is not None:
		env = {"v": 1, "t": "c", "id": int(conversation_id), "p": payload}
	elif business_id is not None:
		env = {"v": 1, "t": "b", "id": int(business_id), "p": payload}
	else:
		return False
	try:
		await asyncio.to_thread(_publish_raw, env)
		return True
	except (RedisError, OSError, TypeError, ValueError):
		logger.debug("crm chat fanout publish failed", exc_info=True)
		return False


async def broadcast_conversation_cross_worker(conversation_id: int, payload: Dict[str, Any]) -> None:
	ok = await _fanout_publish(conversation_id, None, payload)
	if not ok:
		from app.services.crm_chat_realtime import crm_chat_realtime_manager

		await crm_chat_realtime_manager.deliver_conversation(conversation_id, payload)


async def broadcast_business_cross_worker(business_id: int, payload: Dict[str, Any]) -> None:
	ok = await _fanout_publish(None, business_id, payload)
	if not ok:
		from app.services.crm_chat_realtime import crm_chat_realtime_manager

		await crm_chat_realtime_manager.deliver_business(business_id, payload)


def _schedule_deliver(envelope: Dict[str, Any]) -> None:
	loop = _main_loop_holder.get("loop")
	if loop is None or loop.is_closed():
		return

	async def _run() -> None:
		from app.services.crm_chat_realtime import crm_chat_realtime_manager

		if envelope.get("v") != 1:
			return
		t = envelope.get("t")
		eid = envelope.get("id")
		pl = envelope.get("p")
		if not isinstance(pl, dict) or eid is None:
			return
		try:
			if t == "c":
				await crm_chat_realtime_manager.deliver_conversation(int(eid), pl)
			elif t == "b":
				await crm_chat_realtime_manager.deliver_business(int(eid), pl)
		except Exception:
			logger.debug("crm chat fanout local deliver failed", exc_info=True)

	try:
		asyncio.run_coroutine_threadsafe(_run(), loop)
	except RuntimeError:
		logger.debug("crm chat fanout could not schedule on main loop")


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
		logger.exception("crm chat fanout subscriber: redis connect failed")
		return

	pubsub = r.pubsub(ignore_subscribe_messages=True)
	try:
		pubsub.subscribe(CHANNEL)
		logger.info("CRM chat WS fan-out subscriber subscribed to %s", CHANNEL)
	except Exception:
		logger.exception("crm chat fanout subscribe failed")
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
			if msg is None:
				continue
			if msg.get("type") != "message":
				continue
			raw = msg.get("data")
			if isinstance(raw, bytes):
				raw = raw.decode("utf-8", errors="replace")
			if not raw or not isinstance(raw, str):
				continue
			try:
				envelope = json.loads(raw)
			except json.JSONDecodeError:
				logger.debug("crm chat fanout bad json: %s", raw[:200])
				continue
			if not isinstance(envelope, dict):
				continue
			_schedule_deliver(envelope)
	except RedisError:
		logger.warning("crm chat fanout subscriber redis stopped", exc_info=True)
	except Exception:
		logger.exception("crm chat fanout subscriber died")
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


def start_crm_chat_fanout_subscriber(loop: asyncio.AbstractEventLoop) -> None:
	global _fanout_listen_thread
	_set_main_loop(loop)

	if _fanout_listen_thread is not None and _fanout_listen_thread.is_alive():
		return

	if not load_redis_settings_from_configuration()[0]:
		logger.info(
			"CRM chat WS fan-out: Redis غیرفعال؛ با چند worker ممکن است رویدادهای زنده بین فرایندها نرسند."
		)
		return

	def _runner() -> None:
		while True:
			_fanout_listen_loop()
			# قطع شبکهٔ موقت: قبل از قطع نامحدود یک ثانیه صبر کن
			try:
				threading.Event().wait(timeout=5.0)
			except KeyboardInterrupt:
				break

	thread = threading.Thread(target=_runner, name="crm_chat_ws_fanout", daemon=True)
	thread.start()
	_fanout_listen_thread = thread
