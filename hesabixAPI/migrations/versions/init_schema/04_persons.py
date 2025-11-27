"""جداول persons و person_bank_accounts"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


def upgrade():
    # جدول persons
    op.create_table(
        'persons',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('code', sa.Integer(), nullable=True),
        sa.Column('alias_name', sa.String(length=255), nullable=False),
        sa.Column('first_name', sa.String(length=100), nullable=True),
        sa.Column('last_name', sa.String(length=100), nullable=True),
        sa.Column('person_types', sa.Text(), nullable=False),
        sa.Column('company_name', sa.String(length=255), nullable=True),
        sa.Column('payment_id', sa.String(length=100), nullable=True),
        sa.Column('share_count', sa.Integer(), nullable=True),
        sa.Column('commission_sale_percent', sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column('commission_sales_return_percent', sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column('commission_sales_amount', sa.Numeric(precision=12, scale=2), nullable=True),
        sa.Column('commission_sales_return_amount', sa.Numeric(precision=12, scale=2), nullable=True),
        sa.Column('commission_exclude_discounts', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('commission_exclude_additions_deductions', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('commission_post_in_invoice_document', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('credit_limit', sa.Numeric(precision=14, scale=2), nullable=True),
        sa.Column('credit_check_enabled', sa.Boolean(), nullable=True),
        sa.Column('national_id', sa.String(length=20), nullable=True),
        sa.Column('registration_number', sa.String(length=50), nullable=True),
        sa.Column('economic_id', sa.String(length=50), nullable=True),
        sa.Column('country', sa.String(length=100), nullable=True),
        sa.Column('province', sa.String(length=100), nullable=True),
        sa.Column('city', sa.String(length=100), nullable=True),
        sa.Column('address', sa.Text(), nullable=True),
        sa.Column('postal_code', sa.String(length=20), nullable=True),
        sa.Column('phone', sa.String(length=20), nullable=True),
        sa.Column('mobile', sa.String(length=20), nullable=True),
        sa.Column('fax', sa.String(length=20), nullable=True),
        sa.Column('email', sa.String(length=255), nullable=True),
        sa.Column('website', sa.String(length=255), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'code', name='uq_persons_business_code')
    )
    op.create_index(op.f('ix_persons_business_id'), 'persons', ['business_id'], unique=False)
    op.create_index(op.f('ix_persons_alias_name'), 'persons', ['alias_name'], unique=False)
    op.create_index(op.f('ix_persons_national_id'), 'persons', ['national_id'], unique=False)

    # جدول person_bank_accounts
    op.create_table(
        'person_bank_accounts',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('person_id', sa.Integer(), nullable=False),
        sa.Column('bank_name', sa.String(length=255), nullable=False),
        sa.Column('account_number', sa.String(length=50), nullable=True),
        sa.Column('card_number', sa.String(length=20), nullable=True),
        sa.Column('sheba_number', sa.String(length=30), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['person_id'], ['persons.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_person_bank_accounts_person_id'), 'person_bank_accounts', ['person_id'], unique=False)

    # جدول person_share_links
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
    
    op.drop_index(op.f('ix_person_bank_accounts_person_id'), table_name='person_bank_accounts')
    op.drop_table('person_bank_accounts')
    
    op.drop_index(op.f('ix_persons_national_id'), table_name='persons')
    op.drop_index(op.f('ix_persons_alias_name'), table_name='persons')
    op.drop_index(op.f('ix_persons_business_id'), table_name='persons')
    op.drop_table('persons')

