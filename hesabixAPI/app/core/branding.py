"""ریبرندینگ محصول از ‎.deploy_env و پک لوگو (همان منبع Flutter / CLI)."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

_CUSTOM_MODES = frozenset({"custom", "yes", "on", "1", "true"})
_DEFAULT_MODES = frozenset({"", "default", "hesabix", "off", "none", "0"})
_DEFAULT_DEPLOY_ENV = Path("/opt/hesabix/.deploy_env")
_LOGO_NAMES = (
	"logo-blue.png",
	"logo.png",
	"logo-light.png",
	"Icon-192.png",
	"Icon-512.png",
	"favicon.png",
)
_LOGO_SUBDIRS = ("logos", "images", "icons", ".")
_LOGO_CONTENT_TYPES = {
	".png": "image/png",
	".jpg": "image/jpeg",
	".jpeg": "image/jpeg",
	".webp": "image/webp",
	".gif": "image/gif",
	".ico": "image/x-icon",
}
_MAX_LOGO_BYTES = 2 * 1024 * 1024


def deploy_env_path() -> Path:
	raw = (
		os.environ.get("HESABIX_DEPLOY_ENV")
		or os.environ.get("HESABIX_DEPLOY_ENV_FILE")
		or ""
	).strip()
	return Path(raw) if raw else _DEFAULT_DEPLOY_ENV


def parse_env_assignments(path: Path) -> Dict[str, str]:
	out: Dict[str, str] = {}
	try:
		raw = path.read_text(encoding="utf-8", errors="replace")
	except OSError:
		return out
	for line in raw.splitlines():
		text = line.strip()
		if not text or text.startswith("#") or "=" not in text:
			continue
		key, _, value = text.partition("=")
		out[key.strip()] = value.strip().strip('"').strip("'")
	return out


def normalize_branding_mode(raw: str) -> str:
	mode = (raw or "").strip().lower().replace(" ", "")
	if mode in _DEFAULT_MODES:
		return "default"
	if mode in _CUSTOM_MODES:
		return "custom"
	return "default"


def names_from_branding_json(directory: str) -> tuple[str, str]:
	root = Path(directory)
	for candidate in (root / "names.json", root / "meta" / "names.json"):
		if not candidate.is_file():
			continue
		try:
			data = json.loads(candidate.read_text(encoding="utf-8"))
		except (OSError, json.JSONDecodeError, TypeError, ValueError):
			continue
		if not isinstance(data, dict):
			continue
		fa = str(data.get("fa") or data.get("fa_IR") or data.get("persian") or "").strip()
		en = str(data.get("en") or data.get("en_US") or data.get("english") or "").strip()
		if fa or en:
			return fa, en
	return "", ""


def _find_logo_file(directory: str) -> Optional[Path]:
	root = Path(directory)
	if not root.is_dir():
		return None
	try:
		root_resolved = root.resolve()
	except OSError:
		return None
	for name in _LOGO_NAMES:
		for sub in _LOGO_SUBDIRS:
			candidate = root / name if sub == "." else root / sub / name
			if not candidate.is_file():
				continue
			try:
				resolved = candidate.resolve()
			except OSError:
				continue
			if root_resolved not in resolved.parents and resolved != root_resolved:
				continue
			if resolved.suffix.lower() not in _LOGO_CONTENT_TYPES:
				continue
			try:
				if resolved.stat().st_size > _MAX_LOGO_BYTES:
					continue
			except OSError:
				continue
			return resolved
	return None


@dataclass(frozen=True)
class BrandingState:
	mode: str
	name_fa: str
	name_en: str
	branding_dir: str
	logo_path: Optional[Path]

	@property
	def enabled(self) -> bool:
		return self.mode == "custom" and bool(
			self.name_fa or self.name_en or self.logo_path is not None
		)

	@property
	def has_logo(self) -> bool:
		return self.logo_path is not None and self.logo_path.is_file()


def resolve_branding_state() -> BrandingState:
	fa = (os.environ.get("APP_NAME_FA") or "").strip()
	en = (os.environ.get("APP_NAME_EN") or "").strip()
	mode_raw = (os.environ.get("BRANDING_MODE") or "").strip()
	branding_dir = (os.environ.get("BRANDING_DIR") or "").strip()

	env_path = deploy_env_path()
	if env_path.is_file():
		parsed = parse_env_assignments(env_path)
		mode_raw = (parsed.get("BRANDING_MODE") or mode_raw).strip() or mode_raw
		branding_dir = (parsed.get("BRANDING_DIR") or branding_dir).strip()
		if not fa:
			fa = (parsed.get("APP_NAME_FA") or "").strip()
		if not en:
			en = (parsed.get("APP_NAME_EN") or "").strip()

	mode = normalize_branding_mode(mode_raw)
	if mode != "custom":
		return BrandingState(
			mode="default",
			name_fa="",
			name_en="",
			branding_dir=branding_dir,
			logo_path=None,
		)

	if branding_dir and (not fa or not en):
		json_fa, json_en = names_from_branding_json(branding_dir)
		fa = fa or json_fa
		en = en or json_en

	logo_path = _find_logo_file(branding_dir) if branding_dir else None
	if not fa and not en and logo_path is None:
		return BrandingState(
			mode="default",
			name_fa="",
			name_en="",
			branding_dir=branding_dir,
			logo_path=None,
		)

	return BrandingState(
		mode="custom",
		name_fa=fa,
		name_en=en,
		branding_dir=branding_dir,
		logo_path=logo_path,
	)


def branding_display_names() -> tuple[str, str]:
	"""نام فارسی/انگلیسی ریبرند از env یا ‎.deploy_env (همان منبع Flutter)."""
	state = resolve_branding_state()
	if not state.enabled:
		return "", ""
	return state.name_fa, state.name_en


def logo_content_type(path: Path) -> str:
	return _LOGO_CONTENT_TYPES.get(path.suffix.lower(), "application/octet-stream")


def logo_etag(path: Path) -> str:
	stat = path.stat()
	return f'W/"{stat.st_mtime_ns:x}-{stat.st_size:x}"'


def _normalize_etag_token(value: str) -> str:
	token = (value or "").strip()
	if token.lower().startswith("w/"):
		token = token[2:].strip()
	if len(token) >= 2 and token[0] == '"' and token[-1] == '"':
		token = token[1:-1]
	return token


def etags_match(if_none_match: str | None, current: str) -> bool:
	sent = (if_none_match or "").strip()
	if not sent or not current:
		return False
	want = _normalize_etag_token(current)
	for part in sent.split(","):
		if _normalize_etag_token(part) == want:
			return True
	return False


def branding_public_payload() -> Dict[str, Any]:
	state = resolve_branding_state()
	payload: Dict[str, Any] = {
		"enabled": state.enabled,
		"mode": "custom" if state.enabled else "default",
		"name_fa": state.name_fa if state.enabled else "",
		"name_en": state.name_en if state.enabled else "",
		"has_logo": bool(state.enabled and state.has_logo),
		"logo_etag": None,
		"logo_content_type": None,
	}
	if payload["has_logo"] and state.logo_path is not None:
		payload["logo_etag"] = logo_etag(state.logo_path)
		payload["logo_content_type"] = logo_content_type(state.logo_path)
	return payload
