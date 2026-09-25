"""ارتقای عملیاتی پخش مویرگی: چرخه ویزیت، پروفایل مشتری، لات ون، POD.

Revision ID: 20260907_000002_distribution_field_ops_upgrade
Revises: 20260907_000001_distribution_live_location
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260907_000002_distribution_field_ops_upgrade"
down_revision = "20260907_000001_distribution_live_location"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"distribution_business_settings",
		sa.Column("carry_over_missed_visits", sa.Boolean(), nullable=False, server_default=sa.text("true")),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("carry_over_days", sa.Integer(), nullable=False, server_default="7"),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("require_pod_signature", sa.Boolean(), nullable=False, server_default=sa.text("false")),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("require_pod_photo", sa.Boolean(), nullable=False, server_default=sa.text("false")),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("nav_provider", sa.String(length=16), nullable=False, server_default="neshan"),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("setup_completed", sa.Boolean(), nullable=False, server_default=sa.text("false")),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("auto_apply_promotions", sa.Boolean(), nullable=False, server_default=sa.text("true")),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("enable_perfect_store", sa.Boolean(), nullable=False, server_default=sa.text("true")),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("near_expiry_days", sa.Integer(), nullable=False, server_default="14"),
	)

	op.add_column(
		"distribution_route_stops",
		sa.Column("frequency", sa.String(length=16), nullable=False, server_default="weekly"),
	)
	op.add_column(
		"distribution_route_stops",
		sa.Column("cycle_offset", sa.Integer(), nullable=False, server_default="0"),
	)
	op.add_column(
		"distribution_route_stops",
		sa.Column("customer_class", sa.String(length=8), nullable=True),
	)

	op.add_column("distribution_vans", sa.Column("max_weight_kg", sa.Numeric(12, 2), nullable=True))
	op.add_column("distribution_vans", sa.Column("max_volume_m3", sa.Numeric(12, 3), nullable=True))
	op.add_column("distribution_vans", sa.Column("plate_number", sa.String(length=32), nullable=True))

	op.add_column(
		"distribution_field_visits",
		sa.Column("supervisor_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
	)
	op.add_column(
		"distribution_field_visits",
		sa.Column("no_order_reason_code", sa.String(length=32), nullable=True),
	)
	op.add_column(
		"distribution_field_visits",
		sa.Column("is_carried_over", sa.Boolean(), nullable=False, server_default=sa.text("false")),
	)
	op.add_column(
		"distribution_field_visits",
		sa.Column("pod_signature_file_id", sa.Integer(), nullable=True),
	)

	op.create_table(
		"distribution_customer_profiles",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("customer_class", sa.String(length=8), nullable=True),
		sa.Column("visit_frequency", sa.String(length=16), nullable=False, server_default="weekly"),
		sa.Column("cycle_offset", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("price_list_id", sa.Integer(), nullable=True),
		sa.Column("outlet_type", sa.String(length=32), nullable=True),
		sa.Column("assortment_id", sa.Integer(), nullable=True),
		sa.Column("storefront_photo_file_id", sa.Integer(), nullable=True),
		sa.Column("onboarded_at", sa.DateTime(), nullable=True),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["price_list_id"], ["price_lists.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "person_id", name="uq_dist_customer_profile_person"),
	)
	op.create_index("ix_dist_cust_profile_biz", "distribution_customer_profiles", ["business_id"])
	op.create_index("ix_dist_cust_profile_person", "distribution_customer_profiles", ["person_id"])

	op.create_table(
		"distribution_assortments",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=50), nullable=False),
		sa.Column("name", sa.String(length=255), nullable=False),
		sa.Column("outlet_type", sa.String(length=32), nullable=True),
		sa.Column("product_ids", sa.JSON(), nullable=True),
		sa.Column("must_sell_product_ids", sa.JSON(), nullable=True),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_dist_assortment_code"),
	)
	op.create_index("ix_dist_assortment_biz", "distribution_assortments", ["business_id"])

	op.create_table(
		"distribution_van_lots",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("van_id", sa.Integer(), nullable=False),
		sa.Column("product_id", sa.Integer(), nullable=False),
		sa.Column("lot_code", sa.String(length=64), nullable=False, server_default="-"),
		sa.Column("expiry_date", sa.Date(), nullable=True),
		sa.Column("quantity", sa.Numeric(18, 3), nullable=False),
		sa.Column("unit_weight_kg", sa.Numeric(12, 3), nullable=True),
		sa.Column("unit_volume_m3", sa.Numeric(12, 4), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["van_id"], ["distribution_vans.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint(
			"van_id", "product_id", "lot_code", "expiry_date",
			name="uq_dist_van_lot_key",
		),
	)
	op.create_index("ix_dist_van_lot_van", "distribution_van_lots", ["van_id"])
	op.create_index("ix_dist_van_lot_product", "distribution_van_lots", ["product_id"])

	op.create_foreign_key(
		"fk_dist_cust_profile_assortment",
		"distribution_customer_profiles",
		"distribution_assortments",
		["assortment_id"],
		["id"],
		ondelete="SET NULL",
	)


def downgrade() -> None:
	op.drop_constraint("fk_dist_cust_profile_assortment", "distribution_customer_profiles", type_="foreignkey")
	op.drop_index("ix_dist_van_lot_product", table_name="distribution_van_lots")
	op.drop_index("ix_dist_van_lot_van", table_name="distribution_van_lots")
	op.drop_table("distribution_van_lots")
	op.drop_index("ix_dist_assortment_biz", table_name="distribution_assortments")
	op.drop_table("distribution_assortments")
	op.drop_index("ix_dist_cust_profile_person", table_name="distribution_customer_profiles")
	op.drop_index("ix_dist_cust_profile_biz", table_name="distribution_customer_profiles")
	op.drop_table("distribution_customer_profiles")
	op.drop_column("distribution_field_visits", "pod_signature_file_id")
	op.drop_column("distribution_field_visits", "is_carried_over")
	op.drop_column("distribution_field_visits", "no_order_reason_code")
	op.drop_column("distribution_field_visits", "supervisor_user_id")
	op.drop_column("distribution_vans", "plate_number")
	op.drop_column("distribution_vans", "max_volume_m3")
	op.drop_column("distribution_vans", "max_weight_kg")
	op.drop_column("distribution_route_stops", "customer_class")
	op.drop_column("distribution_route_stops", "cycle_offset")
	op.drop_column("distribution_route_stops", "frequency")
	op.drop_column("distribution_business_settings", "near_expiry_days")
	op.drop_column("distribution_business_settings", "enable_perfect_store")
	op.drop_column("distribution_business_settings", "auto_apply_promotions")
	op.drop_column("distribution_business_settings", "setup_completed")
	op.drop_column("distribution_business_settings", "nav_provider")
	op.drop_column("distribution_business_settings", "require_pod_photo")
	op.drop_column("distribution_business_settings", "require_pod_signature")
	op.drop_column("distribution_business_settings", "carry_over_days")
	op.drop_column("distribution_business_settings", "carry_over_missed_visits")
