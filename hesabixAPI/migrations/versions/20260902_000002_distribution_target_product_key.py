"""پخش تجاری: یکتایی هدف فروش با product_id=0 به‌جای NULL.

Revision ID: 20260902_000002_distribution_target_product_key
Revises: 20260902_000001_distribution_commercial_ops
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260902_000002_distribution_target_product_key"
down_revision = "20260902_000001_distribution_commercial_ops"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)
	# drop FK if present
	fks = insp.get_foreign_keys("distribution_sales_targets")
	for fk in fks:
		if "product_id" in (fk.get("constrained_columns") or []):
			op.drop_constraint(fk["name"], "distribution_sales_targets", type_="foreignkey")

	# normalize NULL → 0
	op.execute(sa.text("UPDATE distribution_sales_targets SET product_id = 0 WHERE product_id IS NULL"))

	# drop unique and recreate (names may differ)
	uq_names = {c["name"] for c in insp.get_unique_constraints("distribution_sales_targets")}
	for name in ("uq_distribution_sales_target_metric", "uq_distribution_sales_target_period"):
		if name in uq_names:
			op.drop_constraint(name, "distribution_sales_targets", type_="unique")

	# alter nullable
	with op.batch_alter_table("distribution_sales_targets") as batch:
		batch.alter_column(
			"product_id",
			existing_type=sa.Integer(),
			nullable=False,
			server_default="0",
		)

	op.create_unique_constraint(
		"uq_distribution_sales_target_metric",
		"distribution_sales_targets",
		["business_id", "user_id", "period_type", "period_start", "metric", "product_id"],
	)


def downgrade() -> None:
	op.drop_constraint("uq_distribution_sales_target_metric", "distribution_sales_targets", type_="unique")
	with op.batch_alter_table("distribution_sales_targets") as batch:
		batch.alter_column("product_id", existing_type=sa.Integer(), nullable=True, server_default=None)
	op.execute(sa.text("UPDATE distribution_sales_targets SET product_id = NULL WHERE product_id = 0"))
	op.create_unique_constraint(
		"uq_distribution_sales_target_metric",
		"distribution_sales_targets",
		["business_id", "user_id", "period_type", "period_start", "metric", "product_id"],
	)
