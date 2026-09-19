"""تست‌های واحد Softphone Media Hub و پروفایل فریم."""
from __future__ import annotations

from app.services.telephony.media_hub import TelephonyMediaHub


def test_pcm_frame_roundtrip():
	hub = TelephonyMediaHub()
	sid = "11111111-2222-3333-4444-555555555555"
	pcm = b"\x00\x01" * 160
	blob = hub.pack_pcm_frame(sid, pcm, direction_type=1)
	parsed = hub.unpack_pcm_frame(blob)
	assert parsed is not None
	ftype, out_sid, out_pcm = parsed
	assert ftype == 1
	assert out_sid == sid
	assert out_pcm == pcm


def test_pcm_frame_rejects_short():
	hub = TelephonyMediaHub()
	assert hub.unpack_pcm_frame(b"nope") is None
	assert hub.unpack_pcm_frame(b"HSXM" + b"\x00" * 10) is None


def test_media_hub_health_shape():
	hub = TelephonyMediaHub()
	h = hub.health()
	assert "node_id" in h
	assert "pcm_ws_v1" in h["supported_profiles"]
	assert h["clients"] == 0
	assert h["tunnels"] == 0
