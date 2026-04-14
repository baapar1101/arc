from __future__ import annotations

from datetime import datetime
from enum import Enum

from sqlalchemy import String, DateTime, Integer, ForeignKey, Enum as SQLEnum, Text, Boolean, JSON, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class WorkflowStatus(str, Enum):
    """وضعیت workflow"""
    ACTIVE = "فعال"
    INACTIVE = "غیرفعال"
    DRAFT = "پیش‌نویس"


class WorkflowExecutionStatus(str, Enum):
    """وضعیت اجرای workflow"""
    PENDING = "در انتظار"
    RUNNING = "در حال اجرا"
    COMPLETED = "تکمیل شده"
    FAILED = "ناموفق"
    CANCELLED = "لغو شده"


class WorkflowNodeType(str, Enum):
    """نوع node در workflow"""
    TRIGGER = "trigger"  # شروع کننده
    ACTION = "action"  # عملیات
    CONDITION = "condition"  # شرط
    LOOP = "loop"  # حلقه


class WorkflowLogLevel(str, Enum):
    """سطح لاگ"""
    DEBUG = "debug"
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"


class Workflow(Base):
    """مدل workflow - تعریف یک workflow خودکار"""
    __tablename__ = "workflows"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True, comment="نام workflow")
    description: Mapped[str | None] = mapped_column(Text, nullable=True, comment="توضیحات")
    status: Mapped[WorkflowStatus] = mapped_column(
        SQLEnum(WorkflowStatus, values_callable=lambda obj: [e.value for e in obj]),
        nullable=False,
        default=WorkflowStatus.DRAFT,
        index=True,
        comment="وضعیت workflow"
    )
    # ساختار workflow به صورت JSON (nodes و connections)
    workflow_data: Mapped[dict] = mapped_column(JSON, nullable=False, comment="ساختار workflow (nodes, connections)")
    # تنظیمات workflow
    settings: Mapped[dict | None] = mapped_column(JSON, nullable=True, comment="تنظیمات workflow")
    created_by_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relationships
    executions: Mapped[list["WorkflowExecution"]] = relationship(
        "WorkflowExecution", back_populates="workflow", cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index("idx_workflows_business_status", "business_id", "status"),
    )


class WorkflowExecution(Base):
    """مدل اجرای workflow - هر بار که workflow اجرا می‌شود"""
    __tablename__ = "workflow_executions"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    workflow_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("workflows.id", ondelete="CASCADE"), nullable=False, index=True
    )
    status: Mapped[WorkflowExecutionStatus] = mapped_column(
        SQLEnum(WorkflowExecutionStatus, values_callable=lambda obj: [e.value for e in obj]),
        nullable=False,
        default=WorkflowExecutionStatus.PENDING,
        index=True,
        comment="وضعیت اجرا"
    )
    # داده‌های ورودی trigger
    trigger_data: Mapped[dict | None] = mapped_column(JSON, nullable=True, comment="داده‌های trigger")
    # داده‌های خروجی و میانی
    execution_data: Mapped[dict | None] = mapped_column(JSON, nullable=True, comment="داده‌های اجرا")
    # پیام خطا در صورت ناموفق بودن
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True, comment="پیام خطا")
    started_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, comment="زمان شروع")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, comment="زمان پایان")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

    # Relationships
    workflow: Mapped["Workflow"] = relationship("Workflow", back_populates="executions")
    logs: Mapped[list["WorkflowLog"]] = relationship(
        "WorkflowLog", back_populates="execution", cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index("idx_workflow_executions_workflow_status", "workflow_id", "status"),
        Index("idx_workflow_executions_created", "created_at"),
    )


class WorkflowLog(Base):
    """مدل لاگ workflow - ثبت رویدادهای اجرای workflow"""
    __tablename__ = "workflow_logs"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    execution_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("workflow_executions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    node_id: Mapped[str | None] = mapped_column(String(100), nullable=True, index=True, comment="شناسه node")
    level: Mapped[WorkflowLogLevel] = mapped_column(
        SQLEnum(WorkflowLogLevel, values_callable=lambda obj: [e.value for e in obj]),
        nullable=False,
        default=WorkflowLogLevel.INFO,
        index=True,
        comment="سطح لاگ"
    )
    message: Mapped[str] = mapped_column(Text, nullable=False, comment="پیام لاگ")
    data: Mapped[dict | None] = mapped_column(JSON, nullable=True, comment="داده‌های اضافی")
    timestamp: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    # Relationships
    execution: Mapped["WorkflowExecution"] = relationship("WorkflowExecution", back_populates="logs")

    __table_args__ = (
        Index("idx_workflow_logs_execution_timestamp", "execution_id", "timestamp"),
    )

