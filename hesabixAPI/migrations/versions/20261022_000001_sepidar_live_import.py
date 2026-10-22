"""Sepidar live import plugin storage.

Revision ID: 20261022_000001_sepidar_live_import
Revises: 20261019_000002_quick_sale_job_error_details
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "20261022_000001_sepidar_live_import"
down_revision = "20261019_000002_quick_sale_job_error_details"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("sepidar_import_settings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("host", sa.String(255), nullable=False), sa.Column("port", sa.Integer(), nullable=False, server_default="1433"),
        sa.Column("database_name", sa.String(255), nullable=False), sa.Column("username", sa.String(255), nullable=False),
        sa.Column("password_encrypted", sa.Text(), nullable=False), sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("sync_interval_minutes", sa.Integer(), nullable=False, server_default="15"), sa.Column("batch_size", sa.Integer(), nullable=False, server_default="500"),
        sa.Column("included_schemas", postgresql.JSONB()), sa.Column("included_tables", postgresql.JSONB()),
        sa.Column("last_started_at", sa.DateTime()), sa.Column("last_success_at", sa.DateTime()), sa.Column("last_error", sa.Text()),
        sa.Column("created_at", sa.DateTime(), nullable=False), sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("business_id", name="uq_sepidar_import_settings_business"))
    op.create_index("ix_sepidar_import_settings_business_id", "sepidar_import_settings", ["business_id"])
    op.create_table("sepidar_import_rows",
        sa.Column("id", sa.Integer(), primary_key=True), sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("source_schema", sa.String(128), nullable=False), sa.Column("source_table", sa.String(128), nullable=False),
        sa.Column("source_key", sa.String(1000), nullable=False), sa.Column("payload", postgresql.JSONB(), nullable=False),
        sa.Column("content_hash", sa.String(64), nullable=False), sa.Column("first_seen_at", sa.DateTime(), nullable=False), sa.Column("last_seen_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("business_id", "source_schema", "source_table", "source_key", name="uq_sepidar_import_row_source"))
    op.create_index("ix_sepidar_import_rows_business_id", "sepidar_import_rows", ["business_id"])
    op.create_table("sepidar_import_runs",
        sa.Column("id", sa.Integer(), primary_key=True), sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("status", sa.String(24), nullable=False), sa.Column("tables_total", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("tables_completed", sa.Integer(), nullable=False, server_default="0"), sa.Column("rows_seen", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("rows_changed", sa.Integer(), nullable=False, server_default="0"), sa.Column("error", sa.Text()),
        sa.Column("started_at", sa.DateTime(), nullable=False), sa.Column("finished_at", sa.DateTime()))
    op.create_index("ix_sepidar_import_runs_business_id", "sepidar_import_runs", ["business_id"])


def downgrade():
    op.drop_table("sepidar_import_runs")
    op.drop_table("sepidar_import_rows")
    op.drop_table("sepidar_import_settings")
