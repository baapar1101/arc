"""تونل رسانه خروجی Connector → Hesabix Media Hub (WSS)."""
from __future__ import annotations

import json
import logging
import ssl
import threading
import time
from typing import Any, Callable, Dict, Optional
from urllib.parse import urlparse

LOG = logging.getLogger("hesabix.telephony.media_tunnel")


def _ws_url_from_api(api_base: str) -> str:
	base = api_base.rstrip("/")
	# https://x -> wss://x/ws/telephony/connector/media
	parsed = urlparse(base)
	scheme = "wss" if parsed.scheme == "https" else "ws"
	# اگر path مثل /api داشته باشد، ریشه را بگیر
	host = parsed.netloc
	return f"{scheme}://{host}/ws/telephony/connector/media"


class MediaTunnelClient:
	"""کلاینت سبک WSS بدون وابستگی خارجی (استفاده از websocket-client اگر بود، وگرنه fallback ساده)."""

	def __init__(
		self,
		api_base: str,
		business_id: int,
		pbx_id: int,
		token: str,
		on_json: Optional[Callable[[Dict[str, Any]], None]] = None,
		on_pcm: Optional[Callable[[str, bytes], None]] = None,
	) -> None:
		self.ws_url = _ws_url_from_api(api_base)
		self.business_id = business_id
		self.pbx_id = pbx_id
		self.token = token
		self.on_json = on_json
		self.on_pcm = on_pcm
		self._ws = None
		self._thread: Optional[threading.Thread] = None
		self._stop = threading.Event()
		self.tunnel_id: Optional[str] = None
		self.connected = False

	def start(self) -> None:
		if self._thread and self._thread.is_alive():
			return
		self._stop.clear()
		self._thread = threading.Thread(target=self._run, name="hesabix-media-tunnel", daemon=True)
		self._thread.start()
		self._ping_thread = threading.Thread(target=self._ping_loop, name="hesabix-media-ping", daemon=True)
		self._ping_thread.start()

	def stop(self) -> None:
		self._stop.set()
		try:
			if self._ws is not None:
				self._ws.close()
		except Exception:
			pass
		if self._thread:
			self._thread.join(timeout=3)
		ping_th = getattr(self, "_ping_thread", None)
		if ping_th:
			ping_th.join(timeout=2)

	def _ping_loop(self) -> None:
		"""Keepalive اپلیکیشنی مستقل از حلقه AMI."""
		while not self._stop.wait(15):
			if self.connected:
				self.send_json({"type": "ping", "ts": int(time.time())})

	def send_json(self, payload: Dict[str, Any]) -> bool:
		if not self._ws or not self.connected:
			return False
		try:
			self._ws.send(json.dumps(payload))
			return True
		except Exception as e:
			LOG.debug("tunnel send_json failed: %s", e)
			return False

	def send_pcm(self, session_id: str, pcm: bytes) -> bool:
		if not self._ws or not self.connected:
			return False
		try:
			sid = (session_id or "").encode("ascii")[:36].ljust(36, b" ")
			frame = b"HSXM" + bytes([2, 0]) + len(pcm).to_bytes(2, "big") + sid + pcm
			self._ws.send(frame, opcode=2)  # binary
			return True
		except Exception as e:
			LOG.debug("tunnel send_pcm failed: %s", e)
			return False

	def _run(self) -> None:
		while not self._stop.is_set():
			try:
				self._connect_once()
			except Exception as e:
				LOG.warning("media tunnel disconnected: %s", e)
			self.connected = False
			self.tunnel_id = None
			if self._stop.is_set():
				break
			time.sleep(3)

	def _connect_once(self) -> None:
		try:
			from websocket import WebSocketApp  # type: ignore
		except ImportError:
			LOG.error(
				"بسته websocket-client نصب نیست. روی سرور PBX اجرا کنید: pip install websocket-client"
			)
			time.sleep(10)
			return

		auth_sent = {"ok": False}

		def on_open(ws):
			ws.send(
				json.dumps(
					{
						"type": "auth",
						"connector_token": self.token,
						"business_id": self.business_id,
						"pbx_id": self.pbx_id,
						"capabilities": ["audiosocket", "pcm_ws_v1"],
					}
				)
			)
			auth_sent["ok"] = True

		def on_message(ws, message):
			if isinstance(message, bytes):
				if len(message) >= 44 and message[:4] == b"HSXM":
					pcm_len = int.from_bytes(message[6:8], "big")
					session_id = message[8:44].decode("ascii", errors="ignore").strip()
					pcm = message[44 : 44 + pcm_len]
					if self.on_pcm and session_id:
						self.on_pcm(session_id, pcm)
				return
			try:
				payload = json.loads(message)
			except Exception:
				return
			if payload.get("type") == "auth_ok":
				self.connected = True
				self.tunnel_id = payload.get("tunnel_id")
				LOG.info("media tunnel auth_ok tunnel_id=%s", self.tunnel_id)
			if self.on_json:
				self.on_json(payload)

		def on_error(ws, error):
			LOG.warning("media tunnel error: %s", error)

		def on_close(ws, status, msg):
			self.connected = False
			LOG.info("media tunnel closed status=%s", status)

		sslopt = {"cert_reqs": ssl.CERT_REQUIRED}
		# در محیط‌های با گواهی داخلی می‌توان HESABIX_MEDIA_INSECURE_SSL=1 گذاشت
		import os

		if os.environ.get("HESABIX_MEDIA_INSECURE_SSL") == "1":
			sslopt = {"cert_reqs": ssl.CERT_NONE}

		ws = WebSocketApp(
			self.ws_url,
			on_open=on_open,
			on_message=on_message,
			on_error=on_error,
			on_close=on_close,
		)
		self._ws = ws
		# ping برای keepalive
		ws.run_forever(sslopt=sslopt, ping_interval=20, ping_timeout=10)
