"""ترجمه متای تریگرهای اتوماسیون اداری (fa/en) برای API ورک‌فلو."""
from __future__ import annotations

_COMMON_FA: dict[str, str] = {
	"field_enabled": "فعال‌بودن تریگر",
	"field_enabled_desc": "اگر خاموش باشد این ورک‌فلو با این تریگر اجرا نمی‌شود",
	"field_letter_kind_filter": "نوع نامه",
	"field_letter_kind_filter_desc": "incoming / outgoing / internal؛ خالی یعنی همه انواع",
	"field_confidentiality_filter": "سطح محرمانگی",
	"field_confidentiality_filter_desc": "normal / confidential / highly_confidential / secret؛ خالی یعنی همه سطوح",
	"field_cooldown_seconds": "حداقل فاصله بین اجرا (ثانیه)",
	"field_cooldown_seconds_desc": "پس از یک اجرا، تا این مدت تریگر دوباره برای همان ورک‌فلو اجرا نمی‌شود",
}

_COMMON_EN: dict[str, str] = {
	"field_enabled": "Trigger enabled",
	"field_enabled_desc": "When off, this workflow will not run for this trigger",
	"field_letter_kind_filter": "Letter kind",
	"field_letter_kind_filter_desc": "incoming / outgoing / internal; empty means all kinds",
	"field_confidentiality_filter": "Confidentiality",
	"field_confidentiality_filter_desc": "normal / confidential / highly_confidential / secret; empty means all levels",
	"field_cooldown_seconds": "Minimum cooldown (seconds)",
	"field_cooldown_seconds_desc": "After a run, suppress retriggers for this workflow until this interval passes",
}

OA_LETTER_REGISTERED_TRANSLATIONS: dict[str, dict[str, str]] = {
	"fa": {
		"trigger_name": "ثبت نامه در دبیرخانه",
		"trigger_description": "پس از شماره‌گذاری نامه در دبیرخانه",
		**_COMMON_FA,
	},
	"en": {
		"trigger_name": "Office letter registered",
		"trigger_description": "After the letter is numbered by the secretariat",
		**_COMMON_EN,
	},
}

OA_LETTER_REFERRED_TRANSLATIONS: dict[str, dict[str, str]] = {
	"fa": {
		"trigger_name": "ارجاع نامه",
		"trigger_description": "پس از ارجاع نامه به کارتابل سمت",
		**_COMMON_FA,
	},
	"en": {
		"trigger_name": "Office letter referred",
		"trigger_description": "After the letter is referred to a position inbox",
		**_COMMON_EN,
	},
}

OA_LETTER_ARCHIVED_TRANSLATIONS: dict[str, dict[str, str]] = {
	"fa": {
		"trigger_name": "بایگانی نامه",
		"trigger_description": "پس از بایگانی نامه در پرونده",
		**_COMMON_FA,
	},
	"en": {
		"trigger_name": "Office letter archived",
		"trigger_description": "After the letter is filed in the archive",
		**_COMMON_EN,
	},
}

OA_LETTER_DISPATCHED_TRANSLATIONS: dict[str, dict[str, str]] = {
	"fa": {
		"trigger_name": "ابلاغ نامه",
		"trigger_description": "پس از ابلاغ رسمی نامه به سمت مخاطب",
		**_COMMON_FA,
	},
	"en": {
		"trigger_name": "Office letter dispatched",
		"trigger_description": "After an official dispatch (ابلاغ) to a position",
		**_COMMON_EN,
	},
}

OA_LETTER_SIGNED_TRANSLATIONS: dict[str, dict[str, str]] = {
	"fa": {
		"trigger_name": "امضای نامه",
		"trigger_description": "پس از امضای یک مرحله از مسیر تأیید",
		**_COMMON_FA,
	},
	"en": {
		"trigger_name": "Office letter signed",
		"trigger_description": "After a signature step on the approval path is completed",
		**_COMMON_EN,
	},
}
