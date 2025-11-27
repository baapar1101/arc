"""جدول email_configs"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    op.create_table(
        'email_configs',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('name', sa.String(length=100), nullable=False),
        sa.Column('smtp_host', sa.String(length=255), nullable=False),
        sa.Column('smtp_port', sa.Integer(), nullable=False),
        sa.Column('smtp_username', sa.String(length=255), nullable=False),
        sa.Column('smtp_password', sa.String(length=255), nullable=False),
        sa.Column('use_tls', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('use_ssl', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('from_email', sa.String(length=255), nullable=False),
        sa.Column('from_name', sa.String(length=100), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('is_default', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_email_configs_name'), 'email_configs', ['name'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_email_configs_name'), table_name='email_configs')
    op.drop_table('email_configs')

