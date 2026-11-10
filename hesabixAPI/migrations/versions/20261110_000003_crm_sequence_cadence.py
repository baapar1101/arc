"""سقف پیامک و قاعده توقف توالی CRM.

Revision ID: 20261110_000003_crm_sequence_cadence
Revises: 20261110_000002_crm_saved_views
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000003_crm_sequence_cadence"
down_revision = "20261110_000002_crm_saved_views"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if "crm_sequences" not in set(inspector.get_table_names()):
        return
    columns = {col["name"] for col in inspector.get_columns("crm_sequences")}
    if "sms_daily_cap" not in columns:
        op.add_column("crm_sequences", sa.Column("sms_daily_cap", sa.Integer(), nullable=True))
    if "stop_on_reply" not in columns:
        op.add_column(
            "crm_sequences",
            sa.Column("stop_on_reply", sa.Boolean(), nullable=False, server_default=sa.true()),
        )
    if "stop_on_close" not in columns:
        op.add_column(
            "crm_sequences",
            sa.Column("stop_on_close", sa.Boolean(), nullable=False, server_default=sa.true()),
        )


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if "crm_sequences" not in set(inspector.get_table_names()):
        return
    columns = {col["name"] for col in inspector.get_columns("crm_sequences")}
    if "stop_on_close" in columns:
        op.drop_column("crm_sequences", "stop_on_close")
    if "stop_on_reply" in columns:
        op.drop_column("crm_sequences", "stop_on_reply")
    if "sms_daily_cap" in columns:
        op.drop_column("crm_sequences", "sms_daily_cap")
