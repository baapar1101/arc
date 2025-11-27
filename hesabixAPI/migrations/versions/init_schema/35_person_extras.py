"""جدول person_share_links"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    op.create_table(
        'person_share_links',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('person_id', sa.Integer(), nullable=False),
        sa.Column('created_by_user_id', sa.Integer(), nullable=True),
        sa.Column('revoked_by_user_id', sa.Integer(), nullable=True),
        sa.Column('code', sa.String(length=16), nullable=False),
        sa.Column('token_hash', sa.String(length=128), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=True),
        sa.Column('revoked_at', sa.DateTime(), nullable=True),
        sa.Column('last_view_at', sa.DateTime(), nullable=True),
        sa.Column('view_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('max_view_count', sa.Integer(), nullable=True),
        sa.Column('options', sa.JSON(), nullable=True),
        sa.Column('meta', sa.JSON(), nullable=True),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['person_id'], ['persons.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['revoked_by_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('code', name='uq_person_share_links_code')
    )
    op.create_index('ix_person_share_links_code', 'person_share_links', ['code'], unique=False)
    op.create_index('ix_person_share_links_person_id', 'person_share_links', ['person_id'], unique=False)
    op.create_index('ix_person_share_links_business_id', 'person_share_links', ['business_id'], unique=False)


def downgrade():
    op.drop_index('ix_person_share_links_business_id', table_name='person_share_links')
    op.drop_index('ix_person_share_links_person_id', table_name='person_share_links')
    op.drop_index('ix_person_share_links_code', table_name='person_share_links')
    op.drop_table('person_share_links')

