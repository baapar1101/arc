"""رنگ‌های برند تم‌های سراسری — هم‌تراز با کاتالوگ Flutter."""

from __future__ import annotations

from typing import Any, Dict

_THEME_PALETTES: Dict[str, Dict[str, str]] = {
	"classic_blue": {
		"primary": "#0F4C81",
		"secondary": "#5A6A7A",
		"positive": "#2E7D32",
		"negative": "#B3261E",
		"warning": "#F0B92A",
	},
	"turquoise_sea": {
		"primary": "#00A8BD",
		"secondary": "#4F546D",
		"positive": "#41B96B",
		"negative": "#EF2223",
		"warning": "#F0B92A",
	},
	"emerald_forest": {
		"primary": "#0F766E",
		"secondary": "#3F4A5A",
		"positive": "#41B96B",
		"negative": "#EF2223",
		"warning": "#F0B92A",
	},
	"warm_copper": {
		"primary": "#B45309",
		"secondary": "#4F546D",
		"positive": "#41B96B",
		"negative": "#EF2223",
		"warning": "#F0B92A",
	},
}


def normalize_theme_id(theme_id: str | None) -> str:
	key = str(theme_id or "").strip().lower()
	if key in _THEME_PALETTES:
		return key
	return "classic_blue"


def primary_hex_for_theme_id(theme_id: str | None) -> str:
	return _THEME_PALETTES[normalize_theme_id(theme_id)]["primary"]


def theme_palette_for_theme_id(theme_id: str | None) -> Dict[str, str]:
	"""پالت کامل تم برای قالب‌های HTML/PDF."""
	pal = dict(_THEME_PALETTES[normalize_theme_id(theme_id)])
	# نام‌های سازگار با قالب‌ها
	return {
		"brand_primary": pal["primary"],
		"brand_secondary": pal["secondary"],
		"brand_positive": pal["positive"],
		"brand_negative": pal["negative"],
		"brand_warning": pal["warning"],
		**{f"theme_{k}": v for k, v in pal.items()},
	}


def resolve_theme_brand_context(db: Any | None = None) -> Dict[str, str]:
	"""خواندن تم پیش‌فرض سیستم و برگرداندن کلیدهای برند برای قالب‌ها."""
	theme_id = "classic_blue"
	if db is not None:
		try:
			from app.services.system_settings_service import get_default_theme_id

			theme_id = get_default_theme_id(db)
		except Exception:
			theme_id = "classic_blue"
	else:
		try:
			from adapters.db.session import get_db_session
			from app.services.system_settings_service import get_default_theme_id

			with get_db_session() as session:
				theme_id = get_default_theme_id(session)
		except Exception:
			theme_id = "classic_blue"
	return theme_palette_for_theme_id(theme_id)
