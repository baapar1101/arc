#!/usr/bin/env python3
"""
Hesabix Telephony Connector — عامل سمت Issabel/Asterisk

رویدادهای AMI را به Hesabix می‌فرستد، دستورات Originate/Softphone را اجرا می‌کند،
و تونل رسانه خروجی (Softphone Relay) را نگه می‌دارد.
نصب: روی سرور تلفن مشتری (نه روی سرور حسابیکس).

پیکربندی از متغیر محیطی یا فایل .env:
  HESABIX_API_URL=https://api.example.com
  HESABIX_BUSINESS_ID=12
  HESABIX_PBX_ID=3
  HESABIX_CONNECTOR_TOKEN=hsx_tel_...
  AMI_HOST=127.0.0.1
  AMI_PORT=5038
  AMI_USER=hesabix
  AMI_SECRET=secret
  AUDIOSOCKET_HOST=127.0.0.1
  AUDIOSOCKET_PORT=9092
  MEDIA_TUNNEL_ENABLED=1
"""
from __future__ import annotations

import json
import logging
import os
import socket
import threading
import time
import uuid
from typing import Any, Dict, Optional
from urllib import error, request

LOG = logging.getLogger("hesabix.telephony.connector")

try:
	from media_audiosocket import AudioSocketServer
	from media_tunnel import MediaTunnelClient
except ImportError:
	# وقتی به‌صورت پکیج از parent اجرا شود
	from app.media_audiosocket import AudioSocketServer  # type: ignore
	from app.media_tunnel import MediaTunnelClient  # type: ignore


def load_dotenv(path: str) -> None:
	"""بارگذاری ساده .env بدون وابستگی خارجی (برای وقتی EnvironmentFile اعمال نشده)."""
	if not os.path.isfile(path):
		return
	try:
		with open(path, "r", encoding="utf-8") as f:
			for raw in f:
				line = raw.strip()
				if not line or line.startswith("#") or "=" not in line:
					continue
				key, _, val = line.partition("=")
				key = key.strip()
				val = val.strip().strip("'").strip('"')
				if key and key not in os.environ:
					os.environ[key] = val
	except Exception as e:
		LOG.warning("could not read .env (%s): %s", path, e)


def env(key: str, default: Optional[str] = None) -> str:
	v = os.environ.get(key, default)
	if v is None or v == "":
		raise RuntimeError(f"Missing env: {key}")
	return v


class HesabixClient:
	def __init__(self, base_url: str, business_id: int, pbx_id: int, token: str) -> None:
		self.base = base_url.rstrip("/")
		self.business_id = business_id
		self.pbx_id = pbx_id
		self.token = token

	def _headers(self) -> Dict[str, str]:
		return {
			"Authorization": f"Bearer {self.token}",
			"Content-Type": "application/json",
			"X-Hesabix-Business-Id": str(self.business_id),
			"X-Hesabix-Pbx-Id": str(self.pbx_id),
		}

	def _post(self, path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
		req = request.Request(
			f"{self.base}{path}",
			data=json.dumps(payload).encode("utf-8"),
			headers=self._headers(),
			method="POST",
		)
		with request.urlopen(req, timeout=20) as resp:
			return json.loads(resp.read().decode("utf-8"))

	def _get(self, path: str) -> Dict[str, Any]:
		req = request.Request(f"{self.base}{path}", headers=self._headers(), method="GET")
		with request.urlopen(req, timeout=20) as resp:
			return json.loads(resp.read().decode("utf-8"))

	def heartbeat(self, status: str = "ok", **extra: Any) -> None:
		body = {"status": status, "connector_version": "0.1.0", **extra}
		try:
			self._post("/api/v1/telephony/connector/heartbeat", body)
		except Exception as e:
			LOG.warning("heartbeat failed: %s", e)

	def send_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
		try:
			data = self._post("/api/v1/telephony/connector/events", event)
			payload = data.get("data") if isinstance(data, dict) else None
			return payload if isinstance(payload, dict) else (data if isinstance(data, dict) else {})
		except Exception as e:
			LOG.warning("event failed: %s", e)
			return {}

	def poll_commands(self) -> list:
		try:
			data = self._get("/api/v1/telephony/connector/commands/poll?limit=10")
			payload = data.get("data") or data
			items = payload.get("items") if isinstance(payload, dict) else []
			return items or []
		except Exception as e:
			LOG.warning("poll failed: %s", e)
			return []

	def ack(self, command_id: str, accepted: bool = True, **extra: Any) -> None:
		try:
			self._post(
				f"/api/v1/telephony/connector/commands/{command_id}/ack",
				{"accepted": accepted, **extra},
			)
		except Exception as e:
			LOG.warning("ack failed: %s", e)


class AmiClient:
	"""کلاینت AMI بسیار ساده برای Login / Originate / رویدادهای متنی."""

	def __init__(self, host: str, port: int, username: str, secret: str) -> None:
		self.host = host
		self.port = port
		self.username = username
		self.secret = secret
		self._sock: Optional[socket.socket] = None
		self._buf = b""
		self._lock = threading.Lock()

	def connect(self) -> None:
		self._sock = socket.create_connection((self.host, self.port), timeout=10)
		self._sock.settimeout(1.0)
		self._login()

	def close(self) -> None:
		if self._sock:
			try:
				self._sock.close()
			except Exception:
				pass
			self._sock = None

	def _send(self, lines: Dict[str, str]) -> None:
		assert self._sock is not None
		payload = "".join(f"{k}: {v}\r\n" for k, v in lines.items()) + "\r\n"
		with self._lock:
			self._sock.sendall(payload.encode("utf-8"))

	def _login(self) -> None:
		self._send({"Action": "Login", "Username": self.username, "Secret": self.secret})
		# پاسخ Login را بخوان
		deadline = time.time() + 5
		buf = b""
		assert self._sock is not None
		while time.time() < deadline:
			try:
				chunk = self._sock.recv(4096)
				if not chunk:
					break
				buf += chunk
				if b"\r\n\r\n" in buf:
					break
			except socket.timeout:
				continue
		text = buf.decode("utf-8", errors="ignore")
		if "Success" not in text and "Authentication accepted" not in text:
			raise RuntimeError(f"AMI login rejected: {text[:300]!r}")

	def originate(self, extension: str, destination: str, context: str = "from-internal", timeout_ms: int = 30000) -> None:
		self._send(
			{
				"Action": "Originate",
				"Channel": f"Local/{extension}@{context}",
				"Context": context,
				"Exten": destination,
				"Priority": "1",
				"Timeout": str(timeout_ms),
				"CallerID": extension,
				"Async": "true",
			}
		)

	def originate_to_application(
		self,
		channel: str,
		application: str,
		data: str,
		*,
		caller_id: str = "",
		timeout_ms: int = 30000,
		variable: Optional[str] = None,
	) -> None:
		payload: Dict[str, str] = {
			"Action": "Originate",
			"Channel": channel,
			"Application": application,
			"Data": data,
			"Timeout": str(timeout_ms),
			"Async": "true",
		}
		if caller_id:
			payload["CallerID"] = caller_id
		if variable:
			payload["Variable"] = variable
		self._send(payload)

	def play_dtmf(self, channel: str, digit: str) -> None:
		self._send({"Action": "PlayDTMF", "Channel": channel, "Digit": digit})

	def hangup(self, channel: str) -> None:
		self._send({"Action": "Hangup", "Channel": channel})

	def set_var(self, channel: str, variable: str, value: str) -> None:
		self._send(
			{
				"Action": "Setvar",
				"Channel": channel,
				"Variable": variable,
				"Value": value,
			}
		)

	def redirect(self, channel: str, exten: str, context: str = "from-internal") -> None:
		self._send(
			{
				"Action": "Redirect",
				"Channel": channel,
				"Exten": exten,
				"Context": context,
				"Priority": "1",
			}
		)

	def park_or_hold(self, channel: str) -> None:
		# Issabel/Asterisk: soft hold via Park or Redirect to parking lot if configured
		self._send(
			{
				"Action": "Park",
				"Channel": channel,
			}
		)

	def read_events(self):
		assert self._sock is not None
		while True:
			try:
				chunk = self._sock.recv(4096)
				if not chunk:
					break
				self._buf += chunk
				while b"\r\n\r\n" in self._buf:
					raw, self._buf = self._buf.split(b"\r\n\r\n", 1)
					text = raw.decode("utf-8", errors="ignore")
					ev: Dict[str, str] = {}
					for line in text.split("\r\n"):
						if ": " in line:
							k, v = line.split(": ", 1)
							ev[k.strip()] = v.strip()
					if ev:
						yield ev
			except socket.timeout:
				yield {"Event": "Idle"}
			except Exception as e:
				LOG.error("AMI read error: %s", e)
				break


def map_ami_event(ev: Dict[str, str]) -> Optional[Dict[str, Any]]:
	name = ev.get("Event")
	if name == "UserEvent" and (ev.get("UserEvent") or "") == "HesabixInboundSoftphone":
		extension = ev.get("Extension") or "500"
		return {
			"event_id": str(uuid.uuid4()),
			"type": "call.ringing",
			"uniqueid": ev.get("Uniqueid") or str(uuid.uuid4()),
			"linkedid": ev.get("Linkedid"),
			"direction": "inbound",
			"from": ev.get("CallerID") or ev.get("CallerIDNum"),
			"to": extension,
			"extension": extension,
			"channel": ev.get("Channel"),
			"softphone_relay": True,
		}
	if name == "DialBegin":
		return {
			"event_id": str(uuid.uuid4()),
			"type": "call.ringing",
			"uniqueid": ev.get("DestUniqueid") or ev.get("Uniqueid") or str(uuid.uuid4()),
			"linkedid": ev.get("Linkedid"),
			"direction": "inbound",
			"from": ev.get("CallerIDNum"),
			"to": ev.get("DestExten") or ev.get("Exten"),
			"extension": ev.get("DestCallerIDNum") or ev.get("DestExten"),
			"channel": ev.get("Channel"),
		}
	if name == "Hangup":
		return {
			"event_id": str(uuid.uuid4()),
			"type": "call.ended",
			"uniqueid": ev.get("Uniqueid") or str(uuid.uuid4()),
			"linkedid": ev.get("Linkedid"),
			"hangup_cause": ev.get("Cause"),
			"extension": ev.get("CallerIDNum"),
			"from": ev.get("CallerIDNum"),
			"to": ev.get("ConnectedLineNum"),
		}
	return None


def main() -> int:
	logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
	# مسیرهای محتمل .env
	for candidate in (
		os.environ.get("HESABIX_PBX_ENV"),
		"/opt/HesabixTelephonyConnector/.env",
		os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env"),
		os.path.join(os.getcwd(), ".env"),
	):
		if candidate:
			load_dotenv(candidate)

	try:
		api = HesabixClient(
			base_url=env("HESABIX_API_URL"),
			business_id=int(env("HESABIX_BUSINESS_ID")),
			pbx_id=int(env("HESABIX_PBX_ID")),
			token=env("HESABIX_CONNECTOR_TOKEN"),
		)
		ami = AmiClient(
			host=os.environ.get("AMI_HOST", "127.0.0.1"),
			port=int(os.environ.get("AMI_PORT", "5038")),
			username=env("AMI_USER"),
			secret=env("AMI_SECRET"),
		)
	except Exception as e:
		LOG.error("پیکربندی ناقص یا نامعتبر: %s", e)
		return 1

	LOG.info("Connecting AMI %s@%s:%s …", ami.username, ami.host, ami.port)
	try:
		ami.connect()
	except Exception as e:
		LOG.error("اتصال/ورود AMI ناموفق: %s", e)
		LOG.error("روی سرور تلفن بررسی کنید: manager.conf، AMI_USER/AMI_SECRET، و: asterisk -rx 'manager show connected'")
		return 1

	try:
		api.heartbeat(status="ok", media_tunnel=False)
	except Exception as e:
		LOG.error("heartbeat حسابیکس ناموفق: %s", e)
		return 1

	# Softphone media state
	as_uuid_to_session: Dict[str, str] = {}
	session_to_as_uuid: Dict[str, str] = {}
	session_to_bridge_id: Dict[str, str] = {}
	session_to_call_id: Dict[str, Any] = {}
	online_agents_by_ext: Dict[str, str] = {}  # extension -> session_id
	media_lock = threading.Lock()
	tunnel_ref: Dict[str, Any] = {"client": None}

	def _notify_bridge_active(session_id: str, as_uuid: str, *, call_id: Any = None) -> None:
		client = tunnel_ref.get("client")
		if not client or not session_id:
			return
		with media_lock:
			bridge_id = session_to_bridge_id.get(session_id)
			if call_id is None:
				call_id = session_to_call_id.get(session_id)
		payload: Dict[str, Any] = {
			"type": "bridge.active",
			"session_id": session_id,
			"audiosocket_uuid": as_uuid,
		}
		if bridge_id:
			payload["bridge_id"] = bridge_id
		if call_id is not None:
			payload["call_id"] = call_id
		client.send_json(payload)

	def on_as_pcm(as_uuid: str, pcm: bytes) -> None:
		with media_lock:
			session_id = as_uuid_to_session.get(as_uuid)
		client: Optional[MediaTunnelClient] = tunnel_ref.get("client")
		if session_id and client:
			client.send_pcm(session_id, pcm)

	def on_as_connect(as_uuid: str) -> None:
		with media_lock:
			session_id = as_uuid_to_session.get(as_uuid)
		if session_id:
			LOG.info("AudioSocket ready → bridge.active session=%s uuid=%s", session_id, as_uuid)
			_notify_bridge_active(session_id, as_uuid)

	def on_as_hangup(as_uuid: str) -> None:
		with media_lock:
			session_id = as_uuid_to_session.pop(as_uuid, None)
			if session_id:
				session_to_as_uuid.pop(session_id, None)
				session_to_bridge_id.pop(session_id, None)
		client = tunnel_ref.get("client")
		if client and session_id:
			client.send_json({"type": "bridge.failed", "session_id": session_id, "reason": "audiosocket_hangup", "audiosocket_uuid": as_uuid})

	def on_tunnel_pcm(session_id: str, pcm: bytes) -> None:
		with media_lock:
			as_uuid = session_to_as_uuid.get(session_id)
		if as_uuid:
			audio_server.send_pcm(as_uuid, pcm)

	def on_tunnel_json(payload: Dict[str, Any]) -> None:
		typ = payload.get("type")
		if typ == "bridge.start":
			session_id = str(payload.get("session_id") or "")
			as_uuid = str(payload.get("audiosocket_uuid") or "")
			bridge_id = str(payload.get("bridge_id") or "")
			if session_id and as_uuid:
				with media_lock:
					as_uuid_to_session[as_uuid] = session_id
					session_to_as_uuid[session_id] = as_uuid
					if bridge_id:
						session_to_bridge_id[session_id] = bridge_id
				# اگر AudioSocket از قبل وصل است (نادر)، فوری active کن؛ وگرنه بعد از TCP connect
				if audio_server.has_connection(as_uuid):
					_notify_bridge_active(session_id, as_uuid, call_id=payload.get("call_id"))
				else:
					LOG.info("bridge.start mapped session=%s uuid=%s (waiting AudioSocket)", session_id, as_uuid)
		elif typ == "bridge.stop":
			session_id = str(payload.get("session_id") or "")
			as_uuid = str(payload.get("audiosocket_uuid") or "")
			with media_lock:
				if not as_uuid:
					as_uuid = session_to_as_uuid.pop(session_id, "")
				else:
					session_to_as_uuid.pop(session_id, None)
				if as_uuid:
					as_uuid_to_session.pop(as_uuid, None)
				if session_id:
					session_to_bridge_id.pop(session_id, None)
					session_to_call_id.pop(session_id, None)
			if as_uuid:
				audio_server.hangup(as_uuid)
		elif typ == "agent.online":
			ext = str(payload.get("extension") or "").strip()
			sid = str(payload.get("session_id") or "").strip()
			if ext and sid:
				with media_lock:
					online_agents_by_ext[ext] = sid
			LOG.info("softphone agent online ext=%s session=%s", ext, sid)
		elif typ == "agent.offline":
			sid = str(payload.get("session_id") or "").strip()
			ext = str(payload.get("extension") or "").strip()
			with media_lock:
				if ext and online_agents_by_ext.get(ext) == sid:
					online_agents_by_ext.pop(ext, None)
				elif sid:
					for k, v in list(online_agents_by_ext.items()):
						if v == sid:
							online_agents_by_ext.pop(k, None)
			LOG.info("softphone agent offline session=%s", sid)

	audio_host = os.environ.get("AUDIOSOCKET_HOST", "127.0.0.1")
	audio_port = int(os.environ.get("AUDIOSOCKET_PORT", "9092"))
	audio_server = AudioSocketServer(
		host=audio_host,
		port=audio_port,
		on_pcm=on_as_pcm,
		on_hangup=on_as_hangup,
		on_connect=on_as_connect,
	)
	try:
		audio_server.start()
	except Exception as e:
		LOG.error("شروع AudioSocket ناموفق: %s — Softphone Relay کار نمی‌کند تا پورت آزاد شود.", e)

	media_enabled = os.environ.get("MEDIA_TUNNEL_ENABLED", "1") != "0"
	if media_enabled:
		tunnel = MediaTunnelClient(
			api_base=api.base,
			business_id=api.business_id,
			pbx_id=api.pbx_id,
			token=api.token,
			on_json=on_tunnel_json,
			on_pcm=on_tunnel_pcm,
		)
		tunnel_ref["client"] = tunnel
		tunnel.start()
		LOG.info("Media tunnel starter → %s", tunnel.ws_url)
	else:
		LOG.warning("MEDIA_TUNNEL_ENABLED=0 — فقط CTI بدون Softphone Relay")

	LOG.info("Connector آماده است (AMI + Hesabix + Softphone media).")

	last_hb = 0.0
	last_poll = 0.0
	last_media_ping = 0.0
	try:
		for ev in ami.read_events():
			now = time.time()
			if now - last_hb > 60:
				api.heartbeat(status="ok", media_tunnel=bool(tunnel_ref.get("client") and tunnel_ref["client"].connected))
				last_hb = now
			# ping رسانه جدا از heartbeat حسابیکس — تا tunnel_online سمت API پایدار بماند
			if now - last_media_ping > 15:
				client = tunnel_ref.get("client")
				if client and client.connected:
					client.send_json({"type": "ping", "ts": int(now)})
				last_media_ping = now
			if now - last_poll > 2:
				for cmd in api.poll_commands():
					cid = cmd.get("command_id")
					ctype = cmd.get("type")
					try:
						if ctype == "originate":
							ami.originate(
								extension=str(cmd.get("extension")),
								destination=str(cmd.get("destination")),
								context=str(cmd.get("context") or "from-internal"),
								timeout_ms=int(cmd.get("timeout_ms") or 30000),
							)
						elif ctype == "softphone_bridge_out":
							destination = str(cmd.get("destination"))
							context = str(cmd.get("context") or "from-internal")
							as_uuid = str(cmd.get("audiosocket_uuid") or uuid.uuid4())
							session_id = str(cmd.get("session_id") or "")
							host = str(cmd.get("audiosocket_host") or audio_host)
							port = int(cmd.get("audiosocket_port") or audio_port)
							with media_lock:
								if session_id:
									as_uuid_to_session[as_uuid] = session_id
									session_to_as_uuid[session_id] = as_uuid
									if cmd.get("call_id") is not None:
										session_to_call_id[session_id] = cmd.get("call_id")
							# Asterisk AudioSocket(uuid,host:port) — ترتیب آرگومان مهم است.
							# /n روی Local مانع channel optimization می‌شود تا AudioSocket قطع نشود.
							ami.originate_to_application(
								channel=f"Local/{destination}@{context}/n",
								application="AudioSocket",
								data=f"{as_uuid},{host}:{port}",
								caller_id=str(cmd.get("extension") or ""),
								timeout_ms=int(cmd.get("timeout_ms") or 30000),
								variable=f"HSX_UUID={as_uuid}",
							)
							LOG.info(
								"softphone_bridge_out dest=%s uuid=%s as=%s:%s",
								destination,
								as_uuid,
								host,
								port,
							)
							# bridge.active بعد از TCP AudioSocket (on_as_connect) تا میکروفون/سکوت به‌موقع برسد
							if audio_server.has_connection(as_uuid):
								_notify_bridge_active(session_id, as_uuid, call_id=cmd.get("call_id"))
						elif ctype == "softphone_bridge_in":
							as_uuid = str(cmd.get("audiosocket_uuid") or uuid.uuid4())
							session_id = str(cmd.get("session_id") or "")
							channel = cmd.get("channel")
							host = str(cmd.get("audiosocket_host") or audio_host)
							port = int(cmd.get("audiosocket_port") or audio_port)
							with media_lock:
								if session_id:
									as_uuid_to_session[as_uuid] = session_id
									session_to_as_uuid[session_id] = as_uuid
							if channel:
								# انتقال کانال زنگ‌خور به AudioSocket — UUID را روی کانال ست کن
								ami.set_var(str(channel), "HSX_UUID", as_uuid)
								ami.redirect(str(channel), "s", context="hesabix-softphone-relay")
							else:
								ext = str(cmd.get("extension") or "")
								ami.originate_to_application(
									channel=f"Local/{ext}@from-internal/n",
									application="AudioSocket",
									data=f"{as_uuid},{host}:{port}",
									caller_id=ext,
									timeout_ms=30000,
									variable=f"HSX_UUID={as_uuid}",
								)
							if audio_server.has_connection(as_uuid):
								_notify_bridge_active(session_id, as_uuid, call_id=cmd.get("call_id"))
						elif ctype == "softphone_dtmf":
							channel = cmd.get("channel")
							digit = str(cmd.get("digit") or "")
							if channel and digit:
								ami.play_dtmf(str(channel), digit)
						elif ctype == "hangup":
							channel = cmd.get("channel")
							if channel:
								ami.hangup(str(channel))
							session_id = str(cmd.get("session_id") or "")
							as_uuid = str(cmd.get("audiosocket_uuid") or "")
							with media_lock:
								if not as_uuid and session_id:
									as_uuid = session_to_as_uuid.pop(session_id, "") or ""
								elif as_uuid:
									mapped_session = as_uuid_to_session.pop(as_uuid, "") or ""
									session_id = session_id or mapped_session
									if session_id:
										session_to_as_uuid.pop(session_id, None)
								if as_uuid:
									as_uuid_to_session.pop(as_uuid, None)
								if session_id:
									session_to_bridge_id.pop(session_id, None)
							if as_uuid:
								LOG.info("hangup AudioSocket uuid=%s session=%s", as_uuid, session_id)
								audio_server.hangup(as_uuid)
							elif not channel:
								LOG.warning("hangup without channel/session/uuid cmd=%s", cmd)
						elif ctype == "transfer":
							channel = cmd.get("channel")
							target = cmd.get("target")
							if channel and target:
								ami.redirect(str(channel), str(target), context=str(cmd.get("context") or "from-internal"))
						elif ctype in ("hold", "resume"):
							channel = cmd.get("channel")
							if channel and ctype == "hold":
								ami.park_or_hold(str(channel))
						if cid:
							api.ack(str(cid), accepted=True)
					except Exception as e:
						LOG.exception("command failed: %s", ctype)
						if cid:
							api.ack(str(cid), accepted=False, error=str(e))
				last_poll = now
			mapped = map_ami_event(ev)
			if mapped:
				result = api.send_event(mapped)
				call_obj = result.get("call") if isinstance(result, dict) else None
				call_id = None
				if isinstance(call_obj, dict):
					call_id = call_obj.get("id")
				elif isinstance(result, dict):
					call_id = result.get("call_id")
				# زنگ Softphone وب وقتی داخلی Relay آنلاین است
				if mapped.get("softphone_relay"):
					ext = str(mapped.get("extension") or "").strip()
					with media_lock:
						session_id = online_agents_by_ext.get(ext)
					client = tunnel_ref.get("client")
					if session_id and client:
						LOG.info(
							"inbound softphone ring ext=%s session=%s channel=%s from=%s call_id=%s",
							ext,
							session_id,
							mapped.get("channel"),
							mapped.get("from"),
							call_id,
						)
						client.send_json(
							{
								"type": "incoming_softphone_ring",
								"session_id": session_id,
								"extension": ext,
								"from": mapped.get("from"),
								"channel": mapped.get("channel"),
								"uniqueid": mapped.get("uniqueid"),
								"linkedid": mapped.get("linkedid"),
								"call_id": call_id,
							}
						)
	except KeyboardInterrupt:
		LOG.info("Stopping…")
	except Exception as e:
		LOG.exception("حلقه رویداد قطع شد: %s", e)
		return 1
	finally:
		client = tunnel_ref.get("client")
		if client:
			client.stop()
		audio_server.stop()
		ami.close()
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
