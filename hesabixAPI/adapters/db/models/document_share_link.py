from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    Integer,
    String,
    DateTime,
    ForeignKey,
    UniqueConstraint,
    Index,
    JSON,
)
from sqlalchemy.ext.hybrid import hybrid_property
from sqlalchemy.orm import Mapped, mapped_column, relationship, backref

from adapters.db.session import Base


class DocumentShareLink(Base):
    """
    لینک عمومی مشاهده/اعتبارسنجی فاکتور (سند) — مشابه person_share_links.
    """

    __tablename__ = "document_share_links"
    __table_args__ = (
        UniqueConstraint("code", name="uq_document_share_links_code"),
        Index("ix_document_share_links_code", "code"),
        Index("ix_document_share_links_document_id", "document_id"),
        Index("ix_document_share_links_business_id", "business_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
    )
    document_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("documents.id", ondelete="CASCADE"), nullable=False
    )
    created_by_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    revoked_by_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    code: Mapped[str] = mapped_column(String(16), nullable=False, unique=True)
    token_hash: Mapped[str] = mapped_column(String(128), nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False
    )
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_view_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    view_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    max_view_count: Mapped[int | None] = mapped_column(Integer, nullable=True)

    options: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    meta: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    business = relationship("Business", backref="document_share_links")
    # passive_deletes: با حذف سند، DB با ON DELETE CASCADE لینک‌ها را حذف می‌کند؛
    # بدون این، ORM تلاش می‌کند document_id را NULL کند و با NOT NULL برخورد می‌کند.
    document = relationship(
        "Document",
        backref=backref("share_links", passive_deletes=True),
    )
    created_by = relationship("User", foreign_keys=[created_by_user_id])
    revoked_by = relationship("User", foreign_keys=[revoked_by_user_id])

    @hybrid_property
    def is_revoked(self) -> bool:
        return self.revoked_at is not None

    @hybrid_property
    def is_expired(self) -> bool:
        if self.expires_at is None:
            return False
        return datetime.utcnow() >= self.expires_at

    @hybrid_property
    def is_view_limited(self) -> bool:
        return self.max_view_count is not None and self.view_count >= self.max_view_count

    @hybrid_property
    def is_active(self) -> bool:
        return not (self.is_revoked or self.is_expired or self.is_view_limited)
