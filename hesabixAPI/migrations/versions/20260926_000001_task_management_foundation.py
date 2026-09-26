"""Task/project-management domain foundation.

Benchmarks:
- Plane: project/work-item workflow and status grouping.
- Vikunja: task semantics, relations, reminders, and recurrence.

Revision ID: 20260926_000001_task_management_foundation
Revises: 20260907_000002_distribution_field_ops_upgrade
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260926_000001_task_management_foundation"
down_revision = "20260907_000002_distribution_field_ops_upgrade"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "project_members",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("project_id", sa.Integer(), sa.ForeignKey("projects.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("role", sa.String(length=20), nullable=False, server_default="member"),
        sa.Column("added_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.CheckConstraint("role IN ('viewer','member','manager','owner')", name="ck_project_members_role"),
        sa.UniqueConstraint("project_id", "user_id", name="uq_project_members_project_user"),
    )
    op.create_index("ix_project_members_project_id", "project_members", ["project_id"])
    op.create_index("ix_project_members_user_id", "project_members", ["user_id"])
    op.create_index("ix_project_members_user_project", "project_members", ["user_id", "project_id"])

    op.create_table(
        "task_statuses",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("key", sa.String(length=40), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("category", sa.String(length=20), nullable=False, server_default="unstarted"),
        sa.Column("color", sa.String(length=20), nullable=True),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("is_closed", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.CheckConstraint(
            "category IN ('backlog','unstarted','started','completed','cancelled')",
            name="ck_task_statuses_category",
        ),
        sa.UniqueConstraint("business_id", "key", name="uq_task_statuses_business_key"),
    )
    op.create_index("ix_task_statuses_business_id", "task_statuses", ["business_id"])
    op.create_index("ix_task_statuses_business_order", "task_statuses", ["business_id", "sort_order"])

    op.create_table(
        "task_labels",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("color", sa.String(length=20), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.UniqueConstraint("business_id", "name", name="uq_task_labels_business_name"),
    )
    op.create_index("ix_task_labels_business_id", "task_labels", ["business_id"])
    op.create_index("ix_task_labels_business_name", "task_labels", ["business_id", "name"])

    op.create_table(
        "tasks",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("project_id", sa.Integer(), sa.ForeignKey("projects.id", ondelete="SET NULL"), nullable=True),
        sa.Column("parent_task_id", sa.Integer(), sa.ForeignKey("tasks.id", ondelete="SET NULL"), nullable=True),
        sa.Column("status_id", sa.Integer(), sa.ForeignKey("task_statuses.id", ondelete="RESTRICT"), nullable=True),
        sa.Column("title", sa.String(length=500), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("priority", sa.String(length=20), nullable=False, server_default="normal"),
        sa.Column("sort_order", sa.Numeric(20, 6), nullable=False, server_default="0"),
        sa.Column("start_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("estimated_minutes", sa.Integer(), nullable=True),
        sa.Column("recurrence_rule", sa.String(length=512), nullable=True),
        sa.Column("recurrence_timezone", sa.String(length=80), nullable=True),
        sa.Column("recurrence_end_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint("priority IN ('low','normal','high','urgent')", name="ck_tasks_priority"),
        sa.CheckConstraint(
            "estimated_minutes IS NULL OR estimated_minutes >= 0",
            name="ck_tasks_estimated_minutes",
        ),
    )
    op.create_index("ix_tasks_business_id", "tasks", ["business_id"])
    op.create_index("ix_tasks_project_id", "tasks", ["project_id"])
    op.create_index("ix_tasks_status_id", "tasks", ["status_id"])
    op.create_index("ix_tasks_title", "tasks", ["title"])
    op.create_index("ix_tasks_priority", "tasks", ["priority"])
    op.create_index("ix_tasks_due_at", "tasks", ["due_at"])
    op.create_index("ix_tasks_created_by_user_id", "tasks", ["created_by_user_id"])
    op.create_index("ix_tasks_deleted_at", "tasks", ["deleted_at"])
    op.create_index("ix_tasks_parent_task", "tasks", ["parent_task_id"])
    op.create_index("ix_tasks_biz_deleted_due", "tasks", ["business_id", "deleted_at", "due_at"])
    op.create_index("ix_tasks_biz_project_pos", "tasks", ["business_id", "project_id", "sort_order"])
    op.create_index("ix_tasks_biz_status_pos", "tasks", ["business_id", "status_id", "sort_order"])

    op.create_table(
        "task_assignees",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("task_id", sa.Integer(), sa.ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("assigned_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("assigned_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.UniqueConstraint("task_id", "user_id", name="uq_task_assignees_task_user"),
    )
    op.create_index("ix_task_assignees_task_id", "task_assignees", ["task_id"])
    op.create_index("ix_task_assignees_user_id", "task_assignees", ["user_id"])
    op.create_index("ix_task_assignees_user_task", "task_assignees", ["user_id", "task_id"])

    op.create_table(
        "task_label_links",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("task_id", sa.Integer(), sa.ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False),
        sa.Column("label_id", sa.Integer(), sa.ForeignKey("task_labels.id", ondelete="CASCADE"), nullable=False),
        sa.UniqueConstraint("task_id", "label_id", name="uq_task_label_links_task_label"),
    )
    op.create_index("ix_task_label_links_task_id", "task_label_links", ["task_id"])
    op.create_index("ix_task_label_links_label_id", "task_label_links", ["label_id"])

    op.create_table(
        "task_relations",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("task_id", sa.Integer(), sa.ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False),
        sa.Column("related_task_id", sa.Integer(), sa.ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False),
        sa.Column("relation_type", sa.String(length=20), nullable=False),
        sa.Column("created_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.CheckConstraint("task_id <> related_task_id", name="ck_task_relations_not_self"),
        sa.CheckConstraint(
            "relation_type IN ('blocks','related','duplicates')",
            name="ck_task_relations_type",
        ),
        sa.UniqueConstraint("task_id", "related_task_id", "relation_type", name="uq_task_relations_pair_type"),
    )
    op.create_index("ix_task_relations_task_id", "task_relations", ["task_id"])
    op.create_index("ix_task_relations_related_task_id", "task_relations", ["related_task_id"])
    op.create_index("ix_task_relations_related", "task_relations", ["related_task_id", "relation_type"])

    op.create_table(
        "task_comments",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("task_id", sa.Integer(), sa.ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False),
        sa.Column("author_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_task_comments_task_id", "task_comments", ["task_id"])
    op.create_index("ix_task_comments_author_user_id", "task_comments", ["author_user_id"])
    op.create_index("ix_task_comments_task_created", "task_comments", ["task_id", "created_at"])

    op.create_table(
        "task_attachments",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("task_id", sa.Integer(), sa.ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False),
        sa.Column("storage_key", sa.String(length=1024), nullable=False),
        sa.Column("original_name", sa.String(length=512), nullable=False),
        sa.Column("mime_type", sa.String(length=255), nullable=True),
        sa.Column("size_bytes", sa.BigInteger(), nullable=True),
        sa.Column("uploaded_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
    )
    op.create_index("ix_task_attachments_task_id", "task_attachments", ["task_id"])
    op.create_index("ix_task_attachments_task_created", "task_attachments", ["task_id", "created_at"])

    op.create_table(
        "task_reminders",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("task_id", sa.Integer(), sa.ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=True),
        sa.Column("remind_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("relative_to", sa.String(length=20), nullable=True),
        sa.Column("offset_minutes", sa.Integer(), nullable=True),
        sa.Column("sent_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
        sa.CheckConstraint("offset_minutes IS NULL OR offset_minutes >= 0", name="ck_task_reminders_offset"),
    )
    op.create_index("ix_task_reminders_task_id", "task_reminders", ["task_id"])
    op.create_index("ix_task_reminders_user_id", "task_reminders", ["user_id"])
    op.create_index("ix_task_reminders_user_due", "task_reminders", ["user_id", "remind_at", "sent_at"])
    op.create_index("ix_task_reminders_task_due", "task_reminders", ["task_id", "remind_at"])

    op.create_table(
        "task_activity_events",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("task_id", sa.Integer(), sa.ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False),
        sa.Column("actor_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("event_type", sa.String(length=80), nullable=False),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("NOW()")),
    )
    op.create_index("ix_task_activity_events_business_id", "task_activity_events", ["business_id"])
    op.create_index("ix_task_activity_events_task_id", "task_activity_events", ["task_id"])
    op.create_index("ix_task_activity_events_actor_user_id", "task_activity_events", ["actor_user_id"])
    op.create_index("ix_task_activity_events_event_type", "task_activity_events", ["event_type"])
    op.create_index("ix_task_activity_task_created", "task_activity_events", ["task_id", "created_at"])
    op.create_index("ix_task_activity_business_created", "task_activity_events", ["business_id", "created_at"])


def downgrade() -> None:
    op.drop_table("task_activity_events")
    op.drop_table("task_reminders")
    op.drop_table("task_attachments")
    op.drop_table("task_comments")
    op.drop_table("task_relations")
    op.drop_table("task_label_links")
    op.drop_table("task_assignees")
    op.drop_table("tasks")
    op.drop_table("task_labels")
    op.drop_table("task_statuses")
    op.drop_table("project_members")
