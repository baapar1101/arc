"""add payment gateways tables

Revision ID: 20251109_120001_add_payment_gateways
Revises: 20251108_232101_add_wallet_tables
Create Date: 2025-11-09 12:00:01.000001

"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251109_120001_add_payment_gateways'
down_revision = '20251108_232101_add_wallet_tables'
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	inspector = sa.inspect(bind)
	tables = inspector.get_table_names()

	if 'payment_gateways' not in tables:
		op.create_table(
			'payment_gateways',
			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column('provider', sa.String(length=50), nullable=False),  # zarinpal | parsian | ...
			sa.Column('display_name', sa.String(length=100), nullable=False),
			sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
			sa.Column('is_sandbox', sa.Boolean(), nullable=False, server_default=sa.text('1')),
			sa.Column('config_json', sa.Text(), nullable=True),
			sa.Column('created_at', sa.DateTime(), nullable=False),
			sa.Column('updated_at', sa.DateTime(), nullable=False),
		)
		try:
			op.create_index('ix_payment_gateways_provider', 'payment_gateways', ['provider'])
			op.create_index('ix_payment_gateways_is_active', 'payment_gateways', ['is_active'])
		except Exception:
			pass

	if 'business_payment_gateways' not in tables:
		op.create_table(
			'business_payment_gateways',
			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
			sa.Column('gateway_id', sa.Integer(), sa.ForeignKey('payment_gateways.id', ondelete='CASCADE'), nullable=False),
			sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
			sa.Column('created_at', sa.DateTime(), nullable=False),
			sa.Column('updated_at', sa.DateTime(), nullable=False),
		)
		try:
			op.create_index('ix_business_payment_gateways_business', 'business_payment_gateways', ['business_id'])
			op.create_index('ix_business_payment_gateways_gateway', 'business_payment_gateways', ['gateway_id'])
		except Exception:
			pass


def downgrade() -> None:
	for name in ['business_payment_gateways', 'payment_gateways']:
		try:
			op.drop_table(name)
		except Exception:
			pass



