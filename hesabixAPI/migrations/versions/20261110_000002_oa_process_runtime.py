"""فرآیند انسانی نسخه‌دار اتوماسیون اداری.

Revision ID: 20261110_000002_oa_process_runtime
Revises: 20261110_000001_oa_cartable_saved_filters
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000002_oa_process_runtime"
down_revision = "20261110_000001_oa_cartable_saved_filters"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"oa_process_definitions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("name_i18n", sa.JSON(), nullable=False),
		sa.Column("graph", sa.JSON(), nullable=False),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_oa_process_definitions_code"),
	)
	op.create_index("ix_oa_process_definitions_business_id", "oa_process_definitions", ["business_id"])
	op.create_table(
		"oa_process_versions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("definition_id", sa.Integer(), nullable=False),
		sa.Column("version_no", sa.Integer(), nullable=False),
		sa.Column("graph", sa.JSON(), nullable=False),
		sa.Column("published_by_user_id", sa.Integer(), nullable=True),
		sa.Column("published_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["definition_id"], ["oa_process_definitions.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["published_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("definition_id", "version_no", name="uq_oa_process_versions_no"),
	)
	op.create_index("ix_oa_process_versions_business_id", "oa_process_versions", ["business_id"])
	op.create_table(
		"oa_process_instances",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("version_id", sa.Integer(), nullable=False),
		sa.Column("graph_snapshot", sa.JSON(), nullable=False),
		sa.Column("status", sa.String(length=16), nullable=False),
		sa.Column("variables", sa.JSON(), nullable=False),
		sa.Column("started_by_user_id", sa.Integer(), nullable=True),
		sa.Column("started_by_position_id", sa.Integer(), nullable=True),
		sa.Column("parent_instance_id", sa.Integer(), nullable=True),
		sa.Column("started_at", sa.DateTime(), nullable=False),
		sa.Column("completed_at", sa.DateTime(), nullable=True),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["version_id"], ["oa_process_versions.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["started_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["started_by_position_id"], ["oa_positions.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["parent_instance_id"], ["oa_process_instances.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_process_instances_business_id", "oa_process_instances", ["business_id"])
	op.create_table(
		"oa_process_tokens",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("instance_id", sa.Integer(), nullable=False),
		sa.Column("node_id", sa.String(length=64), nullable=False),
		sa.Column("status", sa.String(length=16), nullable=False),
		sa.Column("wait_kind", sa.String(length=16), nullable=True),
		sa.Column("resume_at", sa.DateTime(), nullable=True),
		sa.Column("child_instance_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["instance_id"], ["oa_process_instances.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["child_instance_id"], ["oa_process_instances.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_process_tokens_instance_id", "oa_process_tokens", ["instance_id"])
	op.create_table(
		"oa_process_tasks",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("instance_id", sa.Integer(), nullable=False),
		sa.Column("token_id", sa.Integer(), nullable=False),
		sa.Column("node_id", sa.String(length=64), nullable=False),
		sa.Column("name", sa.String(length=200), nullable=False),
		sa.Column("assignee_position_id", sa.Integer(), nullable=False),
		sa.Column("status", sa.String(length=16), nullable=False),
		sa.Column("form_schema", sa.JSON(), nullable=False),
		sa.Column("form_data", sa.JSON(), nullable=True),
		sa.Column("due_at", sa.DateTime(), nullable=True),
		sa.Column("escalated_at", sa.DateTime(), nullable=True),
		sa.Column("completed_by_user_id", sa.Integer(), nullable=True),
		sa.Column("completed_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("note", sa.Text(), nullable=True),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["instance_id"], ["oa_process_instances.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["token_id"], ["oa_process_tokens.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["assignee_position_id"], ["oa_positions.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["completed_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_process_tasks_business_position", "oa_process_tasks", ["business_id", "assignee_position_id"])
	op.create_index("ix_oa_process_tasks_instance_id", "oa_process_tasks", ["instance_id"])


def downgrade() -> None:
	op.drop_index("ix_oa_process_tasks_instance_id", table_name="oa_process_tasks")
	op.drop_index("ix_oa_process_tasks_business_position", table_name="oa_process_tasks")
	op.drop_table("oa_process_tasks")
	op.drop_index("ix_oa_process_tokens_instance_id", table_name="oa_process_tokens")
	op.drop_table("oa_process_tokens")
	op.drop_index("ix_oa_process_instances_business_id", table_name="oa_process_instances")
	op.drop_table("oa_process_instances")
	op.drop_index("ix_oa_process_versions_business_id", table_name="oa_process_versions")
	op.drop_table("oa_process_versions")
	op.drop_index("ix_oa_process_definitions_business_id", table_name="oa_process_definitions")
	op.drop_table("oa_process_definitions")
