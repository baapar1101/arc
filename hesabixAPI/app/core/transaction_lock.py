from __future__ import annotations

"""
قفل‌های سطح دیتابیس برای جلوگیری از نشت سهمیهٔ ارسال OTP/SMS ناشی از race همزمان.
"""
from sqlalchemy import text
from sqlalchemy.orm import Session


def acquire_sms_rate_lock(db: Session, key: str) -> None:
	"""
	قفل تراکنشی (PostgreSQL: pg_advisory_xact_lock) تا پایان تراکنش جاری.
	مقدار key باید برای هر شناسهٔ ارسال (موبایل، ایمیل، user_id) یکتا باشد.
	"""
	bind = db.get_bind()
	if bind.dialect.name != "postgresql":
		return
	# hashtext و cast به bigint — پایدار برای رشتهٔ داده‌شده
	db.execute(
		text("SELECT pg_advisory_xact_lock((hashtext(CAST(:k AS text)))::bigint)"),
		{"k": key[:4000]},
	)
