"""Optional warehouse_location_id on warehouse_document_lines

Revision ID: 20260418_000004_warehouse_document_line_location
Revises: 20260418_000003_warehouse_locations_and_placements
Create Date: 2026-04-18
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260418_000004_warehouse_document_line_location"
down_revision = "20260418_000003_warehouse_locations_and_placements"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"warehouse_document_lines",
		sa.Column(
			"warehouse_location_id",
			sa.Integer(),
			nullable=True,
			comment="محل انبار (همگام با قرارگیری کالا)",
		),
	)
	op.create_index(
		op.f("ix_wh_doc_lines_warehouse_location_id"),
		"warehouse_document_lines",
		["warehouse_location_id"],
		unique=False,
	)
	op.create_foreign_key(
		"fk_wh_doc_lines_warehouse_location_id",
		"warehouse_document_lines",
		"warehouse_locations",
		["warehouse_location_id"],
		["id"],
		ondelete="SET NULL",
	)


def downgrade() -> None:
	op.drop_constraint("fk_wh_doc_lines_warehouse_location_id", "warehouse_document_lines", type_="foreignkey")
	op.drop_index(op.f("ix_wh_doc_lines_warehouse_location_id"), table_name="warehouse_document_lines")
	op.drop_column("warehouse_document_lines", "warehouse_location_id")
