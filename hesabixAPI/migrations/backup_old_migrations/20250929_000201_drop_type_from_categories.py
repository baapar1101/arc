from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20250929_000201_drop_type_from_categories'
down_revision = '20250929_000101_add_categories_table'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # حذف ایندکس مرتبط با ستون type اگر وجود دارد
    try:
        op.drop_index('ix_categories_type', table_name='categories')
    except Exception:
        pass
    # حذف ستون type
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    cols = [c['name'] for c in inspector.get_columns('categories')]
    if 'type' in cols:
        with op.batch_alter_table('categories') as batch_op:
            try:
                batch_op.drop_column('type')
            except Exception:
                pass


def downgrade() -> None:
    # بازگردانی ستون type (اختیاری)
    with op.batch_alter_table('categories') as batch_op:
        try:
            batch_op.add_column(sa.Column('type', sa.String(length=16), nullable=False, server_default='global'))
        except Exception:
            pass
    try:
        op.create_index('ix_categories_type', 'categories', ['type'])
    except Exception:
        pass


