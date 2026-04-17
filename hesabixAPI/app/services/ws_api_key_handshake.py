from __future__ import annotations

import asyncio
import json

from fastapi import WebSocket, WebSocketDisconnect

DEFAULT_WS_AUTH_TIMEOUT_SEC = 15.0


class WsAuthClientDisconnected(Exception):
	"""کلاینت قبل از تکمیل احراز هویت قطع شد."""


class WsAuthTimeout(Exception):
	"""اولین پیام احراز هویت در مهلت مقرر نرسید."""


class WsAuthRejected(Exception):
	"""درخواست نامعتبر؛ از ویژگی close_code برای بستن اتصال استفاده کنید."""

	def __init__(self, close_code: int = 4400) -> None:
		self.close_code = close_code
		super().__init__(f"WebSocket auth rejected ({close_code})")


async def read_api_key_from_first_text_message(
	websocket: WebSocket,
	*,
	timeout_sec: float = DEFAULT_WS_AUTH_TIMEOUT_SEC,
) -> str:
	"""
	بلافاصله پس از `websocket.accept()` صدا بزنید.

	کلاینت باید اولین فریم متنی را بفرستد (روی TLS، نه در query):
	{"type":"auth","api_key":"..."}
	"""
	try:
		raw = await asyncio.wait_for(websocket.receive_text(), timeout=timeout_sec)
	except asyncio.TimeoutError:
		raise WsAuthTimeout from None
	except WebSocketDisconnect:
		raise WsAuthClientDisconnected from None
	except Exception as exc:
		raise WsAuthRejected(4400) from exc

	try:
		payload = json.loads(raw)
	except json.JSONDecodeError:
		raise WsAuthRejected(4400) from None

	if not isinstance(payload, dict) or payload.get("type") != "auth":
		raise WsAuthRejected(4400)

	api_key = payload.get("api_key")
	if not api_key or not isinstance(api_key, str):
		raise WsAuthRejected(4401)

	api_key = api_key.strip()
	if not api_key:
		raise WsAuthRejected(4401)

	return api_key


async def close_ws_safe(websocket: WebSocket, code: int) -> None:
	try:
		await websocket.close(code=code)
	except Exception:
		pass
