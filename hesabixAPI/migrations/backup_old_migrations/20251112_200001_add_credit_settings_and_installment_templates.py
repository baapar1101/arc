"""add credit settings and installment plan templates

Revision ID: 20251112_200001_add_credit_settings_and_installment_templates
Revises: 20251112_170001_add_credit_fields
Create Date: 2025-11-12 20:00:01
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = '20251112_200001_add_credit_settings_and_installment_templates'
down_revision = '20251112_170001_add_credit_fields'
branch_labels = None
depends_on = None


def _has_table(inspector, table_name: str) -> bool:
	tables = inspector.get_table_names()
	return table_name in tables


def upgrade() -> None:
	bind = op.get_bind()
	inspector = sa.inspect(bind)

	# business_credit_settings
	if not _has_table(inspector, 'business_credit_settings'):
		op.create_table(
			'business_credit_settings',
			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
			sa.Column('is_enabled', sa.Boolean(), nullable=False, server_default=sa.text('0')),
			sa.Column('default_limit', sa.Numeric(14, 2), nullable=True),
			sa.Column('grace_days', sa.Integer(), nullable=True),
			sa.Column('late_fee_rate', sa.Numeric(8, 4), nullable=True),
			sa.Column('auto_block_after_days', sa.Integer(), nullable=True),
			sa.Column('strategy', sa.String(length=30), nullable=True),
			sa.Column('created_at', sa.DateTime(), nullable=False),
			sa.Column('updated_at', sa.DateTime(), nullable=False),
			sa.UniqueConstraint('business_id', name='uq_credit_settings_business'),
		)
		try:
			op.create_index('ix_credit_settings_business_id', 'business_credit_settings', ['business_id'])
		except Exception:
			pass

	# installment_plan_templates
	if not _has_table(inspector, 'installment_plan_templates'):
		op.create_table(
			'installment_plan_templates',
			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
			sa.Column('name', sa.String(length=120), nullable=False),
			sa.Column('method', sa.String(length=20), nullable=False, server_default='flat'),
			sa.Column('num_installments', sa.Integer(), nullable=False),
			sa.Column('period_days', sa.Integer(), nullable=False, server_default=sa.text('30')),
			sa.Column('down_payment_percent', sa.Numeric(8, 4), nullable=True),
			sa.Column('interest_rate', sa.Numeric(8, 4), nullable=True),
			sa.Column('late_fee_rate', sa.Numeric(8, 4), nullable=True),
			sa.Column('issue_fee', sa.Numeric(14, 2), nullable=True),
			sa.Column('description', sa.Text(), nullable=True),
			sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
			sa.Column('created_at', sa.DateTime(), nullable=False),
			sa.Column('updated_at', sa.DateTime(), nullable=False),
			sa.UniqueConstraint('business_id', 'name', name='uq_installment_plan_name_per_business'),
		)
		try:
			op.create_index('ix_installment_plans_business_id', 'installment_plan_templates', ['business_id'])
			op.create_index('ix_installment_plans_is_active', 'installment_plan_templates', ['is_active'])
		except Exception:
			pass


def downgrade() -> None:
	for name in ['installment_plan_templates', 'business_credit_settings']:
		try:
			op.drop_table(name)
		except Exception:
			pass


