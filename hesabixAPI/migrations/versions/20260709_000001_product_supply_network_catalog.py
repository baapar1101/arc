"""شبکه تأمین کالا: پروفایل کاتالوگ محصول و قالب فیلدهای مشخصات

Revision ID: 20260709_000001_product_supply_network_catalog
Revises: 20260707_000001_payroll_plugin_tables
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260709_000001_product_supply_network_catalog"
down_revision = "20260707_000001_payroll_plugin_tables"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"products",
		sa.Column(
			"catalog_short_description",
			sa.Text(),
			nullable=True,
			comment="خلاصه کوتاه برای کاتالوگ عمومی",
		),
	)
	op.add_column(
		"products",
		sa.Column(
			"catalog_expert_review",
			sa.Text(),
			nullable=True,
			comment="بررسی تخصصی برای کاتالوگ عمومی",
		),
	)
	op.add_column(
		"products",
		sa.Column(
			"catalog_specifications",
			sa.JSON(),
			nullable=True,
			comment="مشخصات فنی کاتالوگ [{field_id, label, value, sort_order}]",
		),
	)
	op.add_column(
		"products",
		sa.Column(
			"catalog_brand",
			sa.String(length=255),
			nullable=True,
			comment="برند در کاتالوگ عمومی",
		),
	)
	op.add_column(
		"products",
		sa.Column(
			"catalog_model",
			sa.String(length=255),
			nullable=True,
			comment="مدل در کاتالوگ عمومی",
		),
	)
	op.add_column(
		"products",
		sa.Column(
			"catalog_country_of_origin",
			sa.String(length=128),
			nullable=True,
			comment="کشور سازنده در کاتالوگ عمومی",
		),
	)
	op.add_column(
		"products",
		sa.Column(
			"catalog_video_url",
			sa.String(length=512),
			nullable=True,
			comment="لینک ویدیو معرفی در کاتالوگ عمومی",
		),
	)

	op.create_table(
		"business_catalog_spec_fields",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("title", sa.String(length=255), nullable=False),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column(
			"data_type",
			sa.String(length=32),
			nullable=False,
			server_default="text",
			comment="text, number, date, select, boolean",
		),
		sa.Column("options", sa.JSON(), nullable=True),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("is_required", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("now()")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("now()")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "title", name="uq_business_catalog_spec_fields_business_title"),
	)
	op.create_index(
		"ix_business_catalog_spec_fields_business_id",
		"business_catalog_spec_fields",
		["business_id"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index("ix_business_catalog_spec_fields_business_id", table_name="business_catalog_spec_fields")
	op.drop_table("business_catalog_spec_fields")
	for col in (
		"catalog_video_url",
		"catalog_country_of_origin",
		"catalog_model",
		"catalog_brand",
		"catalog_specifications",
		"catalog_expert_review",
		"catalog_short_description",
	):
		op.drop_column("products", col)
