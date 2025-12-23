from __future__ import annotations

from datetime import datetime
from sqlalchemy import Integer, DateTime, Text, String, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class AIVoiceInteraction(Base):
	"""
	ذخیره تعامل صوتی (اختیاری، فقط با رضایت کاربر) برای:
	- ارزیابی و بهبود کیفیت TTS در گذر زمان
	- قابلیت بازتولید و مقایسه مدل‌ها (A/B) در آینده

	نکته: در فاز اول، فقط متادیتا + مسیر فایل‌ها ذخیره می‌شود.
	"""

	__tablename__ = "ai_voice_interactions"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)

	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
	business_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="SET NULL"), index=True)
	ai_session_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("ai_chat_sessions.id", ondelete="SET NULL"), index=True
	)

	consent: Mapped[bool] = mapped_column(nullable=False, default=False)

	input_transcript: Mapped[str | None] = mapped_column(Text, nullable=True)
	input_audio_path: Mapped[str | None] = mapped_column(Text, nullable=True)

	assistant_text: Mapped[str | None] = mapped_column(Text, nullable=True)
	assistant_audio_path: Mapped[str | None] = mapped_column(Text, nullable=True)

	stt_model: Mapped[str | None] = mapped_column(String(255), nullable=True)
	tts_engine: Mapped[str | None] = mapped_column(String(64), nullable=True)
	tts_model: Mapped[str | None] = mapped_column(String(255), nullable=True)

	# بازخورد کاربر (اختیاری، برای رتبه‌بندی/انتخاب مدل‌های بهتر)
	rating: Mapped[int | None] = mapped_column(Integer, nullable=True)  # 1..5
	feedback_text: Mapped[str | None] = mapped_column(Text, nullable=True)

	# JSON serialized string for extra metadata (avoid JSON type for portability)
	meta_json: Mapped[str | None] = mapped_column(Text, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False, index=True)


