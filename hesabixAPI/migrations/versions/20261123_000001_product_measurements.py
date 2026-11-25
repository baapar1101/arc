"""Store product measurements and business display units."""

import sqlalchemy as sa
from alembic import op

revision = "20261123_000001_product_measurements"
down_revision = "20261110_000009_merge_crm_enterprise_and_oa_letter_ocr_heads"
branch_labels = None
depends_on = None

MEASUREMENT_COLUMNS = ("length_mm", "width_mm", "height_mm", "weight_g")


def upgrade() -> None:
    op.add_column(
        "businesses",
        sa.Column("product_dimension_unit", sa.String(2), nullable=False, server_default="mm"),
    )
    op.add_column(
        "businesses",
        sa.Column("product_weight_unit", sa.String(2), nullable=False, server_default="g"),
    )
    for column in MEASUREMENT_COLUMNS:
        op.add_column("products", sa.Column(column, sa.Numeric(18, 6), nullable=True))


def downgrade() -> None:
    for column in reversed(MEASUREMENT_COLUMNS):
        op.drop_column("products", column)
    op.drop_column("businesses", "product_weight_unit")
    op.drop_column("businesses", "product_dimension_unit")
