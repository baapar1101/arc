"""Extend product measurement precision for imperial units."""

import sqlalchemy as sa
from alembic import op

revision = "20261123_000002_product_measurement_units"
down_revision = "20261123_000001_product_measurements"
branch_labels = None
depends_on = None

MEASUREMENT_COLUMNS = ("length_mm", "width_mm", "height_mm", "weight_g")


def _alter_measurements(previous_type: sa.Numeric, new_type: sa.Numeric) -> None:
    for column in MEASUREMENT_COLUMNS:
        op.alter_column("products", column, existing_type=previous_type, type_=new_type)


def upgrade() -> None:
    _alter_measurements(sa.Numeric(18, 6), sa.Numeric(27, 15))


def downgrade() -> None:
    op.execute("""
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1 FROM businesses
                WHERE product_dimension_unit NOT IN ('mm', 'cm', 'm')
                    OR product_weight_unit NOT IN ('g', 'kg', 't')
            ) THEN
                RAISE EXCEPTION 'Restore the original product display units before downgrading';
            END IF;
            IF EXISTS (
                SELECT 1 FROM products
                WHERE length_mm <> trunc(length_mm, 6)
                    OR width_mm <> trunc(width_mm, 6)
                    OR height_mm <> trunc(height_mm, 6)
                    OR weight_g <> trunc(weight_g, 6)
            ) THEN
                RAISE EXCEPTION 'Product measurements would lose precision on downgrade';
            END IF;
        END;
        $$;
    """)
    _alter_measurements(sa.Numeric(27, 15), sa.Numeric(18, 6))
