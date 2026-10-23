from pathlib import Path

from app.services import captcha_service


def test_captcha_font_candidates_keep_linux_font_first(
	monkeypatch,
) -> None:
	monkeypatch.delenv("WINDIR", raising=False)

	candidates = captcha_service._captcha_font_candidates()

	assert candidates[0] == Path(
		"/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
	)
	assert candidates[-1] == captcha_service._BUNDLED_CAPTCHA_FONT


def test_captcha_font_candidates_include_windows_fonts(
	monkeypatch,
) -> None:
	windows_dir = r"C:\Windows"
	monkeypatch.setenv("WINDIR", windows_dir)

	candidates = captcha_service._captcha_font_candidates()
	fonts_dir = Path(windows_dir) / "Fonts"

	assert fonts_dir / "arialbd.ttf" in candidates
	assert fonts_dir / "segoeuib.ttf" in candidates


def test_load_captcha_font_skips_missing_candidate(
	monkeypatch,
	tmp_path,
) -> None:
	missing_font = tmp_path / "missing.ttf"
	available_font = tmp_path / "available.ttf"
	available_font.write_bytes(b"test-font")

	expected_font = object()
	loaded: list[tuple[Path, int]] = []

	def fake_truetype(path: str, size: int):
		loaded.append((Path(path), size))
		return expected_font

	monkeypatch.setattr(
		captcha_service,
		"_captcha_font_candidates",
		lambda: (missing_font, available_font),
	)
	monkeypatch.setattr(
		captcha_service.ImageFont,
		"truetype",
		fake_truetype,
	)

	font = captcha_service._load_captcha_font(26)

	assert font is expected_font
	assert loaded == [(available_font, 26)]