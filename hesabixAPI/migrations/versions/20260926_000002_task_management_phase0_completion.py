"""Complete Phase 0 task/project-management foundation.

Adds planning entities, explicit tenant scoping on association tables, time
tracking, generic entity links, file-storage linkage, and task integrity checks.

Revision ID: 20260926_000002_task_management_phase0_completion
Revises: 20260926_000001_task_management_foundation
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260926_000002_task_management_phase0_completion"
down_revision = "20260926_000001_task_management_foundation"
branch_labels = None
depends_on = None


def _add_task_business_scope(table_name: str, task_column: str = "task_id") -> None:
    op.add_column(table_name, sa.Column("business_id", sa.Integer(), nullable=True))
    op.execute(
        sa.text(
            f"""
            UPDATE {table_name} AS scoped
            SET business_id = task.business_id
            FROM tasks AS task
            WHERE scoped.{task_column} = task.id
              AND scoped.business_id IS NULL
            """
        )
    )
    op.alter_column(
        table_name,
        "business_id",
        existing_type=sa.Integer(),
        nullable=False,
    )
    op.create_foreign_key(
        f"fk_{table_name}_business_id",
        table_name,
        "businesses",
        ["business_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_index(f"ix_{table_name}_business_id", table_name, ["business_id"])


def _drop_task_business_scope(table_name: str) -> None:
    op.drop_index(f"ix_{table_name}_business_id", table_name=table_name)
    op.drop_constraint(
        f"fk_{table_name}_business_id",
        table_name,
        type_="foreignkey",
    )
    op.drop_column(table_name, "business_id")


def upgrade() -> None:
    # Explicit tenant scope on existing association/detail tables.
    op.add_column("project_members", sa.Column("business_id", sa.Integer(), nullable=True))
    op.execute(
        sa.text(
            """
            UPDATE project_members AS member
            SET business_id = project.business_id
            FROM projects AS project
            WHERE member.project_id = project.id
              AND member.business_id IS NULL
            """
        )
    )
    op.alter_column(
        "project_members",
        "business_id",
        existing_type=sa.Integer(),
        nullable=False,
    )
    op.create_foreign_key(
        "fk_project_members_business_id",
        "project_members",
        "businesses",
        ["business_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_index("ix_project_members_business_id", "project_members", ["business_id"])
    op.create_index(
        "ix_project_members_business_project",
        "project_members",
        ["business_id", "project_id"],
    )

    for table_name in (
        "task_assignees",
        "task_label_links",
        "task_relations",
        "task_comments",
        "task_attachments",
        "task_reminders",
    ):
        _add_task_business_scope(table_name)

    op.create_index(
        "ix_task_assignees_business_user",
        "task_assignees",
        ["business_id", "user_id"],
    )
    op.create_index(
        "ix_task_relations_business_task",
        "task_relations",
        ["business_id", "task_id"],
    )
    op.create_index(
        "ix_task_comments_business_task",
        "task_comments",
        ["business_id", "task_id"],
    )
    op.create_index(
        "ix_task_attachments_business_task",
        "task_attachments",
        ["business_id", "task_id"],
    )
    op.create_index(
        "ix_task_reminders_business_due",
        "task_reminders",
        ["business_id", "remind_at"],
    )

    # Strengthen task-level integrity independently of service/UI validation.
    op.create_check_constraint(
        "ck_tasks_not_own_parent",
        "tasks",
        "parent_task_id IS NULL OR parent_task_id <> id",
    )
    op.create_check_constraint(
        "ck_tasks_dates",
        "tasks",
        "due_at IS NULL OR start_at IS NULL OR due_at >= start_at",
    )

    # Reuse the native shared file storage while preserving Phase 0 legacy
    # metadata columns for backwards compatibility.
    op.add_column(
        "task_attachments",
        sa.Column("file_storage_id", sa.String(length=36), nullable=True),
    )
    op.create_foreign_key(
        "fk_task_attachments_file_storage_id",
        "task_attachments",
        "file_storage",
        ["file_storage_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_index(
        "ix_task_attachments_file_storage_id",
        "task_attachments",
        ["file_storage_id"],
    )
    op.create_unique_constraint(
        "uq_task_attachments_task_file",
        "task_attachments",
        ["task_id", "file_storage_id"],
    )

    # Leantime-inspired milestone planning.
    op.create_table(
        "project_milestones",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "business_id",
            sa.Integer(),
            sa.ForeignKey("businesses.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "project_id",
            sa.Integer(),
            sa.ForeignKey("projects.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("start_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("target_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="open"),
        sa.Column("sort_order", sa.Numeric(20, 6), nullable=False, server_default="0"),
        sa.Column(
            "created_by_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.CheckConstraint(
            "target_at IS NULL OR start_at IS NULL OR target_at >= start_at",
            name="ck_project_milestones_dates",
        ),
    )
    op.create_index(
        "ix_project_milestones_business_id",
        "project_milestones",
        ["business_id"],
    )
    op.create_index(
        "ix_project_milestones_project_id",
        "project_milestones",
        ["project_id"],
    )
    op.create_index(
        "ix_project_milestones_project_target",
        "project_milestones",
        ["project_id", "target_at"],
    )

    op.add_column("tasks", sa.Column("milestone_id", sa.Integer(), nullable=True))
    op.create_foreign_key(
        "fk_tasks_milestone_id",
        "tasks",
        "project_milestones",
        ["milestone_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_tasks_milestone_id", "tasks", ["milestone_id"])

    # Plane-style cycles/sprints.
    op.create_table(
        "project_cycles",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "business_id",
            sa.Integer(),
            sa.ForeignKey("businesses.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "project_id",
            sa.Integer(),
            sa.ForeignKey("projects.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("goal", sa.Text(), nullable=True),
        sa.Column("start_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("end_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="planned"),
        sa.Column(
            "created_by_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.CheckConstraint(
            "end_at IS NULL OR start_at IS NULL OR end_at >= start_at",
            name="ck_project_cycles_dates",
        ),
    )
    op.create_index("ix_project_cycles_business_id", "project_cycles", ["business_id"])
    op.create_index("ix_project_cycles_project_id", "project_cycles", ["project_id"])
    op.create_index(
        "ix_project_cycles_project_dates",
        "project_cycles",
        ["project_id", "start_at", "end_at"],
    )

    op.create_table(
        "project_cycle_tasks",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "business_id",
            sa.Integer(),
            sa.ForeignKey("businesses.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "cycle_id",
            sa.Integer(),
            sa.ForeignKey("project_cycles.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "task_id",
            sa.Integer(),
            sa.ForeignKey("tasks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "added_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.UniqueConstraint(
            "cycle_id",
            "task_id",
            name="uq_project_cycle_tasks_cycle_task",
        ),
    )
    op.create_index(
        "ix_project_cycle_tasks_business_id",
        "project_cycle_tasks",
        ["business_id"],
    )
    op.create_index(
        "ix_project_cycle_tasks_cycle_id",
        "project_cycle_tasks",
        ["cycle_id"],
    )
    op.create_index(
        "ix_project_cycle_tasks_task_id",
        "project_cycle_tasks",
        ["task_id"],
    )
    op.create_index(
        "ix_project_cycle_tasks_business_cycle",
        "project_cycle_tasks",
        ["business_id", "cycle_id"],
    )

    # Leantime-style time tracking foundation.
    op.create_table(
        "task_time_entries",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "business_id",
            sa.Integer(),
            sa.ForeignKey("businesses.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "task_id",
            sa.Integer(),
            sa.ForeignKey("tasks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column(
            "billable",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.CheckConstraint(
            "ended_at IS NULL OR ended_at >= started_at",
            name="ck_task_time_entries_dates",
        ),
        sa.CheckConstraint(
            "duration_seconds IS NULL OR duration_seconds >= 0",
            name="ck_task_time_entries_duration",
        ),
    )
    op.create_index(
        "ix_task_time_entries_business_id",
        "task_time_entries",
        ["business_id"],
    )
    op.create_index("ix_task_time_entries_task_id", "task_time_entries", ["task_id"])
    op.create_index("ix_task_time_entries_user_id", "task_time_entries", ["user_id"])
    op.create_index(
        "ix_task_time_entries_task_started",
        "task_time_entries",
        ["task_id", "started_at"],
    )
    op.create_index(
        "uq_task_time_entries_active_user",
        "task_time_entries",
        ["business_id", "user_id"],
        unique=True,
        postgresql_where=sa.text("ended_at IS NULL"),
    )

    # Generic CRM/accounting/support linkage without hard-coding domain FKs.
    op.create_table(
        "task_entity_links",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "business_id",
            sa.Integer(),
            sa.ForeignKey("businesses.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "task_id",
            sa.Integer(),
            sa.ForeignKey("tasks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("entity_type", sa.String(length=50), nullable=False),
        sa.Column("entity_id", sa.String(length=64), nullable=False),
        sa.Column(
            "relationship_type",
            sa.String(length=50),
            nullable=False,
            server_default="related",
        ),
        sa.Column(
            "created_by_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.UniqueConstraint(
            "task_id",
            "entity_type",
            "entity_id",
            "relationship_type",
            name="uq_task_entity_links_task_entity_relation",
        ),
    )
    op.create_index(
        "ix_task_entity_links_business_id",
        "task_entity_links",
        ["business_id"],
    )
    op.create_index(
        "ix_task_entity_links_task_id",
        "task_entity_links",
        ["task_id"],
    )
    op.create_index(
        "ix_task_entity_links_entity",
        "task_entity_links",
        ["business_id", "entity_type", "entity_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_task_entity_links_entity", table_name="task_entity_links")
    op.drop_index("ix_task_entity_links_task_id", table_name="task_entity_links")
    op.drop_index("ix_task_entity_links_business_id", table_name="task_entity_links")
    op.drop_table("task_entity_links")

    op.drop_index("uq_task_time_entries_active_user", table_name="task_time_entries")
    op.drop_index("ix_task_time_entries_task_started", table_name="task_time_entries")
    op.drop_index("ix_task_time_entries_user_id", table_name="task_time_entries")
    op.drop_index("ix_task_time_entries_task_id", table_name="task_time_entries")
    op.drop_index("ix_task_time_entries_business_id", table_name="task_time_entries")
    op.drop_table("task_time_entries")

    op.drop_index(
        "ix_project_cycle_tasks_business_cycle",
        table_name="project_cycle_tasks",
    )
    op.drop_index("ix_project_cycle_tasks_task_id", table_name="project_cycle_tasks")
    op.drop_index("ix_project_cycle_tasks_cycle_id", table_name="project_cycle_tasks")
    op.drop_index("ix_project_cycle_tasks_business_id", table_name="project_cycle_tasks")
    op.drop_table("project_cycle_tasks")

    op.drop_index("ix_project_cycles_project_dates", table_name="project_cycles")
    op.drop_index("ix_project_cycles_project_id", table_name="project_cycles")
    op.drop_index("ix_project_cycles_business_id", table_name="project_cycles")
    op.drop_table("project_cycles")

    op.drop_index("ix_tasks_milestone_id", table_name="tasks")
    op.drop_constraint("fk_tasks_milestone_id", "tasks", type_="foreignkey")
    op.drop_column("tasks", "milestone_id")

    op.drop_index(
        "ix_project_milestones_project_target",
        table_name="project_milestones",
    )
    op.drop_index("ix_project_milestones_project_id", table_name="project_milestones")
    op.drop_index("ix_project_milestones_business_id", table_name="project_milestones")
    op.drop_table("project_milestones")

    op.drop_constraint(
        "uq_task_attachments_task_file",
        "task_attachments",
        type_="unique",
    )
    op.drop_index(
        "ix_task_attachments_file_storage_id",
        table_name="task_attachments",
    )
    op.drop_constraint(
        "fk_task_attachments_file_storage_id",
        "task_attachments",
        type_="foreignkey",
    )
    op.drop_column("task_attachments", "file_storage_id")

    op.drop_constraint("ck_tasks_dates", "tasks", type_="check")
    op.drop_constraint("ck_tasks_not_own_parent", "tasks", type_="check")

    op.drop_index(
        "ix_task_reminders_business_due",
        table_name="task_reminders",
    )
    op.drop_index(
        "ix_task_attachments_business_task",
        table_name="task_attachments",
    )
    op.drop_index(
        "ix_task_comments_business_task",
        table_name="task_comments",
    )
    op.drop_index(
        "ix_task_relations_business_task",
        table_name="task_relations",
    )
    op.drop_index(
        "ix_task_assignees_business_user",
        table_name="task_assignees",
    )

    for table_name in (
        "task_reminders",
        "task_attachments",
        "task_comments",
        "task_relations",
        "task_label_links",
        "task_assignees",
    ):
        _drop_task_business_scope(table_name)

    op.drop_index(
        "ix_project_members_business_project",
        table_name="project_members",
    )
    op.drop_index("ix_project_members_business_id", table_name="project_members")
    op.drop_constraint(
        "fk_project_members_business_id",
        "project_members",
        type_="foreignkey",
    )
    op.drop_column("project_members", "business_id")
