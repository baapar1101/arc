"""قوانین عضویت زمانی کاربر در کسب‌وکار (جدول business_permissions)."""

from __future__ import annotations

from datetime import datetime, timezone

from adapters.db.models.business_permission import BusinessPermission


def to_naive_utc(dt: datetime) -> datetime:
	"""ذخیرهٔ یکسان در DB به صورت naive UTC."""
	if dt.tzinfo is not None:
		return dt.astimezone(timezone.utc).replace(tzinfo=None)
	return dt


def membership_is_active(permission: BusinessPermission, *, now: datetime | None = None) -> bool:
	"""
	عضویت زمانی فعال است.
	`membership_expires_at is None` یعنی نامحدود (رفتار پیش‌فرض برای ردیف‌های قدیمی).
	"""
	when = now or datetime.utcnow()
	expires = getattr(permission, "membership_expires_at", None)
	if expires is None:
		return True
	exp = to_naive_utc(expires) if expires.tzinfo is not None else expires
	return when < exp
