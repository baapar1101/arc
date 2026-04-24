from __future__ import annotations

from datetime import datetime

from sqlalchemy import BigInteger, String, DateTime, Index
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class SmsDestinationSendLog(Base):
	"""
	ثبت هر تلاش ارسال SMS به یک شماره مقصد (برای سقف نرخ سراسری به‌ازای مقصد، مستقل از IP).
	"""

	__tablename__ = "sms_destination_send_logs"
	__table_args__ = (
		Index("ix_sms_dest_phone_created", "destination_phone", "created_at"),
	)

	id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
	destination_phone: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False, index=True)
