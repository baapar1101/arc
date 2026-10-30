"""Telephony operator privacy, teams, exclusive extensions, audit

Revision ID: 20261030_000002_telephony_operator_privacy
Revises: 20261030_000001_fixed_assets_purchase_invoice_bridge
Create Date: 2026-10-30
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261030_000002_telephony_operator_privacy"
down_revision = "20261030_000001_fixed_assets_purchase_invoice_bridge"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"telephony_extensions",
		sa.Column("team_code", sa.String(length=64), nullable=True, comment="کد تیم/بخش مثلاً sales"),
	)
	op.add_column(
		"telephony_extensions",
		sa.Column(
			"allow_shared",
			sa.Boolean(),
			nullable=False,
			server_default="0",
			comment="اگر خاموش باشد فقط یک کاربر به این داخلی وصل می‌شود",
		),
	)
	op.create_index(
		"idx_telephony_extensions_team",
		"telephony_extensions",
		["business_id", "team_code"],
	)

	op.create_table(
		"telephony_team_supervisors",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("team_code", sa.String(length=64), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "user_id", "team_code", name="uq_telephony_team_sup_biz_user_team"),
	)
	op.create_index("idx_telephony_team_sup_lookup", "telephony_team_supervisors", ["business_id", "user_id"])

	op.create_table(
		"telephony_audit_logs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=True),
		sa.Column("action", sa.String(length=40), nullable=False),
		sa.Column("call_id", sa.Integer(), nullable=True),
		sa.Column("target", sa.String(length=120), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["call_id"], ["telephony_calls.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("idx_telephony_audit_biz_created", "telephony_audit_logs", ["business_id", "created_at"])


def downgrade() -> None:
	op.drop_index("idx_telephony_audit_biz_created", table_name="telephony_audit_logs")
	op.drop_table("telephony_audit_logs")
	op.drop_index("idx_telephony_team_sup_lookup", table_name="telephony_team_supervisors")
	op.drop_table("telephony_team_supervisors")
	op.drop_index("idx_telephony_extensions_team", table_name="telephony_extensions")
	op.drop_column("telephony_extensions", "allow_shared")
	op.drop_column("telephony_extensions", "team_code")
