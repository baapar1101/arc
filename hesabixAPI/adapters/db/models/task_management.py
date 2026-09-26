from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    JSON,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


def _utc_now() -> datetime:
    """UTC-aware timestamp for the task-management domain."""
    return datetime.now(timezone.utc)


class ProjectMember(Base):
    """Membership and task-planning role inside an existing accounting project."""

    __tablename__ = "project_members"
    __table_args__ = (
        UniqueConstraint("project_id", "user_id", name="uq_project_members_project_user"),
        CheckConstraint(
            "role IN ('viewer','member','manager','owner')",
            name="ck_project_members_role",
        ),
        Index("ix_project_members_user_project", "user_id", "project_id"),
        Index("ix_project_members_business_project", "business_id", "project_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    project_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("projects.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    role: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="member",
        server_default="member",
    )
    added_by_user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        nullable=False,
    )

    project = relationship("Project")
    user = relationship("User", foreign_keys=[user_id])
    added_by = relationship("User", foreign_keys=[added_by_user_id])


class TaskStatus(Base):
    """Business-scoped workflow state; compatible with Plane-style board grouping."""

    __tablename__ = "task_statuses"
    __table_args__ = (
        UniqueConstraint("business_id", "key", name="uq_task_statuses_business_key"),
        CheckConstraint(
            "category IN ('backlog','unstarted','started','completed','cancelled')",
            name="ck_task_statuses_category",
        ),
        Index("ix_task_statuses_business_order", "business_id", "sort_order"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    key: Mapped[str] = mapped_column(String(40), nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    category: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="unstarted",
        server_default="unstarted",
    )
    color: Mapped[str | None] = mapped_column(String(20), nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    is_closed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
        nullable=False,
    )

    business = relationship("Business")


class TaskLabel(Base):
    """Reusable business-scoped task label."""

    __tablename__ = "task_labels"
    __table_args__ = (
        UniqueConstraint("business_id", "name", name="uq_task_labels_business_name"),
        Index("ix_task_labels_business_name", "business_id", "name"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    color: Mapped[str | None] = mapped_column(String(20), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
        nullable=False,
    )

    business = relationship("Business")


class TaskSavedView(Base):
    """User-owned structured task filter/view configuration."""

    __tablename__ = "task_saved_views"
    __table_args__ = (
        UniqueConstraint(
            "business_id",
            "user_id",
            "name",
            name="uq_task_saved_views_business_user_name",
        ),
        Index(
            "ix_task_saved_views_business_user",
            "business_id",
            "user_id",
        ),
        Index(
            "ix_task_saved_views_business_project",
            "business_id",
            "project_id",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    project_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("projects.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    view_type: Mapped[str] = mapped_column(
        String(30),
        nullable=False,
        default="list",
        server_default="list",
    )
    filters_json: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    sort_json: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    is_shared: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
        nullable=False,
    )

    business = relationship("Business")
    user = relationship("User")
    project = relationship("Project")


class Task(Base):
    """First-class task/work-item independent from CRM activity logs."""

    __tablename__ = "tasks"
    __table_args__ = (
        CheckConstraint(
            "priority IN ('low','normal','high','urgent')",
            name="ck_tasks_priority",
        ),
        CheckConstraint(
            "estimated_minutes IS NULL OR estimated_minutes >= 0",
            name="ck_tasks_estimated_minutes",
        ),
        CheckConstraint(
            "parent_task_id IS NULL OR parent_task_id <> id",
            name="ck_tasks_not_own_parent",
        ),
        CheckConstraint(
            "due_at IS NULL OR start_at IS NULL OR due_at >= start_at",
            name="ck_tasks_dates",
        ),
        Index("ix_tasks_biz_deleted_due", "business_id", "deleted_at", "due_at"),
        Index("ix_tasks_biz_project_pos", "business_id", "project_id", "sort_order"),
        Index("ix_tasks_biz_status_pos", "business_id", "status_id", "sort_order"),
        Index("ix_tasks_parent_task", "parent_task_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    project_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("projects.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    parent_task_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("tasks.id", ondelete="SET NULL"),
        nullable=True,
    )
    status_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("task_statuses.id", ondelete="RESTRICT"),
        nullable=True,
        index=True,
    )
    milestone_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("project_milestones.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    title: Mapped[str] = mapped_column(String(500), nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    priority: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="normal",
        server_default="normal",
        index=True,
    )
    sort_order: Mapped[Decimal] = mapped_column(
        Numeric(20, 6),
        nullable=False,
        default=0,
        server_default="0",
    )

    start_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    due_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    estimated_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # Recurrence is stored as RFC 5545-style RRULE text and activated in Phase 8.
    recurrence_rule: Mapped[str | None] = mapped_column(String(512), nullable=True)
    recurrence_timezone: Mapped[str | None] = mapped_column(String(80), nullable=True)
    recurrence_end_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    created_by_user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
        nullable=False,
    )
    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)

    business = relationship("Business")
    project = relationship("Project")
    status = relationship("TaskStatus")
    milestone = relationship("Milestone", foreign_keys=[milestone_id])
    parent = relationship("Task", remote_side="Task.id", foreign_keys=[parent_task_id])
    created_by = relationship("User", foreign_keys=[created_by_user_id])


class TaskAssignee(Base):
    __tablename__ = "task_assignees"
    __table_args__ = (
        UniqueConstraint("task_id", "user_id", name="uq_task_assignees_task_user"),
        Index("ix_task_assignees_user_task", "user_id", "task_id"),
        Index("ix_task_assignees_business_user", "business_id", "user_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    task_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    assigned_by_user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    assigned_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)

    task = relationship("Task")
    user = relationship("User", foreign_keys=[user_id])
    assigned_by = relationship("User", foreign_keys=[assigned_by_user_id])


class TaskLabelLink(Base):
    __tablename__ = "task_label_links"
    __table_args__ = (
        UniqueConstraint("task_id", "label_id", name="uq_task_label_links_task_label"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    task_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    label_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("task_labels.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    task = relationship("Task")
    label = relationship("TaskLabel")


class TaskRelation(Base):
    """Directed relation. Inverse labels (for example blocked_by) are derived in services."""

    __tablename__ = "task_relations"
    __table_args__ = (
        UniqueConstraint(
            "task_id",
            "related_task_id",
            "relation_type",
            name="uq_task_relations_pair_type",
        ),
        CheckConstraint("task_id <> related_task_id", name="ck_task_relations_not_self"),
        CheckConstraint(
            "relation_type IN ('blocks','related','duplicates')",
            name="ck_task_relations_type",
        ),
        Index("ix_task_relations_related", "related_task_id", "relation_type"),
        Index("ix_task_relations_business_task", "business_id", "task_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    task_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    related_task_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    relation_type: Mapped[str] = mapped_column(String(20), nullable=False)
    created_by_user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)

    task = relationship("Task", foreign_keys=[task_id])
    related_task = relationship("Task", foreign_keys=[related_task_id])
    created_by = relationship("User", foreign_keys=[created_by_user_id])


class TaskComment(Base):
    __tablename__ = "task_comments"
    __table_args__ = (
        Index("ix_task_comments_task_created", "task_id", "created_at"),
        Index("ix_task_comments_business_task", "business_id", "task_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    task_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    author_user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
        nullable=False,
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    task = relationship("Task")
    author = relationship("User", foreign_keys=[author_user_id])


class TaskAttachment(Base):
    __tablename__ = "task_attachments"
    __table_args__ = (
        Index("ix_task_attachments_task_created", "task_id", "created_at"),
        Index("ix_task_attachments_business_task", "business_id", "task_id"),
        UniqueConstraint("task_id", "file_storage_id", name="uq_task_attachments_task_file"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    task_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    file_storage_id: Mapped[str | None] = mapped_column(
        String(36),
        ForeignKey("file_storage.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    storage_key: Mapped[str] = mapped_column(String(1024), nullable=False)
    original_name: Mapped[str] = mapped_column(String(512), nullable=False)
    mime_type: Mapped[str | None] = mapped_column(String(255), nullable=True)
    size_bytes: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    uploaded_by_user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)

    task = relationship("Task")
    file = relationship("FileStorage", foreign_keys=[file_storage_id])
    uploaded_by = relationship("User", foreign_keys=[uploaded_by_user_id])


class TaskReminder(Base):
    __tablename__ = "task_reminders"
    __table_args__ = (
        CheckConstraint(
            "offset_minutes IS NULL OR offset_minutes >= 0",
            name="ck_task_reminders_offset",
        ),
        Index("ix_task_reminders_user_due", "user_id", "remind_at", "sent_at"),
        Index("ix_task_reminders_task_due", "task_id", "remind_at"),
        Index("ix_task_reminders_business_due", "business_id", "remind_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    task_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    remind_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    relative_to: Mapped[str | None] = mapped_column(String(20), nullable=True)
    offset_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)

    task = relationship("Task")
    user = relationship("User", foreign_keys=[user_id])


class TaskActivity(Base):
    """Immutable task-domain event stream for audit/activity feeds."""

    __tablename__ = "task_activity_events"
    __table_args__ = (
        Index("ix_task_activity_task_created", "task_id", "created_at"),
        Index("ix_task_activity_business_created", "business_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    task_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    actor_user_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    event_type: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    event_data: Mapped[dict | None] = mapped_column("metadata_json", JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)

    business = relationship("Business")
    task = relationship("Task")
    actor = relationship("User", foreign_keys=[actor_user_id])

class Milestone(Base):
    """Project milestone used by timeline/Gantt and milestone planning."""

    __tablename__ = "project_milestones"
    __table_args__ = (
        CheckConstraint(
            "target_at IS NULL OR start_at IS NULL OR target_at >= start_at",
            name="ck_project_milestones_dates",
        ),
        Index("ix_project_milestones_project_target", "project_id", "target_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    project_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("projects.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    start_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    target_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="open", server_default="open")
    sort_order: Mapped[Decimal] = mapped_column(
        Numeric(20, 6), nullable=False, default=0, server_default="0"
    )
    created_by_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utc_now, onupdate=_utc_now, nullable=False
    )

    project = relationship("Project")
    created_by = relationship("User", foreign_keys=[created_by_user_id])


class ProjectCycle(Base):
    """Plane-style cycle / sprint planning container."""

    __tablename__ = "project_cycles"
    __table_args__ = (
        CheckConstraint(
            "end_at IS NULL OR start_at IS NULL OR end_at >= start_at",
            name="ck_project_cycles_dates",
        ),
        Index("ix_project_cycles_project_dates", "project_id", "start_at", "end_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    project_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("projects.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    goal: Mapped[str | None] = mapped_column(Text, nullable=True)
    start_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    end_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="planned", server_default="planned"
    )
    created_by_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utc_now, onupdate=_utc_now, nullable=False
    )

    project = relationship("Project")
    created_by = relationship("User", foreign_keys=[created_by_user_id])


class ProjectCycleTask(Base):
    __tablename__ = "project_cycle_tasks"
    __table_args__ = (
        UniqueConstraint("cycle_id", "task_id", name="uq_project_cycle_tasks_cycle_task"),
        Index("ix_project_cycle_tasks_business_cycle", "business_id", "cycle_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    cycle_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("project_cycles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    task_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False, index=True
    )
    added_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)

    cycle = relationship("ProjectCycle")
    task = relationship("Task")


class TaskTimeEntry(Base):
    """Leantime-inspired time entry with one active timer per business/user."""

    __tablename__ = "task_time_entries"
    __table_args__ = (
        CheckConstraint("ended_at IS NULL OR ended_at >= started_at", name="ck_task_time_entries_dates"),
        CheckConstraint(
            "duration_seconds IS NULL OR duration_seconds >= 0",
            name="ck_task_time_entries_duration",
        ),
        Index("ix_task_time_entries_task_started", "task_id", "started_at"),
        Index(
            "uq_task_time_entries_active_user",
            "business_id",
            "user_id",
            unique=True,
            postgresql_where=text("ended_at IS NULL"),
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    task_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    duration_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    billable: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utc_now, onupdate=_utc_now, nullable=False
    )

    task = relationship("Task")
    user = relationship("User")


class TaskEntityLink(Base):
    """Generic native link from a task to CRM/accounting/support/domain entities."""

    __tablename__ = "task_entity_links"
    __table_args__ = (
        UniqueConstraint(
            "task_id",
            "entity_type",
            "entity_id",
            "relationship_type",
            name="uq_task_entity_links_task_entity_relation",
        ),
        Index("ix_task_entity_links_entity", "business_id", "entity_type", "entity_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    task_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False, index=True
    )
    entity_type: Mapped[str] = mapped_column(String(50), nullable=False)
    entity_id: Mapped[str] = mapped_column(String(64), nullable=False)
    relationship_type: Mapped[str] = mapped_column(
        String(50), nullable=False, default="related", server_default="related"
    )
    created_by_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now, nullable=False)

    task = relationship("Task")
    created_by = relationship("User", foreign_keys=[created_by_user_id])

