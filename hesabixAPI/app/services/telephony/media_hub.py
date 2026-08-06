"""Media Hub درحافظه — تونل Connector و سشن‌های Softphone کلاینت."""
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
		return (time.time() - t.last_heartbeat_at) < 30

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

	async def unregister_client(self, session_id: str, *, reason: str = "client_disconnect") -> None:
		async with self._lock:
			link = self._clients.pop(session_id, None)
			bridge_id = self._bridges_by_session.pop(session_id, None)
			bridge = self._bridges.pop(bridge_id, None) if bridge_id else None
		if not link:
			return
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
			return
		tunnel = self._tunnels_by_pbx.get(link.pbx_id)
		if not tunnel:
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

	async def stop_bridge(self, session_id: str, *, reason: str = "hangup") -> None:
		async with self._lock:
			bridge_id = self._bridges_by_session.pop(session_id, None)
			bridge = self._bridges.pop(bridge_id, None) if bridge_id else None
			link = self._clients.get(session_id)
			if link:
				link.bridge_id = None
				link.active_call_id = None
		if not bridge:
			return
		bridge.state = "ended"
		await self.send_to_tunnel(
			bridge.pbx_id,
			{
				"type": "bridge.stop",
				"bridge_id": bridge.bridge_id,
				"session_id": session_id,
				"audiosocket_uuid": bridge.audiosocket_uuid,
				"reason": reason,
			},
		)
		await self.send_to_client(
			session_id,
			{"type": "bridge.ended", "bridge_id": bridge.bridge_id, "reason": reason},
		)


media_hub = TelephonyMediaHub()
