"""Media Hub درحافظه — تونل Connector و سشن‌های Softphone کلاینت.

این هاب باید فقط روی یک process (Media Edge با workers=1) زنده بماند.
با چند worker، کلاینت/تونل/REST روی processهای متفاوت می‌افتند.
رجوع: app/services/telephony/media_edge.py و docs/TELEPHONY_SOFTPHONE_MEDIA_EDGE.md
"""
from __future__ import annotations

import asyncio
import logging
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, Optional, Set

LOG = logging.getLogger("hesabix.telephony.media_hub")

# پروفایل رسانه فاز R1: PCM16LE 8kHz mono روی WSS (سازگار با Asterisk AudioSocket)
MEDIA_PROFILE_PCM_WS_V1 = "pcm_ws_v1"
SUPPORTED_MEDIA_PROFILES = (MEDIA_PROFILE_PCM_WS_V1,)
# Connector معمولاً هر ~۶۰ثانیه ping اپلیکیشنی می‌فرستد؛ حاشیه برای تأخیر شبکه/AMI
TUNNEL_ONLINE_TTL_SEC = 120.0


@dataclass
class SoftphoneClientLink:
	session_id: str
	business_id: int
	pbx_id: int
	user_id: int
	extension: str
	websocket: Any
	media_profile: str = MEDIA_PROFILE_PCM_WS_V1
	muted: bool = False
	connected_at: float = field(default_factory=time.time)
	active_call_id: Optional[int] = None
	bridge_id: Optional[str] = None


@dataclass
class ConnectorTunnelLink:
	tunnel_id: str
	business_id: int
	pbx_id: int
	websocket: Any
	capabilities: Set[str] = field(default_factory=set)
	connected_at: float = field(default_factory=time.time)
	last_heartbeat_at: float = field(default_factory=time.time)
	# session_id -> meta
	online_agents: Dict[str, Dict[str, Any]] = field(default_factory=dict)


@dataclass
class MediaBridge:
	bridge_id: str
	session_id: str
	business_id: int
	pbx_id: int
	call_id: Optional[int]
	direction: str  # inbound | outbound
	audiosocket_uuid: str
	created_at: float = field(default_factory=time.time)
	state: str = "starting"  # starting | active | ending | ended


class TelephonyMediaHub:
	"""هاب مرکزی رسانه Softphone (یک نود؛ بعداً قابل افقی‌سازی)."""

	def __init__(self) -> None:
		self.node_id = f"media-{uuid.uuid4().hex[:8]}"
		self._lock = asyncio.Lock()
		self._clients: Dict[str, SoftphoneClientLink] = {}
		self._tunnels_by_pbx: Dict[int, ConnectorTunnelLink] = {}
		self._bridges: Dict[str, MediaBridge] = {}
		self._bridges_by_session: Dict[str, str] = {}
		self._pcm_drop_log_at: Dict[str, float] = {}

	def _log_pcm_drop(self, key: str, message: str, *args: Any) -> None:
		now = time.time()
		last = self._pcm_drop_log_at.get(key, 0.0)
		if now - last < 5.0:
			return
		self._pcm_drop_log_at[key] = now
		LOG.warning(message, *args)

	def health(self) -> Dict[str, Any]:
		return {
			"node_id": self.node_id,
			"clients": len(self._clients),
			"tunnels": len(self._tunnels_by_pbx),
			"bridges": len(self._bridges),
			"supported_profiles": list(SUPPORTED_MEDIA_PROFILES),
		}

	def tunnel_online(self, pbx_id: int) -> bool:
		t = self._tunnels_by_pbx.get(pbx_id)
		if not t:
			return False
		return (time.time() - t.last_heartbeat_at) < TUNNEL_ONLINE_TTL_SEC

	def tunnel_snapshot(self, pbx_id: int) -> Optional[Dict[str, Any]]:
		t = self._tunnels_by_pbx.get(pbx_id)
		if not t:
			return None
		return {
			"tunnel_id": t.tunnel_id,
			"business_id": t.business_id,
			"pbx_id": t.pbx_id,
			"online": self.tunnel_online(pbx_id),
			"capabilities": sorted(t.capabilities),
			"agents_online": len(t.online_agents),
			"connected_at": t.connected_at,
			"last_heartbeat_at": t.last_heartbeat_at,
		}

	async def register_tunnel(
		self,
		*,
		business_id: int,
		pbx_id: int,
		websocket: WebSocket,
		capabilities: Optional[list[str]] = None,
	) -> ConnectorTunnelLink:
		async with self._lock:
			old = self._tunnels_by_pbx.get(pbx_id)
			if old and old.websocket is not websocket:
				try:
					await old.websocket.close(code=4000)
				except Exception:
					pass
			link = ConnectorTunnelLink(
				tunnel_id=str(uuid.uuid4()),
				business_id=business_id,
				pbx_id=pbx_id,
				websocket=websocket,
				capabilities=set(capabilities or ["audiosocket", "pcm_ws_v1"]),
			)
			self._tunnels_by_pbx[pbx_id] = link
			LOG.info("media tunnel up pbx=%s tunnel=%s", pbx_id, link.tunnel_id)
			return link

	async def unregister_tunnel(self, pbx_id: int, tunnel_id: str) -> None:
		async with self._lock:
			cur = self._tunnels_by_pbx.get(pbx_id)
			if cur and cur.tunnel_id == tunnel_id:
				self._tunnels_by_pbx.pop(pbx_id, None)
				LOG.info("media tunnel down pbx=%s tunnel=%s", pbx_id, tunnel_id)

	async def touch_tunnel(self, pbx_id: int) -> None:
		t = self._tunnels_by_pbx.get(pbx_id)
		if t:
			t.last_heartbeat_at = time.time()

	async def notify_softphone_incoming(
		self,
		*,
		pbx_id: int,
		extension: str,
		call_id: int,
		from_number: Optional[str] = None,
		channel: Optional[str] = None,
	) -> int:
		"""ارسال زنگ ورودی به Softphone clientهای آنلاین روی همان داخلی."""
		ext = str(extension or "").strip()
		sent = 0
		for session_id, link in list(self._clients.items()):
			if link.pbx_id != pbx_id:
				continue
			if str(link.extension or "").strip() != ext:
				continue
			ok = await self.send_to_client(
				session_id,
				{
					"type": "incoming_ring",
					"call_id": call_id,
					"from": from_number,
					"extension": ext,
					"channel": channel,
				},
			)
			if ok:
				sent += 1
				link.active_call_id = call_id
		if sent:
			LOG.info(
				"softphone incoming_ring sent=%s pbx=%s ext=%s call_id=%s",
				sent,
				pbx_id,
				ext,
				call_id,
			)
		return sent

	async def register_client(self, link: SoftphoneClientLink) -> None:
		async with self._lock:
			old = self._clients.get(link.session_id)
			if old and old.websocket is not link.websocket:
				try:
					await old.websocket.close(code=4001)
				except Exception:
					pass
			self._clients[link.session_id] = link
		# اطلاع به Connector
		await self.send_to_tunnel(
			link.pbx_id,
			{
				"type": "agent.online",
				"session_id": link.session_id,
				"user_id": link.user_id,
				"extension": link.extension,
				"media_profile": link.media_profile,
			},
		)
		tunnel = self._tunnels_by_pbx.get(link.pbx_id)
		if tunnel:
			tunnel.online_agents[link.session_id] = {
				"user_id": link.user_id,
				"extension": link.extension,
			}

	async def unregister_client(
		self,
		session_id: str,
		*,
		reason: str = "client_disconnect",
		websocket: Any = None,
	) -> Optional[SoftphoneClientLink]:
		"""اگر websocket داده شود و کلاینت جدید جایگزین شده باشد، no-op (handoff امن)."""
		async with self._lock:
			link = self._clients.get(session_id)
			if not link:
				return None
			if websocket is not None and link.websocket is not websocket:
				# اتصال جدید همین session را گرفته؛ سشن را قطع نکن
				return None
			self._clients.pop(session_id, None)
			bridge_id = self._bridges_by_session.pop(session_id, None)
			bridge = self._bridges.pop(bridge_id, None) if bridge_id else None
		tunnel = self._tunnels_by_pbx.get(link.pbx_id)
		if tunnel:
			tunnel.online_agents.pop(session_id, None)
		await self.send_to_tunnel(
			link.pbx_id,
			{
				"type": "agent.offline",
				"session_id": session_id,
				"extension": link.extension,
				"reason": reason,
			},
		)
		if bridge:
			await self.send_to_tunnel(
				link.pbx_id,
				{
					"type": "bridge.stop",
					"bridge_id": bridge.bridge_id,
					"session_id": session_id,
					"audiosocket_uuid": bridge.audiosocket_uuid,
					"reason": reason,
				},
			)
		return link

	def get_client(self, session_id: str) -> Optional[SoftphoneClientLink]:
		return self._clients.get(session_id)

	async def send_to_client(self, session_id: str, payload: Dict[str, Any]) -> bool:
		link = self._clients.get(session_id)
		if not link:
			return False
		try:
			await link.websocket.send_json(payload)
			return True
		except Exception as e:
			LOG.warning("send_to_client failed session=%s: %s", session_id, e)
			return False

	async def send_to_tunnel(self, pbx_id: int, payload: Dict[str, Any]) -> bool:
		tunnel = self._tunnels_by_pbx.get(pbx_id)
		if not tunnel:
			return False
		try:
			await tunnel.websocket.send_json(payload)
			return True
		except Exception as e:
			LOG.warning("send_to_tunnel failed pbx=%s: %s", pbx_id, e)
			return False

	@staticmethod
	def pack_pcm_frame(session_id: str, pcm: bytes, *, direction_type: int = 1) -> bytes:
		"""HSXM + type + flags + len + session_id(36) + pcm."""
		sid = (session_id or "").encode("ascii")[:36].ljust(36, b" ")
		return b"HSXM" + bytes([direction_type & 0xFF, 0]) + len(pcm).to_bytes(2, "big") + sid + pcm

	@staticmethod
	def unpack_pcm_frame(blob: bytes) -> Optional[tuple[int, str, bytes]]:
		if len(blob) < 44 or blob[:4] != b"HSXM":
			return None
		frame_type = blob[4]
		pcm_len = int.from_bytes(blob[6:8], "big")
		session_id = blob[8:44].decode("ascii", errors="ignore").strip()
		pcm = blob[44 : 44 + pcm_len]
		if len(pcm) != pcm_len:
			return None
		return frame_type, session_id, pcm

	async def forward_media_client_to_tunnel(self, session_id: str, data: bytes) -> None:
		link = self._clients.get(session_id)
		if not link or link.muted:
			return
		if self._bridges_by_session.get(session_id) is None:
			self._log_pcm_drop(f"c2t:{session_id}", "PCM client→tunnel dropped: no bridge for session=%s", session_id)
			return
		tunnel = self._tunnels_by_pbx.get(link.pbx_id)
		if not tunnel:
			self._log_pcm_drop(f"c2t-tun:{session_id}", "PCM client→tunnel dropped: no tunnel pbx=%s session=%s", link.pbx_id, session_id)
			return
		try:
			await tunnel.websocket.send_bytes(self.pack_pcm_frame(session_id, data, direction_type=1))
		except Exception as e:
			LOG.debug("media client→tunnel drop: %s", e)

	async def forward_media_tunnel_to_client(self, session_id: str, data: bytes) -> None:
		link = self._clients.get(session_id)
		if not link:
			return
		if self._bridges_by_session.get(session_id) is None:
			self._log_pcm_drop(f"t2c:{session_id}", "PCM tunnel→client dropped: no bridge for session=%s", session_id)
			return
		try:
			await link.websocket.send_bytes(self.pack_pcm_frame(session_id, data, direction_type=2))
		except Exception as e:
			LOG.debug("media tunnel→client drop: %s", e)

	async def start_bridge(
		self,
		*,
		session_id: str,
		call_id: Optional[int],
		direction: str,
		audiosocket_uuid: Optional[str] = None,
	) -> MediaBridge:
		link = self._clients.get(session_id)
		if not link:
			raise RuntimeError("softphone client not connected")
		if not self.tunnel_online(link.pbx_id):
			raise RuntimeError("media tunnel offline")
		bridge_id = str(uuid.uuid4())
		as_uuid = audiosocket_uuid or bridge_id
		bridge = MediaBridge(
			bridge_id=bridge_id,
			session_id=session_id,
			business_id=link.business_id,
			pbx_id=link.pbx_id,
			call_id=call_id,
			direction=direction,
			audiosocket_uuid=as_uuid,
			state="starting",
		)
		async with self._lock:
			old_id = self._bridges_by_session.get(session_id)
			if old_id and old_id in self._bridges:
				self._bridges[old_id].state = "ended"
				self._bridges.pop(old_id, None)
			self._bridges[bridge_id] = bridge
			self._bridges_by_session[session_id] = bridge_id
			link.active_call_id = call_id
			link.bridge_id = bridge_id
		ok = await self.send_to_tunnel(
			link.pbx_id,
			{
				"type": "bridge.start",
				"bridge_id": bridge_id,
				"session_id": session_id,
				"extension": link.extension,
				"call_id": call_id,
				"direction": direction,
				"audiosocket_uuid": as_uuid,
				"media_profile": link.media_profile,
			},
		)
		if not ok:
			raise RuntimeError("failed to signal connector bridge.start")
		await self.send_to_client(
			session_id,
			{
				"type": "bridge.starting",
				"bridge_id": bridge_id,
				"call_id": call_id,
				"direction": direction,
			},
		)
		return bridge

	async def mark_bridge_active(self, bridge_id: str) -> None:
		bridge = self._bridges.get(bridge_id)
		if not bridge:
			return
		bridge.state = "active"
		await self.send_to_client(
			bridge.session_id,
			{"type": "bridge.active", "bridge_id": bridge_id, "call_id": bridge.call_id},
		)

	async def mark_bridge_active_by_session(self, session_id: str) -> None:
		bridge_id = self._bridges_by_session.get(session_id)
		if bridge_id:
			await self.mark_bridge_active(bridge_id)

	async def ensure_bridge_active(
		self,
		*,
		session_id: str,
		audiosocket_uuid: Optional[str] = None,
		call_id: Optional[int] = None,
		bridge_id: Optional[str] = None,
		direction: str = "outbound",
	) -> Optional[MediaBridge]:
		"""اگر start_bridge روی worker اشتباه اجرا شده/نشده، از bridge.active کانکتور پل را اینجا بساز."""
		link = self._clients.get(session_id)
		if not link:
			LOG.warning("ensure_bridge_active: softphone client missing session=%s", session_id)
			return None

		existing_id = self._bridges_by_session.get(session_id)
		if existing_id and existing_id in self._bridges:
			bridge = self._bridges[existing_id]
			if audiosocket_uuid:
				bridge.audiosocket_uuid = str(audiosocket_uuid)
			if call_id is not None:
				bridge.call_id = call_id
				link.active_call_id = call_id
			await self.mark_bridge_active(existing_id)
			return bridge

		new_id = str(bridge_id or uuid.uuid4())
		as_uuid = str(audiosocket_uuid or new_id)
		bridge = MediaBridge(
			bridge_id=new_id,
			session_id=session_id,
			business_id=link.business_id,
			pbx_id=link.pbx_id,
			call_id=call_id if call_id is not None else link.active_call_id,
			direction=direction,
			audiosocket_uuid=as_uuid,
			state="active",
		)
		async with self._lock:
			self._bridges[new_id] = bridge
			self._bridges_by_session[session_id] = new_id
			link.bridge_id = new_id
			if call_id is not None:
				link.active_call_id = call_id
		LOG.info(
			"ensure_bridge_active created bridge=%s session=%s uuid=%s call_id=%s",
			new_id,
			session_id,
			as_uuid,
			bridge.call_id,
		)
		await self.send_to_client(
			session_id,
			{"type": "bridge.active", "bridge_id": new_id, "call_id": bridge.call_id},
		)
		return bridge

	async def stop_bridge(self, session_id: str, *, reason: str = "hangup") -> None:
		async with self._lock:
			bridge_id = self._bridges_by_session.pop(session_id, None)
			bridge = self._bridges.pop(bridge_id, None) if bridge_id else None
			link = self._clients.get(session_id)
			pbx_id = (bridge.pbx_id if bridge else None) or (link.pbx_id if link else None)
			as_uuid = bridge.audiosocket_uuid if bridge else None
			if link:
				link.bridge_id = None
				link.active_call_id = None
		# حتی بدون bridge محلی، به Connector بگو AudioSocket را ببند (قطع واقعی تماس)
		if pbx_id:
			await self.send_to_tunnel(
				pbx_id,
				{
					"type": "bridge.stop",
					"bridge_id": bridge_id,
					"session_id": session_id,
					"audiosocket_uuid": as_uuid,
					"reason": reason,
				},
			)
		await self.send_to_client(
			session_id,
			{"type": "bridge.ended", "bridge_id": bridge_id, "reason": reason},
		)


media_hub = TelephonyMediaHub()
