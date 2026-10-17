"""قفل‌های تراکنشی نام‌دار برای سری‌کردن عملیات همزمان حساس."""

from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.orm import Session


def acquire_transaction_lock(db: Session, key: str) -> None:
	"""قفل تراکنشی نام‌دار را تا پایان تراکنش جاری نگه می‌دارد."""
	bind = db.get_bind()
	if bind.dialect.name != "postgresql":
		return
	# hashtext و cast به bigint — پایدار برای رشتهٔ داده‌شده
	db.execute(
		text("SELECT pg_advisory_xact_lock((hashtext(CAST(:k AS text)))::bigint)"),
		{"k": key[:4000]},
	)


def acquire_sms_rate_lock(db: Session, key: str) -> None:
	"""سازگاری با فراخوان‌های قدیمی محدودکنندهٔ پیامک."""
	acquire_transaction_lock(db, key)
