"""Business public pay-page (unique username + settings)

Revision ID: 20261101_000004_business_pay_pages
Revises: 20261101_000003_product_variant_prices
Create Date: 2026-11-01
"""
from __future__ import annotations

import json

import sqlalchemy as sa
from alembic import op

from adapters.db.seed_data.notification_event_types_seed import (
	PAY_LINK_RECEIVED_EVENT_CODES,
	NOTIFICATION_EVENT_TYPES_ROWS,
)

revision = "20261101_000004_business_pay_pages"
down_revision = "20261101_000003_product_variant_prices"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"business_pay_pages",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column(
			"business_id",
			sa.Integer(),
			sa.ForeignKey("businesses.id", ondelete="CASCADE"),
			nullable=False,
		),
		sa.Column("username", sa.String(length=30), nullable=True),
		sa.Column("is_enabled", sa.Boolean(), nullable=False, server_default="0"),
		sa.Column("display_title", sa.String(length=120), nullable=True),
		sa.Column("show_logo", sa.Boolean(), nullable=False, server_default="1"),
		sa.Column("intro_text", sa.Text(), nullable=True),
		sa.Column(
			"gateway_id",
			sa.Integer(),
			sa.ForeignKey("payment_gateways.id", ondelete="SET NULL"),
			nullable=True,
		),
		sa.Column("min_amount", sa.Numeric(18, 2), nullable=False, server_default="50000"),
		sa.Column("max_amount", sa.Numeric(18, 2), nullable=True),
		sa.Column("notify_inapp", sa.Boolean(), nullable=False, server_default="1"),
		sa.Column("notify_sms", sa.Boolean(), nullable=False, server_default="0"),
		sa.Column("match_customer_by_mobile", sa.Boolean(), nullable=False, server_default="1"),
		sa.Column("create_customer_if_missing", sa.Boolean(), nullable=False, server_default="1"),
		sa.Column("use_anonymous_if_no_mobile", sa.Boolean(), nullable=False, server_default="1"),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
	)
	op.create_unique_constraint("uq_business_pay_pages_business", "business_pay_pages", ["business_id"])
	op.create_unique_constraint("uq_business_pay_pages_username", "business_pay_pages", ["username"])
	op.create_index("ix_business_pay_pages_username", "business_pay_pages", ["username"])
	op.create_index("ix_business_pay_pages_business_id", "business_pay_pages", ["business_id"])

	op.create_table(
		"business_pay_page_username_history",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column(
			"business_id",
			sa.Integer(),
			sa.ForeignKey("businesses.id", ondelete="CASCADE"),
			nullable=False,
		),
		sa.Column("username", sa.String(length=30), nullable=False),
		sa.Column("expires_at", sa.DateTime(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
	)
	op.create_index(
		"ix_pay_page_username_history_username",
		"business_pay_page_username_history",
		["username"],
	)
	op.create_index(
		"ix_pay_page_username_history_business",
		"business_pay_page_username_history",
		["business_id"],
	)

	conn = op.get_bind()
	insp = sa.inspect(conn)
	if "notification_event_types" in insp.get_table_names():
		rows = [r for r in NOTIFICATION_EVENT_TYPES_ROWS if r["code"] in PAY_LINK_RECEIVED_EVENT_CODES]
		for row in rows:
			conn.execute(
				sa.text(
					"""
					INSERT INTO notification_event_types (
						code, name, description, category, available_variables,
						default_sms_template, default_email_template, default_email_subject,
						is_active, requires_approval, created_at, updated_at
					) VALUES (
						:code, :name, :description, :category, CAST(:vars AS JSONB),
						:dst, :det, :des,
						true, false, NOW(), NOW()
					)
					ON CONFLICT (code) DO NOTHING
					"""
				),
				{
					"code": row["code"],
					"name": row["name"],
					"description": row.get("description"),
					"category": row.get("category"),
					"vars": json.dumps(row["available_variables"], ensure_ascii=False),
					"dst": row.get("default_sms_template"),
					"det": row.get("default_email_template"),
					"des": row.get("default_email_subject"),
				},
			)


def downgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)
	if "notification_event_types" in insp.get_table_names():
		for code in PAY_LINK_RECEIVED_EVENT_CODES:
			conn.execute(
				sa.text("DELETE FROM notification_event_types WHERE code = :c"),
				{"c": code},
			)
	op.drop_index("ix_pay_page_username_history_business", table_name="business_pay_page_username_history")
	op.drop_index("ix_pay_page_username_history_username", table_name="business_pay_page_username_history")
	op.drop_table("business_pay_page_username_history")
	op.drop_index("ix_business_pay_pages_business_id", table_name="business_pay_pages")
	op.drop_index("ix_business_pay_pages_username", table_name="business_pay_pages")
	op.drop_constraint("uq_business_pay_pages_username", "business_pay_pages", type_="unique")
	op.drop_constraint("uq_business_pay_pages_business", "business_pay_pages", type_="unique")
	op.drop_table("business_pay_pages")
