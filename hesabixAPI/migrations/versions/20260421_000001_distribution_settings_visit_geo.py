"""تنظیمات افزونه پخش و مختصات شروع ویزیت

Revision ID: 20260421_000001_distribution_settings_visit_geo
Revises: 20260420_000002_warehouse_document_code_per_business
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260421_000001_distribution_settings_visit_geo"
down_revision = "20260420_000002_warehouse_document_code_per_business"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"distribution_business_settings",
		sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), primary_key=True),
		sa.Column(
			"shared_routing_catalog",
			sa.Boolean(),
			nullable=False,
			server_default="0",
			comment="اگر 0 باشد ویزیتور عادی فقط مسیرها و قلمروهای تخصیص‌خوردهٔ خود را می‌بیند",
		),
		sa.Column(
			"require_visit_in_daily_plan",
			sa.Boolean(),
			nullable=False,
			server_default="0",
			comment="شروع ویزیت فقط برای اشخاص حاضر در برنامهٔ روز همان ویزیتور",
		),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
	)
	op.add_column(
		"distribution_field_visits",
		sa.Column("start_latitude", sa.Numeric(11, 8), nullable=True),
	)
	op.add_column(
		"distribution_field_visits",
		sa.Column("start_longitude", sa.Numeric(11, 8), nullable=True),
	)


def downgrade() -> None:
	op.drop_column("distribution_field_visits", "start_longitude")
	op.drop_column("distribution_field_visits", "start_latitude")
	op.drop_table("distribution_business_settings")
