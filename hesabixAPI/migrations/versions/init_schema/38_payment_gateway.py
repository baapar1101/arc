"""جداول payment_gateways, business_payment_gateways"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول payment_gateways
    op.create_table(
        'payment_gateways',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('provider', sa.String(length=50), nullable=False),
        sa.Column('display_name', sa.String(length=100), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('is_sandbox', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('config_json', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )

    # جدول business_payment_gateways
    op.create_table(
        'business_payment_gateways',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('gateway_id', sa.Integer(), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['gateway_id'], ['payment_gateways.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_business_payment_gateways_business_id'), 'business_payment_gateways', ['business_id'], unique=False)
    op.create_index(op.f('ix_business_payment_gateways_gateway_id'), 'business_payment_gateways', ['gateway_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_business_payment_gateways_gateway_id'), table_name='business_payment_gateways')
    op.drop_index(op.f('ix_business_payment_gateways_business_id'), table_name='business_payment_gateways')
    op.drop_table('business_payment_gateways')
    
    op.drop_table('payment_gateways')

