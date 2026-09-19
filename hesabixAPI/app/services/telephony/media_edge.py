"""Media Edge — یک نود واحد برای Softphone WS + تونل Connector + کنترل‌پلن رسانه.

media_hub در حافظهٔ هر process است؛ با چند worker uvicorn، کلاینت WS و
درخواست POST تماس روی processهای متفاوت می‌افتند و SOFTPHONE_WS_REQUIRED رخ می‌دهد.

نقش‌ها:
- media_edge: تنها process مجاز برای نگه داشتن media_hub زنده (workers=1)
- api: API عمومی؛ عملیات وابسته به media_hub را رد می‌کند مگر از طریق nginx به edge برود
- auto: سازگار با dev/تست تک‌process (اجازهٔ عملیات media)
"""
from __future__ import annotations

import logging
from typing import Any, Dict, Optional

import httpx

from app.core.responses import ApiError
from app.core.settings import get_settings

LOG = logging.getLogger("hesabix.telephony.media_edge")

ROLE_API = "api"
ROLE_MEDIA_EDGE = "media_edge"
ROLE_AUTO = "auto"


def process_role() -> str:
	role = (get_settings().hesabix_process_role or ROLE_AUTO).strip().lower()
	if role in (ROLE_API, ROLE_MEDIA_EDGE, ROLE_AUTO):
		return role
	return ROLE_AUTO


def is_media_edge_process() -> bool:
	"""True وقتی این process باید media_hub را داشته باشد."""
	role = process_role()
	return role in (ROLE_MEDIA_EDGE, ROLE_AUTO)


def require_media_edge_process() -> None:
	"""برای endpointهایی که به media_hub زنده نیاز دارند."""
	if is_media_edge_process():
		return
	raise ApiError(
		"SOFTPHONE_MEDIA_EDGE_REQUIRED",
		"درخواست Softphone باید به Media Edge برسد. مسیر nginx برای /softphone و /ws/telephony را بررسی کنید.",
		http_status=503,
	)


def media_edge_internal_base() -> str:
	return (get_settings().hesabix_media_edge_url or "http://127.0.0.1:8001").rstrip("/")


def media_edge_internal_token() -> str:
	return (get_settings().hesabix_media_edge_token or "").strip()


def fetch_media_edge_snapshot(*, pbx_id: Optional[int] = None, timeout_sec: float = 1.5) -> Optional[Dict[str, Any]]:
	"""خواندن وضعیت media_hub از process لبه (برای API workers)."""
	if is_media_edge_process():
		from app.services.telephony.media_hub import media_hub

		out: Dict[str, Any] = {
			"process_role": process_role(),
			"media_hub": media_hub.health(),
			"tunnel": media_hub.tunnel_snapshot(pbx_id) if pbx_id is not None else None,
		}
		if pbx_id is not None:
			out["tunnel_online"] = media_hub.tunnel_online(pbx_id)
		return out

	url = f"{media_edge_internal_base()}/api/v1/telephony/internal/media-edge/snapshot"
	headers: Dict[str, str] = {}
	token = media_edge_internal_token()
	if token:
		headers["X-Hesabix-Media-Edge-Token"] = token
	params: Dict[str, Any] = {}
	if pbx_id is not None:
		params["pbx_id"] = int(pbx_id)
	try:
		with httpx.Client(timeout=timeout_sec) as client:
			resp = client.get(url, headers=headers, params=params)
			if resp.status_code != 200:
				LOG.warning("media edge snapshot HTTP %s", resp.status_code)
				return None
			body = resp.json()
			data = body.get("data") if isinstance(body, dict) else None
			return data if isinstance(data, dict) else None
	except Exception as e:
		LOG.warning("media edge snapshot failed: %s", e)
		return None
