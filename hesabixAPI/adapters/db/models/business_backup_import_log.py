from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class BusinessBackupImportLog(Base):
    """ثبت ایمپورت بکاپ (new_business) برای جلوگیری از تکرار همان فایل."""

    __tablename__ = "business_backup_import_logs"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "backup_checksum",
            "import_mode",
            name="uq_business_backup_import_user_checksum_mode",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    backup_checksum: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    import_mode: Mapped[str] = mapped_column(String(32), nullable=False, default="new_business")
    source_business_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="SET NULL"), nullable=True
    )
    target_business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
