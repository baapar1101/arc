from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Integer, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class Account(Base):
	__tablename__ = "accounts"
	__table_args__ = (
		UniqueConstraint('business_id', 'code', name='uq_accounts_business_code'),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
	business_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=True, index=True)
	account_type: Mapped[str] = mapped_column(String(50), nullable=False)
	code: Mapped[str] = mapped_column(String(50), nullable=False)
	parent_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True, index=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	# Relationships
	business = relationship("Business", back_populates="accounts")
	parent = relationship("Account", remote_side="Account.id", back_populates="children")
	children = relationship("Account", back_populates="parent", cascade="all, delete-orphan")
	document_lines = relationship("DocumentLine", back_populates="account")


