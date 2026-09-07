"""موقعیت زنده ویزیتور برای نقشه تیم.

Revision ID: 20260907_000001_distribution_live_location
Revises: 20260906_000001_distribution_map_tile_source
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260907_000001_distribution_live_location"
down_revision = "20260906_000001_distribution_map_tile_source"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"distribution_business_settings",
		sa.Column(
			"share_live_location",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("true"),
			comment="اشتراک موقعیت ویزیتور با مدیر",
		),
	)
	op.alter_column(
		"distribution_visit_heartbeats",
		"visit_id",
		existing_type=sa.Integer(),
		nullable=True,
	)
	op.create_table(
		"distribution_user_live_locations",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("visit_id", sa.Integer(), nullable=True),
		sa.Column("latitude", sa.Numeric(11, 8), nullable=False),
		sa.Column("longitude", sa.Numeric(11, 8), nullable=False),
		sa.Column("recorded_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["visit_id"], ["distribution_field_visits.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "user_id", name="uq_dist_user_live_location"),
	)
	op.create_index(
		"ix_dist_user_live_loc_biz",
		"distribution_user_live_locations",
		["business_id"],
	)
	op.create_index(
		"ix_dist_user_live_loc_user",
		"distribution_user_live_locations",
		["user_id"],
	)


def downgrade() -> None:
	op.drop_index("ix_dist_user_live_loc_user", table_name="distribution_user_live_locations")
	op.drop_index("ix_dist_user_live_loc_biz", table_name="distribution_user_live_locations")
	op.drop_table("distribution_user_live_locations")
	op.alter_column(
		"distribution_visit_heartbeats",
		"visit_id",
		existing_type=sa.Integer(),
		nullable=False,
	)
	op.drop_column("distribution_business_settings", "share_live_location")
