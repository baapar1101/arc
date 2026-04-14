from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250929_000401_drop_is_active_from_product_attributes'
down_revision = '20250929_000301_add_product_attributes_table'
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    cols = [c['name'] for c in inspector.get_columns('product_attributes')]
    if 'is_active' in cols:
        with op.batch_alter_table('product_attributes') as batch_op:
            try:
                batch_op.drop_column('is_active')
            except Exception:
                pass


def downgrade() -> None:
    with op.batch_alter_table('product_attributes') as batch_op:
        try:
            batch_op.add_column(sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')))
        except Exception:
            pass


