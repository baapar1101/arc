from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class QuickSalesPaymentButton(Base):
    """دکمهٔ مقصد پرداخت در فروش سریع، مشترک یا شخصی."""

    __tablename__ = "quick_sales_payment_buttons"
    __table_args__ = (
        CheckConstraint(
            "scope IN ('business', 'user')",
            name="ck_qspb_scope",
        ),
        CheckConstraint(
            "(scope = 'business' AND owner_user_id IS NULL) OR "
            "(scope = 'user' AND owner_user_id IS NOT NULL)",
            name="ck_qspb_scope_owner",
        ),
        CheckConstraint(
            "(target_type = 'cash_register' AND cash_register_id IS NOT NULL "
            "AND bank_account_id IS NULL AND person_id IS NULL) OR "
            "(target_type = 'bank' AND bank_account_id IS NOT NULL "
            "AND cash_register_id IS NULL AND person_id IS NULL) OR "
            "(target_type = 'person' AND person_id IS NOT NULL "
            "AND cash_register_id IS NULL AND bank_account_id IS NULL)",
            name="ck_qspb_exact_target",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    scope: Mapped[str] = mapped_column(String(16), nullable=False, default="user")
    owner_user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    target_type: Mapped[str] = mapped_column(String(24), nullable=False)
    cash_register_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("cash_registers.id", ondelete="CASCADE"),
        nullable=True,
    )
    bank_account_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("bank_accounts.id", ondelete="CASCADE"),
        nullable=True,
    )
    person_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("persons.id", ondelete="CASCADE"),
        nullable=True,
    )
    label: Mapped[str | None] = mapped_column(String(120), nullable=True)
    shortcut: Mapped[str | None] = mapped_column(String(32), nullable=True)
    position: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_by_user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=datetime.utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow
    )
