from __future__ import annotations

from datetime import datetime
from enum import Enum

from sqlalchemy import String, DateTime, Integer, ForeignKey, Text, JSON, Index
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class WorkflowMarketplacePackageStatus(str, Enum):
    """وضعیت بسته در مخزن"""

    DRAFT = "draft"
    PUBLISHED = "published"
    HIDDEN = "hidden"


class WorkflowMarketplacePackage(Base):
    """ورک‌فلو منتشرشده در مخزن (محتوای sanitize شده)"""

    __tablename__ = "workflow_marketplace_packages"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    source_workflow_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("workflows.id", ondelete="SET NULL"), nullable=True, index=True
    )
    publisher_user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=False, index=True
    )
    publisher_business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="SET NULL"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    short_description: Mapped[str | None] = mapped_column(Text, nullable=True)
    long_description: Mapped[str | None] = mapped_column(Text, nullable=True)
    tags: Mapped[list | None] = mapped_column(JSON, nullable=True, comment="لیست رشته تگ‌های مخزن")
    workflow_data: Mapped[dict] = mapped_column(JSON, nullable=False)
    settings: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    version_label: Mapped[str] = mapped_column(String(64), nullable=False, default="1.0.0")
    changelog: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=WorkflowMarketplacePackageStatus.PUBLISHED.value,
        index=True,
    )
    install_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    published_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    __table_args__ = (Index("ix_wf_mpkg_pub_status_published", "status", "published_at"),)


class WorkflowMarketplaceInstall(Base):
    """ثبت هر بار نصب ورک‌فلو از مخزن (برای ردیابی و آمار)"""

    __tablename__ = "workflow_marketplace_installs"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    package_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("workflow_marketplace_packages.id", ondelete="CASCADE"), nullable=False, index=True
    )
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    installed_workflow_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("workflows.id", ondelete="SET NULL"), nullable=True, index=True
    )
    installed_by_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
