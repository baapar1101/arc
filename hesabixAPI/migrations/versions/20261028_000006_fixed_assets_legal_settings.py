"""تنظیمات قانونی اموال: آستانه و عامل رکود مالیاتی/حسابداری.

Revision ID: 20261028_000006_fixed_assets_legal_settings
Revises: 20261028_000005_fixed_assets_phase2
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261028_000006_fixed_assets_legal_settings"
down_revision = "20261028_000005_fixed_assets_phase2"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"fa_settings",
		sa.Column("tax_idle_months", sa.Integer(), nullable=False, server_default=sa.text("6")),
	)
	op.add_column(
		"fa_settings",
		sa.Column(
			"tax_idle_factor",
			sa.Numeric(8, 6),
			nullable=False,
			server_default=sa.text("0.7"),
		),
	)
	op.add_column(
		"fa_settings",
		sa.Column(
			"accounting_idle_factor",
			sa.Numeric(8, 6),
			nullable=False,
			server_default=sa.text("1"),
		),
	)


def downgrade() -> None:
	op.drop_column("fa_settings", "accounting_idle_factor")
	op.drop_column("fa_settings", "tax_idle_factor")
	op.drop_column("fa_settings", "tax_idle_months")
