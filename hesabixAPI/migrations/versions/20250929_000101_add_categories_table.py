from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250929_000101_add_categories_table'
down_revision = '20250928_000023_remove_person_is_active_force'
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if 'categories' in inspector.get_table_names():
        return

    op.create_table(
        'categories',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('parent_id', sa.Integer(), sa.ForeignKey('categories.id', ondelete='SET NULL'), nullable=True, index=True),
        sa.Column('type', sa.String(length=16), nullable=False, index=True),
        sa.Column('title_translations', sa.JSON(), nullable=False),
        sa.Column('sort_order', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('now()')),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('now()')),
    )
    # Indexes are created automatically if defined at ORM/model level or can be added in a later migration if needed


def downgrade() -> None:
    op.drop_table('categories')


