"""Add expiring point lots, reward catalog, vouchers, and campaigns.

Revision ID: 20261025_000001_customer_club_rewards_campaigns
Revises: 20261023_000001_mcp_tool_permissions
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261025_000001_customer_club_rewards_campaigns"
down_revision = "20261023_000001_mcp_tool_permissions"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column("customer_club_tiers", sa.Column("benefits_json", sa.JSON(), nullable=True))
	op.add_column("customer_club_settings", sa.Column("referral_points", sa.Numeric(18, 6), nullable=False, server_default="0"))
	op.add_column("customer_club_settings", sa.Column("survey_points", sa.Numeric(18, 6), nullable=False, server_default="0"))
	# Existing aggregate balances remain valid; the service will create legacy
	# non-expiring lots lazily when those balances are first consumed.
	op.create_table(
		"customer_club_point_lots",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("ledger_id", sa.Integer(), nullable=True),
		sa.Column("original_points", sa.Numeric(18, 6), nullable=False),
		sa.Column("remaining_points", sa.Numeric(18, 6), nullable=False),
		sa.Column("expires_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["ledger_id"], ["customer_club_ledger.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("ledger_id", name="uq_customer_club_point_lot_ledger"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_customer_club_point_lots_business_id", "customer_club_point_lots", ["business_id"])
	op.create_index("ix_customer_club_point_lots_person_id", "customer_club_point_lots", ["person_id"])
	op.create_index("ix_customer_club_point_lots_expires_at", "customer_club_point_lots", ["expires_at"])

	op.create_table(
		"customer_club_rewards",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("name", sa.String(160), nullable=False),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("reward_type", sa.String(32), nullable=False, server_default="discount_amount"),
		sa.Column("points_cost", sa.Numeric(18, 6), nullable=False, server_default="0"),
		sa.Column("value", sa.Numeric(18, 4), nullable=False, server_default="0"),
		sa.Column("product_id", sa.Integer(), nullable=True),
		sa.Column("valid_days", sa.Integer(), nullable=True),
		sa.Column("max_issuances", sa.Integer(), nullable=True),
		sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.true()),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_customer_club_rewards_business_id", "customer_club_rewards", ["business_id"])

	op.create_table(
		"customer_club_campaigns",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("name", sa.String(160), nullable=False),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("trigger_type", sa.String(24), nullable=False, server_default="manual"),
		sa.Column("segment_json", sa.JSON(), nullable=False),
		sa.Column("reward_type", sa.String(32), nullable=False, server_default="points"),
		sa.Column("reward_value", sa.Numeric(18, 4), nullable=False, server_default="0"),
		sa.Column("min_purchase_amount", sa.Numeric(18, 4), nullable=True),
		sa.Column("reward_valid_days", sa.Integer(), nullable=True),
		sa.Column("message_template", sa.Text(), nullable=True),
		sa.Column("channel", sa.String(16), nullable=False, server_default="none"),
		sa.Column("starts_at", sa.DateTime(), nullable=True),
		sa.Column("ends_at", sa.DateTime(), nullable=True),
		sa.Column("status", sa.String(20), nullable=False, server_default="draft"),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_customer_club_campaigns_business_id", "customer_club_campaigns", ["business_id"])

	op.create_table(
		"customer_club_vouchers",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("reward_id", sa.Integer(), nullable=True),
		sa.Column("product_id", sa.Integer(), nullable=True),
		sa.Column("campaign_id", sa.Integer(), nullable=True),
		sa.Column("code", sa.String(40), nullable=False),
		sa.Column("status", sa.String(20), nullable=False, server_default="issued"),
		sa.Column("value", sa.Numeric(18, 4), nullable=False, server_default="0"),
		sa.Column("reward_type", sa.String(32), nullable=False),
		sa.Column("expires_at", sa.DateTime(), nullable=True),
		sa.Column("redeemed_at", sa.DateTime(), nullable=True),
		sa.Column("redeemed_document_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["reward_id"], ["customer_club_rewards.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["campaign_id"], ["customer_club_campaigns.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["redeemed_document_id"], ["documents.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_customer_club_voucher_code"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_customer_club_vouchers_business_id", "customer_club_vouchers", ["business_id"])
	op.create_index("ix_customer_club_vouchers_person_id", "customer_club_vouchers", ["person_id"])
	op.create_index("ix_customer_club_vouchers_expires_at", "customer_club_vouchers", ["expires_at"])
	op.add_column("customer_club_invoice_snapshots", sa.Column("voucher_id", sa.Integer(), nullable=True))
	op.create_foreign_key("fk_customer_club_invoice_snapshots_voucher_id", "customer_club_invoice_snapshots", "customer_club_vouchers", ["voucher_id"], ["id"], ondelete="SET NULL")

	op.create_table(
		"customer_club_campaign_members",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("campaign_id", sa.Integer(), nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("status", sa.String(20), nullable=False, server_default="rewarded"),
		sa.Column("reward_value", sa.Numeric(18, 4), nullable=False, server_default="0"),
		sa.Column("voucher_code", sa.String(40), nullable=True),
		sa.Column("sent_at", sa.DateTime(), nullable=True),
		sa.Column("send_error", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["campaign_id"], ["customer_club_campaigns.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("campaign_id", "person_id", name="uq_customer_club_campaign_member"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_customer_club_campaign_members_campaign_id", "customer_club_campaign_members", ["campaign_id"])
	op.create_index("ix_customer_club_campaign_members_business_id", "customer_club_campaign_members", ["business_id"])
	op.create_index("ix_customer_club_campaign_members_person_id", "customer_club_campaign_members", ["person_id"])
	op.add_column("customer_club_campaign_members", sa.Column("conversion_document_id", sa.Integer(), nullable=True))
	op.add_column("customer_club_campaign_members", sa.Column("conversion_amount", sa.Numeric(18, 4), nullable=False, server_default="0"))
	op.add_column("customer_club_campaign_members", sa.Column("converted_at", sa.DateTime(), nullable=True))
	op.create_foreign_key("fk_customer_club_campaign_members_conversion_document", "customer_club_campaign_members", "documents", ["conversion_document_id"], ["id"], ondelete="SET NULL")

	op.create_table(
		"customer_club_members",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("joined_at", sa.DateTime(), nullable=False),
		sa.Column("referral_code", sa.String(24), nullable=True),
		sa.Column("referrer_person_id", sa.Integer(), nullable=True),
		sa.Column("sms_consent", sa.Boolean(), nullable=False, server_default=sa.false()),
		sa.Column("sms_consent_at", sa.DateTime(), nullable=True),
		sa.Column("email_consent", sa.Boolean(), nullable=False, server_default=sa.false()),
		sa.Column("email_consent_at", sa.DateTime(), nullable=True),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["referrer_person_id"], ["persons.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "person_id", name="uq_customer_club_member_biz_person"),
		sa.UniqueConstraint("business_id", "referral_code", name="uq_customer_club_member_referral"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_customer_club_members_business_id", "customer_club_members", ["business_id"])
	op.create_index("ix_customer_club_members_person_id", "customer_club_members", ["person_id"])
	op.add_column("customer_club_members", sa.Column("referral_rewarded_at", sa.DateTime(), nullable=True))

	op.create_table(
		"customer_club_survey_responses",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("survey_key", sa.String(80), nullable=False),
		sa.Column("score", sa.SmallInteger(), nullable=True),
		sa.Column("comment", sa.Text(), nullable=True),
		sa.Column("points_awarded", sa.Numeric(18, 6), nullable=False, server_default="0"),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "person_id", "survey_key", name="uq_customer_club_survey_person"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_customer_club_survey_responses_business_id", "customer_club_survey_responses", ["business_id"])
	op.create_index("ix_customer_club_survey_responses_person_id", "customer_club_survey_responses", ["person_id"])


def downgrade() -> None:
	op.drop_column("customer_club_tiers", "benefits_json")
	op.drop_table("customer_club_survey_responses")
	op.drop_column("customer_club_members", "referral_rewarded_at")
	op.drop_table("customer_club_members")
	op.drop_constraint("fk_customer_club_campaign_members_conversion_document", "customer_club_campaign_members", type_="foreignkey")
	op.drop_column("customer_club_campaign_members", "converted_at")
	op.drop_column("customer_club_campaign_members", "conversion_amount")
	op.drop_column("customer_club_campaign_members", "conversion_document_id")
	op.drop_constraint("fk_customer_club_invoice_snapshots_voucher_id", "customer_club_invoice_snapshots", type_="foreignkey")
	op.drop_column("customer_club_invoice_snapshots", "voucher_id")
	op.drop_table("customer_club_campaign_members")
	op.drop_table("customer_club_vouchers")
	op.drop_table("customer_club_campaigns")
	op.drop_table("customer_club_rewards")
	op.drop_table("customer_club_point_lots")
	op.drop_column("customer_club_settings", "survey_points")
	op.drop_column("customer_club_settings", "referral_points")
