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
        fk_rows = conn.execute(sa.text(
            """
            SELECT CONSTRAINT_NAME
            FROM information_schema.KEY_COLUMN_USAGE
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'price_lists'
              AND COLUMN_NAME = 'currency_id'
              AND REFERENCED_TABLE_NAME IS NOT NULL
            GROUP BY CONSTRAINT_NAME
            """
        )).fetchall()
        for (fk_name,) in fk_rows:
            conn.execute(sa.text(f"ALTER TABLE price_lists DROP FOREIGN KEY {fk_name}"))

        # Finally drop columns if they exist (manual check)
        for col in ('currency_id', 'default_unit_id'):
            exists = conn.execute(sa.text(
                """
                SELECT COUNT(*) as cnt FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'price_lists' AND COLUMN_NAME = :col
                """
            ), {"col": col}).scalar() or 0
            if int(exists) > 0:
                conn.execute(sa.text(f"ALTER TABLE price_lists DROP COLUMN {col}"))
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


