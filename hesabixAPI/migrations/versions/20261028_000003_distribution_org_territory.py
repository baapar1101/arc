"""ساختار سازمانی پخش: انحصار قلمرو، مالکیت مشتری، ناظر، رضایت GPS، قفل برنامه.

Revision ID: 20261028_000003_distribution_org_territory
Revises: 20261028_000002_distribution_offline_batch_user
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261028_000003_distribution_org_territory"
down_revision = "20261028_000002_distribution_offline_batch_user"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"distribution_business_settings",
		sa.Column("exclusive_assignments", sa.Boolean(), nullable=False, server_default=sa.text("true")),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("exclusive_territories", sa.Boolean(), nullable=False, server_default=sa.text("false")),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column(
			"exclusive_customer_ownership",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("true"),
		),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("require_location_consent", sa.Boolean(), nullable=False, server_default=sa.text("true")),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("lock_published_plans", sa.Boolean(), nullable=False, server_default=sa.text("false")),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column("require_published_plan", sa.Boolean(), nullable=False, server_default=sa.text("false")),
	)

	op.add_column(
		"distribution_territories",
		sa.Column("parent_id", sa.Integer(), sa.ForeignKey("distribution_territories.id", ondelete="SET NULL"), nullable=True),
	)
	op.add_column(
		"distribution_territories",
		sa.Column("supervisor_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
	)
	op.create_index("ix_distribution_territories_parent_id", "distribution_territories", ["parent_id"])
	op.create_index("ix_distribution_territories_supervisor_user_id", "distribution_territories", ["supervisor_user_id"])

	op.add_column(
		"distribution_customer_profiles",
		sa.Column("owner_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
	)
	op.create_index("ix_distribution_customer_profiles_owner_user_id", "distribution_customer_profiles", ["owner_user_id"])

	op.create_table(
		"distribution_user_preferences",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True),
		sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
		sa.Column("location_consent", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("location_consent_at", sa.DateTime(), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.UniqueConstraint("business_id", "user_id", name="uq_dist_user_pref_business_user"),
	)
	op.create_table(
		"distribution_daily_plan_locks",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True),
		sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
		sa.Column("plan_date", sa.Date(), nullable=False, index=True),
		sa.Column("is_locked", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("published_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
		sa.Column("published_at", sa.DateTime(), nullable=False),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.UniqueConstraint("business_id", "user_id", "plan_date", name="uq_dist_daily_plan_lock"),
	)


def downgrade() -> None:
	op.drop_table("distribution_daily_plan_locks")
	op.drop_table("distribution_user_preferences")
	op.drop_index("ix_distribution_customer_profiles_owner_user_id", table_name="distribution_customer_profiles")
	op.drop_column("distribution_customer_profiles", "owner_user_id")
	op.drop_index("ix_distribution_territories_supervisor_user_id", table_name="distribution_territories")
	op.drop_index("ix_distribution_territories_parent_id", table_name="distribution_territories")
	op.drop_column("distribution_territories", "supervisor_user_id")
	op.drop_column("distribution_territories", "parent_id")
	op.drop_column("distribution_business_settings", "require_published_plan")
	op.drop_column("distribution_business_settings", "lock_published_plans")
	op.drop_column("distribution_business_settings", "require_location_consent")
	op.drop_column("distribution_business_settings", "exclusive_customer_ownership")
	op.drop_column("distribution_business_settings", "exclusive_territories")
	op.drop_column("distribution_business_settings", "exclusive_assignments")
