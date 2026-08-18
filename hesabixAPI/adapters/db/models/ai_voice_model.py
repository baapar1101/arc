from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class AIVoiceModel(Base):
	"""کاتالوگ موتورهای STT / TTS / realtime قابل ارائه به کاربران."""

	__tablename__ = "ai_voice_models"
	__table_args__ = (UniqueConstraint("code", name="uq_ai_voice_models_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	code: Mapped[str] = mapped_column(String(80), nullable=False, unique=True, index=True)
	kind: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
	display_name: Mapped[str] = mapped_column(String(255), nullable=False)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	provider: Mapped[str] = mapped_column(String(50), nullable=False, default="local")
	model_id: Mapped[str] = mapped_column(String(160), nullable=False)
	language: Mapped[str] = mapped_column(String(16), nullable=False, default="fa")
	voice_id: Mapped[str | None] = mapped_column(String(80), nullable=True)
	tier: Mapped[str | None] = mapped_column(String(50), nullable=True)
	reference_cost_per_minute: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
	reference_cost_per_1k_chars: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
	is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	extra_json: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class AIVoicePolicy(Base):
	"""سیاست سراسری صوت (یک ردیف)."""

	__tablename__ = "ai_voice_policy"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	allow_cloud_audio: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	default_stt_code: Mapped[str | None] = mapped_column(String(80), nullable=True)
	default_tts_code: Mapped[str | None] = mapped_column(String(80), nullable=True)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class BusinessAIVoiceSettings(Base):
	"""تنظیمات صوت هر کسب‌وکار (حریم ابر + انتخاب پیش‌فرض)."""

	__tablename__ = "business_ai_voice_settings"
	__table_args__ = (
		UniqueConstraint("business_id", name="uq_business_ai_voice_settings_business"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	allow_cloud_audio: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	preferred_stt_code: Mapped[str | None] = mapped_column(String(80), nullable=True)
	preferred_tts_code: Mapped[str | None] = mapped_column(String(80), nullable=True)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)
