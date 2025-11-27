"""جداول businesses و جداول مرتبط"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


def upgrade():
    # ایجاد enum types
    op.execute("CREATE TYPE business_type_enum AS ENUM ('شرکت', 'مغازه', 'فروشگاه', 'اتحادیه', 'باشگاه', 'موسسه', 'شخصی')")
    op.execute("CREATE TYPE business_field_enum AS ENUM ('تولیدی', 'بازرگانی', 'خدماتی', 'سایر')")

    # جدول businesses
    op.create_table(
        'businesses',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('business_type', mysql.ENUM('شرکت', 'مغازه', 'فروشگاه', 'اتحادیه', 'باشگاه', 'موسسه', 'شخصی'), nullable=False),
        sa.Column('business_field', mysql.ENUM('تولیدی', 'بازرگانی', 'خدماتی', 'سایر'), nullable=False),
        sa.Column('owner_id', sa.Integer(), nullable=False),
        sa.Column('default_currency_id', sa.Integer(), nullable=True),
        sa.Column('address', sa.Text(), nullable=True),
        sa.Column('phone', sa.String(length=20), nullable=True),
        sa.Column('mobile', sa.String(length=20), nullable=True),
        sa.Column('national_id', sa.String(length=20), nullable=True),
        sa.Column('registration_number', sa.String(length=50), nullable=True),
        sa.Column('economic_id', sa.String(length=50), nullable=True),
        sa.Column('logo_file_id', sa.String(length=36), nullable=True),
        sa.Column('stamp_file_id', sa.String(length=36), nullable=True),
        sa.Column('country', sa.String(length=100), nullable=True),
        sa.Column('province', sa.String(length=100), nullable=True),
        sa.Column('city', sa.String(length=100), nullable=True),
        sa.Column('postal_code', sa.String(length=20), nullable=True),
        sa.Column('default_credit_limit', sa.Numeric(precision=14, scale=2), nullable=True),
        sa.Column('check_credit_enabled_by_default', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['owner_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['default_currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_businesses_name'), 'businesses', ['name'], unique=False)
    op.create_index(op.f('ix_businesses_owner_id'), 'businesses', ['owner_id'], unique=False)
    op.create_index(op.f('ix_businesses_default_currency_id'), 'businesses', ['default_currency_id'], unique=False)
    op.create_index(op.f('ix_businesses_national_id'), 'businesses', ['national_id'], unique=False)
    op.create_index(op.f('ix_businesses_registration_number'), 'businesses', ['registration_number'], unique=False)
    op.create_index(op.f('ix_businesses_economic_id'), 'businesses', ['economic_id'], unique=False)

    # جدول business_permissions
    op.create_table(
        'business_permissions',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('business_permissions', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_business_permissions_business_id'), 'business_permissions', ['business_id'], unique=False)
    op.create_index(op.f('ix_business_permissions_user_id'), 'business_permissions', ['user_id'], unique=False)

    # جدول business_print_settings
    op.create_table(
        'business_print_settings',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('document_type', sa.String(length=50), nullable=False),
        sa.Column('show_logo', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('show_stamp', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('show_payments', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('show_installment_plan', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('footer_note', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'document_type', name='uq_business_print_settings_business_doc_type')
    )
    op.create_index(op.f('ix_business_print_settings_business_id'), 'business_print_settings', ['business_id'], unique=False)
    op.create_index(op.f('ix_business_print_settings_document_type'), 'business_print_settings', ['document_type'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_business_print_settings_document_type'), table_name='business_print_settings')
    op.drop_index(op.f('ix_business_print_settings_business_id'), table_name='business_print_settings')
    op.drop_table('business_print_settings')
    
    op.drop_index(op.f('ix_business_permissions_user_id'), table_name='business_permissions')
    op.drop_index(op.f('ix_business_permissions_business_id'), table_name='business_permissions')
    op.drop_table('business_permissions')
    
    op.drop_index(op.f('ix_businesses_economic_id'), table_name='businesses')
    op.drop_index(op.f('ix_businesses_registration_number'), table_name='businesses')
    op.drop_index(op.f('ix_businesses_national_id'), table_name='businesses')
    op.drop_index(op.f('ix_businesses_default_currency_id'), table_name='businesses')
    op.drop_index(op.f('ix_businesses_owner_id'), table_name='businesses')
    op.drop_index(op.f('ix_businesses_name'), table_name='businesses')
    op.drop_table('businesses')
    
    op.execute("DROP TYPE IF EXISTS business_field_enum")
    op.execute("DROP TYPE IF EXISTS business_type_enum")

