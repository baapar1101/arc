from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Integer, DateTime, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class SystemSetting(Base):
	__tablename__ = "system_settings"
	__table_args__ = (
		UniqueConstraint('key', name='uq_system_settings_key'),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)

	# کلید یکتا
	key: Mapped[str] = mapped_column(String(100), nullable=False, index=True)

	# مقادیر قابل نگهداری (یکی از این‌ها استفاده می‌شود)
	value_string: Mapped[str | None] = mapped_column(String(255), nullable=True)
	value_int: Mapped[int | None] = mapped_column(Integer, nullable=True)
	value_json: Mapped[str | None] = mapped_column(Text, nullable=True)

	# زمان‌بندی
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


