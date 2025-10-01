from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251001_001101_drop_price_list_currency_default_unit'
down_revision = '20251001_000601_update_price_items_currency_unique_not_null'
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    dialect = conn.dialect.name

    # Try to drop FK on price_lists.currency_id if exists
    if dialect == 'mysql':
        # Find foreign key constraint name dynamically and drop it
        op.execute(sa.text(
            """
            SET @fk_name := (
              SELECT CONSTRAINT_NAME
              FROM information_schema.KEY_COLUMN_USAGE
              WHERE TABLE_SCHEMA = DATABASE()
                AND TABLE_NAME = 'price_lists'
                AND COLUMN_NAME = 'currency_id'
                AND REFERENCED_TABLE_NAME IS NOT NULL
              LIMIT 1
            );
            """
        ))
        op.execute(sa.text(
            """
            SET @q := IF(@fk_name IS NOT NULL, CONCAT('ALTER TABLE price_lists DROP FOREIGN KEY ', @fk_name), 'SELECT 1');
            PREPARE stmt FROM @q; EXECUTE stmt; DEALLOCATE PREPARE stmt;
            """
        ))
        # Drop indexes on columns if any
        for col in ('currency_id', 'default_unit_id'):
            op.execute(sa.text(
                f"""
                SET @idx := (
                  SELECT INDEX_NAME FROM information_schema.STATISTICS
                  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'price_lists' AND COLUMN_NAME = '{col}' LIMIT 1
                );
                """
            ))
            op.execute(sa.text(
                """
                SET @qi := IF(@idx IS NOT NULL, CONCAT('ALTER TABLE price_lists DROP INDEX ', @idx), 'SELECT 1');
                PREPARE s FROM @qi; EXECUTE s; DEALLOCATE PREPARE s;
                """
            ))

        # Finally drop columns if they exist
        op.execute(sa.text("ALTER TABLE price_lists DROP COLUMN IF EXISTS currency_id"))
        op.execute(sa.text("ALTER TABLE price_lists DROP COLUMN IF EXISTS default_unit_id"))
    else:
        # Best-effort: drop constraint by common names, then drop columns
        for name in ('price_lists_currency_id_fkey', 'fk_price_lists_currency_id', 'price_lists_currency_id_fk'):
            try:
                op.drop_constraint(name, 'price_lists', type_='foreignkey')
                break
            except Exception:
                pass
        try:
            op.drop_column('price_lists', 'currency_id')
        except Exception:
            pass
        try:
            op.drop_column('price_lists', 'default_unit_id')
        except Exception:
            pass


def downgrade() -> None:
    conn = op.get_bind()
    dialect = conn.dialect.name

    # Recreate columns (nullable) and FK back to currencies
    with op.batch_alter_table('price_lists') as batch_op:
        try:
            batch_op.add_column(sa.Column('currency_id', sa.Integer(), nullable=True))
        except Exception:
            pass
        try:
            batch_op.add_column(sa.Column('default_unit_id', sa.Integer(), nullable=True))
        except Exception:
            pass

    # Add FK for currency_id where supported
    try:
        op.create_foreign_key(
            'fk_price_lists_currency_id',
            'price_lists', 'currencies', ['currency_id'], ['id'], ondelete='RESTRICT'
        )
    except Exception:
        pass


