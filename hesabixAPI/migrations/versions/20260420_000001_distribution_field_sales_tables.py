"""جداول افزونه پخش مویرگی و ویزیتوری

Revision ID: 20260420_000001_distribution_field_sales_tables
Revises: 20260419_000002_seed_year_end_fixed_accounts
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260420_000001_distribution_field_sales_tables"
down_revision = "20260419_000002_seed_year_end_fixed_accounts"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"distribution_territories",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=50), nullable=False),
		sa.Column("name", sa.String(length=255), nullable=False),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_distribution_territories_business_code"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_distribution_territories_business_id", "distribution_territories", ["business_id"])

	op.create_table(
		"distribution_routes",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("territory_id", sa.Integer(), nullable=True),
		sa.Column("code", sa.String(length=50), nullable=False),
		sa.Column("name", sa.String(length=255), nullable=False),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["territory_id"], ["distribution_territories.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_distribution_routes_business_code"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_distribution_routes_business_id", "distribution_routes", ["business_id"])
	op.create_index("ix_distribution_routes_territory_id", "distribution_routes", ["territory_id"])

	op.create_table(
		"distribution_route_stops",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("route_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column(
			"weekday",
			sa.Integer(),
			nullable=True,
			comment="0=دوشنبه .. 6=یکشنبه ISO؛ NULL = هر روز",
		),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["route_id"], ["distribution_routes.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("route_id", "person_id", "weekday", name="uq_distribution_route_stop_route_person_weekday"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_distribution_route_stops_route_id", "distribution_route_stops", ["route_id"])
	op.create_index("ix_distribution_route_stops_person_id", "distribution_route_stops", ["person_id"])

	op.create_table(
		"distribution_route_assignments",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("route_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("valid_from", sa.Date(), nullable=False),
		sa.Column("valid_to", sa.Date(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["route_id"], ["distribution_routes.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index(
		"ix_distribution_route_assignments_business_route_user",
		"distribution_route_assignments",
		["business_id", "route_id", "user_id"],
	)

	op.create_table(
		"distribution_field_visits",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("route_id", sa.Integer(), nullable=True),
		sa.Column("route_stop_id", sa.Integer(), nullable=True),
		sa.Column("status", sa.String(length=32), nullable=False),
		sa.Column("started_at", sa.DateTime(), nullable=False),
		sa.Column("ended_at", sa.DateTime(), nullable=True),
		sa.Column("outcome", sa.String(length=32), nullable=True),
		sa.Column("no_order_reason", sa.String(length=255), nullable=True),
		sa.Column("document_id", sa.Integer(), nullable=True),
		sa.Column("deal_id", sa.Integer(), nullable=True),
		sa.Column("crm_activity_id", sa.Integer(), nullable=True),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["route_id"], ["distribution_routes.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["route_stop_id"], ["distribution_route_stops.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["deal_id"], ["crm_deals.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["crm_activity_id"], ["crm_activities.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_distribution_field_visits_business_started", "distribution_field_visits", ["business_id", "started_at"])
	op.create_index("ix_distribution_field_visits_user_started", "distribution_field_visits", ["user_id", "started_at"])
	op.create_index("ix_distribution_field_visits_person", "distribution_field_visits", ["business_id", "person_id"])

	op.create_table(
		"distribution_return_requests",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("visit_id", sa.Integer(), nullable=True),
		sa.Column("status", sa.String(length=32), nullable=False, server_default=sa.text("'pending'")),
		sa.Column("lines", sa.JSON(), nullable=False),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("resolved_document_id", sa.Integer(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("resolved_by_user_id", sa.Integer(), nullable=True),
		sa.Column("resolved_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["visit_id"], ["distribution_field_visits.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["resolved_document_id"], ["documents.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["resolved_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_distribution_return_requests_business_status", "distribution_return_requests", ["business_id", "status"])


def downgrade() -> None:
	op.drop_index("ix_distribution_return_requests_business_status", table_name="distribution_return_requests")
	op.drop_table("distribution_return_requests")
	op.drop_index("ix_distribution_field_visits_person", table_name="distribution_field_visits")
	op.drop_index("ix_distribution_field_visits_user_started", table_name="distribution_field_visits")
	op.drop_index("ix_distribution_field_visits_business_started", table_name="distribution_field_visits")
	op.drop_table("distribution_field_visits")
	op.drop_index("ix_distribution_route_assignments_business_route_user", table_name="distribution_route_assignments")
	op.drop_table("distribution_route_assignments")
	op.drop_index("ix_distribution_route_stops_person_id", table_name="distribution_route_stops")
	op.drop_index("ix_distribution_route_stops_route_id", table_name="distribution_route_stops")
	op.drop_table("distribution_route_stops")
	op.drop_index("ix_distribution_routes_territory_id", table_name="distribution_routes")
	op.drop_index("ix_distribution_routes_business_id", table_name="distribution_routes")
	op.drop_table("distribution_routes")
	op.drop_index("ix_distribution_territories_business_id", table_name="distribution_territories")
	op.drop_table("distribution_territories")
