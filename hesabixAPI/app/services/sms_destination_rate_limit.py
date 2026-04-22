from __future__ import annotations

import logging
import random
from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from adapters.db.models.sms_destination_send_log import SmsDestinationSendLog
from adapters.db.session import SessionLocal
from app.core.transaction_lock import acquire_sms_rate_lock
from app.services.system_settings_service import get_sms_destination_rate_effective

logger = logging.getLogger(__name__)


def check_and_record_destination_sms(normalized_destination_phone: str) -> Optional[str]:
	"""
	سقف نرخ سراسری به‌ازای شماره مقصد (در دیتابیس، مشترک بین همه worker حتی بدون Redis).

	Returns:
		None اگر مجاز باشد؛ رشته پیام خطا (فارسی) اگر از سقف گذشته باشد.
	"""
	phone = (normalized_destination_phone or "").strip()
	if not phone:
		return None

	# گاهی رکوردهای قدیمی را حذف کن تا جدول رشد بی‌رویه نداشته باشد
	prune_cutoff = datetime.utcnow() - timedelta(days=14)

	try:
		with SessionLocal() as db:  # type: Session
			enabled, max_sends, window_minutes = get_sms_destination_rate_effective(db)
			if not enabled:
				return None
			max_sends = int(max_sends or 0)
			window_minutes = int(window_minutes or 60)
			if max_sends <= 0:
				return None
			cutoff = datetime.utcnow() - timedelta(minutes=window_minutes)
			acquire_sms_rate_lock(db, f"sms_dest_global:{phone[:4000]}")
			cnt_stmt = select(func.count()).select_from(SmsDestinationSendLog).where(
				SmsDestinationSendLog.destination_phone == phone,
				SmsDestinationSendLog.created_at >= cutoff,
			)
			current = int(db.execute(cnt_stmt).scalar_one() or 0)
			if current >= max_sends:
				return (
					f"تعداد ارسال پیامک به این شماره در {window_minutes} دقیقه اخیر "
					f"بیش از حد مجاز ({max_sends}) است. لطفاً بعداً تلاش کنید."
				)
			if random.random() < 0.05:
				db.execute(delete(SmsDestinationSendLog).where(SmsDestinationSendLog.created_at < prune_cutoff))
			db.add(SmsDestinationSendLog(destination_phone=phone))
			db.commit()
		return None
	except Exception as e:
		logger.exception("sms_destination_rate_check_failed: %s (phone=%s)", e, phone)
		# در خطای DB ارسال را متوقف نمی‌کنیم (تا سرویس از کار نیافتد)؛ migration را اجرا کنید.
		return None
