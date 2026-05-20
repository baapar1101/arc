"""ابزارهای کمکی کاتالوگ عمومی (بدون وابستگی به Session)."""

from __future__ import annotations

import uuid as uuid_module


def normalize_catalog_public_uuid(raw: str) -> str:
	"""
	اعتبارسنجی و نرمال‌سازی UUID (همان قالب استاندارد با خط تیره).
	raises ValueError: رشتهٔ خالی یا UUID نامعتبر
	"""
	s = (raw or "").strip()
	if not s:
		raise ValueError("empty_uuid")
	return str(uuid_module.UUID(s))
