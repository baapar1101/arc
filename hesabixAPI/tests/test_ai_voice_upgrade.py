from app.services.voice.audio_wav import looks_like_wav, pcm16_to_wav, wav_to_pcm16
from app.services.voice.contracts import provider_is_cloud
from app.services.voice.session_limit import VoiceSessionGuard, reset_voice_session_limits_for_tests
from app.services.voice.tts import DummyTTSEngine
from app.services.voice.voice_catalog import env_fallback_catalog_items


def test_pcm_wav_roundtrip():
	pcm = b"\x00\x01" * 160
	wav = pcm16_to_wav(pcm, 16000)
	assert looks_like_wav(wav)
	out, rate, channels = wav_to_pcm16(wav)
	assert out == pcm
	assert rate == 16000
	assert channels == 1


def test_provider_is_cloud():
	assert provider_is_cloud("openai") is True
	assert provider_is_cloud("local") is False
	assert provider_is_cloud("dummy") is False
	assert provider_is_cloud("piper") is False


def test_dummy_tts_async_silence():
	import asyncio

	engine = DummyTTSEngine(16000)
	pcm, sr = asyncio.run(engine.synthesize_pcm16_async("سلام"))
	assert sr == 16000
	assert len(pcm) > 0
	assert pcm == b"\x00\x00" * (len(pcm) // 2)


def test_env_fallback_catalog_has_stt_and_tts():
	stt, tts = env_fallback_catalog_items()
	assert stt["kind"] == "stt"
	assert tts["kind"] == "tts"
	assert stt["code"]
	assert tts["code"]


def test_voice_session_limit(monkeypatch):
	reset_voice_session_limits_for_tests()

	class _S:
		voice_max_concurrent_sessions_per_user = 1

	monkeypatch.setattr("app.services.voice.session_limit.get_settings", lambda: _S())

	async def _run():
		g1 = VoiceSessionGuard(7)
		await g1.acquire()
		g2 = VoiceSessionGuard(7)
		raised = False
		try:
			await g2.acquire()
		except Exception as exc:
			raised = getattr(exc, "error_code", "") == "VOICE_SESSION_LIMIT"
		await g1.release()
		g3 = VoiceSessionGuard(7)
		await g3.acquire()
		await g3.release()
		return raised

	import asyncio

	assert asyncio.run(_run()) is True
	reset_voice_session_limits_for_tests()
