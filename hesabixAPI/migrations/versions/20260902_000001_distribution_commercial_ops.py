"""فاز تجاری پخش: Pre-sell، پروموشن، تحویل، بارگیری، پورسانت، trail، ممیزی، دارایی.

Revision ID: 20260902_000001_distribution_commercial_ops
Revises: 20260901_000002_distribution_day_sort
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260902_000001_distribution_commercial_ops"
down_revision = "20260901_000002_distribution_day_sort"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# --- settings columns ---
	op.add_column(
		"distribution_business_settings",
		sa.Column("enable_presell", sa.Boolean(), nullable=False, server_default=sa.text("0")),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("enable_promotions", sa.Boolean(), nullable=False, server_default=sa.text("0")),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column(
			"visitor_max_discount_percent",
			sa.Numeric(5, 2),
			nullable=False,
			server_default="0",
		),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("enable_suggested_order", sa.Boolean(), nullable=False, server_default=sa.text("1")),
	)

	# --- settlement cheque refs ---
	op.add_column(
		"distribution_daily_settlements",
		sa.Column("cheque_refs", sa.JSON(), nullable=True),
	)

	# --- sales targets: multi-metric ---
	op.add_column(
		"distribution_sales_targets",
		sa.Column("metric", sa.String(length=32), nullable=False, server_default="amount"),
	)
	op.add_column(
		"distribution_sales_targets",
		sa.Column("product_id", sa.Integer(), nullable=True),
	)
	op.add_column(
		"distribution_sales_targets",
		sa.Column("target_value", sa.Numeric(18, 2), nullable=True),
	)
	try:
		op.create_foreign_key(
			"fk_distribution_sales_targets_product",
			"distribution_sales_targets",
			"products",
			["product_id"],
			["id"],
			ondelete="SET NULL",
		)
	except Exception:
		pass
	# relax unique: drop old, add new including metric+product
	try:
		op.drop_constraint("uq_distribution_sales_target_period", "distribution_sales_targets", type_="unique")
	except Exception:
		pass
	op.create_unique_constraint(
		"uq_distribution_sales_target_metric",
		"distribution_sales_targets",
		["business_id", "user_id", "period_type", "period_start", "metric", "product_id"],
	)

	# --- visit GPS trail ---
	op.create_table(
		"distribution_visit_heartbeats",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("visit_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("latitude", sa.Numeric(11, 8), nullable=False),
		sa.Column("longitude", sa.Numeric(11, 8), nullable=False),
		sa.Column("recorded_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["visit_id"], ["distribution_field_visits.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_dist_visit_hb_visit", "distribution_visit_heartbeats", ["visit_id"])
	op.create_index("ix_dist_visit_hb_biz_user", "distribution_visit_heartbeats", ["business_id", "user_id"])

	# --- pre-sell orders ---
	op.create_table(
		"distribution_visit_orders",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("visit_id", sa.Integer(), nullable=True),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("route_id", sa.Integer(), nullable=True),
		sa.Column("status", sa.String(length=32), nullable=False, server_default="draft"),
		sa.Column("lines", sa.JSON(), nullable=False),
		sa.Column("document_id", sa.Integer(), nullable=True),
		sa.Column("delivery_trip_id", sa.Integer(), nullable=True),
		sa.Column("requested_delivery_date", sa.Date(), nullable=True),
		sa.Column("promotion_ids", sa.JSON(), nullable=True),
		sa.Column("discount_total", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("net_total", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["visit_id"], ["distribution_field_visits.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["route_id"], ["distribution_routes.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_dist_visit_orders_biz", "distribution_visit_orders", ["business_id"])
	op.create_index("ix_dist_visit_orders_status", "distribution_visit_orders", ["business_id", "status"])
	op.create_index("ix_dist_visit_orders_person", "distribution_visit_orders", ["person_id"])

	# --- trade promotions ---
	op.create_table(
		"distribution_trade_promotions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=50), nullable=False),
		sa.Column("name", sa.String(length=255), nullable=False),
		sa.Column("mechanic", sa.String(length=32), nullable=False),
		sa.Column("config", sa.JSON(), nullable=False),
		sa.Column("valid_from", sa.Date(), nullable=False),
		sa.Column("valid_to", sa.Date(), nullable=True),
		sa.Column("territory_id", sa.Integer(), nullable=True),
		sa.Column("route_id", sa.Integer(), nullable=True),
		sa.Column("product_ids", sa.JSON(), nullable=True),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("1")),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["territory_id"], ["distribution_territories.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["route_id"], ["distribution_routes.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_distribution_promo_code"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_dist_promo_biz", "distribution_trade_promotions", ["business_id"])

	# --- delivery trips ---
	op.create_table(
		"distribution_delivery_trips",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("driver_user_id", sa.Integer(), nullable=False),
		sa.Column("van_id", sa.Integer(), nullable=True),
		sa.Column("trip_date", sa.Date(), nullable=False),
		sa.Column("status", sa.String(length=32), nullable=False, server_default="draft"),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("started_at", sa.DateTime(), nullable=True),
		sa.Column("completed_at", sa.DateTime(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["driver_user_id"], ["users.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["van_id"], ["distribution_vans.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_dist_delivery_trips_biz_date", "distribution_delivery_trips", ["business_id", "trip_date"])

	op.create_table(
		"distribution_delivery_stops",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("trip_id", sa.Integer(), nullable=False),
		sa.Column("order_id", sa.Integer(), nullable=True),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("status", sa.String(length=32), nullable=False, server_default="pending"),
		sa.Column("pod_confirmed", sa.Boolean(), nullable=False, server_default=sa.text("0")),
		sa.Column("pod_signer_name", sa.String(length=255), nullable=True),
		sa.Column("pod_note", sa.Text(), nullable=True),
		sa.Column("pod_photo_file_id", sa.Integer(), nullable=True),
		sa.Column("pod_latitude", sa.Numeric(11, 8), nullable=True),
		sa.Column("pod_longitude", sa.Numeric(11, 8), nullable=True),
		sa.Column("delivered_qty_snapshot", sa.JSON(), nullable=True),
		sa.Column("failure_reason", sa.String(length=255), nullable=True),
		sa.Column("completed_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["trip_id"], ["distribution_delivery_trips.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["order_id"], ["distribution_visit_orders.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_dist_delivery_stops_trip", "distribution_delivery_stops", ["trip_id"])

	# FK order → trip (after trips exist)
	op.create_foreign_key(
		"fk_dist_visit_orders_delivery_trip",
		"distribution_visit_orders",
		"distribution_delivery_trips",
		["delivery_trip_id"],
		["id"],
		ondelete="SET NULL",
	)

	# --- load plans ---
	op.create_table(
		"distribution_load_plans",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("plan_date", sa.Date(), nullable=False),
		sa.Column("warehouse_id", sa.Integer(), nullable=True),
		sa.Column("van_id", sa.Integer(), nullable=True),
		sa.Column("status", sa.String(length=32), nullable=False, server_default="draft"),
		sa.Column("lines", sa.JSON(), nullable=False),
		sa.Column("order_ids", sa.JSON(), nullable=True),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("confirmed_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["warehouse_id"], ["warehouses.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["van_id"], ["distribution_vans.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_dist_load_plans_biz_date", "distribution_load_plans", ["business_id", "plan_date"])

	# --- commission ---
	op.create_table(
		"distribution_commission_rules",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("name", sa.String(length=255), nullable=False),
		sa.Column("rule_type", sa.String(length=32), nullable=False, server_default="percent_of_sales"),
		sa.Column("config", sa.JSON(), nullable=False),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("1")),
		sa.Column("valid_from", sa.Date(), nullable=True),
		sa.Column("valid_to", sa.Date(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_dist_commission_rules_biz", "distribution_commission_rules", ["business_id"])

	op.create_table(
		"distribution_commission_runs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("period_start", sa.Date(), nullable=False),
		sa.Column("period_end", sa.Date(), nullable=False),
		sa.Column("rule_id", sa.Integer(), nullable=True),
		sa.Column("sales_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("commission_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("status", sa.String(length=32), nullable=False, server_default="draft"),
		sa.Column("breakdown", sa.JSON(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["rule_id"], ["distribution_commission_rules.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_dist_commission_runs_biz", "distribution_commission_runs", ["business_id", "period_start"])

	# --- shelf audits ---
	op.create_table(
		"distribution_shelf_audits",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("visit_id", sa.Integer(), nullable=True),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("answers", sa.JSON(), nullable=False),
		sa.Column("score", sa.Numeric(5, 2), nullable=True),
		sa.Column("photo_file_ids", sa.JSON(), nullable=True),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["visit_id"], ["distribution_field_visits.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_dist_shelf_audits_biz", "distribution_shelf_audits", ["business_id"])

	# --- customer assets ---
	op.create_table(
		"distribution_customer_assets",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("asset_code", sa.String(length=64), nullable=False),
		sa.Column("asset_type", sa.String(length=64), nullable=False),
		sa.Column("name", sa.String(length=255), nullable=False),
		sa.Column("status", sa.String(length=32), nullable=False, server_default="active"),
		sa.Column("placed_at", sa.Date(), nullable=True),
		sa.Column("last_checked_at", sa.DateTime(), nullable=True),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "asset_code", name="uq_dist_customer_asset_code"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_dist_customer_assets_person", "distribution_customer_assets", ["person_id"])


def downgrade() -> None:
	op.drop_table("distribution_customer_assets")
	op.drop_table("distribution_shelf_audits")
	op.drop_table("distribution_commission_runs")
	op.drop_table("distribution_commission_rules")
	op.drop_table("distribution_load_plans")
	op.drop_constraint("fk_dist_visit_orders_delivery_trip", "distribution_visit_orders", type_="foreignkey")
	op.drop_table("distribution_delivery_stops")
	op.drop_table("distribution_delivery_trips")
	op.drop_table("distribution_trade_promotions")
	op.drop_table("distribution_visit_orders")
	op.drop_table("distribution_visit_heartbeats")
	try:
		op.drop_constraint("uq_distribution_sales_target_metric", "distribution_sales_targets", type_="unique")
	except Exception:
		pass
	try:
		op.drop_constraint("fk_distribution_sales_targets_product", "distribution_sales_targets", type_="foreignkey")
	except Exception:
		pass
	op.drop_column("distribution_sales_targets", "target_value")
	op.drop_column("distribution_sales_targets", "product_id")
	op.drop_column("distribution_sales_targets", "metric")
	op.drop_column("distribution_daily_settlements", "cheque_refs")
	op.drop_column("distribution_business_settings", "enable_suggested_order")
	op.drop_column("distribution_business_settings", "visitor_max_discount_percent")
	op.drop_column("distribution_business_settings", "enable_promotions")
	op.drop_column("distribution_business_settings", "enable_presell")
