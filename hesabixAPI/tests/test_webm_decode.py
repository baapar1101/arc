from __future__ import annotations

import pytest

from app.services.voice.webm_decode import WebmOpusStreamDecoder, webm_opus_available


def test_webm_opus_available_flag() -> None:
	assert isinstance(webm_opus_available(), bool)


@pytest.mark.skipif(not webm_opus_available(), reason="PyAV not installed")
def test_webm_decoder_empty_chunk() -> None:
	decoder = WebmOpusStreamDecoder(16000)
	assert decoder.feed(b"") == b""


@pytest.mark.skipif(not webm_opus_available(), reason="PyAV not installed")
def test_webm_decoder_reset() -> None:
	decoder = WebmOpusStreamDecoder(16000)
	decoder._buffer.extend(b"dummy")
	decoder.reset()
	assert len(decoder._buffer) == 0
