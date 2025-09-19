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

	def t(self, key: str, default: str | None = None) -> str:
		"""Translate a key using gettext. Falls back to default or key if not found."""
		try:
			if self._gt is not None:
				msg = self._gt.gettext(key)
				if msg and msg != key:
					return msg
		except Exception:
			pass
		return default or key


async def locale_dependency(request: Request) -> Translator:
	lang = negotiate_locale(request.headers.get("Accept-Language"))
	return Translator(lang)


def get_translator(locale: str = "fa") -> Translator:
	"""Get translator for the given locale"""
	return Translator(locale)


