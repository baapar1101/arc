from __future__ import annotations

from typing import Any, Callable

from fastapi import Request
from .i18n_catalog import get_gettext_translation


SUPPORTED_LOCALES: tuple[str, ...] = ("fa", "en")
DEFAULT_LOCALE: str = "en"


def negotiate_locale(accept_language: str | None) -> str:
	if not accept_language:
		return DEFAULT_LOCALE
	parts = [p.strip() for p in accept_language.split(",") if p.strip()]
	for part in parts:
		lang = part.split(";")[0].strip().lower()
		base = lang.split("-")[0]
		if lang in SUPPORTED_LOCALES:
			return lang
		if base in SUPPORTED_LOCALES:
			return base
	return DEFAULT_LOCALE


class Translator:
	def __init__(self, locale: str) -> None:
		self.locale = locale if locale in SUPPORTED_LOCALES else DEFAULT_LOCALE
		self._gt = get_gettext_translation(self.locale)

	_catalog: dict[str, dict[str, str]] = {
		"en": {
			"OK": "OK",
			"INVALID_CAPTCHA": "Invalid captcha code.",
			"INVALID_CREDENTIALS": "Invalid credentials.",
			"IDENTIFIER_REQUIRED": "Identifier is required.",
			"INVALID_IDENTIFIER": "Identifier must be a valid email or mobile number.",
			"EMAIL_IN_USE": "Email is already in use.",
			"MOBILE_IN_USE": "Mobile number is already in use.",
			"INVALID_MOBILE": "Invalid mobile number.",
			"ACCOUNT_DISABLED": "Your account is disabled.",
			"RESET_TOKEN_INVALID_OR_EXPIRED": "Reset token is invalid or expired.",
			"VALIDATION_ERROR": "Validation error",
			"STRING_TOO_SHORT": "String is too short",
			"STRING_TOO_LONG": "String is too long",
			"FIELD_REQUIRED": "Field is required",
			"INVALID_EMAIL": "Invalid email address",
			"HTTP_ERROR": "Request failed",
		},
		"fa": {
			"OK": "باشه",
			"INVALID_CAPTCHA": "کد امنیتی نامعتبر است.",
			"INVALID_CREDENTIALS": "ایمیل/موبایل یا رمز عبور نادرست است.",
			"IDENTIFIER_REQUIRED": "شناسه ورود الزامی است.",
			"INVALID_IDENTIFIER": "شناسه باید ایمیل یا شماره موبایل معتبر باشد.",
			"EMAIL_IN_USE": "این ایمیل قبلاً استفاده شده است.",
			"MOBILE_IN_USE": "این شماره موبایل قبلاً استفاده شده است.",
			"INVALID_MOBILE": "شماره موبایل نامعتبر است.",
			"ACCOUNT_DISABLED": "حساب کاربری شما غیرفعال است.",
			"RESET_TOKEN_INVALID_OR_EXPIRED": "توکن بازنشانی نامعتبر یا منقضی شده است.",
			"VALIDATION_ERROR": "خطای اعتبارسنجی",
			"STRING_TOO_SHORT": "رشته خیلی کوتاه است",
			"STRING_TOO_LONG": "رشته خیلی بلند است",
			"FIELD_REQUIRED": "فیلد الزامی است",
			"INVALID_EMAIL": "ایمیل نامعتبر است",
			"HTTP_ERROR": "درخواست ناموفق بود",
		},
	}

	def t(self, key: str, default: str | None = None) -> str:
		# 1) gettext domain (if present)
		try:
			if self._gt is not None:
				msg = self._gt.gettext(key)
				if msg and msg != key:
					return msg
		except Exception:
			pass
		# 2) in-memory catalog fallback
		catalog = self._catalog.get(self.locale) or {}
		if key in catalog:
			return catalog[key]
		return default or key


async def locale_dependency(request: Request) -> Translator:
	lang = negotiate_locale(request.headers.get("Accept-Language"))
	return Translator(lang)


