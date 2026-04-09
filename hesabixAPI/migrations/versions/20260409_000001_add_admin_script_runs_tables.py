"""add admin script runs tables

Revision ID: 20260409_000001
Revises: 20250228_000002_add_crm_follow_up_and_history
Create Date: 2026-04-09
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260409_000001_add_admin_script_runs_tables"
down_revision = "20250228_000002_add_crm_follow_up_and_history"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"admin_script_runs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("script_key", sa.String(length=120), nullable=False),
		sa.Column("status", sa.String(length=30), nullable=False),
		sa.Column("dry_run", sa.Boolean(), nullable=False, server_default="1"),
		sa.Column("params_json", sa.JSON(), nullable=True),
		sa.Column("result_json", sa.JSON(), nullable=True),
		sa.Column("error_text", sa.Text(), nullable=True),
		sa.Column("scanned_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("updated_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("skipped_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("error_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("started_at", sa.DateTime(), nullable=True),
		sa.Column("finished_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_admin_script_runs_script_key", "admin_script_runs", ["script_key"], unique=False)
	op.create_index("ix_admin_script_runs_status", "admin_script_runs", ["status"], unique=False)
	op.create_index("ix_admin_script_runs_created_by_user_id", "admin_script_runs", ["created_by_user_id"], unique=False)
	op.create_index("ix_admin_script_runs_created_at", "admin_script_runs", ["created_at"], unique=False)

	op.create_table(
		"admin_script_run_logs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("run_id", sa.Integer(), nullable=False),
		sa.Column("level", sa.String(length=20), nullable=False),
		sa.Column("message", sa.Text(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["run_id"], ["admin_script_runs.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_admin_script_run_logs_run_id", "admin_script_run_logs", ["run_id"], unique=False)
	op.create_index("ix_admin_script_run_logs_created_at", "admin_script_run_logs", ["created_at"], unique=False)


def downgrade() -> None:
	op.drop_index("ix_admin_script_run_logs_created_at", "admin_script_run_logs")
	op.drop_index("ix_admin_script_run_logs_run_id", "admin_script_run_logs")
	op.drop_table("admin_script_run_logs")

	op.drop_index("ix_admin_script_runs_created_at", "admin_script_runs")
	op.drop_index("ix_admin_script_runs_created_by_user_id", "admin_script_runs")
	op.drop_index("ix_admin_script_runs_status", "admin_script_runs")
	op.drop_index("ix_admin_script_runs_script_key", "admin_script_runs")
	op.drop_table("admin_script_runs")

