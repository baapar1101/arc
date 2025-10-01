from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250929_000301_add_product_attributes_table'
down_revision = '20250929_000201_drop_type_from_categories'
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if 'product_attributes' in inspector.get_table_names():
        return

    op.create_table(
        'product_attributes',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('title', sa.String(length=255), nullable=False, index=True),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('now()')),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('now()')),
        sa.UniqueConstraint('business_id', 'title', name='uq_product_attributes_business_title'),
    )


def downgrade() -> None:
    op.drop_table('product_attributes')


