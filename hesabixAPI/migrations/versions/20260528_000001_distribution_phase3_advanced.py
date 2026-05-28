"""فاز ۳ افزونه پخش: ون، geofence، چک‌لیست، مختصات

Revision ID: 20260528_000001_distribution_phase3_advanced
Revises: 20260627_000001_ai_phase7_schedule
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260528_000001_distribution_phase3_advanced"
down_revision = "20260627_000001_ai_phase7_schedule"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"distribution_business_settings",
		sa.Column("geofence_radius_meters", sa.Integer(), nullable=False, server_default="0"),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("require_geofence", sa.Boolean(), nullable=False, server_default="0"),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("visit_checklist_template", sa.JSON(), nullable=True),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("enable_van_sales", sa.Boolean(), nullable=False, server_default="0"),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column(
			"default_source_warehouse_id",
			sa.Integer(),
			sa.ForeignKey("warehouses.id", ondelete="SET NULL"),
			nullable=True,
		),
	)

	op.add_column("persons", sa.Column("latitude", sa.Numeric(11, 8), nullable=True))
	op.add_column("persons", sa.Column("longitude", sa.Numeric(11, 8), nullable=True))

	op.add_column("distribution_field_visits", sa.Column("end_latitude", sa.Numeric(11, 8), nullable=True))
	op.add_column("distribution_field_visits", sa.Column("end_longitude", sa.Numeric(11, 8), nullable=True))
	op.add_column("distribution_field_visits", sa.Column("checklist_answers", sa.JSON(), nullable=True))
	op.add_column("distribution_field_visits", sa.Column("shelf_photo_file_id", sa.Integer(), nullable=True))

	op.create_table(
		"distribution_vans",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("warehouse_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=True),
		sa.Column("code", sa.String(length=50), nullable=False),
		sa.Column("name", sa.String(length=255), nullable=False),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default="1"),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["warehouse_id"], ["warehouses.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_distribution_vans_business_code"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_distribution_vans_business_user", "distribution_vans", ["business_id", "user_id"])

	op.create_table(
		"distribution_offline_sync_batches",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("client_batch_id", sa.String(length=64), nullable=False),
		sa.Column("actions", sa.JSON(), nullable=False),
		sa.Column("results", sa.JSON(), nullable=True),
		sa.Column("status", sa.String(length=32), nullable=False, server_default="'completed'"),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "client_batch_id", name="uq_distribution_offline_batch"),
		mysql_charset="utf8mb4",
	)


def downgrade() -> None:
	op.drop_table("distribution_offline_sync_batches")
	op.drop_index("ix_distribution_vans_business_user", table_name="distribution_vans")
	op.drop_table("distribution_vans")
	op.drop_column("distribution_field_visits", "shelf_photo_file_id")
	op.drop_column("distribution_field_visits", "checklist_answers")
	op.drop_column("distribution_field_visits", "end_longitude")
	op.drop_column("distribution_field_visits", "end_latitude")
	op.drop_column("persons", "longitude")
	op.drop_column("persons", "latitude")
	op.drop_column("distribution_business_settings", "default_source_warehouse_id")
	op.drop_column("distribution_business_settings", "enable_van_sales")
	op.drop_column("distribution_business_settings", "visit_checklist_template")
	op.drop_column("distribution_business_settings", "require_geofence")
	op.drop_column("distribution_business_settings", "geofence_radius_meters")
