from __future__ import annotations

from datetime import datetime
from enum import Enum

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, Numeric, String, Text, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class AISkillSourceType(str, Enum):
    """منبع مهارت — سازگار با agentskills.io و Anthropic."""

    PORTABLE = "portable"
    ANTHROPIC_PREBUILT = "anthropic_prebuilt"
    HESABIX_NATIVE = "hesabix_native"


class AISkillVisibility(str, Enum):
    """وضعیت انتشار مهارت."""

    DRAFT = "draft"
    BUSINESS_ONLY = "business_only"
    PENDING_REVIEW = "pending_review"
    PUBLISHED = "published"
    HIDDEN = "hidden"


class AISkillPackage(Base):
    """بسته مهارت — import ZIP، ساخت محلی، یا prebuilt Anthropic."""

    __tablename__ = "ai_skill_packages"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    skill_slug: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    skill_body: Mapped[str] = mapped_column(Text, nullable=False, default="")

    source_type: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=AISkillSourceType.PORTABLE.value,
        index=True,
    )
    anthropic_skill_id: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)

    bundle_files: Mapped[dict | None] = mapped_column(
        JSON,
        nullable=True,
        comment="فایل‌های bundle: path -> {content, encoding}",
    )
    allowed_tool_names: Mapped[list | None] = mapped_column(JSON, nullable=True)
    compatibility_report: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    has_scripts: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    publisher_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    publisher_business_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="SET NULL"), nullable=True, index=True
    )
    owner_business_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
        comment="کسب‌وکار مالک draft/local",
    )

    visibility: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=AISkillVisibility.DRAFT.value,
        index=True,
    )
    version_label: Mapped[str] = mapped_column(String(64), nullable=False, default="1.0.0")
    changelog: Mapped[str | None] = mapped_column(Text, nullable=True)
    tags: Mapped[list | None] = mapped_column(JSON, nullable=True)
    short_description: Mapped[str | None] = mapped_column(Text, nullable=True)
    long_description: Mapped[str | None] = mapped_column(Text, nullable=True)

    price_amount: Mapped[float | None] = mapped_column(Numeric(18, 2), nullable=True)
    currency_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("currencies.id", ondelete="SET NULL"), nullable=True, index=True
    )
    is_official: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, index=True)
    source_repo_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)

    install_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    published_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    __table_args__ = (
        Index("ix_ai_skill_pkg_vis_published", "visibility", "published_at"),
    )


class AISkillPurchase(Base):
    """خرید مهارت پولی برای یک کسب‌وکار."""

    __tablename__ = "ai_skill_purchases"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    package_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("ai_skill_packages.id", ondelete="CASCADE"), nullable=False, index=True
    )
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
    currency_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("currencies.id", ondelete="SET NULL"), nullable=True
    )
    wallet_transaction_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("wallet_transactions.id", ondelete="SET NULL"), nullable=True, index=True
    )
    publisher_amount: Mapped[float | None] = mapped_column(Numeric(18, 2), nullable=True)
    platform_fee: Mapped[float | None] = mapped_column(Numeric(18, 2), nullable=True)
    publisher_wallet_transaction_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("wallet_transactions.id", ondelete="SET NULL"), nullable=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

    __table_args__ = (
        Index("ix_ai_skill_purchase_biz_pkg", "business_id", "package_id", unique=True),
    )


class AISkillReview(Base):
    """امتیاز و نظر کاربران روی مهارت مارکت‌پلیس."""

    __tablename__ = "ai_skill_reviews"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    package_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("ai_skill_packages.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    rating: Mapped[int] = mapped_column(Integer, nullable=False)
    comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    __table_args__ = (
        Index("ix_ai_skill_review_pkg_user", "package_id", "user_id", unique=True),
    )


class AISkillInstall(Base):
    """نصب مهارت در یک کسب‌وکار — فعال/غیرفعال داینامیک."""

    __tablename__ = "ai_skill_installs"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    package_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("ai_skill_packages.id", ondelete="CASCADE"), nullable=False, index=True
    )
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    installed_by_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    is_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    custom_title: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    package = relationship("AISkillPackage", backref="installs")

    __table_args__ = (
        Index("ix_ai_skill_install_biz_pkg", "business_id", "package_id", unique=True),
    )
