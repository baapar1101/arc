from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251001_000601_update_price_items_currency_unique_not_null'
down_revision = '20250929_000501_add_products_and_pricing'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1) Backfill price_items.currency_id from price_lists.currency_id where NULL
    op.execute(
        sa.text(
            """
            UPDATE price_items pi
            JOIN price_lists pl ON pl.id = pi.price_list_id
            SET pi.currency_id = pl.currency_id
            WHERE pi.currency_id IS NULL
            """
        )
    )

    # 2) Drop old unique constraint if exists
    conn = op.get_bind()
    dialect_name = conn.dialect.name

    # MySQL: information_schema to check constraints
    if dialect_name == 'mysql':
        op.execute(
            sa.text(
                """
                SET @exists := (
                  SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
                  WHERE CONSTRAINT_SCHEMA = DATABASE()
                    AND TABLE_NAME = 'price_items'
                    AND CONSTRAINT_NAME = 'uq_price_items_unique_tier'
                );
                """
            )
        )
        op.execute(sa.text("""SET @q := IF(@exists > 0, 'ALTER TABLE price_items DROP INDEX uq_price_items_unique_tier', 'SELECT 1'); PREPARE stmt FROM @q; EXECUTE stmt; DEALLOCATE PREPARE stmt;"""))
    else:
        # Generic drop constraint best-effort
        try:
            op.drop_constraint('uq_price_items_unique_tier', 'price_items', type_='unique')
        except Exception:
            pass

    # 3) Make currency_id NOT NULL
    op.alter_column('price_items', 'currency_id', existing_type=sa.Integer(), nullable=False, existing_nullable=True)

    # 4) Create new unique constraint including currency_id
    # For MySQL, unique constraints are created as indexes as well
    op.create_unique_constraint(
        'uq_price_items_unique_tier_currency',
        'price_items',
        ['price_list_id', 'product_id', 'unit_id', 'tier_name', 'min_qty', 'currency_id']
    )


def downgrade() -> None:
    # Drop new unique constraint
    try:
        op.drop_constraint('uq_price_items_unique_tier_currency', 'price_items', type_='unique')
    except Exception:
        pass

    # Make currency_id nullable again
    op.alter_column('price_items', 'currency_id', existing_type=sa.Integer(), nullable=True, existing_nullable=False)

    # Recreate old unique constraint
    op.create_unique_constraint(
        'uq_price_items_unique_tier',
        'price_items',
        ['price_list_id', 'product_id', 'unit_id', 'tier_name', 'min_qty']
    )


