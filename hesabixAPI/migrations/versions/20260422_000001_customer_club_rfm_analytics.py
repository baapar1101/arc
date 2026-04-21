"""باشگاه مشتریان: تنظیمات تحلیل RFM/CLV و جدول snapshot

Revision ID: 20260422_000001_customer_club_rfm_analytics
Revises: 20260421_000001_distribution_settings_visit_geo
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260422_000001_customer_club_rfm_analytics"
down_revision = "20260421_000001_distribution_settings_visit_geo"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"rfm_analytics_enabled",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("false"),
			comment="فعال‌سازی محاسبه و نمایش تحلیل RFM",
		),
	)
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"clv_analytics_enabled",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("false"),
			comment="فعال‌سازی تخمین ارزش طول عمر مشتری",
		),
	)
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"rfm_analysis_window_months",
			sa.Integer(),
			nullable=False,
			server_default=sa.text("12"),
			comment="پنجرهٔ ماه برای تجمیع F و M",
		),
	)
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"rfm_monetary_basis",
			sa.String(length=40),
			nullable=False,
			server_default=sa.text("'net'"),
			comment="net | total_with_tax برای متریک M",
		),
	)
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"rfm_scoring_method",
			sa.String(length=32),
			nullable=False,
			server_default=sa.text("'quintiles'"),
			comment="quintiles | weighted",
		),
	)
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"rfm_weight_recency",
			sa.Numeric(precision=18, scale=8),
			nullable=True,
			comment="وزن R در حالت weighted (اختیاری)",
		),
	)
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"rfm_weight_frequency",
			sa.Numeric(precision=18, scale=8),
			nullable=True,
			comment="وزن F در حالت weighted",
		),
	)
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"rfm_weight_monetary",
			sa.Numeric(precision=18, scale=8),
			nullable=True,
			comment="وزن M در حالت weighted",
		),
	)
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"clv_formula",
			sa.String(length=40),
			nullable=False,
			server_default=sa.text("'historical_total'"),
			comment="historical_total | avg_order_projection",
		),
	)
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"clv_avg_lifespan_years",
			sa.Numeric(precision=10, scale=4),
			nullable=True,
			server_default=sa.text("3"),
			comment="عمر مشتری تخمینی (سال) برای فرمول projection",
		),
	)
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"rfm_segment_labels_json",
			sa.JSON(),
			nullable=True,
			comment='برچسب سفارشی برای کلید "r-f-m" مثل {"5-5-5":"قهرمانان"}',
		),
	)

	op.create_table(
		"customer_club_rfm_snapshots",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("recency_days", sa.Integer(), nullable=True),
		sa.Column("frequency_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column(
			"monetary_total",
			sa.Numeric(precision=18, scale=4),
			nullable=False,
			server_default=sa.text("0"),
		),
		sa.Column("r_score", sa.SmallInteger(), nullable=True),
		sa.Column("f_score", sa.SmallInteger(), nullable=True),
		sa.Column("m_score", sa.SmallInteger(), nullable=True),
		sa.Column("rfm_cell", sa.String(length=16), nullable=True),
		sa.Column("segment_label", sa.String(length=160), nullable=True),
		sa.Column("composite_score", sa.Numeric(precision=18, scale=8), nullable=True),
		sa.Column("clv_estimate", sa.Numeric(precision=18, scale=4), nullable=True),
		sa.Column("computed_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "person_id", name="uq_cc_rfm_snap_biz_person"),
		mysql_charset="utf8mb4",
	)
	op.create_index(op.f("ix_customer_club_rfm_snapshots_business_id"), "customer_club_rfm_snapshots", ["business_id"], unique=False)
	op.create_index(op.f("ix_customer_club_rfm_snapshots_person_id"), "customer_club_rfm_snapshots", ["person_id"], unique=False)
	op.create_index("ix_cc_rfm_snap_biz_segment", "customer_club_rfm_snapshots", ["business_id", "segment_label"], unique=False)
	op.create_index("ix_cc_rfm_snap_biz_computed", "customer_club_rfm_snapshots", ["business_id", "computed_at"], unique=False)


def downgrade() -> None:
	op.drop_index("ix_cc_rfm_snap_biz_computed", table_name="customer_club_rfm_snapshots")
	op.drop_index("ix_cc_rfm_snap_biz_segment", table_name="customer_club_rfm_snapshots")
	op.drop_index(op.f("ix_customer_club_rfm_snapshots_person_id"), table_name="customer_club_rfm_snapshots")
	op.drop_index(op.f("ix_customer_club_rfm_snapshots_business_id"), table_name="customer_club_rfm_snapshots")
	op.drop_table("customer_club_rfm_snapshots")

	op.drop_column("customer_club_settings", "rfm_segment_labels_json")
	op.drop_column("customer_club_settings", "clv_avg_lifespan_years")
	op.drop_column("customer_club_settings", "clv_formula")
	op.drop_column("customer_club_settings", "rfm_weight_monetary")
	op.drop_column("customer_club_settings", "rfm_weight_frequency")
	op.drop_column("customer_club_settings", "rfm_weight_recency")
	op.drop_column("customer_club_settings", "rfm_scoring_method")
	op.drop_column("customer_club_settings", "rfm_monetary_basis")
	op.drop_column("customer_club_settings", "rfm_analysis_window_months")
	op.drop_column("customer_club_settings", "clv_analytics_enabled")
	op.drop_column("customer_club_settings", "rfm_analytics_enabled")
