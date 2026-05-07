"""ai_configs: function_calling_enabled برای gatewayهای بدون tool calling

Revision ID: 20260503_000001_ai_config_function_calling_enabled
Revises: 20260502_000001_internal_firewall
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260503_000001_ai_config_function_calling_enabled"
down_revision = "20260502_000001_internal_firewall"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "ai_configs",
        sa.Column(
            "function_calling_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
    )


def downgrade() -> None:
    op.drop_column("ai_configs", "function_calling_enabled")
