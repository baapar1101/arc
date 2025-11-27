"""init_complete_schema

Revision ID: 20251202_000000
Revises: None
Create Date: 2025-11-26 19:24:48

این میگریشن تمام جداول و تغییرات را در یک میگریشن واحد ترکیب می‌کند.
"""
from __future__ import annotations

from datetime import datetime
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = '20251202_000000'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = inspect(bind)
    tables = set(inspector.get_table_names())

    # From: 1f0abcdd7300_add_petty_cash_table.py (revision: 1f0abcdd7300)
    # Check if table already exists
    connection = op.get_bind()
    result = connection.execute(sa.text("""
            SELECT COUNT(*) 
            FROM information_schema.tables 
            WHERE table_schema = DATABASE() 
            AND table_name = 'petty_cash'
    """)).fetchone()
    
    if result[0] == 0:
            op.create_table('petty_cash',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('business_id', sa.Integer(), nullable=False),
    sa.Column('name', sa.String(length=255), nullable=False, comment='نام تنخواه گردان'),
    sa.Column('code', sa.String(length=50), nullable=True, comment='کد یکتا در هر کسب\u200cوکار (اختیاری)'),
    sa.Column('description', sa.String(length=500), nullable=True),
    sa.Column('currency_id', sa.Integer(), nullable=False),
    sa.Column('is_active', sa.Boolean(), server_default=sa.text('1'), nullable=False),
    sa.Column('is_default', sa.Boolean(), server_default=sa.text('0'), nullable=False),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.Column('updated_at', sa.DateTime(), nullable=False),
    sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('business_id', 'code', name='uq_petty_cash_business_code')
            )
            op.create_index(op.f('ix_petty_cash_business_id'), 'petty_cash', ['business_id'], unique=False)
            op.create_index(op.f('ix_petty_cash_code'), 'petty_cash', ['code'], unique=False)
            op.create_index(op.f('ix_petty_cash_currency_id'), 'petty_cash', ['currency_id'], unique=False)
            op.create_index(op.f('ix_petty_cash_name'), 'petty_cash', ['name'], unique=False)
        # ### end Alembic commands ###

    # From: 20250102_000001_seed_support_data.py (revision: 20250102_000001)
    # اضافه کردن دسته‌بندی‌های اولیه
    categories_table = sa.table('support_categories',
            sa.column('id', sa.Integer),
            sa.column('name', sa.String),
            sa.column('description', sa.Text),
            sa.column('is_active', sa.Boolean),
            sa.column('created_at', sa.DateTime),
            sa.column('updated_at', sa.DateTime)
    )
    
    categories_data = [
            {
            'name': 'مشکل فنی',
            'description': 'مشکلات فنی و باگ‌ها',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            },
            {
            'name': 'درخواست ویژگی',
            'description': 'درخواست ویژگی‌های جدید',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            },
            {
            'name': 'سوال',
            'description': 'سوالات عمومی',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            },
            {
            'name': 'شکایت',
            'description': 'شکایات و انتقادات',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            },
            {
            'name': 'سایر',
            'description': 'سایر موارد',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            }
    ]
    
    op.bulk_insert(categories_table, categories_data)
    
        # اضافه کردن اولویت‌های اولیه
    priorities_table = sa.table('support_priorities',
            sa.column('id', sa.Integer),
            sa.column('name', sa.String),
            sa.column('description', sa.Text),
            sa.column('color', sa.String),
            sa.column('order', sa.Integer),
            sa.column('created_at', sa.DateTime),
            sa.column('updated_at', sa.DateTime)
    )
    
    priorities_data = [
            {
            'name': 'کم',
            'description': 'اولویت کم',
            'color': '#28a745',
            'order': 1,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            },
            {
            'name': 'متوسط',
            'description': 'اولویت متوسط',
            'color': '#ffc107',
            'order': 2,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            },
            {
            'name': 'بالا',
            'description': 'اولویت بالا',
            'color': '#fd7e14',
            'order': 3,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            },
            {
            'name': 'فوری',
            'description': 'اولویت فوری',
            'color': '#dc3545',
            'order': 4,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            }
    ]
    
    op.bulk_insert(priorities_table, priorities_data)
    
        # اضافه کردن وضعیت‌های اولیه
    statuses_table = sa.table('support_statuses',
            sa.column('id', sa.Integer),
            sa.column('name', sa.String),
            sa.column('description', sa.Text),
            sa.column('color', sa.String),
            sa.column('is_final', sa.Boolean),
            sa.column('created_at', sa.DateTime),
            sa.column('updated_at', sa.DateTime)
    )
    
    statuses_data = [
            {
            'name': 'باز',
            'description': 'تیکت باز و در انتظار پاسخ',
            'color': '#007bff',
            'is_final': False,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            },
            {
            'name': 'در حال پیگیری',
            'description': 'تیکت در حال بررسی',
            'color': '#6f42c1',
            'is_final': False,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            },
            {
            'name': 'در انتظار کاربر',
            'description': 'در انتظار پاسخ کاربر',
            'color': '#17a2b8',
            'is_final': False,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            },
            {
            'name': 'بسته',
            'description': 'تیکت بسته شده',
            'color': '#6c757d',
            'is_final': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            },
            {
            'name': 'حل شده',
            'description': 'مشکل حل شده',
            'color': '#28a745',
            'is_final': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
            }
    ]
    
    op.bulk_insert(statuses_table, statuses_data)

    # From: 20250106_000001_fix_tax_types_structure.py (revision: 20250106_000001)
    # First, clear existing data to avoid conflicts
    op.execute("DELETE FROM tax_types")
    
        # Drop the business_id column (if it exists)
    try:
            op.drop_column('tax_types', 'business_id')
    except Exception:
            pass  # Column doesn't exist
    
        # Make code column NOT NULL and UNIQUE
    try:
            op.alter_column('tax_types', 'code', 
            existing_type=sa.String(length=64),
            nullable=False)
    except Exception:
            pass  # Already NOT NULL
    
    try:
            op.create_unique_constraint('uq_tax_types_code', 'tax_types', ['code'])
    except Exception:
            pass  # Constraint already exists
    
        # Add tax_rate column (if it doesn't exist)
    try:
            op.add_column('tax_types', sa.Column('tax_rate', sa.Numeric(5, 2), nullable=True, comment='نرخ مالیات (درصد)'))
    except Exception:
            pass  # Column already exists
    
        # Drop the old business_id index (if it exists)
    try:
            op.drop_index('ix_tax_types_business_id', table_name='tax_types')
    except Exception:

    # From: 20250106_000002_remove_tax_fields.py (revision: 20250106_000002)
    # Remove is_active column (if it exists)
    try:
            op.drop_column('tax_types', 'is_active')
    except Exception:
            pass  # Column doesn't exist
    
        # Remove tax_rate column (if it exists)
    try:
            op.drop_column('tax_types', 'tax_rate')
    except Exception:
            pass  # Column doesn't exist

    # From: 20250106_000003_cleanup_tax_units_table.py (revision: 20250106_000003)
    # Drop columns if exist (idempotent behavior)
    try:
            op.drop_index('ix_tax_units_business_id', table_name='tax_units')
    except Exception:
        
    for col in ('business_id', 'tax_rate', 'is_active'):
            try:
            op.drop_column('tax_units', col)
            except Exception:

    # From: 20250106_000004_seed_tax_units_list.py (revision: 20250106_000004)
    conn = op.get_bind()

        # Insert units if not already present (by code)
    for name in UNIT_NAMES:
            code = _slugify(name)
            exists = conn.execute(sa.text("SELECT id FROM tax_units WHERE code = :code LIMIT 1"), {"code": code}).fetchone()
            if not exists:
            conn.execute(
            sa.text(
            """
            INSERT INTO tax_units (name, code, description, created_at, updated_at)
            VALUES (:name, :code, :description, NOW(), NOW())
            """
            ),
            {"name": name, "code": code, "description": None},
            )
            conn.commit()

    # From: 20250117_000003_add_business_table.py (revision: 20250117_000003)
    bind = op.get_bind()
    inspector = inspect(bind)

        # Create businesses table if not exists
    if 'businesses' not in inspector.get_table_names():
            op.create_table(
            'businesses',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('name', sa.String(length=255), nullable=False),
            sa.Column('business_type', mysql.ENUM('شرکت', 'مغازه', 'فروشگاه', 'اتحادیه', 'باشگاه', 'موسسه', 'شخصی', name='businesstype'), nullable=False),
            sa.Column('business_field', mysql.ENUM('تولیدی', 'بازرگانی', 'خدماتی', 'سایر', name='businessfield'), nullable=False),
            sa.Column('owner_id', sa.Integer(), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['owner_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
            )
    
        # Create indexes if not exists
    existing_indexes = {idx['name'] for idx in inspector.get_indexes('businesses')} if 'businesses' in inspector.get_table_names() else set()
    if 'ix_businesses_name' not in existing_indexes:
            op.create_index('ix_businesses_name', 'businesses', ['name'])
    if 'ix_businesses_owner_id' not in existing_indexes:
            op.create_index('ix_businesses_owner_id', 'businesses', ['owner_id'])

    # From: 20250117_000004_add_business_contact_fields.py (revision: 20250117_000004)
    # Add new contact and identification fields to businesses table
    op.add_column('businesses', sa.Column('address', sa.Text(), nullable=True))
    op.add_column('businesses', sa.Column('phone', sa.String(length=20), nullable=True))
    op.add_column('businesses', sa.Column('mobile', sa.String(length=20), nullable=True))
    op.add_column('businesses', sa.Column('national_id', sa.String(length=20), nullable=True))
    op.add_column('businesses', sa.Column('registration_number', sa.String(length=50), nullable=True))
    op.add_column('businesses', sa.Column('economic_id', sa.String(length=50), nullable=True))
    
        # Create indexes for the new fields
    op.create_index('ix_businesses_national_id', 'businesses', ['national_id'])
    op.create_index('ix_businesses_registration_number', 'businesses', ['registration_number'])
    op.create_index('ix_businesses_economic_id', 'businesses', ['economic_id'])

    # From: 20250117_000005_add_business_geographic_fields.py (revision: 20250117_000005)
    # Add geographic fields to businesses table
    op.add_column('businesses', sa.Column('country', sa.String(length=100), nullable=True))
    op.add_column('businesses', sa.Column('province', sa.String(length=100), nullable=True))
    op.add_column('businesses', sa.Column('city', sa.String(length=100), nullable=True))
    op.add_column('businesses', sa.Column('postal_code', sa.String(length=20), nullable=True))

    # From: 20250117_000006_add_app_permissions_to_users.py (revision: 20250117_000006)
    # ### commands auto generated by Alembic - please adjust! ###
    op.add_column('users', sa.Column('app_permissions', sa.JSON(), nullable=True))
        # ### end Alembic commands ###

    # From: 20250117_000007_create_business_permissions_table.py (revision: 20250117_000007)
    # ### commands auto generated by Alembic - please adjust! ###
    op.create_table('business_permissions',
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
        # ### end Alembic commands ###

    # From: 20250117_000008_add_email_config_table.py (revision: 20250117_000008)
    # ### commands auto generated by Alembic - please adjust! ###
    op.create_table('email_configs',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('name', sa.String(length=100), nullable=False),
    sa.Column('smtp_host', sa.String(length=255), nullable=False),
    sa.Column('smtp_port', sa.Integer(), nullable=False),
    sa.Column('smtp_username', sa.String(length=255), nullable=False),
    sa.Column('smtp_password', sa.String(length=255), nullable=False),
    sa.Column('use_tls', sa.Boolean(), nullable=False),
    sa.Column('use_ssl', sa.Boolean(), nullable=False),
    sa.Column('from_email', sa.String(length=255), nullable=False),
    sa.Column('from_name', sa.String(length=100), nullable=False),
    sa.Column('is_active', sa.Boolean(), nullable=False),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.Column('updated_at', sa.DateTime(), nullable=False),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_email_configs_name'), 'email_configs', ['name'], unique=False)
        # ### end Alembic commands ###

    # From: 20250117_000009_add_is_default_to_email_config.py (revision: 20250117_000009)
    # Add is_default column to email_configs table
    op.add_column('email_configs', sa.Column('is_default', sa.Boolean(), nullable=False, server_default='0'))

    # From: 20250119_000001_add_check_reconciliations_tables.py (revision: 20250119_000001_add_check_reconciliations_tables)
    # ایجاد جدول check_reconciliations
    op.create_table(
            'check_reconciliations',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
            sa.Column('name', sa.String(length=255), nullable=False),
            sa.Column('base_date', sa.DateTime(), nullable=False),
            sa.Column('calculated_average_days', sa.Numeric(10, 2), nullable=False),
            sa.Column('calculated_date', sa.DateTime(), nullable=False),
            sa.Column('total_amount', sa.Numeric(18, 2), nullable=False),
            sa.Column('check_count', sa.Integer(), nullable=False),
            sa.Column('currency_id', sa.Integer(), sa.ForeignKey('currencies.id', ondelete='RESTRICT'), nullable=False),
            sa.Column('description', sa.String(length=1000), nullable=True),
            sa.Column('created_by_user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='RESTRICT'), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
    )
    
        # ایجاد ایندکس‌ها برای check_reconciliations
    op.create_index('ix_check_reconciliations_business', 'check_reconciliations', ['business_id'])
    op.create_index('ix_check_reconciliations_created_at', 'check_reconciliations', ['created_at'])
    
        # ایجاد جدول check_reconciliation_items
    op.create_table(
            'check_reconciliation_items',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('reconciliation_id', sa.Integer(), sa.ForeignKey('check_reconciliations.id', ondelete='CASCADE'), nullable=False),
            sa.Column('check_id', sa.Integer(), sa.ForeignKey('checks.id', ondelete='CASCADE'), nullable=False),
            sa.Column('days_to_maturity', sa.Integer(), nullable=False),
            sa.Column('weighted_value', sa.Numeric(18, 2), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
    )
    
        # ایجاد ایندکس‌ها برای check_reconciliation_items
    op.create_index('ix_check_reconciliation_items_reconciliation', 'check_reconciliation_items', ['reconciliation_id'])
    op.create_index('ix_check_reconciliation_items_check', 'check_reconciliation_items', ['check_id'])

    # From: 20250120_000001_add_persons_tables.py (revision: 20250120_000001)
    # ### commands auto generated by Alembic - please adjust! ###
    
        # Create persons table
    op.create_table('persons',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('business_id', sa.Integer(), nullable=False, comment='شناسه کسب و کار'),
            sa.Column('alias_name', sa.String(length=255), nullable=False, comment='نام مستعار (الزامی)'),
            sa.Column('first_name', sa.String(length=100), nullable=True, comment='نام'),
            sa.Column('last_name', sa.String(length=100), nullable=True, comment='نام خانوادگی'),
            sa.Column('person_type', sa.Enum('CUSTOMER', 'MARKETER', 'EMPLOYEE', 'SUPPLIER', 'PARTNER', 'SELLER', name='persontype'), nullable=False, comment='نوع شخص'),
            sa.Column('company_name', sa.String(length=255), nullable=True, comment='نام شرکت'),
            sa.Column('payment_id', sa.String(length=100), nullable=True, comment='شناسه پرداخت'),
            sa.Column('national_id', sa.String(length=20), nullable=True, comment='شناسه ملی'),
            sa.Column('registration_number', sa.String(length=50), nullable=True, comment='شماره ثبت'),
            sa.Column('economic_id', sa.String(length=50), nullable=True, comment='شناسه اقتصادی'),
            sa.Column('country', sa.String(length=100), nullable=True, comment='کشور'),
            sa.Column('province', sa.String(length=100), nullable=True, comment='استان'),
            sa.Column('city', sa.String(length=100), nullable=True, comment='شهرستان'),
            sa.Column('address', sa.Text(), nullable=True, comment='آدرس'),
            sa.Column('postal_code', sa.String(length=20), nullable=True, comment='کد پستی'),
            sa.Column('phone', sa.String(length=20), nullable=True, comment='تلفن'),
            sa.Column('mobile', sa.String(length=20), nullable=True, comment='موبایل'),
            sa.Column('fax', sa.String(length=20), nullable=True, comment='فکس'),
            sa.Column('email', sa.String(length=255), nullable=True, comment='پست الکترونیکی'),
            sa.Column('website', sa.String(length=255), nullable=True, comment='وب‌سایت'),
            sa.Column('is_active', sa.Boolean(), nullable=False, comment='وضعیت فعال بودن'),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_persons_business_id'), 'persons', ['business_id'], unique=False)
    op.create_index(op.f('ix_persons_alias_name'), 'persons', ['alias_name'], unique=False)
    op.create_index(op.f('ix_persons_national_id'), 'persons', ['national_id'], unique=False)
    
        # Create person_bank_accounts table
    op.create_table('person_bank_accounts',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('person_id', sa.Integer(), nullable=False, comment='شناسه شخص'),
            sa.Column('bank_name', sa.String(length=255), nullable=False, comment='نام بانک'),
            sa.Column('account_number', sa.String(length=50), nullable=True, comment='شماره حساب'),
            sa.Column('card_number', sa.String(length=20), nullable=True, comment='شماره کارت'),
            sa.Column('sheba_number', sa.String(length=30), nullable=True, comment='شماره شبا'),
            sa.Column('is_active', sa.Boolean(), nullable=False, comment='وضعیت فعال بودن'),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['person_id'], ['persons.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_person_bank_accounts_person_id'), 'person_bank_accounts', ['person_id'], unique=False)
    
        # ### end Alembic commands ###

    # From: 20250120_000001_add_warehouse_contact_fields.py (revision: 20250120_000001_add_warehouse_contact_fields)
    bind = op.get_bind()
    inspector = inspect(bind)
    
        # Check if warehouses table exists
    if inspector.has_table('warehouses'):
            cols = {c['name'] for c in inspector.get_columns('warehouses')}
        
            with op.batch_alter_table('warehouses') as batch_op:
            if 'warehouse_keeper' not in cols:
            batch_op.add_column(sa.Column('warehouse_keeper', sa.String(length=255), nullable=True, comment='نام انباردار'))
            if 'phone' not in cols:
            batch_op.add_column(sa.Column('phone', sa.String(length=32), nullable=True, comment='تلفن'))
            if 'address' not in cols:
            batch_op.add_column(sa.Column('address', sa.Text(), nullable=True, comment='آدرس'))
            if 'postal_code' not in cols:
            batch_op.add_column(sa.Column('postal_code', sa.String(length=16), nullable=True, comment='کد پستی'))

    # From: 20250120_000002_add_join_permission.py (revision: 20250120_000002)
    """Add join permission support"""
            # جدول business_permissions قبلاً وجود دارد و JSON field است
        # بنابراین نیازی به تغییر schema نیست

    # From: 20250125_000001_add_telegram_ai_sessions.py (revision: 20250125_000001)
    # بررسی وجود جدول قبل از ایجاد
    from sqlalchemy import inspect
    conn = op.get_bind()
    inspector = inspect(conn)
    tables = inspector.get_table_names()
    
    if 'telegram_ai_sessions' in tables:
            # جدول از قبل وجود دارد، فقط ایندکس‌ها را بررسی می‌کنیم
            existing_indexes = [idx['name'] for idx in inspector.get_indexes('telegram_ai_sessions')]
            if 'ix_telegram_ai_sessions_user_id' not in existing_indexes:
            op.create_index(op.f('ix_telegram_ai_sessions_user_id'), 'telegram_ai_sessions', ['user_id'], unique=False)
            if 'ix_telegram_ai_sessions_chat_id' not in existing_indexes:
            op.create_index(op.f('ix_telegram_ai_sessions_chat_id'), 'telegram_ai_sessions', ['chat_id'], unique=False)
            if 'ix_telegram_ai_sessions_session_id' not in existing_indexes:
            op.create_index(op.f('ix_telegram_ai_sessions_session_id'), 'telegram_ai_sessions', ['session_id'], unique=False)
            if 'ix_telegram_ai_sessions_business_id' not in existing_indexes:
            op.create_index(op.f('ix_telegram_ai_sessions_business_id'), 'telegram_ai_sessions', ['business_id'], unique=False)
            if 'ix_telegram_ai_sessions_user_chat_active' not in existing_indexes:
            op.create_index('ix_telegram_ai_sessions_user_chat_active', 'telegram_ai_sessions', ['user_id', 'chat_id', 'is_active'], unique=False)
            return
    
        # ایجاد جدول telegram_ai_sessions
    op.create_table(
            'telegram_ai_sessions',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('chat_id', sa.BigInteger(), nullable=False),
            sa.Column('session_id', sa.Integer(), nullable=True),
            sa.Column('business_id', sa.Integer(), nullable=True),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.ForeignKeyConstraint(['session_id'], ['ai_chat_sessions.id'], ondelete='SET NULL'),
            sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('user_id', 'chat_id', 'session_id', name='uq_telegram_ai_sessions_user_chat_session')
    )
    
        # ایجاد ایندکس‌ها
    op.create_index(op.f('ix_telegram_ai_sessions_user_id'), 'telegram_ai_sessions', ['user_id'], unique=False)
    op.create_index(op.f('ix_telegram_ai_sessions_chat_id'), 'telegram_ai_sessions', ['chat_id'], unique=False)
    op.create_index(op.f('ix_telegram_ai_sessions_session_id'), 'telegram_ai_sessions', ['session_id'], unique=False)
    op.create_index(op.f('ix_telegram_ai_sessions_business_id'), 'telegram_ai_sessions', ['business_id'], unique=False)
    op.create_index('ix_telegram_ai_sessions_user_chat_active', 'telegram_ai_sessions', ['user_id', 'chat_id', 'is_active'], unique=False)

    # From: 20250126_000001_add_gift_credit_account.py (revision: 20250126_000001_add_gift_credit_account)
    conn = op.get_bind()
    
        # بررسی وجود حساب 602 (درآمد های غیر عملیاتی)
    select_parent = sa.text("SELECT id FROM accounts WHERE business_id IS NULL AND code = '602' LIMIT 1")
    parent_result = conn.execute(select_parent)
    parent_row = parent_result.fetchone()
    
    if not parent_row:
            # اگر حساب والد وجود ندارد، از migration قبلی استفاده نکنید
            return
    
    parent_id = parent_row[0]
    
        # بررسی وجود حساب 60205
    select_existing = sa.text("SELECT id FROM accounts WHERE business_id IS NULL AND code = '60205' LIMIT 1")
    existing_result = conn.execute(select_existing)
    existing_row = existing_result.fetchone()
    
    if existing_row:
            # حساب از قبل وجود دارد
            return
    
        # اضافه کردن حساب جدید
    insert_query = sa.text(
            """
            INSERT INTO accounts (name, business_id, account_type, code, parent_id, created_at, updated_at)
            VALUES (:name, NULL, :account_type, :code, :parent_id, NOW(), NOW())
            """
    )
    
    conn.execute(
            insert_query,
            {
            "name": "کمک‌های دریافتی / اعتبارات هدیه",
            "account_type": "0",
            "code": "60205",
            "parent_id": parent_id,
            }
    )

    # From: 20250130_000001_create_tax_settings_table.py (revision: 20250130_000001_create_tax_settings_table)
    bind = op.get_bind()
    inspector = inspect(bind)
    created_table = False

    if not inspector.has_table("tax_settings"):
            op.create_table(
            "tax_settings",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), nullable=False),
            sa.Column("created_by_user_id", sa.Integer(), nullable=True),
            sa.Column("tax_memory_id", sa.String(length=128), nullable=True),
            sa.Column("economic_code", sa.String(length=64), nullable=True),
            sa.Column("private_key", sa.Text(), nullable=True),
            sa.Column("public_key", sa.Text(), nullable=True),
            sa.Column("certificate", sa.Text(), nullable=True),
            sa.Column("certificate_request", sa.Text(), nullable=True),
            sa.Column("sandbox_mode", sa.Boolean(), nullable=False, server_default=sa.text("0")),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
            sa.UniqueConstraint("business_id", name="uq_tax_settings_business"),
            )
            created_table = True

    existing_indexes = {idx["name"] for idx in inspector.get_indexes("tax_settings")}

    if created_table or "ix_tax_settings_business_id" not in existing_indexes:
            try:
            op.create_index(op.f("ix_tax_settings_business_id"), "tax_settings", ["business_id"], unique=False)
            except Exception:
            
    if created_table or "ix_tax_settings_created_by_user_id" not in existing_indexes:
            try:
            op.create_index(op.f("ix_tax_settings_created_by_user_id"), "tax_settings", ["created_by_user_id"], unique=False)
            except Exception:

    # From: 20250205_000001_create_document_number_counters.py (revision: 20250205_000001_create_document_number_counters)
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    table_exists = "document_number_counters" in inspector.get_table_names()

    if not table_exists:
            op.create_table(
            "document_number_counters",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column(
            "business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
            ),
            sa.Column("document_type", sa.String(length=50), nullable=False),
            sa.Column("date_bucket", sa.String(length=32), nullable=False, server_default="GLOBAL"),
            sa.Column("last_number", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            )

    existing_indexes = set()
    existing_uniques = set()
    if table_exists:
            existing_indexes = {index["name"] for index in inspector.get_indexes("document_number_counters")}
            existing_uniques = {uc["name"] for uc in inspector.get_unique_constraints("document_number_counters")}

    if not table_exists or "ix_doc_number_counter_business" not in existing_indexes:
            op.create_index(
            "ix_doc_number_counter_business",
            "document_number_counters",
            ["business_id"],
            )
    if not table_exists or "ix_doc_number_counter_document_type" not in existing_indexes:
            op.create_index(
            "ix_doc_number_counter_document_type",
            "document_number_counters",
            ["document_type"],
            )
    if not table_exists or "uq_doc_number_counter_bucket" not in existing_uniques:
            op.create_unique_constraint(
            "uq_doc_number_counter_bucket",
            "document_number_counters",
            ["business_id", "document_type", "date_bucket"],
            )

    # From: 20250206_000001_add_product_instances_and_unique_inventory.py (revision: 20250206_000001_add_product_instances_and_unique_inventory)
    bind = op.get_bind()
    inspector = inspect(bind)
    
        # بررسی و افزودن فیلدهای جدید به جدول products
    products_columns = {c['name'] for c in inspector.get_columns('products')}
    
    if 'inventory_mode' not in products_columns:
            op.add_column(
            "products",
            sa.Column("inventory_mode", sa.String(length=16), nullable=True, server_default="bulk", comment="حالت موجودی: bulk (فله‌ای) یا unique (یونیک)"),
            )
    
    if 'track_serial' not in products_columns:
            op.add_column(
            "products",
            sa.Column("track_serial", sa.Boolean(), nullable=False, server_default="false", comment="ردیابی سریال نامبر برای کالاهای یونیک"),
            )
    
    if 'track_barcode' not in products_columns:
            op.add_column(
            "products",
            sa.Column("track_barcode", sa.Boolean(), nullable=False, server_default="false", comment="ردیابی بارکد برای کالاهای یونیک"),
            )
    
        # بررسی و ایجاد جدول product_instances
    tables = set(inspector.get_table_names())
    
    if 'product_instances' not in tables:
            op.create_table(
            "product_instances",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), nullable=False),
            sa.Column("product_id", sa.Integer(), nullable=False),
            sa.Column("serial_number", sa.String(length=128), nullable=False, comment="شماره سریال یکتا"),
            sa.Column("barcode", sa.String(length=128), nullable=True, comment="بارکد یکتا (اختیاری)"),
            sa.Column("warehouse_id", sa.Integer(), nullable=True),
            sa.Column("status", sa.String(length=16), nullable=False, server_default="available", comment="وضعیت: available, sold, warranty, defective"),
            sa.Column("custom_attributes", sa.JSON(), nullable=True, comment="ویژگی‌های کالا مانند رنگ، سایز، مدل و ..."),
            sa.Column("entry_date", sa.Date(), nullable=False, server_default=sa.text("CURRENT_DATE"), comment="تاریخ ورود به انبار"),
            sa.Column("last_movement_date", sa.Date(), nullable=True, comment="تاریخ آخرین جابجایی"),
            sa.Column("current_invoice_id", sa.Integer(), nullable=True, comment="فاکتور فروش (اگر فروخته شده)"),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
            sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
            sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["warehouse_id"], ["warehouses.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["current_invoice_id"], ["documents.id"], ondelete="SET NULL"),
            sa.UniqueConstraint("business_id", "serial_number", name="uq_product_instances_business_serial"),
            sa.UniqueConstraint("business_id", "barcode", name="uq_product_instances_business_barcode"),
            )
        
            # ایجاد ایندکس‌ها
            op.create_index("idx_product_instances_product", "product_instances", ["product_id"])
            op.create_index("idx_product_instances_warehouse", "product_instances", ["warehouse_id"])
            op.create_index("idx_product_instances_status", "product_instances", ["status"])
            op.create_index("idx_product_instances_business", "product_instances", ["business_id"])
    
        # بررسی و افزودن فیلد instance_ids به warehouse_document_lines
    if 'warehouse_document_lines' in tables:
            warehouse_document_lines_columns = {c['name'] for c in inspector.get_columns('warehouse_document_lines')}
            if 'instance_ids' not in warehouse_document_lines_columns:
            op.add_column(
            "warehouse_document_lines",
            sa.Column("instance_ids", sa.JSON(), nullable=True, comment="لیست ID کالاهای یونیک (برای inventory_mode=unique)"),
            )

    # From: 20250915_000001_init_auth_tables.py (revision: 20250915_000001)
    op.create_table(
    		"users",
    		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
    		sa.Column("email", sa.String(length=255), nullable=True),
    		sa.Column("mobile", sa.String(length=32), nullable=True),
    		sa.Column("first_name", sa.String(length=100), nullable=True),
    		sa.Column("last_name", sa.String(length=100), nullable=True),
    		sa.Column("password_hash", sa.String(length=255), nullable=False),
    		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("1")),
    		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
    		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP")),
    	)
    	op.create_index("ix_users_email", "users", ["email"], unique=True)
    	op.create_index("ix_users_mobile", "users", ["mobile"], unique=True)

    	op.create_table(
    		"api_keys",
    		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
    		sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
    		sa.Column("key_hash", sa.String(length=128), nullable=False),
    		sa.Column("key_type", sa.String(length=16), nullable=False),
    		sa.Column("name", sa.String(length=100), nullable=True),
    		sa.Column("scopes", sa.String(length=500), nullable=True),
    		sa.Column("device_id", sa.String(length=100), nullable=True),
    		sa.Column("user_agent", sa.String(length=255), nullable=True),
    		sa.Column("ip", sa.String(length=64), nullable=True),
    		sa.Column("expires_at", sa.DateTime(), nullable=True),
    		sa.Column("last_used_at", sa.DateTime(), nullable=True),
    		sa.Column("revoked_at", sa.DateTime(), nullable=True),
    		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
    	)
    	op.create_index("ix_api_keys_key_hash", "api_keys", ["key_hash"], unique=True)
    	op.create_index("ix_api_keys_user_id", "api_keys", ["user_id"], unique=False)

    	op.create_table(
    		"captchas",
    		sa.Column("id", sa.String(length=40), primary_key=True),
    		sa.Column("code_hash", sa.String(length=128), nullable=False),
    		sa.Column("expires_at", sa.DateTime(), nullable=False),
    		sa.Column("attempts", sa.Integer(), nullable=False, server_default=sa.text("0")),
    		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
    	)

    	op.create_table(
    		"password_resets",
    		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
    		sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
    		sa.Column("token_hash", sa.String(length=128), nullable=False),
    		sa.Column("expires_at", sa.DateTime(), nullable=False),
    		sa.Column("used_at", sa.DateTime(), nullable=True),
    		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
    	)
    	op.create_index("ix_password_resets_token_hash", "password_resets", ["token_hash"], unique=True)
    	op.create_index("ix_password_resets_user_id", "password_resets", ["user_id"], unique=False)

    # From: 20250916_000002_add_referral_fields.py (revision: 20250916_000002)
    # Add columns (referral_code nullable for backfill, then set NOT NULL)
    op.add_column("users", sa.Column("referral_code", sa.String(length=32), nullable=True))
    op.add_column("users", sa.Column("referred_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True))

        # Backfill referral_code for existing users with unique random strings
    bind = op.get_bind()
    users_tbl = sa.table("users", sa.column("id", sa.Integer), sa.column("referral_code", sa.String))

        # Fetch all user ids
    res = bind.execute(sa.text("SELECT id FROM users"))
    user_ids = [row[0] for row in res] if res else []

        # Helper to generate unique codes
    import secrets
    def gen_code(length: int = 10) -> str:
            return secrets.token_urlsafe(8).replace('-', '').replace('_', '')[:length]

        # Ensure uniqueness at DB level by checking existing set
    codes = set()
    for uid in user_ids:
            code = gen_code()
            # try to avoid duplicates within the batch
            while code in codes:
            code = gen_code()
            codes.add(code)
            bind.execute(sa.text("UPDATE users SET referral_code = :code WHERE id = :id"), {"code": code, "id": uid})

        # Now make referral_code NOT NULL and unique indexed
    op.alter_column("users", "referral_code", existing_type=sa.String(length=32), nullable=False)
    op.create_index("ix_users_referral_code", "users", ["referral_code"], unique=True)

    # From: 20250926_000010_add_person_code.py (revision: 20250926_000010_add_person_code)
    bind = op.get_bind()
    	inspector = inspect(bind)
    	# اگر جدول persons وجود ندارد، این مایگریشن را نادیده بگیر
    	if 'persons' not in inspector.get_table_names():
    		return
    	cols = {c['name'] for c in inspector.get_columns('persons')}
    	with op.batch_alter_table('persons') as batch_op:
    		if 'code' not in cols:
    			batch_op.add_column(sa.Column('code', sa.Integer(), nullable=True))
    		if 'person_types' not in cols:
    			batch_op.add_column(sa.Column('person_types', sa.Text(), nullable=True))
    		# unique constraint if not exists
    		existing_uniques = {uc['name'] for uc in inspector.get_unique_constraints('persons')}
    		if 'uq_persons_business_code' not in existing_uniques:
    			batch_op.create_unique_constraint('uq_persons_business_code', ['business_id', 'code'])

    # From: 20250926_000011_drop_active.py (revision: 20250926_000011_drop_active)
    bind = op.get_bind()
    inspector = inspect(bind)
    tables = set(inspector.get_table_names())
    if 'persons' in tables:
            with op.batch_alter_table('persons') as batch_op:
            try:
            batch_op.drop_column('is_active')
            except Exception:
                
    if 'person_bank_accounts' in tables:
            with op.batch_alter_table('person_bank_accounts') as batch_op:
            try:
            batch_op.drop_column('is_active')
            except Exception:

    # From: 20250927_000012_add_fiscal_years.py (revision: 20250927_000012_add_fiscal_years)
    bind = op.get_bind()
    	inspector = inspect(bind)

    	# Create fiscal_years table if not exists
    	if 'fiscal_years' not in inspector.get_table_names():
    		op.create_table(
    			'fiscal_years',
    			sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    			sa.Column('business_id', sa.Integer(), nullable=False),
    			sa.Column('title', sa.String(length=255), nullable=False),
    			sa.Column('start_date', sa.Date(), nullable=False),
    			sa.Column('end_date', sa.Date(), nullable=False),
    			sa.Column('is_last', sa.Boolean(), nullable=False, server_default=sa.text('0')),
    			sa.Column('created_at', sa.DateTime(), nullable=False),
    			sa.Column('updated_at', sa.DateTime(), nullable=False),
    			sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
    			sa.PrimaryKeyConstraint('id')
    		)

    	# Indexes if not exists
    	existing_indexes = {idx['name'] for idx in inspector.get_indexes('fiscal_years')} if 'fiscal_years' in inspector.get_table_names() else set()
    	if 'ix_fiscal_years_business_id' not in existing_indexes:
    		op.create_index('ix_fiscal_years_business_id', 'fiscal_years', ['business_id'])
    	if 'ix_fiscal_years_title' not in existing_indexes:
    		op.create_index('ix_fiscal_years_title', 'fiscal_years', ['title'])

    # From: 20250927_000013_add_currencies.py (revision: 20250927_000013_add_currencies)
    bind = op.get_bind()
    	inspector = inspect(bind)
    	tables = set(inspector.get_table_names())
	
    	# Create currencies table if it doesn't exist
    	if 'currencies' not in tables:
    		op.create_table(
    			'currencies',
    			sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    			sa.Column('name', sa.String(length=100), nullable=False),
    			sa.Column('title', sa.String(length=100), nullable=False),
    			sa.Column('symbol', sa.String(length=16), nullable=False),
    			sa.Column('code', sa.String(length=16), nullable=False),
    			sa.Column('created_at', sa.DateTime(), nullable=False),
    			sa.Column('updated_at', sa.DateTime(), nullable=False),
    			sa.PrimaryKeyConstraint('id'),
    			mysql_charset='utf8mb4'
    		)
    		# Unique constraints and indexes
    		op.create_unique_constraint('uq_currencies_name', 'currencies', ['name'])
    		op.create_unique_constraint('uq_currencies_code', 'currencies', ['code'])
    		op.create_index('ix_currencies_name', 'currencies', ['name'])

    	# Create business_currencies association table if it doesn't exist
    	if 'business_currencies' not in tables:
    		op.create_table(
    			'business_currencies',
    			sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    			sa.Column('business_id', sa.Integer(), nullable=False),
    			sa.Column('currency_id', sa.Integer(), nullable=False),
    			sa.Column('created_at', sa.DateTime(), nullable=False),
    			sa.Column('updated_at', sa.DateTime(), nullable=False),
    			sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
    			sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='CASCADE'),
    			sa.PrimaryKeyConstraint('id'),
    			mysql_charset='utf8mb4'
    		)
    		# Unique and indexes for association
    		op.create_unique_constraint('uq_business_currencies_business_currency', 'business_currencies', ['business_id', 'currency_id'])
    		op.create_index('ix_business_currencies_business_id', 'business_currencies', ['business_id'])
    		op.create_index('ix_business_currencies_currency_id', 'business_currencies', ['currency_id'])

    	# Add default_currency_id to businesses if not exists
    	if 'businesses' in tables:
    		cols = {c['name'] for c in inspector.get_columns('businesses')}
    		if 'default_currency_id' not in cols:
    			with op.batch_alter_table('businesses') as batch_op:
        batch_op.add_column(sa.Column('default_currency_id', sa.Integer(), nullable=True))
        batch_op.create_foreign_key('fk_businesses_default_currency', 'currencies', ['default_currency_id'], ['id'], ondelete='RESTRICT')
        batch_op.create_index('ix_businesses_default_currency_id', ['default_currency_id'])

    # From: 20250927_000014_add_documents.py (revision: 20250927_000014_add_documents)
    # Create documents table
    	op.create_table(
    		'documents',
    		sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    		sa.Column('code', sa.String(length=50), nullable=False),
    		sa.Column('business_id', sa.Integer(), nullable=False),
    		sa.Column('currency_id', sa.Integer(), nullable=False),
    		sa.Column('created_by_user_id', sa.Integer(), nullable=False),
    		sa.Column('registered_at', sa.DateTime(), nullable=False),
    		sa.Column('document_date', sa.Date(), nullable=False),
    		sa.Column('document_type', sa.String(length=50), nullable=False),
    		sa.Column('is_proforma', sa.Boolean(), nullable=False, server_default=sa.text('0')),
    		sa.Column('extra_info', sa.JSON(), nullable=True),
    		sa.Column('developer_settings', sa.JSON(), nullable=True),
    		sa.Column('created_at', sa.DateTime(), nullable=False),
    		sa.Column('updated_at', sa.DateTime(), nullable=False),
    		sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
    		sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
    		sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='RESTRICT'),
    		sa.PrimaryKeyConstraint('id'),
    		mysql_charset='utf8mb4'
    	)

    	# Unique per business code
    	op.create_unique_constraint('uq_documents_business_code', 'documents', ['business_id', 'code'])

    	# Indexes
    	op.create_index('ix_documents_code', 'documents', ['code'])
    	op.create_index('ix_documents_business_id', 'documents', ['business_id'])
    	op.create_index('ix_documents_currency_id', 'documents', ['currency_id'])
    	op.create_index('ix_documents_created_by_user_id', 'documents', ['created_by_user_id'])

    # From: 20250927_000015_add_lines.py (revision: 20250927_000015_add_lines)
    bind = op.get_bind()
    	inspector = inspect(bind)
    	tables = set(inspector.get_table_names())
	
    	# Create document_lines table if it doesn't exist
    	if 'document_lines' not in tables:
    		op.create_table(
    			'document_lines',
    			sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    			sa.Column('document_id', sa.Integer(), nullable=False),
    			sa.Column('debit', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')), 
    			sa.Column('credit', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
    			sa.Column('description', sa.Text(), nullable=True),
    			sa.Column('extra_info', sa.JSON(), nullable=True),
    			sa.Column('developer_data', sa.JSON(), nullable=True),
    			sa.Column('created_at', sa.DateTime(), nullable=False),
    			sa.Column('updated_at', sa.DateTime(), nullable=False),
    			sa.ForeignKeyConstraint(['document_id'], ['documents.id'], ondelete='CASCADE'),
    			sa.PrimaryKeyConstraint('id'),
    			mysql_charset='utf8mb4'
    		)
		
    		# Create indexes
    		op.create_index('ix_document_lines_document_id', 'document_lines', ['document_id'])

    # From: 20250927_000016_add_accounts_table.py (revision: 20250927_000016_add_accounts_table)
    op.create_table(
    		'accounts',
    		sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    		sa.Column('name', sa.String(length=255), nullable=False),
    		sa.Column('business_id', sa.Integer(), nullable=True),
    		sa.Column('account_type', sa.String(length=50), nullable=False),
    		sa.Column('code', sa.String(length=50), nullable=False),
    		sa.Column('parent_id', sa.Integer(), nullable=True),
    		sa.Column('created_at', sa.DateTime(), nullable=False),
    		sa.Column('updated_at', sa.DateTime(), nullable=False),
    		sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
    		sa.ForeignKeyConstraint(['parent_id'], ['accounts.id'], ondelete='SET NULL'),
    		sa.PrimaryKeyConstraint('id'),
    		mysql_charset='utf8mb4'
    	)

    	op.create_unique_constraint('uq_accounts_business_code', 'accounts', ['business_id', 'code'])
    	op.create_index('ix_accounts_name', 'accounts', ['name'])
    	op.create_index('ix_accounts_business_id', 'accounts', ['business_id'])
    	op.create_index('ix_accounts_parent_id', 'accounts', ['parent_id'])

    # From: 20250927_000017_add_account_id_to_document_lines.py (revision: 20250927_000017_add_account_id_to_document_lines)
    with op.batch_alter_table('document_lines') as batch_op:
    		batch_op.add_column(sa.Column('account_id', sa.Integer(), nullable=True))
    		batch_op.create_foreign_key('fk_document_lines_account_id_accounts', 'accounts', ['account_id'], ['id'], ondelete='RESTRICT')
    		batch_op.create_index('ix_document_lines_account_id', ['account_id'])

    # From: 20250927_000018_seed_currencies.py (revision: 20250927_000018_seed_currencies)
    conn = op.get_bind()
    	insert_sql = sa.text(
    		"""
    		INSERT INTO currencies (name, title, symbol, code, created_at, updated_at)
    		VALUES (:name, :title, :symbol, :code, NOW(), NOW())
    		ON DUPLICATE KEY UPDATE
    			title = VALUES(title),
    			symbol = VALUES(symbol),
    			updated_at = VALUES(updated_at)
    		"""
    	)

    	currencies = [
    		{"name": "Iranian Rial", "title": "ریال ایران", "symbol": "﷼", "code": "IRR"},
    		{"name": "United States Dollar", "title": "US Dollar", "symbol": "$", "code": "USD"},
    		{"name": "Euro", "title": "Euro", "symbol": "€", "code": "EUR"},
    		{"name": "British Pound", "title": "Pound Sterling", "symbol": "£", "code": "GBP"},
    		{"name": "Japanese Yen", "title": "Yen", "symbol": "¥", "code": "JPY"},
    		{"name": "Chinese Yuan", "title": "Yuan", "symbol": "¥", "code": "CNY"},
    		{"name": "Swiss Franc", "title": "Swiss Franc", "symbol": "CHF", "code": "CHF"},
    		{"name": "Canadian Dollar", "title": "Canadian Dollar", "symbol": "$", "code": "CAD"},
    		{"name": "Australian Dollar", "title": "Australian Dollar", "symbol": "$", "code": "AUD"},
    		{"name": "New Zealand Dollar", "title": "New Zealand Dollar", "symbol": "$", "code": "NZD"},
    		{"name": "Russian Ruble", "title": "Ruble", "symbol": "₽", "code": "RUB"},
    		{"name": "Turkish Lira", "title": "Lira", "symbol": "₺", "code": "TRY"},
    		{"name": "UAE Dirham", "title": "Dirham", "symbol": "د.إ", "code": "AED"},
    		{"name": "Saudi Riyal", "title": "Riyal", "symbol": "﷼", "code": "SAR"},
    		{"name": "Qatari Riyal", "title": "Qatari Riyal", "symbol": "﷼", "code": "QAR"},
    		{"name": "Kuwaiti Dinar", "title": "Kuwaiti Dinar", "symbol": "د.ك", "code": "KWD"},
    		{"name": "Omani Rial", "title": "Omani Rial", "symbol": "﷼", "code": "OMR"},
    		{"name": "Bahraini Dinar", "title": "Bahraini Dinar", "symbol": ".د.ب", "code": "BHD"},
    		{"name": "Iraqi Dinar", "title": "Iraqi Dinar", "symbol": "ع.د", "code": "IQD"},
    		{"name": "Afghan Afghani", "title": "Afghani", "symbol": "؋", "code": "AFN"},
    		{"name": "Pakistani Rupee", "title": "Rupee", "symbol": "₨", "code": "PKR"},
    		{"name": "Indian Rupee", "title": "Rupee", "symbol": "₹", "code": "INR"},
    		{"name": "Armenian Dram", "title": "Dram", "symbol": "֏", "code": "AMD"},
    		{"name": "Azerbaijani Manat", "title": "Manat", "symbol": "₼", "code": "AZN"},
    		{"name": "Georgian Lari", "title": "Lari", "symbol": "₾", "code": "GEL"},
    		{"name": "Kazakhstani Tenge", "title": "Tenge", "symbol": "₸", "code": "KZT"},
    		{"name": "Uzbekistani Som", "title": "Som", "symbol": "so'm", "code": "UZS"},
    		{"name": "Tajikistani Somoni", "title": "Somoni", "symbol": "ЅМ", "code": "TJS"},
    		{"name": "Turkmenistani Manat", "title": "Manat", "symbol": "m", "code": "TMT"},
    		{"name": "Afgani Lek", "title": "Lek", "symbol": "L", "code": "ALL"},
    		{"name": "Bulgarian Lev", "title": "Lev", "symbol": "лв", "code": "BGN"},
    		{"name": "Romanian Leu", "title": "Leu", "symbol": "lei", "code": "RON"},
    		{"name": "Polish Złoty", "title": "Zloty", "symbol": "zł", "code": "PLN"},
    		{"name": "Czech Koruna", "title": "Koruna", "symbol": "Kč", "code": "CZK"},
    		{"name": "Hungarian Forint", "title": "Forint", "symbol": "Ft", "code": "HUF"},
    		{"name": "Danish Krone", "title": "Krone", "symbol": "kr", "code": "DKK"},
    		{"name": "Norwegian Krone", "title": "Krone", "symbol": "kr", "code": "NOK"},
    		{"name": "Swedish Krona", "title": "Krona", "symbol": "kr", "code": "SEK"},
    		{"name": "Icelandic Króna", "title": "Krona", "symbol": "kr", "code": "ISK"},
    		{"name": "Croatian Kuna", "title": "Kuna", "symbol": "kn", "code": "HRK"},
    		{"name": "Serbian Dinar", "title": "Dinar", "symbol": "дин.", "code": "RSD"},
    		{"name": "Bosnia and Herzegovina Mark", "title": "Mark", "symbol": "KM", "code": "BAM"},
    		{"name": "Ukrainian Hryvnia", "title": "Hryvnia", "symbol": "₴", "code": "UAH"},
    		{"name": "Belarusian Ruble", "title": "Ruble", "symbol": "Br", "code": "BYN"},
    		{"name": "Egyptian Pound", "title": "Pound", "symbol": "£", "code": "EGP"},
    		{"name": "South African Rand", "title": "Rand", "symbol": "R", "code": "ZAR"},
    		{"name": "Nigerian Naira", "title": "Naira", "symbol": "₦", "code": "NGN"},
    		{"name": "Kenyan Shilling", "title": "Shilling", "symbol": "Sh", "code": "KES"},
    		{"name": "Ethiopian Birr", "title": "Birr", "symbol": "Br", "code": "ETB"},
    		{"name": "Moroccan Dirham", "title": "Dirham", "symbol": "د.م.", "code": "MAD"},
    		{"name": "Tunisian Dinar", "title": "Dinar", "symbol": "د.ت", "code": "TND"},
    		{"name": "Algerian Dinar", "title": "Dinar", "symbol": "د.ج", "code": "DZD"},
    		{"name": "Israeli New Shekel", "title": "Shekel", "symbol": "₪", "code": "ILS"},
    		{"name": "Jordanian Dinar", "title": "Dinar", "symbol": "د.ا", "code": "JOD"},
    		{"name": "Lebanese Pound", "title": "Pound", "symbol": "ل.ل", "code": "LBP"},
    		{"name": "Syrian Pound", "title": "Pound", "symbol": "£", "code": "SYP"},
    		{"name": "Azerbaijani Manat", "title": "Manat", "symbol": "₼", "code": "AZN"},
    		{"name": "Singapore Dollar", "title": "Singapore Dollar", "symbol": "$", "code": "SGD"},
    		{"name": "Hong Kong Dollar", "title": "Hong Kong Dollar", "symbol": "$", "code": "HKD"},
    		{"name": "Thai Baht", "title": "Baht", "symbol": "฿", "code": "THB"},
    		{"name": "Malaysian Ringgit", "title": "Ringgit", "symbol": "RM", "code": "MYR"},
    		{"name": "Indonesian Rupiah", "title": "Rupiah", "symbol": "Rp", "code": "IDR"},
    		{"name": "Philippine Peso", "title": "Peso", "symbol": "₱", "code": "PHP"},
    		{"name": "Vietnamese Dong", "title": "Dong", "symbol": "₫", "code": "VND"},
    		{"name": "South Korean Won", "title": "Won", "symbol": "₩", "code": "KRW"},
    		{"name": "Taiwan New Dollar", "title": "New Dollar", "symbol": "$", "code": "TWD"},
    		{"name": "Mexican Peso", "title": "Peso", "symbol": "$", "code": "MXN"},
    		{"name": "Brazilian Real", "title": "Real", "symbol": "R$", "code": "BRL"},
    		{"name": "Argentine Peso", "title": "Peso", "symbol": "$", "code": "ARS"},
    		{"name": "Chilean Peso", "title": "Peso", "symbol": "$", "code": "CLP"},
    		{"name": "Colombian Peso", "title": "Peso", "symbol": "$", "code": "COP"},
    		{"name": "Peruvian Sol", "title": "Sol", "symbol": "S/.", "code": "PEN"},
    		{"name": "Uruguayan Peso", "title": "Peso", "symbol": "$U", "code": "UYU"},
    		{"name": "Paraguayan Guarani", "title": "Guarani", "symbol": "₲", "code": "PYG"},
    		{"name": "Bolivian Boliviano", "title": "Boliviano", "symbol": "Bs.", "code": "BOB"},
    		{"name": "Dominican Peso", "title": "Peso", "symbol": "RD$", "code": "DOP"},
    		{"name": "Cuban Peso", "title": "Peso", "symbol": "$", "code": "CUP"},
    		{"name": "Costa Rican Colon", "title": "Colon", "symbol": "₡", "code": "CRC"},
    		{"name": "Guatemalan Quetzal", "title": "Quetzal", "symbol": "Q", "code": "GTQ"},
    		{"name": "Honduran Lempira", "title": "Lempira", "symbol": "L", "code": "HNL"},
    		{"name": "Nicaraguan Córdoba", "title": "Cordoba", "symbol": "C$", "code": "NIO"},
    		{"name": "Panamanian Balboa", "title": "Balboa", "symbol": "B/.", "code": "PAB"},
    		{"name": "Venezuelan Bolívar", "title": "Bolivar", "symbol": "Bs.", "code": "VES"},
    	]

    	for row in currencies:
    		conn.execute(insert_sql, row)

    # From: 20250927_000019_seed_accounts_chart.py (revision: 20250927_000019_seed_accounts_chart)
    conn = op.get_bind()

    	# داده‌ها (خلاصه‌شده برای خوانایی؛ از JSON کاربر)
    	accounts = [
    		{"id":2452,"level":1,"code":"1","name":"دارایی ها","parentId":0,"accountType":0},
    		{"id":2453,"level":2,"code":"101","name":"دارایی های جاری","parentId":2452,"accountType":0},
    		{"id":2454,"level":3,"code":"102","name":"موجودی نقد و بانک","parentId":2453,"accountType":0},
    		{"id":2455,"level":4,"code":"10201","name":"تنخواه گردان","parentId":2454,"accountType":2},
    		{"id":2456,"level":4,"code":"10202","name":"صندوق","parentId":2454,"accountType":1},
    		{"id":2457,"level":4,"code":"10203","name":"بانک","parentId":2454,"accountType":3},
    		{"id":2458,"level":4,"code":"10204","name":"وجوه در راه","parentId":2454,"accountType":0},
    		{"id":2459,"level":3,"code":"103","name":"سپرده های کوتاه مدت","parentId":2453,"accountType":0},
    		{"id":2460,"level":4,"code":"10301","name":"سپرده شرکت در مناقصه و مزایده","parentId":2459,"accountType":0},
    		{"id":2461,"level":4,"code":"10302","name":"ضمانت نامه بانکی","parentId":2459,"accountType":0},
    		{"id":2462,"level":4,"code":"10303","name":"سایر سپرده ها","parentId":2459,"accountType":0},
    		{"id":2463,"level":3,"code":"104","name":"حساب های دریافتنی","parentId":2453,"accountType":0},
    		{"id":2464,"level":4,"code":"10401","name":"حساب های دریافتنی","parentId":2463,"accountType":4},
    		{"id":2465,"level":4,"code":"10402","name":"ذخیره مطالبات مشکوک الوصول","parentId":2463,"accountType":0},
    		{"id":2466,"level":4,"code":"10403","name":"اسناد دریافتنی","parentId":2463,"accountType":5},
    		{"id":2467,"level":4,"code":"10404","name":"اسناد در جریان وصول","parentId":2463,"accountType":6},
    		{"id":2468,"level":3,"code":"105","name":"سایر حساب های دریافتنی","parentId":2453,"accountType":0},
    		{"id":2469,"level":4,"code":"10501","name":"وام کارکنان","parentId":2468,"accountType":0},
    		{"id":2470,"level":4,"code":"10502","name":"سایر حساب های دریافتنی","parentId":2468,"accountType":0},
    		{"id":2471,"level":3,"code":"10101","name":"پیش پرداخت ها","parentId":2453,"accountType":0},
    		{"id":2472,"level":3,"code":"10102","name":"موجودی کالا","parentId":2453,"accountType":7},
    		{"id":2473,"level":3,"code":"10103","name":"ملزومات","parentId":2453,"accountType":0},
    		{"id":2474,"level":3,"code":"10104","name":"مالیات بر ارزش افزوده خرید","parentId":2453,"accountType":8},
    		{"id":2475,"level":2,"code":"106","name":"دارایی های غیر جاری","parentId":2452,"accountType":0},
    		{"id":2476,"level":3,"code":"107","name":"دارایی های ثابت","parentId":2475,"accountType":0},
    		{"id":2477,"level":4,"code":"10701","name":"زمین","parentId":2476,"accountType":0},
    		{"id":2478,"level":4,"code":"10702","name":"ساختمان","parentId":2476,"accountType":0},
    		{"id":2479,"level":4,"code":"10703","name":"وسائط نقلیه","parentId":2476,"accountType":0},
    		{"id":2480,"level":4,"code":"10704","name":"اثاثیه اداری","parentId":2476,"accountType":0},
    		{"id":2481,"level":3,"code":"108","name":"استهلاک انباشته","parentId":2475,"accountType":0},
    		{"id":2482,"level":4,"code":"10801","name":"استهلاک انباشته ساختمان","parentId":2481,"accountType":0},
    		{"id":2483,"level":4,"code":"10802","name":"استهلاک انباشته وسائط نقلیه","parentId":2481,"accountType":0},
    		{"id":2484,"level":4,"code":"10803","name":"استهلاک انباشته اثاثیه اداری","parentId":2481,"accountType":0},
    		{"id":2485,"level":3,"code":"109","name":"سپرده های بلندمدت","parentId":2475,"accountType":0},
    		{"id":2486,"level":3,"code":"110","name":"سایر دارائی ها","parentId":2475,"accountType":0},
    		{"id":2487,"level":4,"code":"11001","name":"حق الامتیازها","parentId":2486,"accountType":0},
    		{"id":2488,"level":4,"code":"11002","name":"نرم افزارها","parentId":2486,"accountType":0},
    		{"id":2489,"level":4,"code":"11003","name":"سایر دارایی های نامشهود","parentId":2486,"accountType":0},
    		{"id":2490,"level":1,"code":"2","name":"بدهی ها","parentId":0,"accountType":0},
    		{"id":2491,"level":2,"code":"201","name":"بدهیهای جاری","parentId":2490,"accountType":0},
    		{"id":2492,"level":3,"code":"202","name":"حساب ها و اسناد پرداختنی","parentId":2491,"accountType":0},
    		{"id":2493,"level":4,"code":"20201","name":"حساب های پرداختنی","parentId":2492,"accountType":9},
    		{"id":2494,"level":4,"code":"20202","name":"اسناد پرداختنی","parentId":2492,"accountType":10},
    		{"id":2495,"level":3,"code":"203","name":"سایر حساب های پرداختنی","parentId":2491,"accountType":0},
    		{"id":2496,"level":4,"code":"20301","name":"ذخیره مالیات بر درآمد پرداختنی","parentId":2495,"accountType":40},
    		{"id":2497,"level":4,"code":"20302","name":"مالیات بر درآمد پرداختنی","parentId":2495,"accountType":12},
    		{"id":2498,"level":4,"code":"20303","name":"مالیات حقوق و دستمزد پرداختنی","parentId":2495,"accountType":0},
    		{"id":2499,"level":4,"code":"20304","name":"حق بیمه پرداختنی","parentId":2495,"accountType":0},
    		{"id":2500,"level":4,"code":"20305","name":"حقوق و دستمزد پرداختنی","parentId":2495,"accountType":42},
    		{"id":2501,"level":4,"code":"20306","name":"عیدی و پاداش پرداختنی","parentId":2495,"accountType":0},
    		{"id":2502,"level":4,"code":"20307","name":"سایر هزینه های پرداختنی","parentId":2495,"accountType":0},
    		{"id":2503,"level":3,"code":"204","name":"پیش دریافت ها","parentId":2491,"accountType":0},
    		{"id":2504,"level":4,"code":"20401","name":"پیش دریافت فروش","parentId":2503,"accountType":0},
    		{"id":2505,"level":4,"code":"20402","name":"سایر پیش دریافت ها","parentId":2503,"accountType":0},
    		{"id":2506,"level":3,"code":"20101","name":"مالیات بر ارزش افزوده فروش","parentId":2491,"accountType":11},
    		{"id":2507,"level":2,"code":"205","name":"بدهیهای غیر جاری","parentId":2490,"accountType":0},
    		{"id":2508,"level":3,"code":"206","name":"حساب ها و اسناد پرداختنی بلندمدت","parentId":2507,"accountType":0},
    		{"id":2509,"level":4,"code":"20601","name":"حساب های پرداختنی بلندمدت","parentId":2508,"accountType":0},
    		{"id":2510,"level":4,"code":"20602","name":"اسناد پرداختنی بلندمدت","parentId":2508,"accountType":0},
    		{"id":2511,"level":3,"code":"20501","name":"وام پرداختنی","parentId":2507,"accountType":0},
    		{"id":2512,"level":3,"code":"20502","name":"ذخیره مزایای پایان خدمت کارکنان","parentId":2507,"accountType":0},
    		{"id":2513,"level":1,"code":"3","name":"حقوق صاحبان سهام","parentId":0,"accountType":0},
    		{"id":2514,"level":2,"code":"301","name":"سرمایه","parentId":2513,"accountType":0},
    		{"id":2515,"level":3,"code":"30101","name":"سرمایه اولیه","parentId":2514,"accountType":13},
    		{"id":2516,"level":3,"code":"30102","name":"افزایش یا کاهش سرمایه","parentId":2514,"accountType":14},
    		{"id":2517,"level":3,"code":"30103","name":"اندوخته قانونی","parentId":2514,"accountType":15},
    		{"id":2518,"level":3,"code":"30104","name":"برداشت ها","parentId":2514,"accountType":16},
    		{"id":2519,"level":3,"code":"30105","name":"سهم سود و زیان","parentId":2514,"accountType":17},
    		{"id":2520,"level":3,"code":"30106","name":"سود یا زیان انباشته (سنواتی)","parentId":2514,"accountType":18},
    		{"id":2521,"level":1,"code":"4","name":"بهای تمام شده کالای فروخته شده","parentId":0,"accountType":0},
    		{"id":2522,"level":2,"code":"40001","name":"بهای تمام شده کالای فروخته شده","parentId":2521,"accountType":19},
    		{"id":2523,"level":2,"code":"40002","name":"برگشت از خرید","parentId":2521,"accountType":20},
    		{"id":2524,"level":2,"code":"40003","name":"تخفیفات نقدی خرید","parentId":2521,"accountType":21},
    		{"id":2525,"level":1,"code":"5","name":"فروش","parentId":0,"accountType":0},
    		{"id":2526,"level":2,"code":"50001","name":"فروش کالا","parentId":2525,"accountType":22},
    		{"id":2527,"level":2,"code":"50002","name":"برگشت از فروش","parentId":2525,"accountType":23},
    		{"id":2528,"level":2,"code":"50003","name":"تخفیفات نقدی فروش","parentId":2525,"accountType":24},
    		{"id":2529,"level":1,"code":"6","name":"درآمد","parentId":0,"accountType":0},
    		{"id":2530,"level":2,"code":"601","name":"درآمد های عملیاتی","parentId":2529,"accountType":0},
    		{"id":2531,"level":3,"code":"60101","name":"درآمد حاصل از فروش خدمات","parentId":2530,"accountType":25},
    		{"id":2532,"level":3,"code":"60102","name":"برگشت از خرید خدمات","parentId":2530,"accountType":26},
    		{"id":2533,"level":3,"code":"60103","name":"درآمد اضافه کالا","parentId":2530,"accountType":27},
    		{"id":2534,"level":3,"code":"60104","name":"درآمد حمل کالا","parentId":2530,"accountType":28},
    		{"id":2535,"level":2,"code":"602","name":"درآمد های غیر عملیاتی","parentId":2529,"accountType":0},
    		{"id":2536,"level":3,"code":"60201","name":"درآمد حاصل از سرمایه گذاری","parentId":2535,"accountType":0},
    		{"id":2537,"level":3,"code":"60202","name":"درآمد سود سپرده ها","parentId":2535,"accountType":0},
    		{"id":2538,"level":3,"code":"60203","name":"سایر درآمد ها","parentId":2535,"accountType":0},
    		{"id":2539,"level":3,"code":"60204","name":"درآمد تسعیر ارز","parentId":2535,"accountType":36},
    		{"id":2540,"level":1,"code":"7","name":"هزینه ها","parentId":0,"accountType":0},
    		{"id":2541,"level":2,"code":"701","name":"هزینه های پرسنلی","parentId":2540,"accountType":0},
    		{"id":2542,"level":3,"code":"702","name":"هزینه حقوق و دستمزد","parentId":2541,"accountType":0},
    		{"id":2543,"level":4,"code":"70201","name":"حقوق پایه","parentId":2542,"accountType":0},
    		{"id":2544,"level":4,"code":"70202","name":"اضافه کار","parentId":2542,"accountType":0},
    		{"id":2545,"level":4,"code":"70203","name":"حق شیفت و شب کاری","parentId":2542,"accountType":0},
    		{"id":2546,"level":4,"code":"70204","name":"حق نوبت کاری","parentId":2542,"accountType":0},
    		{"id":2547,"level":4,"code":"70205","name":"حق ماموریت","parentId":2542,"accountType":0},
    		{"id":2548,"level":4,"code":"70206","name":"فوق العاده مسکن و خاروبار","parentId":2542,"accountType":0},
    		{"id":2549,"level":4,"code":"70207","name":"حق اولاد","parentId":2542,"accountType":0},
    		{"id":2550,"level":4,"code":"70208","name":"عیدی و پاداش","parentId":2542,"accountType":0},
    		{"id":2551,"level":4,"code":"70209","name":"بازخرید سنوات خدمت کارکنان","parentId":2542,"accountType":0},
    		{"id":2552,"level":4,"code":"70210","name":"بازخرید مرخصی","parentId":2542,"accountType":0},
    		{"id":2553,"level":4,"code":"70211","name":"بیمه سهم کارفرما","parentId":2542,"accountType":0},
    		{"id":2554,"level":4,"code":"70212","name":"بیمه بیکاری","parentId":2542,"accountType":0},
    		{"id":2555,"level":4,"code":"70213","name":"حقوق مزایای متفرقه","parentId":2542,"accountType":0},
    		{"id":2556,"level":3,"code":"703","name":"سایر هزینه های کارکنان","parentId":2541,"accountType":0},
    		{"id":2557,"level":4,"code":"70301","name":"سفر و ماموریت","parentId":2556,"accountType":0},
    		{"id":2558,"level":4,"code":"70302","name":"ایاب و ذهاب","parentId":2556,"accountType":0},
    		{"id":2559,"level":4,"code":"70303","name":"سایر هزینه های کارکنان","parentId":2556,"accountType":0},
    		{"id":2560,"level":2,"code":"704","name":"هزینه های عملیاتی","parentId":2540,"accountType":0},
    		{"id":2561,"level":3,"code":"70401","name":"خرید خدمات","parentId":2560,"accountType":30},
    		{"id":2562,"level":3,"code":"70402","name":"برگشت از فروش خدمات","parentId":2560,"accountType":29},
    		{"id":2563,"level":3,"code":"70403","name":"هزینه حمل کالا","parentId":2560,"accountType":31},
    		{"id":2564,"level":3,"code":"70404","name":"تعمیر و نگهداری اموال و اثاثیه","parentId":2560,"accountType":0},
    		{"id":2565,"level":3,"code":"70405","name":"هزینه اجاره محل","parentId":2560,"accountType":0},
    		{"id":2566,"level":2,"code":"705","name":"هزینه های عمومی","parentId":2540,"accountType":0},
    		{"id":2567,"level":4,"code":"70501","name":"هزینه آب و برق و گاز و تلفن","parentId":2566,"accountType":0},
    		{"id":2568,"level":4,"code":"70502","name":"هزینه پذیرایی و آبدارخانه","parentId":2566,"accountType":0},
    		{"id":2569,"level":3,"code":"70406","name":"هزینه ملزومات مصرفی","parentId":2560,"accountType":0},
    		{"id":2570,"level":3,"code":"70407","name":"هزینه کسری و ضایعات کالا","parentId":2560,"accountType":32},
    		{"id":2571,"level":3,"code":"70408","name":"بیمه دارایی های ثابت","parentId":2560,"accountType":0},
    		{"id":2572,"level":2,"code":"706","name":"هزینه های استهلاک","parentId":2540,"accountType":0},
    		{"id":2573,"level":3,"code":"70601","name":"هزینه استهلاک ساختمان","parentId":2572,"accountType":0},
    		{"id":2574,"level":3,"code":"70602","name":"هزینه استهلاک وسائط نقلیه","parentId":2572,"accountType":0},
    		{"id":2575,"level":3,"code":"70603","name":"هزینه استهلاک اثاثیه","parentId":2572,"accountType":0},
    		{"id":2576,"level":2,"code":"707","name":"هزینه های بازاریابی و توزیع و فروش","parentId":2540,"accountType":0},
    		{"id":2577,"level":3,"code":"70701","name":"هزینه آگهی و تبلیغات","parentId":2576,"accountType":0},
    		{"id":2578,"level":3,"code":"70702","name":"هزینه بازاریابی و پورسانت","parentId":2576,"accountType":0},
    		{"id":2579,"level":3,"code":"70703","name":"سایر هزینه های توزیع و فروش","parentId":2576,"accountType":0},
    		{"id":2580,"level":2,"code":"708","name":"هزینه های غیرعملیاتی","parentId":2540,"accountType":0},
    		{"id":2581,"level":3,"code":"709","name":"هزینه های بانکی","parentId":2580,"accountType":0},
    		{"id":2582,"level":4,"code":"70901","name":"سود و کارمزد وامها","parentId":2581,"accountType":0},
    		{"id":2583,"level":4,"code":"70902","name":"کارمزد خدمات بانکی","parentId":2581,"accountType":33},
    		{"id":2584,"level":4,"code":"70903","name":"جرائم دیرکرد بانکی","parentId":2581,"accountType":0},
    		{"id":2585,"level":3,"code":"70801","name":"هزینه تسعیر ارز","parentId":2580,"accountType":37},
    		{"id":2586,"level":3,"code":"70802","name":"هزینه مطالبات سوخت شده","parentId":2580,"accountType":0},
    		{"id":2587,"level":1,"code":"8","name":"سایر حساب ها","parentId":0,"accountType":0},
    		{"id":2588,"level":2,"code":"801","name":"حساب های انتظامی","parentId":2587,"accountType":0},
    		{"id":2589,"level":3,"code":"80101","name":"حساب های انتظامی","parentId":2588,"accountType":0},
    		{"id":2590,"level":3,"code":"80102","name":"طرف حساب های انتظامی","parentId":2588,"accountType":0},
    		{"id":2591,"level":2,"code":"802","name":"حساب های کنترلی","parentId":2587,"accountType":0},
    		{"id":2592,"level":3,"code":"80201","name":"کنترل کسری و اضافه کالا","parentId":2591,"accountType":34},
    		{"id":2593,"level":2,"code":"803","name":"حساب خلاصه سود و زیان","parentId":2587,"accountType":0},
    		{"id":2594,"level":3,"code":"80301","name":"خلاصه سود و زیان","parentId":2593,"accountType":35},
    		{"id":2595,"level":5,"code":"70503","name":"هزینه آب","parentId":2567,"accountType":0},
    		{"id":2596,"level":5,"code":"70504","name":"هزینه برق","parentId":2567,"accountType":0},
    		{"id":2597,"level":5,"code":"70505","name":"هزینه گاز","parentId":2567,"accountType":0},
    		{"id":2598,"level":5,"code":"70506","name":"هزینه تلفن","parentId":2567,"accountType":0},
    		{"id":2600,"level":4,"code":"20503","name":"وام از بانک ملت","parentId":2511,"accountType":0},
    		{"id":2601,"level":4,"code":"10405","name":"سود تحقق نیافته فروش اقساطی","parentId":2463,"accountType":39},
    		{"id":2602,"level":3,"code":"60205","name":"سود فروش اقساطی","parentId":2535,"accountType":38},
    		{"id":2603,"level":4,"code":"70214","name":"حق تاهل","parentId":2542,"accountType":0},
    		{"id":2604,"level":4,"code":"20504","name":"وام از بانک پارسیان","parentId":2511,"accountType":0},
    		{"id":2605,"level":3,"code":"10105","name":"مساعده","parentId":2453,"accountType":0},
    		{"id":2606,"level":3,"code":"60105","name":"تعمیرات لوازم آشپزخانه","parentId":2530,"accountType":0},
    		{"id":2607,"level":4,"code":"10705","name":"کامپیوتر","parentId":2476,"accountType":0},
    		{"id":2608,"level":3,"code":"60206","name":"درامد حاصل از فروش ضایعات","parentId":2535,"accountType":0},
    		{"id":2609,"level":3,"code":"60207","name":"سود فروش دارایی","parentId":2535,"accountType":0},
    		{"id":2610,"level":3,"code":"70803","name":"زیان فروش دارایی","parentId":2580,"accountType":0},
    		{"id":2611,"level":3,"code":"10106","name":"موجودی کالای در جریان ساخت","parentId":2453,"accountType":41},
    		{"id":2612,"level":3,"code":"20102","name":"سربار تولید پرداختنی","parentId":2491,"accountType":43},
    	]

    	# نقشه id خارجی به id داخلی
    	ext_to_internal: dict[int, int] = {}

    	# کوئری‌ها
    	select_existing = sa.text("SELECT id FROM accounts WHERE business_id IS NULL AND code = :code LIMIT 1")
    	insert_q = sa.text(
    		"""
    		INSERT INTO accounts (name, business_id, account_type, code, parent_id, created_at, updated_at)
    		VALUES (:name, NULL, :account_type, :code, :parent_id, NOW(), NOW())
    		"""
    	)
    	update_q = sa.text(
    		"""
    		UPDATE accounts
    		SET name = :name, account_type = :account_type, parent_id = :parent_id, updated_at = NOW()
    		WHERE id = :id
    		"""
    	)

    	for item in accounts:
    		parent_internal = None
    		if item.get("parentId") and item["parentId"] in ext_to_internal:
    			parent_internal = ext_to_internal[item["parentId"]]

    		# وجودی؟
    		res = conn.execute(select_existing, {"code": item["code"]})
    		row = res.fetchone()
    		if row is None:
    			result = conn.execute(
        insert_q,
        {
        "name": item["name"],
        "account_type": str(item.get("accountType", 0)),
        "code": item["code"],
        "parent_id": parent_internal,
        },
    			)
    			new_id = result.lastrowid if hasattr(result, "lastrowid") else None
    			if new_id is None:
    				# fallback: انتخاب بر اساس code
        res2 = conn.execute(select_existing, {"code": item["code"]})
        row2 = res2.fetchone()
        if row2:
        new_id = row2[0]
    			else:
				
    			if new_id is not None:
        ext_to_internal[item["id"]] = int(new_id)
    		else:
    			acc_id = int(row[0])
    			conn.execute(
        update_q,
        {
        "id": acc_id,
        "name": item["name"],
        "account_type": str(item.get("accountType", 0)),
        "parent_id": parent_internal,
        },
    			)
    			ext_to_internal[item["id"]] = acc_id

    # From: 20250927_000020_add_share_count_and_shareholder_type.py (revision: 20250927_000020_add_share_count_and_shareholder_type)
    b = op.get_bind()
    	inspector = inspect(b)
    	cols = {c['name'] for c in inspector.get_columns('persons')} if 'persons' in inspector.get_table_names() else set()
    	with op.batch_alter_table('persons') as batch_op:
    		if 'share_count' not in cols:
    			batch_op.add_column(sa.Column('share_count', sa.Integer(), nullable=True))

        # افزودن مقدار جدید به ENUM ستون person_type (برای MySQL)
        # مقادیر فارسی مطابق Enum مدل: 'مشتری','بازاریاب','کارمند','تامین‌کننده','همکار','فروشنده'
        # مقدار جدید: 'سهامدار'
    	op.execute(
    		"""
    		ALTER TABLE persons 
    		MODIFY COLUMN person_type 
            ENUM('مشتری','بازاریاب','کارمند','تامین‌کننده','همکار','فروشنده','سهامدار') NOT NULL
    		"""
    	)

    # From: 20250927_000021_update_person_type_enum_to_persian.py (revision: 20250927_000021_update_person_type_enum_to_persian)
    # 1) Allow both English and Persian, plus new 'سهامدار'
    	op.execute(
    		"""
    		ALTER TABLE persons 
    		MODIFY COLUMN person_type 
    		ENUM('CUSTOMER','MARKETER','EMPLOYEE','SUPPLIER','PARTNER','SELLER',
        'مشتری','بازاریاب','کارمند','تامین‌کننده','همکار','فروشنده','سهامدار') NOT NULL
    		"""
    	)

    	# 2) Migrate existing data from English to Persian
    	op.execute("UPDATE persons SET person_type = 'مشتری' WHERE person_type = 'CUSTOMER'")
    	op.execute("UPDATE persons SET person_type = 'بازاریاب' WHERE person_type = 'MARKETER'")
    	op.execute("UPDATE persons SET person_type = 'کارمند' WHERE person_type = 'EMPLOYEE'")
    	op.execute("UPDATE persons SET person_type = 'تامین‌کننده' WHERE person_type = 'SUPPLIER'")
    	op.execute("UPDATE persons SET person_type = 'همکار' WHERE person_type = 'PARTNER'")
    	op.execute("UPDATE persons SET person_type = 'فروشنده' WHERE person_type = 'SELLER'")

    	# 3) Restrict enum to Persian only (including 'سهامدار')
    	op.execute(
    		"""
    		ALTER TABLE persons 
    		MODIFY COLUMN person_type 
    		ENUM('مشتری','بازاریاب','کارمند','تامین‌کننده','همکار','فروشنده','سهامدار') NOT NULL
    		"""
    	)

    # From: 20250927_000022_add_person_commission_fields.py (revision: 20250927_000022_add_person_commission_fields)
    bind = op.get_bind()
    	inspector = inspect(bind)
    	cols = {c['name'] for c in inspector.get_columns('persons')} if 'persons' in inspector.get_table_names() else set()
    	with op.batch_alter_table('persons') as batch_op:
    		if 'commission_sale_percent' not in cols:
    			batch_op.add_column(sa.Column('commission_sale_percent', sa.Numeric(5, 2), nullable=True))
    		if 'commission_sales_return_percent' not in cols:
    			batch_op.add_column(sa.Column('commission_sales_return_percent', sa.Numeric(5, 2), nullable=True))
    		if 'commission_sales_amount' not in cols:
    			batch_op.add_column(sa.Column('commission_sales_amount', sa.Numeric(12, 2), nullable=True))
    		if 'commission_sales_return_amount' not in cols:
    			batch_op.add_column(sa.Column('commission_sales_return_amount', sa.Numeric(12, 2), nullable=True))
    		if 'commission_exclude_discounts' not in cols:
    			batch_op.add_column(sa.Column('commission_exclude_discounts', sa.Boolean(), server_default=sa.text('0'), nullable=False))
    		if 'commission_exclude_additions_deductions' not in cols:
    			batch_op.add_column(sa.Column('commission_exclude_additions_deductions', sa.Boolean(), server_default=sa.text('0'), nullable=False))
    		if 'commission_post_in_invoice_document' not in cols:
    			batch_op.add_column(sa.Column('commission_post_in_invoice_document', sa.Boolean(), server_default=sa.text('0'), nullable=False))

    # From: 20250928_000023_remove_person_is_active_force.py (revision: 20250928_000023_remove_person_is_active_force)
    bind = op.get_bind()
    inspector = inspect(bind)
    tables = set(inspector.get_table_names())

        # Drop is_active from persons if exists
    if 'persons' in tables:
            columns = {col['name'] for col in inspector.get_columns('persons')}
            if 'is_active' in columns:
            with op.batch_alter_table('persons') as batch_op:
            try:
            batch_op.drop_column('is_active')
            except Exception:
                    
        # Drop is_active from person_bank_accounts if exists
    if 'person_bank_accounts' in tables:
            columns = {col['name'] for col in inspector.get_columns('person_bank_accounts')}
            if 'is_active' in columns:
            with op.batch_alter_table('person_bank_accounts') as batch_op:
            try:
            batch_op.drop_column('is_active')
            except Exception:

    # From: 20250929_000101_add_categories_table.py (revision: 20250929_000101_add_categories_table)
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

    # From: 20250929_000201_drop_type_from_categories.py (revision: 20250929_000201_drop_type_from_categories)
    # حذف ایندکس مرتبط با ستون type اگر وجود دارد
    try:
            op.drop_index('ix_categories_type', table_name='categories')
    except Exception:
        
        # حذف ستون type
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    cols = [c['name'] for c in inspector.get_columns('categories')]
    if 'type' in cols:
            with op.batch_alter_table('categories') as batch_op:
            try:
            batch_op.drop_column('type')
            except Exception:

    # From: 20250929_000301_add_product_attributes_table.py (revision: 20250929_000301_add_product_attributes_table)
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

    # From: 20250929_000401_drop_is_active_from_product_attributes.py (revision: 20250929_000401_drop_is_active_from_product_attributes)
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    cols = [c['name'] for c in inspector.get_columns('product_attributes')]
    if 'is_active' in cols:
            with op.batch_alter_table('product_attributes') as batch_op:
            try:
            batch_op.drop_column('is_active')
            except Exception:

    # From: 20250929_000501_add_products_and_pricing.py (revision: 20250929_000501_add_products_and_pricing)
    # Create products table (with existence check)
    connection = op.get_bind()
    
        # Check if products table exists
    result = connection.execute(sa.text("""
            SELECT COUNT(*) 
            FROM information_schema.tables 
            WHERE table_schema = DATABASE() 
            AND table_name = 'products'
    """)).fetchone()
    
    if result[0] == 0:
            op.create_table(
            'products',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('business_id', sa.Integer(), nullable=False),
            sa.Column('item_type', sa.Enum('کالا', 'خدمت', name='product_item_type_enum'), nullable=False),
            sa.Column('code', sa.String(length=64), nullable=False),
            sa.Column('name', sa.String(length=255), nullable=False),
            sa.Column('description', sa.Text(), nullable=True),
            sa.Column('category_id', sa.Integer(), nullable=True),
            sa.Column('main_unit_id', sa.Integer(), nullable=True),
            sa.Column('secondary_unit_id', sa.Integer(), nullable=True),
            sa.Column('unit_conversion_factor', sa.Numeric(18, 6), nullable=True),
            sa.Column('base_sales_price', sa.Numeric(18, 2), nullable=True),
            sa.Column('base_sales_note', sa.Text(), nullable=True),
            sa.Column('base_purchase_price', sa.Numeric(18, 2), nullable=True),
            sa.Column('base_purchase_note', sa.Text(), nullable=True),
            sa.Column('track_inventory', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('reorder_point', sa.Integer(), nullable=True),
            sa.Column('min_order_qty', sa.Integer(), nullable=True),
            sa.Column('lead_time_days', sa.Integer(), nullable=True),
            sa.Column('is_sales_taxable', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('is_purchase_taxable', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('sales_tax_rate', sa.Numeric(5, 2), nullable=True),
            sa.Column('purchase_tax_rate', sa.Numeric(5, 2), nullable=True),
            sa.Column('tax_type_id', sa.Integer(), nullable=True),
            sa.Column('tax_code', sa.String(length=100), nullable=True),
            sa.Column('tax_unit_id', sa.Integer(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            mysql_charset='utf8mb4'
            )
    
        # Create constraints and indexes (with existence checks)
    try:
            op.create_unique_constraint('uq_products_business_code', 'products', ['business_id', 'code'])
    except Exception:
            pass  # Constraint already exists
    
    try:
            op.create_index('ix_products_business_id', 'products', ['business_id'])
    except Exception:
            pass  # Index already exists
    
    try:
            op.create_index('ix_products_name', 'products', ['name'])
    except Exception:
            pass  # Index already exists
    
    try:
            op.create_foreign_key(None, 'products', 'businesses', ['business_id'], ['id'], ondelete='CASCADE')
    except Exception:
            pass  # Foreign key already exists
    
    try:
            op.create_foreign_key(None, 'products', 'categories', ['category_id'], ['id'], ondelete='SET NULL')
    except Exception:
            pass  # Foreign key already exists

        # Create price_lists table (with existence check)
    result = connection.execute(sa.text("""
            SELECT COUNT(*) 
            FROM information_schema.tables 
            WHERE table_schema = DATABASE() 
            AND table_name = 'price_lists'
    """)).fetchone()
    
    if result[0] == 0:
            op.create_table(
            'price_lists',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('business_id', sa.Integer(), nullable=False),
            sa.Column('name', sa.String(length=255), nullable=False),
            sa.Column('currency_id', sa.Integer(), nullable=True),
            sa.Column('default_unit_id', sa.Integer(), nullable=True),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            mysql_charset='utf8mb4'
            )
    
    try:
            op.create_unique_constraint('uq_price_lists_business_name', 'price_lists', ['business_id', 'name'])
    except Exception:
            pass  # Constraint already exists
    
    try:
            op.create_index('ix_price_lists_business_id', 'price_lists', ['business_id'])
    except Exception:
            pass  # Index already exists
    
    try:
            op.create_foreign_key(None, 'price_lists', 'businesses', ['business_id'], ['id'], ondelete='CASCADE')
    except Exception:
            pass  # Foreign key already exists
    
    try:
            op.create_foreign_key(None, 'price_lists', 'currencies', ['currency_id'], ['id'], ondelete='RESTRICT')
    except Exception:
            pass  # Foreign key already exists

        # Create price_items table (with existence check)
    result = connection.execute(sa.text("""
            SELECT COUNT(*) 
            FROM information_schema.tables 
            WHERE table_schema = DATABASE() 
            AND table_name = 'price_items'
    """)).fetchone()
    
    if result[0] == 0:
            op.create_table(
            'price_items',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('price_list_id', sa.Integer(), nullable=False),
            sa.Column('product_id', sa.Integer(), nullable=False),
            sa.Column('unit_id', sa.Integer(), nullable=True),
            sa.Column('currency_id', sa.Integer(), nullable=True),
            sa.Column('tier_name', sa.String(length=64), nullable=False),
            sa.Column('min_qty', sa.Numeric(18, 3), nullable=False, server_default=sa.text('0')),
            sa.Column('price', sa.Numeric(18, 2), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            mysql_charset='utf8mb4'
            )
    
    try:
            op.create_unique_constraint('uq_price_items_unique_tier', 'price_items', ['price_list_id', 'product_id', 'unit_id', 'tier_name', 'min_qty'])
    except Exception:
            pass  # Constraint already exists
    
    try:
            op.create_index('ix_price_items_price_list_id', 'price_items', ['price_list_id'])
    except Exception:
            pass  # Index already exists
    
    try:
            op.create_index('ix_price_items_product_id', 'price_items', ['product_id'])
    except Exception:
            pass  # Index already exists
    
    try:
            op.create_foreign_key(None, 'price_items', 'price_lists', ['price_list_id'], ['id'], ondelete='CASCADE')
    except Exception:
            pass  # Foreign key already exists
    
    try:
            op.create_foreign_key(None, 'price_items', 'products', ['product_id'], ['id'], ondelete='CASCADE')
    except Exception:
            pass  # Foreign key already exists
    
    try:
            op.create_foreign_key(None, 'price_items', 'currencies', ['currency_id'], ['id'], ondelete='RESTRICT')
    except Exception:
            pass  # Foreign key already exists

        # Create product_attribute_links table (with existence check)
    result = connection.execute(sa.text("""
            SELECT COUNT(*) 
            FROM information_schema.tables 
            WHERE table_schema = DATABASE() 
            AND table_name = 'product_attribute_links'
    """)).fetchone()
    
    if result[0] == 0:
            op.create_table(
            'product_attribute_links',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('product_id', sa.Integer(), nullable=False),
            sa.Column('attribute_id', sa.Integer(), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            mysql_charset='utf8mb4'
            )
    
    try:
            op.create_unique_constraint('uq_product_attribute_links_unique', 'product_attribute_links', ['product_id', 'attribute_id'])
    except Exception:
            pass  # Constraint already exists
    
    try:
            op.create_index('ix_product_attribute_links_product_id', 'product_attribute_links', ['product_id'])
    except Exception:
            pass  # Index already exists
    
    try:
            op.create_index('ix_product_attribute_links_attribute_id', 'product_attribute_links', ['attribute_id'])
    except Exception:
            pass  # Index already exists
    
    try:
            op.create_foreign_key(None, 'product_attribute_links', 'products', ['product_id'], ['id'], ondelete='CASCADE')
    except Exception:
            pass  # Foreign key already exists
    
    try:
            op.create_foreign_key(None, 'product_attribute_links', 'product_attributes', ['attribute_id'], ['id'], ondelete='CASCADE')
    except Exception:
            pass  # Foreign key already exists

    # From: 20251001_000601_update_price_items_currency_unique_not_null.py (revision: 20251001_000601_update_price_items_currency_unique_not_null)
    # 1) Backfill price_items.currency_id from price_lists.currency_id where NULL
    op.execute(
            sa.text(
            """
            UPDATE price_items pi
            JOIN price_lists pl ON pl.id = pi.price_list_id
            SET pi.currency_id = pl.currency_id
            WHERE pi.currency_id IS NULL
            """
            )
    )

        # 2) Drop old unique constraint if exists
    conn = op.get_bind()
    dialect_name = conn.dialect.name

    if dialect_name == 'mysql':
            # Check via information_schema and drop index if present
            exists = conn.execute(sa.text(
            """
            SELECT COUNT(*) as cnt
            FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'price_items'
            AND INDEX_NAME = 'uq_price_items_unique_tier'
            """
            )).scalar() or 0
            if int(exists) > 0:
            conn.execute(sa.text("ALTER TABLE price_items DROP INDEX uq_price_items_unique_tier"))
    else:
            # Generic drop constraint best-effort
            try:
            op.drop_constraint('uq_price_items_unique_tier', 'price_items', type_='unique')
            except Exception:
            
        # 3) Make currency_id NOT NULL
    op.alter_column('price_items', 'currency_id', existing_type=sa.Integer(), nullable=False, existing_nullable=True)

        # 4) Create new unique constraint including currency_id (idempotent)
    if dialect_name == 'mysql':
            exists_uc = conn.execute(sa.text(
            """
            SELECT COUNT(*) as cnt
            FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'price_items'
            AND INDEX_NAME = 'uq_price_items_unique_tier_currency'
            """
            )).scalar() or 0
            if int(exists_uc) == 0:
            op.create_unique_constraint(
            'uq_price_items_unique_tier_currency',
            'price_items',
            ['price_list_id', 'product_id', 'unit_id', 'tier_name', 'min_qty', 'currency_id']
            )
    else:
            try:
            op.create_unique_constraint(
            'uq_price_items_unique_tier_currency',
            'price_items',
            ['price_list_id', 'product_id', 'unit_id', 'tier_name', 'min_qty', 'currency_id']
            )
            except Exception:

    # From: 20251001_001101_drop_price_list_currency_default_unit.py (revision: 20251001_001101_drop_price_list_currency_default_unit)
    conn = op.get_bind()
    dialect = conn.dialect.name

        # Try to drop FK on price_lists.currency_id if exists
    if dialect == 'mysql':
            # Find foreign key constraint name dynamically and drop it
            fk_rows = conn.execute(sa.text(
            """
            SELECT CONSTRAINT_NAME
            FROM information_schema.KEY_COLUMN_USAGE
            WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'price_lists'
            AND COLUMN_NAME = 'currency_id'
            AND REFERENCED_TABLE_NAME IS NOT NULL
            GROUP BY CONSTRAINT_NAME
            """
            )).fetchall()
            for (fk_name,) in fk_rows:
            conn.execute(sa.text(f"ALTER TABLE price_lists DROP FOREIGN KEY {fk_name}"))

            # Finally drop columns if they exist (manual check)
            for col in ('currency_id', 'default_unit_id'):
            exists = conn.execute(sa.text(
            """
            SELECT COUNT(*) as cnt FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'price_lists' AND COLUMN_NAME = :col
            """
            ), {"col": col}).scalar() or 0
            if int(exists) > 0:
            conn.execute(sa.text(f"ALTER TABLE price_lists DROP COLUMN {col}"))
    else:
            # Best-effort: drop constraint by common names, then drop columns
            for name in ('price_lists_currency_id_fkey', 'fk_price_lists_currency_id', 'price_lists_currency_id_fk'):
            try:
            op.drop_constraint(name, 'price_lists', type_='foreignkey')
            break
            except Exception:
                
            try:
            op.drop_column('price_lists', 'currency_id')
            except Exception:
            
            try:
            op.drop_column('price_lists', 'default_unit_id')
            except Exception:

    # From: 20251002_000101_add_bank_accounts_table.py (revision: 20251002_000101_add_bank_accounts_table)
    bind = op.get_bind()
    	inspector = sa.inspect(bind)
    	if 'bank_accounts' not in inspector.get_table_names():
    		op.create_table(
    			'bank_accounts',
    			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
    			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
    			sa.Column('code', sa.String(length=50), nullable=True),
    			sa.Column('name', sa.String(length=255), nullable=False),
    			sa.Column('description', sa.String(length=500), nullable=True),
    			sa.Column('branch', sa.String(length=255), nullable=True),
    			sa.Column('account_number', sa.String(length=50), nullable=True),
    			sa.Column('sheba_number', sa.String(length=30), nullable=True),
    			sa.Column('card_number', sa.String(length=20), nullable=True),
    			sa.Column('owner_name', sa.String(length=255), nullable=True),
    			sa.Column('pos_number', sa.String(length=50), nullable=True),
    			sa.Column('payment_id', sa.String(length=100), nullable=True),
    			sa.Column('currency_id', sa.Integer(), sa.ForeignKey('currencies.id', ondelete='RESTRICT'), nullable=False),
    			sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
    			sa.Column('is_default', sa.Boolean(), nullable=False, server_default=sa.text('0')),
    			sa.Column('created_at', sa.DateTime(), nullable=False),
    			sa.Column('updated_at', sa.DateTime(), nullable=False),
    			sa.UniqueConstraint('business_id', 'code', name='uq_bank_accounts_business_code'),
    		)
    		try:
    			op.create_index('ix_bank_accounts_business_id', 'bank_accounts', ['business_id'])
    			op.create_index('ix_bank_accounts_currency_id', 'bank_accounts', ['currency_id'])
    		except Exception:
			
    	else:
    		# تلاش برای ایجاد ایندکس‌ها اگر وجود ندارند
    		existing_indexes = {idx['name'] for idx in inspector.get_indexes('bank_accounts')}
    		if 'ix_bank_accounts_business_id' not in existing_indexes:
    			try:
        op.create_index('ix_bank_accounts_business_id', 'bank_accounts', ['business_id'])
    			except Exception:
				
    		if 'ix_bank_accounts_currency_id' not in existing_indexes:
    			try:
        op.create_index('ix_bank_accounts_currency_id', 'bank_accounts', ['currency_id'])
    			except Exception:

    # From: 20251003_000201_add_cash_registers_table.py (revision: 20251003_000201_add_cash_registers_table)
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if 'cash_registers' not in inspector.get_table_names():
            op.create_table(
            'cash_registers',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
            sa.Column('code', sa.String(length=50), nullable=True),
            sa.Column('description', sa.String(length=500), nullable=True),
            sa.Column('currency_id', sa.Integer(), sa.ForeignKey('currencies.id', ondelete='RESTRICT'), nullable=False),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
            sa.Column('is_default', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('payment_switch_number', sa.String(length=100), nullable=True),
            sa.Column('payment_terminal_number', sa.String(length=100), nullable=True),
            sa.Column('merchant_id', sa.String(length=100), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.UniqueConstraint('business_id', 'code', name='uq_cash_registers_business_code'),
            )
            try:
            op.create_index('ix_cash_registers_business_id', 'cash_registers', ['business_id'])
            op.create_index('ix_cash_registers_currency_id', 'cash_registers', ['currency_id'])
            op.create_index('ix_cash_registers_is_active', 'cash_registers', ['is_active'])
            except Exception:

    # From: 20251003_010501_add_name_to_cash_registers.py (revision: 20251003_010501_add_name_to_cash_registers)
    # Add column if not exists (MySQL safe): try/except
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    cols = [c['name'] for c in inspector.get_columns('cash_registers')]
    if 'name' not in cols:
            op.add_column('cash_registers', sa.Column('name', sa.String(length=255), nullable=True))
            # Fill default empty name from code or merchant_id to avoid nulls
            try:
            conn.execute(sa.text("UPDATE cash_registers SET name = COALESCE(name, code)"))
            except Exception:
            
            # Alter to not null
            with op.batch_alter_table('cash_registers') as batch_op:
            batch_op.alter_column('name', existing_type=sa.String(length=255), nullable=False)
            # Create index
            try:
            op.create_index('ix_cash_registers_name', 'cash_registers', ['name'])
            except Exception:

    # From: 20251006_000001_add_tax_types_table_and_product_fks.py (revision: 20251006_000001)
    # Check if table already exists before creating it
    try:
            op.create_table(
            'tax_types',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('business_id', sa.Integer(), nullable=False, index=True, comment='شناسه کسب‌وکار'),
            sa.Column('title', sa.String(length=255), nullable=False, comment='عنوان نوع مالیات'),
            sa.Column('code', sa.String(length=64), nullable=True, comment='کد یکتا برای نوع مالیات'),
            sa.Column('description', sa.Text(), nullable=True, comment='توضیحات'),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1'), comment='وضعیت فعال/غیرفعال'),
            sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
            sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
            )
    except Exception:
            pass  # Table already exists
    
        # Create indexes (if they don't exist)
    try:
            op.create_index(op.f('ix_tax_types_business_id'), 'tax_types', ['business_id'], unique=False)
    except Exception:
            pass  # Index already exists
    
    try:
            op.create_index(op.f('ix_tax_types_code'), 'tax_types', ['code'], unique=False)
    except Exception:
            pass  # Index already exists

        # Ensure product indices exist (idempotent)
    try:
            op.create_index(op.f('ix_products_tax_type_id'), 'products', ['tax_type_id'], unique=False)
    except Exception:
        
    try:
            op.create_index(op.f('ix_products_tax_unit_id'), 'products', ['tax_unit_id'], unique=False)
    except Exception:

    # From: 20251011_010001_replace_accounts_chart_seed.py (revision: 20251011_010001_replace_accounts_chart_seed)
    conn = op.get_bind()

        # لیست کامل از کاربر (فقط فیلدهای لازم برای جدول accounts نگه داشته شده)
        # نگاشت: id => extId (صرفاً برای حلقه والد/فرزند). در جدول id خودکار است
    items = [
            {"id": 2452, "level": 1, "code": "1", "name": "دارایی ها", "parentId": 0, "accountType": 0},
            {"id": 2453, "level": 2, "code": "101", "name": "دارایی های جاری", "parentId": 2452, "accountType": 0},
            {"id": 2454, "level": 3, "code": "102", "name": "موجودی نقد و بانک", "parentId": 2453, "accountType": 0},
            {"id": 2455, "level": 4, "code": "10201", "name": "تنخواه گردان", "parentId": 2454, "accountType": 2},
            {"id": 2456, "level": 4, "code": "10202", "name": "صندوق", "parentId": 2454, "accountType": 1},
            {"id": 2457, "level": 4, "code": "10203", "name": "بانک", "parentId": 2454, "accountType": 3},
            {"id": 2458, "level": 4, "code": "10204", "name": "وجوه در راه", "parentId": 2454, "accountType": 0},
            {"id": 2459, "level": 3, "code": "103", "name": "سپرده های کوتاه مدت", "parentId": 2453, "accountType": 0},
            {"id": 2460, "level": 4, "code": "10301", "name": "سپرده شرکت در مناقصه و مزایده", "parentId": 2459, "accountType": 0},
            {"id": 2461, "level": 4, "code": "10302", "name": "ضمانت نامه بانکی", "parentId": 2459, "accountType": 0},
            {"id": 2462, "level": 4, "code": "10303", "name": "سایر سپرده ها", "parentId": 2459, "accountType": 0},
            {"id": 2463, "level": 3, "code": "104", "name": "حساب های دریافتنی", "parentId": 2453, "accountType": 0},
            {"id": 2464, "level": 4, "code": "10401", "name": "حساب های دریافتنی", "parentId": 2463, "accountType": 4},
            {"id": 2465, "level": 4, "code": "10402", "name": "ذخیره مطالبات مشکوک الوصول", "parentId": 2463, "accountType": 0},
            {"id": 2466, "level": 4, "code": "10403", "name": "اسناد دریافتنی", "parentId": 2463, "accountType": 5},
            {"id": 2467, "level": 4, "code": "10404", "name": "اسناد در جریان وصول", "parentId": 2463, "accountType": 6},
            {"id": 2468, "level": 3, "code": "105", "name": "سایر حساب های دریافتنی", "parentId": 2453, "accountType": 0},
            {"id": 2469, "level": 4, "code": "10501", "name": "وام کارکنان", "parentId": 2468, "accountType": 0},
            {"id": 2470, "level": 4, "code": "10502", "name": "سایر حساب های دریافتنی", "parentId": 2468, "accountType": 0},
            {"id": 2471, "level": 3, "code": "10101", "name": "پیش پرداخت ها", "parentId": 2453, "accountType": 0},
            {"id": 2472, "level": 3, "code": "10102", "name": "موجودی کالا", "parentId": 2453, "accountType": 7},
            {"id": 2473, "level": 3, "code": "10103", "name": "ملزومات", "parentId": 2453, "accountType": 0},
            {"id": 2474, "level": 3, "code": "10104", "name": "مالیات بر ارزش افزوده خرید", "parentId": 2453, "accountType": 8},
            {"id": 2475, "level": 2, "code": "106", "name": "دارایی های غیر جاری", "parentId": 2452, "accountType": 0},
            {"id": 2476, "level": 3, "code": "107", "name": "دارایی های ثابت", "parentId": 2475, "accountType": 0},
            {"id": 2477, "level": 4, "code": "10701", "name": "زمین", "parentId": 2476, "accountType": 0},
            {"id": 2478, "level": 4, "code": "10702", "name": "ساختمان", "parentId": 2476, "accountType": 0},
            {"id": 2479, "level": 4, "code": "10703", "name": "وسائط نقلیه", "parentId": 2476, "accountType": 0},
            {"id": 2480, "level": 4, "code": "10704", "name": "اثاثیه اداری", "parentId": 2476, "accountType": 0},
            {"id": 2481, "level": 3, "code": "108", "name": "استهلاک انباشته", "parentId": 2475, "accountType": 0},
            {"id": 2482, "level": 4, "code": "10801", "name": "استهلاک انباشته ساختمان", "parentId": 2481, "accountType": 0},
            {"id": 2483, "level": 4, "code": "10802", "name": "استهلاک انباشته وسائط نقلیه", "parentId": 2481, "accountType": 0},
            {"id": 2484, "level": 4, "code": "10803", "name": "استهلاک انباشته اثاثیه اداری", "parentId": 2481, "accountType": 0},
            {"id": 2485, "level": 3, "code": "109", "name": "سپرده های بلندمدت", "parentId": 2475, "accountType": 0},
            {"id": 2486, "level": 3, "code": "110", "name": "سایر دارائی ها", "parentId": 2475, "accountType": 0},
            {"id": 2487, "level": 4, "code": "11001", "name": "حق الامتیازها", "parentId": 2486, "accountType": 0},
            {"id": 2488, "level": 4, "code": "11002", "name": "نرم افزارها", "parentId": 2486, "accountType": 0},
            {"id": 2489, "level": 4, "code": "11003", "name": "سایر دارایی های نامشهود", "parentId": 2486, "accountType": 0},
            {"id": 2490, "level": 1, "code": "2", "name": "بدهی ها", "parentId": 0, "accountType": 0},
            {"id": 2491, "level": 2, "code": "201", "name": "بدهیهای جاری", "parentId": 2490, "accountType": 0},
            {"id": 2492, "level": 3, "code": "202", "name": "حساب ها و اسناد پرداختنی", "parentId": 2491, "accountType": 0},
            {"id": 2493, "level": 4, "code": "20201", "name": "حساب های پرداختنی", "parentId": 2492, "accountType": 9},
            {"id": 2494, "level": 4, "code": "20202", "name": "اسناد پرداختنی", "parentId": 2492, "accountType": 10},
            {"id": 2495, "level": 3, "code": "203", "name": "سایر حساب های پرداختنی", "parentId": 2491, "accountType": 0},
            {"id": 2496, "level": 4, "code": "20301", "name": "ذخیره مالیات بر درآمد پرداختنی", "parentId": 2495, "accountType": 40},
            {"id": 2497, "level": 4, "code": "20302", "name": "مالیات بر درآمد پرداختنی", "parentId": 2495, "accountType": 12},
            {"id": 2498, "level": 4, "code": "20303", "name": "مالیات حقوق و دستمزد پرداختنی", "parentId": 2495, "accountType": 0},
            {"id": 2499, "level": 4, "code": "20304", "name": "حق بیمه پرداختنی", "parentId": 2495, "accountType": 0},
            {"id": 2500, "level": 4, "code": "20305", "name": "حقوق و دستمزد پرداختنی", "parentId": 2495, "accountType": 42},
            {"id": 2501, "level": 4, "code": "20306", "name": "عیدی و پاداش پرداختنی", "parentId": 2495, "accountType": 0},
            {"id": 2502, "level": 4, "code": "20307", "name": "سایر هزینه های پرداختنی", "parentId": 2495, "accountType": 0},
            {"id": 2503, "level": 3, "code": "204", "name": "پیش دریافت ها", "parentId": 2491, "accountType": 0},
            {"id": 2504, "level": 4, "code": "20401", "name": "پیش دریافت فروش", "parentId": 2503, "accountType": 0},
            {"id": 2505, "level": 4, "code": "20402", "name": "سایر پیش دریافت ها", "parentId": 2503, "accountType": 0},
            {"id": 2506, "level": 3, "code": "20101", "name": "مالیات بر ارزش افزوده فروش", "parentId": 2491, "accountType": 11},
            {"id": 2507, "level": 2, "code": "205", "name": "بدهیهای غیر جاری", "parentId": 2490, "accountType": 0},
            {"id": 2508, "level": 3, "code": "206", "name": "حساب ها و اسناد پرداختنی بلندمدت", "parentId": 2507, "accountType": 0},
            {"id": 2509, "level": 4, "code": "20601", "name": "حساب های پرداختنی بلندمدت", "parentId": 2508, "accountType": 0},
            {"id": 2510, "level": 4, "code": "20602", "name": "اسناد پرداختنی بلندمدت", "parentId": 2508, "accountType": 0},
            {"id": 2511, "level": 3, "code": "20501", "name": "وام پرداختنی", "parentId": 2507, "accountType": 0},
            {"id": 2512, "level": 3, "code": "20502", "name": "ذخیره مزایای پایان خدمت کارکنان", "parentId": 2507, "accountType": 0},
            {"id": 2513, "level": 1, "code": "3", "name": "حقوق صاحبان سهام", "parentId": 0, "accountType": 0},
            {"id": 2514, "level": 2, "code": "301", "name": "سرمایه", "parentId": 2513, "accountType": 0},
            {"id": 2515, "level": 3, "code": "30101", "name": "سرمایه اولیه", "parentId": 2514, "accountType": 13},
            {"id": 2516, "level": 3, "code": "30102", "name": "افزایش یا کاهش سرمایه", "parentId": 2514, "accountType": 14},
            {"id": 2517, "level": 3, "code": "30103", "name": "اندوخته قانونی", "parentId": 2514, "accountType": 15},
            {"id": 2518, "level": 3, "code": "30104", "name": "برداشت ها", "parentId": 2514, "accountType": 16},
            {"id": 2519, "level": 3, "code": "30105", "name": "سهم سود و زیان", "parentId": 2514, "accountType": 17},
            {"id": 2520, "level": 3, "code": "30106", "name": "سود یا زیان انباشته (سنواتی)", "parentId": 2514, "accountType": 18},
            {"id": 2521, "level": 1, "code": "4", "name": "بهای تمام شده کالای فروخته شده", "parentId": 0, "accountType": 0},
            {"id": 2522, "level": 2, "code": "40001", "name": "بهای تمام شده کالای فروخته شده", "parentId": 2521, "accountType": 19},
            {"id": 2523, "level": 2, "code": "40002", "name": "برگشت از خرید", "parentId": 2521, "accountType": 20},
            {"id": 2524, "level": 2, "code": "40003", "name": "تخفیفات نقدی خرید", "parentId": 2521, "accountType": 21},
            {"id": 2525, "level": 1, "code": "5", "name": "فروش", "parentId": 0, "accountType": 0},
            {"id": 2526, "level": 2, "code": "50001", "name": "فروش کالا", "parentId": 2525, "accountType": 22},
            {"id": 2527, "level": 2, "code": "50002", "name": "برگشت از فروش", "parentId": 2525, "accountType": 23},
            {"id": 2528, "level": 2, "code": "50003", "name": "تخفیفات نقدی فروش", "parentId": 2525, "accountType": 24},
            {"id": 2529, "level": 1, "code": "6", "name": "درآمد", "parentId": 0, "accountType": 0},
            {"id": 2530, "level": 2, "code": "601", "name": "درآمد های عملیاتی", "parentId": 2529, "accountType": 0},
            {"id": 2531, "level": 3, "code": "60101", "name": "درآمد حاصل از فروش خدمات", "parentId": 2530, "accountType": 25},
            {"id": 2532, "level": 3, "code": "60102", "name": "برگشت از خرید خدمات", "parentId": 2530, "accountType": 26},
            {"id": 2533, "level": 3, "code": "60103", "name": "درآمد اضافه کالا", "parentId": 2530, "accountType": 27},
            {"id": 2534, "level": 3, "code": "60104", "name": "درآمد حمل کالا", "parentId": 2530, "accountType": 28},
            {"id": 2535, "level": 2, "code": "602", "name": "درآمد های غیر عملیاتی", "parentId": 2529, "accountType": 0},
            {"id": 2536, "level": 3, "code": "60201", "name": "درآمد حاصل از سرمایه گذاری", "parentId": 2535, "accountType": 0},
            {"id": 2537, "level": 3, "code": "60202", "name": "درآمد سود سپرده ها", "parentId": 2535, "accountType": 0},
            {"id": 2538, "level": 3, "code": "60203", "name": "سایر درآمد ها", "parentId": 2535, "accountType": 0},
            {"id": 2539, "level": 3, "code": "60204", "name": "درآمد تسعیر ارز", "parentId": 2535, "accountType": 36},
            {"id": 2540, "level": 1, "code": "7", "name": "هزینه ها", "parentId": 0, "accountType": 0},
            {"id": 2541, "level": 2, "code": "701", "name": "هزینه های پرسنلی", "parentId": 2540, "accountType": 0},
            {"id": 2542, "level": 3, "code": "702", "name": "هزینه حقوق و دستمزد", "parentId": 2541, "accountType": 0},
            {"id": 2543, "level": 4, "code": "70201", "name": "حقوق پایه", "parentId": 2542, "accountType": 0},
            {"id": 2544, "level": 4, "code": "70202", "name": "اضافه کار", "parentId": 2542, "accountType": 0},
            {"id": 2545, "level": 4, "code": "70203", "name": "حق شیفت و شب کاری", "parentId": 2542, "accountType": 0},
            {"id": 2546, "level": 4, "code": "70204", "name": "حق نوبت کاری", "parentId": 2542, "accountType": 0},
            {"id": 2547, "level": 4, "code": "70205", "name": "حق ماموریت", "parentId": 2542, "accountType": 0},
            {"id": 2548, "level": 4, "code": "70206", "name": "فوق العاده مسکن و خاروبار", "parentId": 2542, "accountType": 0},
            {"id": 2549, "level": 4, "code": "70207", "name": "حق اولاد", "parentId": 2542, "accountType": 0},
            {"id": 2550, "level": 4, "code": "70208", "name": "عیدی و پاداش", "parentId": 2542, "accountType": 0},
            {"id": 2551, "level": 4, "code": "70209", "name": "بازخرید سنوات خدمت کارکنان", "parentId": 2542, "accountType": 0},
            {"id": 2552, "level": 4, "code": "70210", "name": "بازخرید مرخصی", "parentId": 2542, "accountType": 0},
            {"id": 2553, "level": 4, "code": "70211", "name": "بیمه سهم کارفرما", "parentId": 2542, "accountType": 0},
            {"id": 2554, "level": 4, "code": "70212", "name": "بیمه بیکاری", "parentId": 2542, "accountType": 0},
            {"id": 2555, "level": 4, "code": "70213", "name": "حقوق مزایای متفرقه", "parentId": 2542, "accountType": 0},
            {"id": 2556, "level": 3, "code": "703", "name": "سایر هزینه های کارکنان", "parentId": 2541, "accountType": 0},
            {"id": 2557, "level": 4, "code": "70301", "name": "سفر و ماموریت", "parentId": 2556, "accountType": 0},
            {"id": 2558, "level": 4, "code": "70302", "name": "ایاب و ذهاب", "parentId": 2556, "accountType": 0},
            {"id": 2559, "level": 4, "code": "70303", "name": "سایر هزینه های کارکنان", "parentId": 2556, "accountType": 0},
            {"id": 2560, "level": 2, "code": "704", "name": "هزینه های عملیاتی", "parentId": 2540, "accountType": 0},
            {"id": 2561, "level": 3, "code": "70401", "name": "خرید خدمات", "parentId": 2560, "accountType": 30},
            {"id": 2562, "level": 3, "code": "70402", "name": "برگشت از فروش خدمات", "parentId": 2560, "accountType": 29},
            {"id": 2563, "level": 3, "code": "70403", "name": "هزینه حمل کالا", "parentId": 2560, "accountType": 31},
            {"id": 2564, "level": 3, "code": "70404", "name": "تعمیر و نگهداری اموال و اثاثیه", "parentId": 2560, "accountType": 0},
            {"id": 2565, "level": 3, "code": "70405", "name": "هزینه اجاره محل", "parentId": 2560, "accountType": 0},
            {"id": 2566, "level": 3, "code": "705", "name": "هزینه های عمومی", "parentId": 2560, "accountType": 0},
            {"id": 2567, "level": 4, "code": "70501", "name": "هزینه آب و برق و گاز و تلفن", "parentId": 2566, "accountType": 0},
            {"id": 2568, "level": 4, "code": "70502", "name": "هزینه پذیرایی و آبدارخانه", "parentId": 2566, "accountType": 0},
            {"id": 2569, "level": 3, "code": "70406", "name": "هزینه ملزومات مصرفی", "parentId": 2560, "accountType": 0},
            {"id": 2570, "level": 3, "code": "70407", "name": "هزینه کسری و ضایعات کالا", "parentId": 2560, "accountType": 32},
            {"id": 2571, "level": 3, "code": "70408", "name": "بیمه دارایی های ثابت", "parentId": 2560, "accountType": 0},
            {"id": 2572, "level": 2, "code": "706", "name": "هزینه های استهلاک", "parentId": 2540, "accountType": 0},
            {"id": 2573, "level": 3, "code": "70601", "name": "هزینه استهلاک ساختمان", "parentId": 2572, "accountType": 0},
            {"id": 2574, "level": 3, "code": "70602", "name": "هزینه استهلاک وسائط نقلیه", "parentId": 2572, "accountType": 0},
            {"id": 2575, "level": 3, "code": "70603", "name": "هزینه استهلاک اثاثیه", "parentId": 2572, "accountType": 0},
            {"id": 2576, "level": 2, "code": "707", "name": "هزینه های بازاریابی و توزیع و فروش", "parentId": 2540, "accountType": 0},
            {"id": 2577, "level": 3, "code": "70701", "name": "هزینه آگهی و تبلیغات", "parentId": 2576, "accountType": 0},
            {"id": 2578, "level": 3, "code": "70702", "name": "هزینه بازاریابی و پورسانت", "parentId": 2576, "accountType": 0},
            {"id": 2579, "level": 3, "code": "70703", "name": "سایر هزینه های توزیع و فروش", "parentId": 2576, "accountType": 0},
            {"id": 2580, "level": 2, "code": "708", "name": "هزینه های غیرعملیاتی", "parentId": 2540, "accountType": 0},
            {"id": 2581, "level": 3, "code": "709", "name": "هزینه های بانکی", "parentId": 2580, "accountType": 0},
            {"id": 2582, "level": 4, "code": "70901", "name": "سود و کارمزد وامها", "parentId": 2581, "accountType": 0},
            {"id": 2583, "level": 4, "code": "70902", "name": "کارمزد خدمات بانکی", "parentId": 2581, "accountType": 33},
            {"id": 2584, "level": 4, "code": "70903", "name": "جرائم دیرکرد بانکی", "parentId": 2581, "accountType": 0},
            {"id": 2585, "level": 3, "code": "70801", "name": "هزینه تسعیر ارز", "parentId": 2580, "accountType": 37},
            {"id": 2586, "level": 3, "code": "70802", "name": "هزینه مطالبات سوخت شده", "parentId": 2580, "accountType": 0},
            {"id": 2587, "level": 1, "code": "8", "name": "سایر حساب ها", "parentId": 0, "accountType": 0},
            {"id": 2588, "level": 2, "code": "801", "name": "حساب های انتظامی", "parentId": 2587, "accountType": 0},
            {"id": 2589, "level": 3, "code": "80101", "name": "حساب های انتظامی", "parentId": 2588, "accountType": 0},
            {"id": 2590, "level": 3, "code": "80102", "name": "طرف حساب های انتظامی", "parentId": 2588, "accountType": 0},
            {"id": 2591, "level": 2, "code": "802", "name": "حساب های کنترلی", "parentId": 2587, "accountType": 0},
            {"id": 2592, "level": 3, "code": "80201", "name": "کنترل کسری و اضافه کالا", "parentId": 2591, "accountType": 34},
            {"id": 2593, "level": 2, "code": "803", "name": "حساب خلاصه سود و زیان", "parentId": 2587, "accountType": 0},
            {"id": 2594, "level": 3, "code": "80301", "name": "خلاصه سود و زیان", "parentId": 2593, "accountType": 35},
            {"id": 2595, "level": 5, "code": "70503", "name": "هزینه آب", "parentId": 2567, "accountType": 0},
            {"id": 2596, "level": 5, "code": "70504", "name": "هزینه برق", "parentId": 2567, "accountType": 0},
            {"id": 2597, "level": 5, "code": "70505", "name": "هزینه گاز", "parentId": 2567, "accountType": 0},
            {"id": 2598, "level": 5, "code": "70506", "name": "هزینه تلفن", "parentId": 2567, "accountType": 0},
            {"id": 2600, "level": 4, "code": "20503", "name": "وام از بانک ملت", "parentId": 2511, "accountType": 0},
            {"id": 2601, "level": 4, "code": "10405", "name": "سود تحقق نیافته فروش اقساطی", "parentId": 2463, "accountType": 39},
            {"id": 2602, "level": 3, "code": "60205", "name": "سود فروش اقساطی", "parentId": 2535, "accountType": 38},
            {"id": 2603, "level": 4, "code": "70214", "name": "حق تاهل", "parentId": 2542, "accountType": 0},
            {"id": 2604, "level": 4, "code": "20504", "name": "وام از بانک پارسیان", "parentId": 2511, "accountType": 0},
            {"id": 2605, "level": 3, "code": "10105", "name": "مساعده", "parentId": 2453, "accountType": 0},
            {"id": 2606, "level": 3, "code": "60105", "name": "تعمیرات لوازم آشپزخانه", "parentId": 2530, "accountType": 0},
            {"id": 2607, "level": 4, "code": "10705", "name": "کامپیوتر", "parentId": 2476, "accountType": 0},
            {"id": 2608, "level": 3, "code": "60206", "name": "درامد حاصل از فروش ضایعات", "parentId": 2535, "accountType": 0},
            {"id": 2609, "level": 3, "code": "60207", "name": "سود فروش دارایی", "parentId": 2535, "accountType": 0},
            {"id": 2610, "level": 3, "code": "70803", "name": "زیان فروش دارایی", "parentId": 2580, "accountType": 0},
            {"id": 2611, "level": 3, "code": "10106", "name": "موجودی کالای در جریان ساخت", "parentId": 2453, "accountType": 41},
            {"id": 2612, "level": 3, "code": "20102", "name": "سربار تولید پرداختنی", "parentId": 2491, "accountType": 43},
            {"id": 2613, "level": 4, "code": "70507", "name": "هزینه جدید", "parentId": 2566, "accountType": 0},
    ]

        # ۱) حذف حساب‌های عمومی موجود که در لیست جدید نیستند
    existing_codes = set(r[0] for r in conn.execute(sa.text("SELECT code FROM accounts WHERE business_id IS NULL")).fetchall())
    new_codes = {row["code"] for row in items}
    to_delete = tuple(sorted(existing_codes - new_codes))
    if to_delete:
            # حذف امن بر اساس کد و فقط عمومی
            del_sql = sa.text("DELETE FROM accounts WHERE business_id IS NULL AND code = :code")
            for c in to_delete:
            conn.execute(del_sql, {"code": c})

        # ۲) درج/به‌روزرسانی حساب‌ها به‌همراه نگاشت والدین
    ext_to_internal: dict[int, int] = {}
    select_existing = sa.text("SELECT id FROM accounts WHERE business_id IS NULL AND code = :code LIMIT 1")
    insert_q = sa.text(
            """
            INSERT INTO accounts (name, business_id, account_type, code, parent_id, created_at, updated_at)
            VALUES (:name, NULL, :account_type, :code, :parent_id, NOW(), NOW())
            """
    )
    update_q = sa.text(
            """
            UPDATE accounts
            SET name = :name, account_type = :account_type, parent_id = :parent_id, updated_at = NOW()
            WHERE id = :id
            """
    )

    for item in items:
            parent_internal = None
            if item.get("parentId") and item["parentId"] in ext_to_internal:
            parent_internal = ext_to_internal[item["parentId"]]

            res = conn.execute(select_existing, {"code": item["code"]})
            row = res.fetchone()
            if row is None:
            result = conn.execute(
            insert_q,
            {
            "name": item["name"],
            "account_type": str(item.get("accountType", 0)),
            "code": item["code"],
            "parent_id": parent_internal,
            },
            )
            new_id = result.lastrowid if hasattr(result, "lastrowid") else None
            if new_id is None:
                    # fallback: انتخاب مجدد بر اساس code
            res2 = conn.execute(select_existing, {"code": item["code"]})
            row2 = res2.fetchone()
            if row2:
            new_id = row2[0]
            if new_id is not None:
            ext_to_internal[item["id"]] = int(new_id)
            else:
            acc_id = int(row[0])
            conn.execute(
            update_q,
            {
            "id": acc_id,
            "name": item["name"],
            "account_type": str(item.get("accountType", 0)),
            "parent_id": parent_internal,
            },
            )
            ext_to_internal[item["id"]] = acc_id

    # From: 20251012_000101_update_accounts_account_type_to_english.py (revision: 20251012_000101_update_accounts_account_type_to_english)
    conn = op.get_bind()

    	# نگاشت مقادیر عددی/قدیمی به مقادیر انگلیسی جدید
    	mapping_updates: list[tuple[str, tuple[str, ...]]] = [
    		("bank", ("3",)),
    		("cash_register", ("1",)),
    		("petty_cash", ("2",)),
    		("check", ("5", "6", "10")),
    		("person", ("4", "9")),
    		("product", ("7",)),
    		("service", ("25", "26", "29", "30", "31")),
    	]

    	for new_val, old_vals in mapping_updates:
    		for old_val in old_vals:
    			conn.execute(
        sa.text(
        "UPDATE accounts SET account_type = :new_val WHERE account_type = :old_val"
        ),
        {"new_val": new_val, "old_val": old_val},
    			)

    	# سایر مقادیر ناشناخته را به accounting_document تنظیم کن
    	placeholders = ", ".join([":v" + str(i) for i in range(len(ALLOWED_TYPES))])
    	params = {("v" + str(i)): v for i, v in enumerate(ALLOWED_TYPES)}
    	conn.execute(
    		sa.text(
    			f"UPDATE accounts SET account_type = 'accounting_document' WHERE account_type NOT IN ({placeholders})"
    		),
    		params,
    	)

    	# افزودن چک‌کانسترینت برای اطمینان از مقادیر مجاز (در صورت نبود)
    	# برخی پایگاه‌ها CHECK را نادیده می‌گیرند؛ این بخش ایمن با try/except است
    	try:
    		op.create_check_constraint(
    			"ck_accounts_account_type_allowed",
    			"accounts",
    			"account_type IN ('bank', 'cash_register', 'petty_cash', 'check', 'person', 'product', 'service', 'accounting_document')",
    		)
    	except Exception:
    		# اگر از قبل وجود داشته باشد، نادیده بگیر

    # From: 20251014_000201_add_person_id_to_document_lines.py (revision: 20251014_000201_add_person_id_to_document_lines)
    with op.batch_alter_table('document_lines') as batch_op:
    		batch_op.add_column(sa.Column('person_id', sa.Integer(), nullable=True))
    		batch_op.create_foreign_key('fk_document_lines_person_id_persons', 'persons', ['person_id'], ['id'], ondelete='SET NULL')
    		batch_op.create_index('ix_document_lines_person_id', ['person_id'])

    # From: 20251014_000301_add_product_id_to_document_lines.py (revision: 20251014_000301_add_product_id_to_document_lines)
    with op.batch_alter_table('document_lines') as batch_op:
    		batch_op.add_column(sa.Column('product_id', sa.Integer(), nullable=True))
    		batch_op.create_foreign_key('fk_document_lines_product_id_products', 'products', ['product_id'], ['id'], ondelete='SET NULL')
    		batch_op.create_index('ix_document_lines_product_id', ['product_id'])

    # From: 20251014_000401_add_payment_refs_to_document_lines.py (revision: 20251014_000401_add_payment_refs_to_document_lines)
    bind = op.get_bind()
    	inspector = inspect(bind)
    	tables = set(inspector.get_table_names())
	
    	# Check if document_lines table exists
    	if 'document_lines' not in tables:
    		return
		
    	# Get existing columns
    	cols = {c['name'] for c in inspector.get_columns('document_lines')}
	
    	with op.batch_alter_table('document_lines') as batch_op:
    		# Only add columns if they don't exist
    		if 'bank_account_id' not in cols:
    			batch_op.add_column(sa.Column('bank_account_id', sa.Integer(), nullable=True))
    		if 'cash_register_id' not in cols:
    			batch_op.add_column(sa.Column('cash_register_id', sa.Integer(), nullable=True))
    		if 'petty_cash_id' not in cols:
    			batch_op.add_column(sa.Column('petty_cash_id', sa.Integer(), nullable=True))
    		if 'check_id' not in cols:
    			batch_op.add_column(sa.Column('check_id', sa.Integer(), nullable=True))

    		# Only create foreign keys if the referenced tables exist
    		if 'bank_accounts' in tables and 'bank_account_id' not in cols:
    			batch_op.create_foreign_key('fk_document_lines_bank_account_id_bank_accounts', 'bank_accounts', ['bank_account_id'], ['id'], ondelete='SET NULL')
    		if 'cash_registers' in tables and 'cash_register_id' not in cols:
    			batch_op.create_foreign_key('fk_document_lines_cash_register_id_cash_registers', 'cash_registers', ['cash_register_id'], ['id'], ondelete='SET NULL')
    		if 'petty_cash' in tables and 'petty_cash_id' not in cols:
    			batch_op.create_foreign_key('fk_document_lines_petty_cash_id_petty_cash', 'petty_cash', ['petty_cash_id'], ['id'], ondelete='SET NULL')
    		if 'checks' in tables and 'check_id' not in cols:
    			batch_op.create_foreign_key('fk_document_lines_check_id_checks', 'checks', ['check_id'], ['id'], ondelete='SET NULL')

    		# Only create indexes if columns were added
    		if 'bank_account_id' not in cols:
    			batch_op.create_index('ix_document_lines_bank_account_id', ['bank_account_id'])
    		if 'cash_register_id' not in cols:
    			batch_op.create_index('ix_document_lines_cash_register_id', ['cash_register_id'])
    		if 'petty_cash_id' not in cols:
    			batch_op.create_index('ix_document_lines_petty_cash_id', ['petty_cash_id'])
    		if 'check_id' not in cols:
    			batch_op.create_index('ix_document_lines_check_id', ['check_id'])

    # From: 20251014_000501_add_quantity_to_document_lines.py (revision: 20251014_000501_add_quantity_to_document_lines)
    with op.batch_alter_table('document_lines') as batch_op:
    		batch_op.add_column(sa.Column('quantity', sa.Numeric(18, 6), nullable=True, server_default=sa.text('0')))

    # From: 20251021_000601_add_bom_and_warehouses.py (revision: 20251021_000601_add_bom_and_warehouses)
    bind = op.get_bind()
    insp = sa.inspect(bind)

        # warehouses (ایجاد فقط اگر وجود ندارد)
    if not insp.has_table("warehouses"):
            op.create_table(
            "warehouses",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
            sa.Column("code", sa.String(length=64), nullable=False),
            sa.Column("name", sa.String(length=255), nullable=False),
            sa.Column("description", sa.Text(), nullable=True),
            sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.text("0")),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("business_id", "code", name="uq_warehouses_business_code"),
            )
            try:
            op.create_index("ix_warehouses_business_id", "warehouses", ["business_id"]) 
            op.create_index("ix_warehouses_code", "warehouses", ["code"]) 
            op.create_index("ix_warehouses_name", "warehouses", ["name"]) 
            op.create_index("ix_warehouses_is_default", "warehouses", ["is_default"]) 
            except Exception:
            
        # product_boms
    if not insp.has_table("product_boms"):
            op.create_table(
            "product_boms",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
            sa.Column("product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="CASCADE"), nullable=False),
            sa.Column("version", sa.String(length=64), nullable=False),
            sa.Column("name", sa.String(length=255), nullable=False),
            sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.text("0")),
            sa.Column("effective_from", sa.Date(), nullable=True),
            sa.Column("effective_to", sa.Date(), nullable=True),
            sa.Column("yield_percent", sa.Numeric(5, 2), nullable=True),
            sa.Column("wastage_percent", sa.Numeric(5, 2), nullable=True),
            sa.Column("status", sa.String(length=16), nullable=False, server_default=sa.text("'draft'")),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column("created_by", sa.Integer(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("business_id", "product_id", "version", name="uq_product_bom_version_per_product"),
            )
            try:
            op.create_index("ix_product_boms_business_id", "product_boms", ["business_id"]) 
            op.create_index("ix_product_boms_product_id", "product_boms", ["product_id"]) 
            op.create_index("ix_product_boms_is_default", "product_boms", ["is_default"]) 
            op.create_index("ix_product_boms_status", "product_boms", ["status"]) 
            except Exception:
            
        # product_bom_items
    if not insp.has_table("product_bom_items"):
            op.create_table(
            "product_bom_items",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("bom_id", sa.Integer(), sa.ForeignKey("product_boms.id", ondelete="CASCADE"), nullable=False),
            sa.Column("line_no", sa.Integer(), nullable=False),
            sa.Column("component_product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="RESTRICT"), nullable=False),
            sa.Column("qty_per", sa.Numeric(18, 6), nullable=False),
            sa.Column("uom", sa.String(length=32), nullable=True),
            sa.Column("wastage_percent", sa.Numeric(5, 2), nullable=True),
            sa.Column("is_optional", sa.Boolean(), nullable=False, server_default=sa.text("0")),
            sa.Column("substitute_group", sa.String(length=64), nullable=True),
            sa.Column("suggested_warehouse_id", sa.Integer(), sa.ForeignKey("warehouses.id", ondelete="SET NULL"), nullable=True),
            sa.UniqueConstraint("bom_id", "line_no", name="uq_bom_items_line"),
            )
            try:
            op.create_index("ix_product_bom_items_bom_id", "product_bom_items", ["bom_id"]) 
            op.create_index("ix_product_bom_items_component_product_id", "product_bom_items", ["component_product_id"]) 
            except Exception:
            
        # product_bom_outputs
    if not insp.has_table("product_bom_outputs"):
            op.create_table(
            "product_bom_outputs",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("bom_id", sa.Integer(), sa.ForeignKey("product_boms.id", ondelete="CASCADE"), nullable=False),
            sa.Column("line_no", sa.Integer(), nullable=False),
            sa.Column("output_product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="RESTRICT"), nullable=False),
            sa.Column("ratio", sa.Numeric(18, 6), nullable=False),
            sa.Column("uom", sa.String(length=32), nullable=True),
            sa.UniqueConstraint("bom_id", "line_no", name="uq_bom_outputs_line"),
            )
            try:
            op.create_index("ix_product_bom_outputs_bom_id", "product_bom_outputs", ["bom_id"]) 
            op.create_index("ix_product_bom_outputs_output_product_id", "product_bom_outputs", ["output_product_id"]) 
            except Exception:
            
        # product_bom_operations
    if not insp.has_table("product_bom_operations"):
            op.create_table(
            "product_bom_operations",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("bom_id", sa.Integer(), sa.ForeignKey("product_boms.id", ondelete="CASCADE"), nullable=False),
            sa.Column("line_no", sa.Integer(), nullable=False),
            sa.Column("operation_name", sa.String(length=255), nullable=False),
            sa.Column("cost_fixed", sa.Numeric(18, 2), nullable=True),
            sa.Column("cost_per_unit", sa.Numeric(18, 6), nullable=True),
            sa.Column("cost_uom", sa.String(length=32), nullable=True),
            sa.Column("work_center", sa.String(length=128), nullable=True),
            sa.UniqueConstraint("bom_id", "line_no", name="uq_bom_operations_line"),
            )
            try:
            op.create_index("ix_product_bom_operations_bom_id", "product_bom_operations", ["bom_id"]) 
            except Exception:

    # From: 20251108_231201_add_system_settings.py (revision: 20251108_231201_add_system_settings)
    bind = op.get_bind()
    	inspector = sa.inspect(bind)

    	# 1) Create table if not exists
    	if 'system_settings' not in inspector.get_table_names():
    		op.create_table(
    			'system_settings',
    			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
    			sa.Column('key', sa.String(length=100), nullable=False, index=True),
    			sa.Column('value_string', sa.String(length=255), nullable=True),
    			sa.Column('value_int', sa.Integer(), nullable=True),
    			sa.Column('value_json', sa.Text(), nullable=True),
    			sa.Column('created_at', sa.DateTime(), nullable=False),
    			sa.Column('updated_at', sa.DateTime(), nullable=False),
    			sa.UniqueConstraint('key', name='uq_system_settings_key'),
    		)
    		try:
    			op.create_index('ix_system_settings_key', 'system_settings', ['key'])
    		except Exception:
			
    	# 2) Seed default wallet base currency code to IRR if not set
    	# prefer code instead of id to avoid id dependency
    	try:
    		conn = op.get_bind()
    		# check if exists
    		exists = conn.execute(sa.text("SELECT 1 FROM system_settings WHERE `key` = :k LIMIT 1"), {"k": "wallet_base_currency_code"}).fetchone()
    		if not exists:
    			conn.execute(
        sa.text(
        """
        INSERT INTO system_settings (`key`, value_string, created_at, updated_at)
        VALUES (:k, :v, NOW(), NOW())
        """
        ),
        {"k": "wallet_base_currency_code", "v": "IRR"},
    			)
    	except Exception:
    		# non-fatal

    # From: 20251108_232101_add_wallet_tables.py (revision: 20251108_232101_add_wallet_tables)
    bind = op.get_bind()
    	inspector = sa.inspect(bind)
    	tables = inspector.get_table_names()

    	if 'wallet_accounts' not in tables:
    		op.create_table(
    			'wallet_accounts',
    			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
    			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
    			sa.Column('available_balance', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
    			sa.Column('pending_balance', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
    			sa.Column('status', sa.String(length=20), nullable=False, server_default='active'),
    			sa.Column('created_at', sa.DateTime(), nullable=False),
    			sa.Column('updated_at', sa.DateTime(), nullable=False),
    			sa.UniqueConstraint('business_id', name='uq_wallet_accounts_business'),
    		)
    		try:
    			op.create_index('ix_wallet_accounts_business_id', 'wallet_accounts', ['business_id'])
    		except Exception:
			
    	if 'wallet_transactions' not in tables:
    		op.create_table(
    			'wallet_transactions',
    			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
    			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
    			sa.Column('type', sa.String(length=50), nullable=False),
    			sa.Column('status', sa.String(length=20), nullable=False, server_default='pending'),
    			sa.Column('amount', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
    			sa.Column('fee_amount', sa.Numeric(18, 2), nullable=True),
    			sa.Column('description', sa.String(length=500), nullable=True),
    			sa.Column('external_ref', sa.String(length=100), nullable=True),
    			sa.Column('document_id', sa.Integer(), sa.ForeignKey('documents.id', ondelete='SET NULL'), nullable=True),
    			sa.Column('extra_info', sa.Text(), nullable=True),
    			sa.Column('created_at', sa.DateTime(), nullable=False),
    			sa.Column('updated_at', sa.DateTime(), nullable=False),
    		)
    		try:
    			op.create_index('ix_wallet_tx_business_id', 'wallet_transactions', ['business_id'])
    			op.create_index('ix_wallet_tx_document_id', 'wallet_transactions', ['document_id'])
    			op.create_index('ix_wallet_tx_type', 'wallet_transactions', ['type'])
    			op.create_index('ix_wallet_tx_status', 'wallet_transactions', ['status'])
    		except Exception:
			
    	if 'wallet_payouts' not in tables:
    		op.create_table(
    			'wallet_payouts',
    			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
    			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
    			sa.Column('bank_account_id', sa.Integer(), sa.ForeignKey('bank_accounts.id', ondelete='RESTRICT'), nullable=False),
    			sa.Column('gross_amount', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
    			sa.Column('fees', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
    			sa.Column('net_amount', sa.Numeric(18, 2), nullable=False, server_default=sa.text('0')),
    			sa.Column('status', sa.String(length=20), nullable=False, server_default='requested'),
    			sa.Column('schedule_type', sa.String(length=20), nullable=False, server_default='manual'),
    			sa.Column('external_ref', sa.String(length=100), nullable=True),
    			sa.Column('extra_info', sa.Text(), nullable=True),
    			sa.Column('created_at', sa.DateTime(), nullable=False),
    			sa.Column('updated_at', sa.DateTime(), nullable=False),
    		)
    		try:
    			op.create_index('ix_wallet_payouts_business_id', 'wallet_payouts', ['business_id'])
    			op.create_index('ix_wallet_payouts_bank_account_id', 'wallet_payouts', ['bank_account_id'])
    			op.create_index('ix_wallet_payouts_status', 'wallet_payouts', ['status'])
    		except Exception:
			
    	if 'wallet_settings' not in tables:
    		op.create_table(
    			'wallet_settings',
    			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
    			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
    			sa.Column('mode', sa.String(length=20), nullable=False, server_default='manual'),
    			sa.Column('frequency', sa.String(length=20), nullable=True),
    			sa.Column('threshold_amount', sa.Numeric(18, 2), nullable=True),
    			sa.Column('min_reserve', sa.Numeric(18, 2), nullable=True),
    			sa.Column('default_bank_account_id', sa.Integer(), sa.ForeignKey('bank_accounts.id', ondelete='SET NULL'), nullable=True),
    			sa.Column('created_at', sa.DateTime(), nullable=False),
    			sa.Column('updated_at', sa.DateTime(), nullable=False),
    			sa.UniqueConstraint('business_id', name='uq_wallet_settings_business'),
    		)
    		try:
    			op.create_index('ix_wallet_settings_business_id', 'wallet_settings', ['business_id'])
    		except Exception:

    # From: 20251109_120001_add_payment_gateways.py (revision: 20251109_120001_add_payment_gateways)
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

    # From: 20251109_150001_add_announcements_tables.py (revision: 20251109_150001_add_announcements_tables)
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = set(inspector.get_table_names())

    if 'announcements' not in existing_tables:
            op.create_table(
            'announcements',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('title', sa.String(length=200), nullable=False),
            sa.Column('body', sa.Text(), nullable=False),
            sa.Column('level', sa.String(length=16), nullable=False, server_default='info'),
            sa.Column('is_pinned', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('starts_at', sa.DateTime(), nullable=True),
            sa.Column('ends_at', sa.DateTime(), nullable=True),
            sa.Column('audience_filters', sa.JSON(), nullable=True),
            sa.Column('created_by', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
            )
            op.create_index('ix_ann_title', 'announcements', ['title'])
            op.create_index('ix_ann_level', 'announcements', ['level'])
            op.create_index('ix_ann_is_pinned', 'announcements', ['is_pinned'])
            op.create_index('ix_ann_is_active', 'announcements', ['is_active'])
            op.create_index('ix_ann_starts_at', 'announcements', ['starts_at'])
            op.create_index('ix_ann_ends_at', 'announcements', ['ends_at'])
            op.create_index('ix_ann_active_schedule', 'announcements', ['is_active', 'starts_at', 'ends_at'])
            op.create_index('ix_ann_pinned_updated', 'announcements', ['is_pinned', 'updated_at'])

    if 'user_announcements' not in existing_tables:
            op.create_table(
            'user_announcements',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
            sa.Column('announcement_id', sa.Integer(), sa.ForeignKey('announcements.id', ondelete='CASCADE'), nullable=False),
            sa.Column('first_seen_at', sa.DateTime(), nullable=True),
            sa.Column('read_at', sa.DateTime(), nullable=True),
            sa.Column('dismissed_at', sa.DateTime(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
            )
            op.create_index('ix_user_ann_user_id', 'user_announcements', ['user_id'])
            op.create_index('ix_user_ann_announcement_id', 'user_announcements', ['announcement_id'])
            op.create_unique_constraint('uq_user_announcement', 'user_announcements', ['user_id', 'announcement_id'])

    # From: 20251110_090001_add_notifications_and_telegram.py (revision: 20251110_090001_add_notifications_and_telegram)
    # users: telegram fields
    op.add_column('users', sa.Column('telegram_chat_id', sa.Integer(), nullable=True))
    op.add_column('users', sa.Column('telegram_connected_at', sa.DateTime(), nullable=True))
    op.create_index(op.f('ix_users_telegram_chat_id'), 'users', ['telegram_chat_id'], unique=False)

        # telegram_link_tokens
    op.create_table(
            'telegram_link_tokens',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('token', sa.String(length=128), nullable=False),
            sa.Column('expires_at', sa.DateTime(), nullable=False),
            sa.Column('used_at', sa.DateTime(), nullable=True),
            sa.Column('created_ip', sa.String(length=64), nullable=True),
            sa.Column('user_agent', sa.String(length=255), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('token'),
    )
    op.create_index(op.f('ix_telegram_link_tokens_user_id'), 'telegram_link_tokens', ['user_id'], unique=False)
    op.create_index(op.f('ix_telegram_link_tokens_token'), 'telegram_link_tokens', ['token'], unique=True)
    op.create_index('ix_telegram_link_validity', 'telegram_link_tokens', ['expires_at', 'used_at'], unique=False)

        # notification_outbox
    op.create_table(
            'notification_outbox',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('channel', sa.String(length=32), nullable=False),
            sa.Column('event_key', sa.String(length=100), nullable=False),
            sa.Column('payload', sa.JSON(), nullable=False),
            sa.Column('locale', sa.String(length=10), nullable=True),
            sa.Column('status', sa.String(length=16), nullable=False, server_default='pending'),
            sa.Column('error_message', sa.Text(), nullable=True),
            sa.Column('retry_count', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('next_attempt_at', sa.DateTime(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_notification_outbox_user_id'), 'notification_outbox', ['user_id'], unique=False)
    op.create_index(op.f('ix_notification_outbox_channel'), 'notification_outbox', ['channel'], unique=False)
    op.create_index(op.f('ix_notification_outbox_event_key'), 'notification_outbox', ['event_key'], unique=False)
    op.create_index(op.f('ix_notification_outbox_status'), 'notification_outbox', ['status'], unique=False)
    op.create_index(op.f('ix_notification_outbox_next_attempt_at'), 'notification_outbox', ['next_attempt_at'], unique=False)
    op.create_index('ix_outbox_pending_next', 'notification_outbox', ['status', 'next_attempt_at'], unique=False)

        # notification_delivery_attempts
    op.create_table(
            'notification_delivery_attempts',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('outbox_id', sa.Integer(), nullable=False),
            sa.Column('channel', sa.String(length=32), nullable=False),
            sa.Column('success', sa.Boolean(), nullable=False),
            sa.Column('error_message', sa.Text(), nullable=True),
            sa.Column('performed_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['outbox_id'], ['notification_outbox.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_notification_delivery_attempts_outbox_id'), 'notification_delivery_attempts', ['outbox_id'], unique=False)
    op.create_index(op.f('ix_notification_delivery_attempts_channel'), 'notification_delivery_attempts', ['channel'], unique=False)
    op.create_index(op.f('ix_notification_delivery_attempts_success'), 'notification_delivery_attempts', ['success'], unique=False)
    op.create_index(op.f('ix_notification_delivery_attempts_performed_at'), 'notification_delivery_attempts', ['performed_at'], unique=False)

    # From: 20251110_100001_add_notification_templates_and_settings.py (revision: 20251110_100001_add_notification_templates_and_settings)
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = set(inspector.get_table_names())

    if 'notification_templates' not in existing_tables:
            op.create_table(
            'notification_templates',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('event_key', sa.String(length=100), nullable=False),
            sa.Column('channel', sa.String(length=32), nullable=False),
            sa.Column('locale', sa.String(length=10), nullable=True),
            sa.Column('subject', sa.String(length=200), nullable=True),
            sa.Column('body', sa.Text(), nullable=False),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('event_key', 'channel', 'locale', name='uq_template_key_channel_locale')
            )
            op.create_index(op.f('ix_notification_templates_event_key'), 'notification_templates', ['event_key'], unique=False)
            op.create_index(op.f('ix_notification_templates_channel'), 'notification_templates', ['channel'], unique=False)
            op.create_index(op.f('ix_notification_templates_locale'), 'notification_templates', ['locale'], unique=False)
            op.create_index(op.f('ix_notification_templates_is_active'), 'notification_templates', ['is_active'], unique=False)

    if 'user_notification_settings' not in existing_tables:
            op.create_table(
            'user_notification_settings',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('channel', sa.String(length=32), nullable=False),
            sa.Column('event_key', sa.String(length=100), nullable=True),
            sa.Column('enabled', sa.Boolean(), nullable=False, server_default=sa.text('1')),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('user_id', 'channel', 'event_key', name='uq_user_channel_event')
            )
            op.create_index(op.f('ix_user_notification_settings_user_id'), 'user_notification_settings', ['user_id'], unique=False)
            op.create_index(op.f('ix_user_notification_settings_channel'), 'user_notification_settings', ['channel'], unique=False)
            op.create_index(op.f('ix_user_notification_settings_event_key'), 'user_notification_settings', ['event_key'], unique=False)
            op.create_index(op.f('ix_user_notification_settings_enabled'), 'user_notification_settings', ['enabled'], unique=False)
            op.create_index('ix_user_settings_user_channel', 'user_notification_settings', ['user_id', 'channel'], unique=False)

    # From: 20251112_170001_add_credit_fields.py (revision: 20251112_170001_add_credit_fields)
    bind = op.get_bind()
    	inspector = sa.inspect(bind)

    	# persons: credit_limit, credit_check_enabled
    	if not _has_column(inspector, 'persons', 'credit_limit'):
    		try:
    			op.add_column('persons', sa.Column('credit_limit', sa.Numeric(14, 2), nullable=True, comment="سقف اعتبار شخص"))
    		except Exception:
			
    	if not _has_column(inspector, 'persons', 'credit_check_enabled'):
    		try:
    			op.add_column('persons', sa.Column('credit_check_enabled', sa.Boolean(), nullable=True, comment="فعال بودن بررسی اعتبار برای شخص (خالی: تبعیت از تنظیمات کسب‌وکار)"))
    		except Exception:
			
    	# businesses: default_credit_limit, check_credit_enabled_by_default
    	if not _has_column(inspector, 'businesses', 'default_credit_limit'):
    		try:
    			op.add_column('businesses', sa.Column('default_credit_limit', sa.Numeric(14, 2), nullable=True, comment="سقف اعتبار پیشفرض اشخاص"))
    		except Exception:
			
    	if not _has_column(inspector, 'businesses', 'check_credit_enabled_by_default'):
    		try:
    			op.add_column('businesses', sa.Column('check_credit_enabled_by_default', sa.Boolean(), nullable=False, server_default="0", comment="بررسی اعتبار مشتریان به صورت پیشفرض"))
    		except Exception:

    # From: 20251112_200001_add_credit_settings_and_installment_templates.py (revision: 20251112_200001_add_credit_settings_and_installment_templates)
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

    # From: 20251117_050152_add_image_file_id_to_products.py (revision: 20251117_050152)
    connection = op.get_bind()
    
        # بررسی وجود ستون
    result = connection.execute(sa.text("""
            SELECT COUNT(*) 
            FROM information_schema.columns 
            WHERE table_schema = DATABASE() 
            AND table_name = 'products' 
            AND column_name = 'image_file_id'
    """)).scalar()
    
        # اگر ستون وجود ندارد، اضافه می‌کنیم
    if result == 0:
            op.add_column(
            'products',
            sa.Column('image_file_id', sa.String(length=36), nullable=True)
            )
        
            # تغییر charset و collation برای سازگاری با file_storage.id
            connection.execute(sa.text("""
            ALTER TABLE products 
            MODIFY COLUMN image_file_id VARCHAR(36) 
            CHARACTER SET utf8mb4 
            COLLATE utf8mb4_general_ci 
            NULL
            """))
    else:
            # اگر ستون وجود دارد، فقط charset و collation را تغییر می‌دهیم
            connection.execute(sa.text("""
            ALTER TABLE products 
            MODIFY COLUMN image_file_id VARCHAR(36) 
            CHARACTER SET utf8mb4 
            COLLATE utf8mb4_general_ci 
            NULL
            """))
    
        # بررسی وجود Foreign Key
    fk_result = connection.execute(sa.text("""
            SELECT COUNT(*) 
            FROM information_schema.table_constraints 
            WHERE table_schema = DATABASE() 
            AND table_name = 'products' 
            AND constraint_name = 'fk_products_image_file_id'
    """)).scalar()
    
        # اگر Foreign Key وجود ندارد، اضافه می‌کنیم
    if fk_result == 0:
            op.create_foreign_key(
            'fk_products_image_file_id',
            'products',
            'file_storage',
            ['image_file_id'],
            ['id'],
            ondelete='SET NULL'
            )
    
        # بررسی وجود Index
    index_result = connection.execute(sa.text("""
            SELECT COUNT(*) 
            FROM information_schema.statistics 
            WHERE table_schema = DATABASE() 
            AND table_name = 'products' 
            AND index_name = 'ix_products_image_file_id'
    """)).scalar()
    
        # اگر Index وجود ندارد، اضافه می‌کنیم
    if index_result == 0:
            op.create_index(
            'ix_products_image_file_id',
            'products',
            ['image_file_id']
            )

    # From: 20251118_000001_add_document_monetization.py (revision: 20251118_000001_add_document_monetization)
    op.create_table(
    		"document_subscription_plans",
    		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
    		sa.Column("name", sa.String(length=200), nullable=False),
    		sa.Column("code", sa.String(length=100), nullable=False),
    		sa.Column("description", sa.Text(), nullable=True),
    		sa.Column("period_months", sa.Integer(), nullable=False),
    		sa.Column("price", sa.Numeric(18, 2), nullable=False, server_default="0"),
    		sa.Column("currency_id", sa.Integer(), sa.ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False),
    		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("1")),
    		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    		sa.UniqueConstraint("code", name="uq_document_subscription_plans_code"),
    	)
    	op.create_index("ix_document_subscription_plans_code", "document_subscription_plans", ["code"], unique=False)

    	op.create_table(
    		"business_document_subscriptions",
    		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
    		sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
    		sa.Column("plan_id", sa.Integer(), sa.ForeignKey("document_subscription_plans.id", ondelete="RESTRICT"), nullable=False),
    		sa.Column("status", sa.String(length=20), nullable=False, server_default="active"),
    		sa.Column("starts_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    		sa.Column("ends_at", sa.DateTime(), nullable=False),
    		sa.Column("auto_renew", sa.Boolean(), nullable=False, server_default=sa.text("0")),
    		sa.Column("created_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
    		sa.Column("extra_data", sa.JSON(), nullable=True),
    		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    	)
    	op.create_index("ix_business_document_subscriptions_business_id", "business_document_subscriptions", ["business_id"])
    	op.create_index("ix_business_document_subscriptions_plan_id", "business_document_subscriptions", ["plan_id"])

    	op.create_table(
    		"document_usage_policies",
    		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
    		sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
    		sa.Column("policy_type", sa.String(length=30), nullable=False),
    		sa.Column("title", sa.String(length=200), nullable=False),
    		sa.Column("priority", sa.Integer(), nullable=False, server_default="100"),
    		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("1")),
    		sa.Column("config", sa.JSON(), nullable=True),
    		sa.Column("starts_at", sa.DateTime(), nullable=True),
    		sa.Column("ends_at", sa.DateTime(), nullable=True),
    		sa.Column("created_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
    		sa.Column("updated_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
    		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    	)
    	op.create_index("ix_document_usage_policies_business_id", "document_usage_policies", ["business_id"])

    	op.create_table(
    		"document_usage_charges",
    		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
    		sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
    		sa.Column("policy_id", sa.Integer(), sa.ForeignKey("document_usage_policies.id", ondelete="SET NULL"), nullable=True),
    		sa.Column("document_id", sa.Integer(), sa.ForeignKey("documents.id", ondelete="SET NULL"), nullable=True),
    		sa.Column("charge_type", sa.String(length=30), nullable=False),
    		sa.Column("status", sa.String(length=20), nullable=False, server_default="pending"),
    		sa.Column("amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
    		sa.Column("currency_id", sa.Integer(), sa.ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False),
    		sa.Column("wallet_transaction_id", sa.Integer(), sa.ForeignKey("wallet_transactions.id", ondelete="SET NULL"), nullable=True),
    		sa.Column("description", sa.String(length=500), nullable=True),
    		sa.Column("metrics", sa.JSON(), nullable=True),
    		sa.Column("period_key", sa.String(length=50), nullable=True),
    		sa.Column("period_start", sa.DateTime(), nullable=True),
    		sa.Column("period_end", sa.DateTime(), nullable=True),
    		sa.Column("issued_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
    		sa.Column("paid_at", sa.DateTime(), nullable=True),
    		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    	)
    	op.create_index("ix_document_usage_charges_business_id", "document_usage_charges", ["business_id"])
    	op.create_index("ix_document_usage_charges_document_id", "document_usage_charges", ["document_id"])
    	op.create_index("ix_document_usage_charges_policy_id", "document_usage_charges", ["policy_id"])
    	op.create_index("ix_document_usage_charges_period_key", "document_usage_charges", ["period_key"])

    	op.create_table(
    		"document_usage_periods",
    		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
    		sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
    		sa.Column("policy_id", sa.Integer(), sa.ForeignKey("document_usage_policies.id", ondelete="CASCADE"), nullable=False),
    		sa.Column("period_key", sa.String(length=50), nullable=False),
    		sa.Column("cycle", sa.String(length=20), nullable=False),
    		sa.Column("period_start", sa.DateTime(), nullable=False),
    		sa.Column("period_end", sa.DateTime(), nullable=False),
    		sa.Column("documents_count", sa.Integer(), nullable=False, server_default="0"),
    		sa.Column("total_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
    		sa.Column("status", sa.String(length=20), nullable=False, server_default="open"),
    		sa.Column("charge_id", sa.Integer(), sa.ForeignKey("document_usage_charges.id", ondelete="SET NULL"), nullable=True),
    		sa.Column("extra_data", sa.JSON(), nullable=True),
    		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    		sa.UniqueConstraint("policy_id", "period_key", name="uq_document_usage_period_policy_key"),
    	)
    	op.create_index("ix_document_usage_periods_business_id", "document_usage_periods", ["business_id"])

    	op.create_table(
    		"document_usage_cursors",
    		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
    		sa.Column("scope", sa.String(length=20), nullable=False, server_default="global"),
    		sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=True),
    		sa.Column("last_document_id", sa.Integer(), nullable=True),
    		sa.Column("last_document_created_at", sa.DateTime(), nullable=True),
    		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    		sa.UniqueConstraint("scope", "business_id", name="uq_document_usage_cursor_scope_business"),
    	)
    	op.create_index("ix_document_usage_cursors_business_id", "document_usage_cursors", ["business_id"])

    # From: 20251119_000001_add_person_share_links.py (revision: 20251119_000001_add_person_share_links)
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    table_name = "person_share_links"

    if table_name not in inspector.get_table_names():
            op.create_table(
            table_name,
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column(
            "business_id",
            sa.Integer(),
            sa.ForeignKey("businesses.id", ondelete="CASCADE"),
            nullable=False,
            ),
            sa.Column(
            "person_id",
            sa.Integer(),
            sa.ForeignKey("persons.id", ondelete="CASCADE"),
            nullable=False,
            ),
            sa.Column(
            "created_by_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
            ),
            sa.Column(
            "revoked_by_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
            ),
            sa.Column("code", sa.String(length=16), nullable=False, unique=True),
            sa.Column("token_hash", sa.String(length=128), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("expires_at", sa.DateTime(), nullable=True),
            sa.Column("revoked_at", sa.DateTime(), nullable=True),
            sa.Column("last_view_at", sa.DateTime(), nullable=True),
            sa.Column("view_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
            sa.Column("max_view_count", sa.Integer(), nullable=True),
            sa.Column("options", sa.JSON(), nullable=True),
            sa.Column("meta", sa.JSON(), nullable=True),
            sa.UniqueConstraint("code", name="uq_person_share_links_code"),
            )
            op.create_index(
            "ix_person_share_links_code", table_name, ["code"], unique=False
            )
            op.create_index(
            "ix_person_share_links_person_id", table_name, ["person_id"], unique=False
            )
            op.create_index(
            "ix_person_share_links_business_id", table_name, ["business_id"], unique=False
            )
    else:
            existing_indexes = {
            idx["name"] for idx in inspector.get_indexes(table_name)
            }
            if "ix_person_share_links_code" not in existing_indexes:
            op.create_index(
            "ix_person_share_links_code", table_name, ["code"], unique=False
            )
            if "ix_person_share_links_person_id" not in existing_indexes:
            op.create_index(
            "ix_person_share_links_person_id", table_name, ["person_id"], unique=False
            )
            if "ix_person_share_links_business_id" not in existing_indexes:
            op.create_index(
            "ix_person_share_links_business_id",
            table_name,
            ["business_id"],
            unique=False,
            )

    # From: 20251120_000001_add_default_warehouse_to_products.py (revision: 20251120_000001_add_default_warehouse_to_products)
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    table_name = "products"

    if table_name in inspector.get_table_names():
            columns = {col["name"] for col in inspector.get_columns(table_name)}
            indexes = {idx["name"] for idx in inspector.get_indexes(table_name)}
            if "default_warehouse_id" not in columns:
            op.add_column(
            table_name,
            sa.Column(
            "default_warehouse_id",
            sa.Integer(),
            sa.ForeignKey("warehouses.id", ondelete="SET NULL"),
            nullable=True,
            comment="انبار پیش‌فرض برای کالا",
            ),
            )
            if "ix_products_default_warehouse_id" not in indexes:
            op.create_index(
            "ix_products_default_warehouse_id",
            table_name,
            ["default_warehouse_id"],
            unique=False,
            )

    # From: 20251120_053716_add_ai_tables.py (revision: 20251120_053716_add_ai_tables)
    # AI Configs
    op.create_table(
            'ai_configs',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('provider', mysql.ENUM('openai', 'anthropic', 'local', 'custom', name='aiprovider'), nullable=False),
            sa.Column('model_name', sa.String(length=100), nullable=False),
            sa.Column('api_base_url', sa.String(length=500), nullable=True),
            sa.Column('api_key', sa.Text(), nullable=True),
            sa.Column('max_tokens', sa.Integer(), nullable=False),
            sa.Column('temperature', sa.Numeric(precision=3, scale=2), nullable=False),
            sa.Column('is_active', sa.Boolean(), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ai_configs_id'), 'ai_configs', ['id'], unique=False)

        # AI Plans
    op.create_table(
            'ai_plans',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('code', sa.String(length=50), nullable=False),
            sa.Column('name', sa.String(length=255), nullable=False),
            sa.Column('description', sa.Text(), nullable=True),
            sa.Column('plan_type', mysql.ENUM('free', 'subscription', 'pay_as_go', 'hybrid', name='aiplantype'), nullable=False),
            sa.Column('pricing_config', sa.Text(), nullable=True),
            sa.Column('usage_limits', sa.Text(), nullable=True),
            sa.Column('features', sa.Text(), nullable=True),
            sa.Column('is_active', sa.Boolean(), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('code', name='uq_ai_plans_code')
    )
    op.create_index(op.f('ix_ai_plans_code'), 'ai_plans', ['code'], unique=True)

        # User AI Subscriptions
    op.create_table(
            'user_ai_subscriptions',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('business_id', sa.Integer(), nullable=True),
            sa.Column('plan_id', sa.Integer(), nullable=False),
            sa.Column('subscription_type', mysql.ENUM('free', 'subscription', 'pay_as_go', name='subscriptiontype'), nullable=False),
            sa.Column('tokens_used', sa.Integer(), nullable=False),
            sa.Column('tokens_limit', sa.Integer(), nullable=True),
            sa.Column('period_start', sa.DateTime(), nullable=False),
            sa.Column('period_end', sa.DateTime(), nullable=True),
            sa.Column('is_active', sa.Boolean(), nullable=False),
            sa.Column('auto_renew', sa.Boolean(), nullable=False),
            sa.Column('wallet_balance_required', sa.Numeric(precision=18, scale=2), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
            sa.ForeignKeyConstraint(['plan_id'], ['ai_plans.id'], ondelete='RESTRICT'),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_user_ai_subscriptions_business_id'), 'user_ai_subscriptions', ['business_id'], unique=False)
    op.create_index(op.f('ix_user_ai_subscriptions_plan_id'), 'user_ai_subscriptions', ['plan_id'], unique=False)
    op.create_index(op.f('ix_user_ai_subscriptions_user_id'), 'user_ai_subscriptions', ['user_id'], unique=False)

        # AI Invoices
    op.create_table(
            'ai_invoices',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('subscription_id', sa.Integer(), nullable=True),
            sa.Column('business_id', sa.Integer(), nullable=False),
            sa.Column('plan_id', sa.Integer(), nullable=True),
            sa.Column('invoice_type', mysql.ENUM('subscription', 'usage', 'renewal', name='aiinvoicetype'), nullable=False),
            sa.Column('code', sa.String(length=50), nullable=False),
            sa.Column('total', sa.Numeric(precision=18, scale=2), nullable=False),
            sa.Column('currency_id', sa.Integer(), nullable=False),
            sa.Column('status', mysql.ENUM('issued', 'paid', 'canceled', name='aiinvoicestatus'), nullable=False),
            sa.Column('issued_at', sa.DateTime(), nullable=False),
            sa.Column('paid_at', sa.DateTime(), nullable=True),
            sa.Column('wallet_transaction_id', sa.Integer(), nullable=True),
            sa.Column('document_id', sa.Integer(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
            sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
            sa.ForeignKeyConstraint(['document_id'], ['documents.id'], ondelete='SET NULL'),
            sa.ForeignKeyConstraint(['plan_id'], ['ai_plans.id'], ondelete='SET NULL'),
            sa.ForeignKeyConstraint(['subscription_id'], ['user_ai_subscriptions.id'], ondelete='SET NULL'),
            sa.ForeignKeyConstraint(['wallet_transaction_id'], ['wallet_transactions.id'], ondelete='SET NULL'),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('code', name='uq_ai_invoices_code')
    )
    op.create_index(op.f('ix_ai_invoices_business_id'), 'ai_invoices', ['business_id'], unique=False)
    op.create_index(op.f('ix_ai_invoices_code'), 'ai_invoices', ['code'], unique=True)
    op.create_index(op.f('ix_ai_invoices_plan_id'), 'ai_invoices', ['plan_id'], unique=False)
    op.create_index(op.f('ix_ai_invoices_subscription_id'), 'ai_invoices', ['subscription_id'], unique=False)
    op.create_index(op.f('ix_ai_invoices_wallet_transaction_id'), 'ai_invoices', ['wallet_transaction_id'], unique=False)

        # AI Usage Logs
    op.create_table(
            'ai_usage_logs',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('business_id', sa.Integer(), nullable=True),
            sa.Column('subscription_id', sa.Integer(), nullable=True),
            sa.Column('invoice_id', sa.Integer(), nullable=True),
            sa.Column('provider', sa.String(length=50), nullable=False),
            sa.Column('model', sa.String(length=100), nullable=False),
            sa.Column('input_tokens', sa.Integer(), nullable=False),
            sa.Column('output_tokens', sa.Integer(), nullable=False),
            sa.Column('cost', sa.Numeric(precision=18, scale=2), nullable=False),
            sa.Column('payment_method', mysql.ENUM('free', 'subscription', 'wallet', name='paymentmethod'), nullable=False),
            sa.Column('wallet_transaction_id', sa.Integer(), nullable=True),
            sa.Column('document_id', sa.Integer(), nullable=True),
            sa.Column('context', sa.Text(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
            sa.ForeignKeyConstraint(['document_id'], ['documents.id'], ondelete='SET NULL'),
            sa.ForeignKeyConstraint(['invoice_id'], ['ai_invoices.id'], ondelete='SET NULL'),
            sa.ForeignKeyConstraint(['subscription_id'], ['user_ai_subscriptions.id'], ondelete='SET NULL'),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.ForeignKeyConstraint(['wallet_transaction_id'], ['wallet_transactions.id'], ondelete='SET NULL'),
            sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ai_usage_logs_business_id'), 'ai_usage_logs', ['business_id'], unique=False)
    op.create_index(op.f('ix_ai_usage_logs_created_at'), 'ai_usage_logs', ['created_at'], unique=False)
    op.create_index(op.f('ix_ai_usage_logs_invoice_id'), 'ai_usage_logs', ['invoice_id'], unique=False)
    op.create_index(op.f('ix_ai_usage_logs_subscription_id'), 'ai_usage_logs', ['subscription_id'], unique=False)
    op.create_index(op.f('ix_ai_usage_logs_user_id'), 'ai_usage_logs', ['user_id'], unique=False)

        # AI Chat Sessions
    op.create_table(
            'ai_chat_sessions',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('business_id', sa.Integer(), nullable=True),
            sa.Column('title', sa.String(length=255), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ai_chat_sessions_business_id'), 'ai_chat_sessions', ['business_id'], unique=False)
    op.create_index(op.f('ix_ai_chat_sessions_user_id'), 'ai_chat_sessions', ['user_id'], unique=False)

        # AI Chat Messages
    op.create_table(
            'ai_chat_messages',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('session_id', sa.Integer(), nullable=False),
            sa.Column('role', mysql.ENUM('user', 'assistant', 'system', 'function', name='messagerole'), nullable=False),
            sa.Column('content', sa.Text(), nullable=False),
            sa.Column('function_calls', sa.Text(), nullable=True),
            sa.Column('function_results', sa.Text(), nullable=True),
            sa.Column('tokens_used', sa.Integer(), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['session_id'], ['ai_chat_sessions.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ai_chat_messages_created_at'), 'ai_chat_messages', ['created_at'], unique=False)
    op.create_index(op.f('ix_ai_chat_messages_session_id'), 'ai_chat_messages', ['session_id'], unique=False)

        # AI Prompts
    op.create_table(
            'ai_prompts',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('role', mysql.ENUM('operator', 'user', 'admin', name='promptrole'), nullable=False),
            sa.Column('prompt_type', mysql.ENUM('system', 'user', name='prompttype'), nullable=False),
            sa.Column('title', sa.String(length=255), nullable=False),
            sa.Column('content', sa.Text(), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=True),
            sa.Column('is_default', sa.Boolean(), nullable=False),
            sa.Column('is_active', sa.Boolean(), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ai_prompts_role'), 'ai_prompts', ['role'], unique=False)
    op.create_index(op.f('ix_ai_prompts_user_id'), 'ai_prompts', ['user_id'], unique=False)

    # From: 20251124_000001_seed_tax_types_list.py (revision: 20251124_000001_seed_tax_types_list)
    conn = op.get_bind()
    conn.execute(sa.text("DELETE FROM tax_types"))

    insert_stmt = sa.text(
            """
            INSERT INTO tax_types (id, title, code, description, created_at, updated_at)
            VALUES (:id, :title, :code, :description, NOW(), NOW())
            """
    )
    for tax_id, title, code in LEGACY_TAX_TYPES:
            conn.execute(
            insert_stmt,
            {
            "id": tax_id,
            "title": title,
            "code": code,
            "description": None,
            },
            )

    # From: 20251124_200000_fix_telegram_chat_id_bigint.py (revision: 20251124_200000)
    # تغییر نوع ستون telegram_chat_id از Integer به BigInteger
        # چون chat_id تلگرام می‌تواند بزرگ‌تر از INT max (2147483647) باشد
    op.alter_column(
            'users',
            'telegram_chat_id',
            existing_type=sa.Integer(),
            type_=sa.BigInteger(),
            existing_nullable=True,
            existing_server_default=None
    )

    # From: 20251124_200001_add_email_verification.py (revision: 20251124_200001)
    # اضافه کردن فیلد email_verified به جدول users (اگر وجود نداشته باشد)
    from sqlalchemy import inspect
    conn = op.get_bind()
    inspector = inspect(conn)
    columns = [col['name'] for col in inspector.get_columns('users')]
    
    if 'email_verified' not in columns:
            op.add_column('users', sa.Column('email_verified', sa.Boolean(), nullable=False, server_default='0'))
    
        # ایجاد ایندکس (اگر وجود نداشته باشد)
    indexes = [idx['name'] for idx in inspector.get_indexes('users')]
    if 'ix_users_email_verified' not in indexes:
            op.create_index(op.f('ix_users_email_verified'), 'users', ['email_verified'], unique=False)
    
        # ایجاد جدول email_verification_tokens (اگر وجود نداشته باشد)
    tables = inspector.get_table_names()
    if 'email_verification_tokens' not in tables:
            op.create_table('email_verification_tokens',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('email', sa.String(length=255), nullable=False),
            sa.Column('token_hash', sa.String(length=128), nullable=False),
            sa.Column('expires_at', sa.DateTime(), nullable=False),
            sa.Column('used_at', sa.DateTime(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('token_hash')
            )
            # ایجاد ایندکس‌ها (اگر وجود نداشته باشند)
            existing_indexes = [idx['name'] for idx in inspector.get_indexes('email_verification_tokens')] if 'email_verification_tokens' in tables else []
            if 'ix_email_verification_tokens_user_id' not in existing_indexes:
            op.create_index(op.f('ix_email_verification_tokens_user_id'), 'email_verification_tokens', ['user_id'], unique=False)
            if 'ix_email_verification_tokens_email' not in existing_indexes:
            op.create_index(op.f('ix_email_verification_tokens_email'), 'email_verification_tokens', ['email'], unique=False)
            if 'ix_email_verification_tokens_token_hash' not in existing_indexes:
            op.create_index(op.f('ix_email_verification_tokens_token_hash'), 'email_verification_tokens', ['token_hash'], unique=True)

    # From: 20251126_170943_add_mobile_verification.py (revision: 20251126_170943)
    from sqlalchemy import inspect
    conn = op.get_bind()
    inspector = inspect(conn)
    
        # اضافه کردن فیلد mobile_verified به جدول users
    columns = [col['name'] for col in inspector.get_columns('users')]
    if 'mobile_verified' not in columns:
            op.add_column('users', sa.Column('mobile_verified', sa.Boolean(), nullable=False, server_default='0'))
    
        # ایجاد ایندکس برای mobile_verified (اختیاری)
    indexes = [idx['name'] for idx in inspector.get_indexes('users')]
    if 'ix_users_mobile_verified' not in indexes:
            op.create_index(op.f('ix_users_mobile_verified'), 'users', ['mobile_verified'], unique=False)
    
        # ایجاد جدول mobile_verification_tokens
    tables = inspector.get_table_names()
    if 'mobile_verification_tokens' not in tables:
            op.create_table('mobile_verification_tokens',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('mobile', sa.String(length=32), nullable=False),
            sa.Column('otp_code_hash', sa.String(length=128), nullable=False),
            sa.Column('expires_at', sa.DateTime(), nullable=False),
            sa.Column('verified_at', sa.DateTime(), nullable=True),
            sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
            )
            # ایجاد ایندکس‌ها
            op.create_index(op.f('ix_mobile_verification_tokens_user_id'), 'mobile_verification_tokens', ['user_id'], unique=False)
            op.create_index(op.f('ix_mobile_verification_tokens_mobile'), 'mobile_verification_tokens', ['mobile'], unique=False)
            op.create_index(op.f('ix_mobile_verification_tokens_otp_code_hash'), 'mobile_verification_tokens', ['otp_code_hash'], unique=False)
            op.create_index(op.f('ix_mobile_verification_tokens_expires_at'), 'mobile_verification_tokens', ['expires_at'], unique=False)
            op.create_index('ix_mobile_verification_validity', 'mobile_verification_tokens', ['expires_at', 'verified_at'], unique=False)

    # From: 20251126_171000_add_otp_login_sessions.py (revision: 20251126_171000)
    from sqlalchemy import inspect
    conn = op.get_bind()
    inspector = inspect(conn)
    
        # ایجاد جدول otp_login_sessions
    tables = inspector.get_table_names()
    if 'otp_login_sessions' not in tables:
            op.create_table('otp_login_sessions',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('session_id', sa.String(length=128), nullable=False),
            sa.Column('mobile', sa.String(length=32), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=True),
            sa.Column('otp_code_hash', sa.String(length=128), nullable=False),
            sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('expires_at', sa.DateTime(), nullable=False),
            sa.Column('verified_at', sa.DateTime(), nullable=True),
            sa.Column('ip_address', sa.String(length=64), nullable=True),
            sa.Column('user_agent', sa.String(length=255), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
            )
            # ایجاد ایندکس‌ها
            op.create_index(op.f('ix_otp_login_sessions_session_id'), 'otp_login_sessions', ['session_id'], unique=True)
            op.create_index(op.f('ix_otp_login_sessions_mobile'), 'otp_login_sessions', ['mobile'], unique=False)
            op.create_index(op.f('ix_otp_login_sessions_user_id'), 'otp_login_sessions', ['user_id'], unique=False)
            op.create_index(op.f('ix_otp_login_sessions_expires_at'), 'otp_login_sessions', ['expires_at'], unique=False)
            op.create_index('ix_otp_login_validity', 'otp_login_sessions', ['expires_at', 'verified_at'], unique=False)

    # From: 20251201_000001_add_activity_logs_table.py (revision: 20251201_000001_add_activity_logs_table)
    # Create activity_logs table
    	op.create_table(
    		'activity_logs',
    		sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    		sa.Column('user_id', sa.Integer(), nullable=True),
    		sa.Column('business_id', sa.Integer(), nullable=True),
    		sa.Column('category', sa.String(length=50), nullable=False),
    		sa.Column('action', sa.String(length=50), nullable=False),
    		sa.Column('entity_type', sa.String(length=50), nullable=True),
    		sa.Column('entity_id', sa.Integer(), nullable=True),
    		sa.Column('description', sa.Text(), nullable=False),
    		sa.Column('before_data', sa.JSON(), nullable=True),
    		sa.Column('after_data', sa.JSON(), nullable=True),
    		sa.Column('extra_info', sa.JSON(), nullable=True),
    		sa.Column('created_at', sa.DateTime(), nullable=False),
    		sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='SET NULL'),
    		sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
    		sa.PrimaryKeyConstraint('id'),
    		mysql_charset='utf8mb4'
    	)
	
    	# Indexes
    	op.create_index('ix_activity_logs_user_id', 'activity_logs', ['user_id'])
    	op.create_index('ix_activity_logs_business_id', 'activity_logs', ['business_id'])
    	op.create_index('ix_activity_logs_category', 'activity_logs', ['category'])
    	op.create_index('ix_activity_logs_action', 'activity_logs', ['action'])
    	op.create_index('ix_activity_logs_entity_type', 'activity_logs', ['entity_type'])
    	op.create_index('ix_activity_logs_entity_id', 'activity_logs', ['entity_id'])
    	op.create_index('ix_activity_logs_created_at', 'activity_logs', ['created_at'])
	
    	# Composite indexes for common queries
    	op.create_index('ix_activity_logs_business_category_action', 'activity_logs', ['business_id', 'category', 'action'])
    	op.create_index('ix_activity_logs_business_entity', 'activity_logs', ['business_id', 'entity_type', 'entity_id'])
    	op.create_index('ix_activity_logs_user_created', 'activity_logs', ['user_id', 'created_at'])
    	op.create_index('ix_activity_logs_business_created', 'activity_logs', ['business_id', 'created_at'])

    # From: 20251202_000001_add_email_channel_to_otp_login.py (revision: 20251202_000001)
    # تغییر mobile به nullable و اضافه کردن email
    op.alter_column('otp_login_sessions', 'mobile',
            existing_type=sa.String(length=32),
            nullable=True)
    
        # اضافه کردن فیلد email
    op.add_column('otp_login_sessions', sa.Column('email', sa.String(length=255), nullable=True))
    op.create_index(op.f('ix_otp_login_sessions_email'), 'otp_login_sessions', ['email'], unique=False)
    
        # اضافه کردن فیلد channel
    op.add_column('otp_login_sessions', sa.Column('channel', sa.String(length=20), nullable=False, server_default='sms'))
    
        # اضافه کردن فیلد last_otp_sent_at برای rate limiting
    op.add_column('otp_login_sessions', sa.Column('last_otp_sent_at', sa.DateTime(), nullable=True))

    # From: 5553f8745c6e_add_support_tables.py (revision: 5553f8745c6e)
    # ### commands auto generated by Alembic - please adjust! ###
    bind = op.get_bind()
    inspector = inspect(bind)
    tables = set(inspector.get_table_names())
    
        # Only create tables if they don't exist
    if 'support_categories' not in tables:
            op.create_table('support_categories',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('name', sa.String(length=100), nullable=False),
            sa.Column('description', sa.Text(), nullable=True),
            sa.Column('is_active', sa.Boolean(), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id')
            )
            op.create_index(op.f('ix_support_categories_name'), 'support_categories', ['name'], unique=False)
    
    if 'support_priorities' not in tables:
            op.create_table('support_priorities',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('name', sa.String(length=50), nullable=False),
            sa.Column('description', sa.Text(), nullable=True),
            sa.Column('color', sa.String(length=7), nullable=True),
            sa.Column('order', sa.Integer(), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id')
            )
            op.create_index(op.f('ix_support_priorities_name'), 'support_priorities', ['name'], unique=False)
    
    if 'support_statuses' not in tables:
            op.create_table('support_statuses',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('name', sa.String(length=50), nullable=False),
            sa.Column('description', sa.Text(), nullable=True),
            sa.Column('color', sa.String(length=7), nullable=True),
            sa.Column('is_final', sa.Boolean(), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id')
            )
            op.create_index(op.f('ix_support_statuses_name'), 'support_statuses', ['name'], unique=False)
    
    if 'support_tickets' not in tables:
            op.create_table('support_tickets',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('title', sa.String(length=255), nullable=False),
            sa.Column('description', sa.Text(), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('category_id', sa.Integer(), nullable=False),
            sa.Column('priority_id', sa.Integer(), nullable=False),
            sa.Column('status_id', sa.Integer(), nullable=False),
            sa.Column('assigned_operator_id', sa.Integer(), nullable=True),
            sa.Column('is_internal', sa.Boolean(), nullable=False),
            sa.Column('closed_at', sa.DateTime(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['assigned_operator_id'], ['users.id'], ondelete='SET NULL'),
            sa.ForeignKeyConstraint(['category_id'], ['support_categories.id'], ondelete='RESTRICT'),
            sa.ForeignKeyConstraint(['priority_id'], ['support_priorities.id'], ondelete='RESTRICT'),
            sa.ForeignKeyConstraint(['status_id'], ['support_statuses.id'], ondelete='RESTRICT'),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
            )
            op.create_index(op.f('ix_support_tickets_assigned_operator_id'), 'support_tickets', ['assigned_operator_id'], unique=False)
            op.create_index(op.f('ix_support_tickets_category_id'), 'support_tickets', ['category_id'], unique=False)
            op.create_index(op.f('ix_support_tickets_priority_id'), 'support_tickets', ['priority_id'], unique=False)
            op.create_index(op.f('ix_support_tickets_status_id'), 'support_tickets', ['status_id'], unique=False)
            op.create_index(op.f('ix_support_tickets_title'), 'support_tickets', ['title'], unique=False)
            op.create_index(op.f('ix_support_tickets_user_id'), 'support_tickets', ['user_id'], unique=False)
    
    if 'support_messages' not in tables:
            op.create_table('support_messages',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('ticket_id', sa.Integer(), nullable=False),
            sa.Column('sender_id', sa.Integer(), nullable=False),
            sa.Column('sender_type', sa.Enum('USER', 'OPERATOR', 'SYSTEM', name='sendertype'), nullable=False),
            sa.Column('content', sa.Text(), nullable=False),
            sa.Column('is_internal', sa.Boolean(), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['sender_id'], ['users.id'], ondelete='CASCADE'),
            sa.ForeignKeyConstraint(['ticket_id'], ['support_tickets.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
            )
            op.create_index(op.f('ix_support_messages_sender_id'), 'support_messages', ['sender_id'], unique=False)
            op.create_index(op.f('ix_support_messages_sender_type'), 'support_messages', ['sender_type'], unique=False)
            op.create_index(op.f('ix_support_messages_ticket_id'), 'support_messages', ['ticket_id'], unique=False)
    
        # Only alter columns if businesses table exists
    if 'businesses' in tables:
            op.alter_column('businesses', 'business_type',
            existing_type=mysql.ENUM('شرکت', 'مغازه', 'فروشگاه', 'اتحادیه', 'باشگاه', 'موسسه', 'شخصی', collation='utf8mb4_general_ci'),
            type_=sa.Enum('COMPANY', 'SHOP', 'STORE', 'UNION', 'CLUB', 'INSTITUTE', 'INDIVIDUAL', name='businesstype'),
            existing_nullable=False)
            op.alter_column('businesses', 'business_field',
            existing_type=mysql.ENUM('تولیدی', 'بازرگانی', 'خدماتی', 'سایر', collation='utf8mb4_general_ci'),
            type_=sa.Enum('MANUFACTURING', 'TRADING', 'SERVICE', 'OTHER', name='businessfield'),
            existing_nullable=False)
        # ### end Alembic commands ###

    # From: 755d6bd2d6d7_add_business_logo_stamp_columns.py (revision: 755d6bd2d6d7)
    # افزودن ستون‌های لوگو و مهر به جدول businesses (با چک کردن وجود قبلی)
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_columns = [col['name'] for col in inspector.get_columns('businesses')]

    if 'logo_file_id' not in existing_columns:
            op.add_column(
            'businesses',
            sa.Column('logo_file_id', sa.String(length=36), nullable=True),
            )
    if 'stamp_file_id' not in existing_columns:
            op.add_column(
            'businesses',
            sa.Column('stamp_file_id', sa.String(length=36), nullable=True),
            )

    # From: 9a06b0cb880a_add_description_to_documents.py (revision: 9a06b0cb880a)
    # افزودن ستون فقط اگر قبلاً وجود ندارد
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    cols = [c['name'] for c in inspector.get_columns('documents')]
    if 'description' not in cols:
            op.add_column('documents', sa.Column('description', sa.Text(), nullable=True))

    # From: 9f9786ae7191_create_tax_units_table.py (revision: 9f9786ae7191)
    bind = op.get_bind()
    inspector = inspect(bind)

    created_tax_units = False
    if not inspector.has_table('tax_units'):
            op.create_table(
            'tax_units',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('business_id', sa.Integer(), nullable=False, comment='شناسه کسب\u200cوکار'),
            sa.Column('name', sa.String(length=255), nullable=False, comment='نام واحد مالیاتی'),
            sa.Column('code', sa.String(length=64), nullable=False, comment='کد واحد مالیاتی'),
            sa.Column('description', sa.Text(), nullable=True, comment='توضیحات'),
            sa.Column('tax_rate', sa.Numeric(precision=5, scale=2), nullable=True, comment='نرخ مالیات (درصد)'),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1'), comment='وضعیت فعال/غیرفعال'),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
            mysql_charset='utf8mb4'
            )
            created_tax_units = True

    if created_tax_units:
            # Create indexes
            op.create_index(op.f('ix_tax_units_business_id'), 'tax_units', ['business_id'], unique=False)

            # Add foreign key constraint to products table
            op.create_foreign_key(None, 'products', 'tax_units', ['tax_unit_id'], ['id'], ondelete='SET NULL')

    # From: ac9e4b3dcffc_add_fiscal_year_to_documents.py (revision: ac9e4b3dcffc)
    # ### commands auto generated by Alembic - please adjust! ###
        # Add fiscal_year_id column if it doesn't exist
    try:
            op.add_column('documents', sa.Column('fiscal_year_id', sa.Integer(), nullable=True))
    except Exception:
            # Column might already exist, continue
        
        # Create index and foreign key for fiscal_year_id
    op.create_index(op.f('ix_documents_fiscal_year_id'), 'documents', ['fiscal_year_id'], unique=False)
    op.create_foreign_key(None, 'documents', 'fiscal_years', ['fiscal_year_id'], ['id'], ondelete='RESTRICT')
        # ### end Alembic commands ###

    # From: b2b68cf299a3_convert_unit_fields_to_string.py (revision: b2b68cf299a3)
    # Check if columns already exist before adding them
    try:
            op.add_column('products', sa.Column('main_unit', sa.String(length=32), nullable=True, comment='واحد اصلی شمارش'))
    except Exception:
            pass  # Column already exists
    
    try:
            op.add_column('products', sa.Column('secondary_unit', sa.String(length=32), nullable=True, comment='واحد فرعی شمارش'))
    except Exception:
            pass  # Column already exists
    
        # Create indexes for new columns (if they don't exist)
    try:
            op.create_index('ix_products_main_unit', 'products', ['main_unit'])
    except Exception:
            pass  # Index already exists
    
    try:
            op.create_index('ix_products_secondary_unit', 'products', ['secondary_unit'])
    except Exception:
            pass  # Index already exists
    
        # Drop old integer columns and their indexes (if they exist)
    try:
            op.drop_index('ix_products_main_unit_id', table_name='products')
    except Exception:
            pass  # Index doesn't exist
    
    try:
            op.drop_index('ix_products_secondary_unit_id', table_name='products')
    except Exception:
            pass  # Index doesn't exist
    
    try:
            op.drop_column('products', 'main_unit_id')
    except Exception:
            pass  # Column doesn't exist
    
    try:
            op.drop_column('products', 'secondary_unit_id')
    except Exception:
            pass  # Column doesn't exist

    # From: c302bc2f2cb8_remove_person_type_column.py (revision: c302bc2f2cb8)
    # Check if column exists before dropping
    connection = op.get_bind()
    result = connection.execute(sa.text("""
            SELECT COUNT(*) 
            FROM information_schema.columns 
            WHERE table_schema = DATABASE() 
            AND table_name = 'persons' 
            AND column_name = 'person_type'
    """)).fetchone()
    
    if result[0] > 0:
            op.drop_column('persons', 'person_type')

    # From: caf3f4ef4b76_add_tax_units_table.py (revision: caf3f4ef4b76)
    # ### commands auto generated by Alembic - please adjust! ###
    bind = op.get_bind()
    inspector = inspect(bind)
    
        # Check if persons table exists and has the code column
    if 'persons' in inspector.get_table_names():
            cols = {c['name'] for c in inspector.get_columns('persons')}
        
            # Only alter code column if it exists
            if 'code' in cols:
            op.alter_column('persons', 'code',
            existing_type=mysql.INTEGER(),
            comment='کد یکتا در هر کسب و کار',
            existing_nullable=True)
        
            # Only alter person_type column if it exists
            if 'person_type' in cols:
            op.alter_column('persons', 'person_type',
            existing_type=mysql.ENUM('مشتری', 'بازاریاب', 'کارمند', 'تامین\u200cکننده', 'همکار', 'فروشنده', 'سهامدار', collation='utf8mb4_general_ci'),
            comment='نوع شخص',
            existing_nullable=False)
        
            # Only alter person_types column if it exists
            if 'person_types' in cols:
            op.alter_column('persons', 'person_types',
            existing_type=mysql.TEXT(collation='utf8mb4_general_ci'),
            comment='لیست انواع شخص به صورت JSON',
            existing_nullable=True)
        
            # Only alter commission columns if they exist
            if 'commission_sale_percent' in cols:
            op.alter_column('persons', 'commission_sale_percent',
            existing_type=mysql.DECIMAL(precision=5, scale=2),
            comment='درصد پورسانت از فروش',
            existing_nullable=True)
        
            if 'commission_sales_return_percent' in cols:
            op.alter_column('persons', 'commission_sales_return_percent',
            existing_type=mysql.DECIMAL(precision=5, scale=2),
            comment='درصد پورسانت از برگشت از فروش',
            existing_nullable=True)
        
            if 'commission_sales_amount' in cols:
            op.alter_column('persons', 'commission_sales_amount',
            existing_type=mysql.DECIMAL(precision=12, scale=2),
            comment='مبلغ فروش مبنا برای پورسانت',
            existing_nullable=True)
        
            if 'commission_sales_return_amount' in cols:
            op.alter_column('persons', 'commission_sales_return_amount',
            existing_type=mysql.DECIMAL(precision=12, scale=2),
            comment='مبلغ برگشت از فروش مبنا برای پورسانت',
            existing_nullable=True)
        
            if 'commission_exclude_discounts' in cols:
            op.alter_column('persons', 'commission_exclude_discounts',
            existing_type=mysql.TINYINT(display_width=1),
            comment='عدم محاسبه تخفیف در پورسانت',
            existing_nullable=False,
            existing_server_default=sa.text("'0'"))
        
            if 'commission_exclude_additions_deductions' in cols:
            op.alter_column('persons', 'commission_exclude_additions_deductions',
            existing_type=mysql.TINYINT(display_width=1),
            comment='عدم محاسبه اضافات و کسورات فاکتور در پورسانت',
            existing_nullable=False,
            existing_server_default=sa.text("'0'"))
        
            if 'commission_post_in_invoice_document' in cols:
            op.alter_column('persons', 'commission_post_in_invoice_document',
            existing_type=mysql.TINYINT(display_width=1),
            comment='ثبت پورسانت در سند حسابداری فاکتور',
            existing_nullable=False,
            existing_server_default=sa.text("'0'"))
    
        # Continue with other operations
    op.alter_column('price_items', 'tier_name',
            existing_type=mysql.VARCHAR(length=64),
            comment='نام پله قیمت (تکی/عمده/همکار/...)',
            existing_nullable=False)
    op.create_index(op.f('ix_price_items_currency_id'), 'price_items', ['currency_id'], unique=False)
    op.create_index(op.f('ix_price_items_unit_id'), 'price_items', ['unit_id'], unique=False)
    op.create_index(op.f('ix_price_lists_currency_id'), 'price_lists', ['currency_id'], unique=False)
    op.create_index(op.f('ix_price_lists_default_unit_id'), 'price_lists', ['default_unit_id'], unique=False)
    op.create_index(op.f('ix_price_lists_name'), 'price_lists', ['name'], unique=False)
    op.alter_column('products', 'item_type',
            existing_type=mysql.ENUM('کالا', 'خدمت'),
            comment='نوع آیتم (کالا/خدمت)',
            existing_nullable=False)
    op.alter_column('products', 'code',
            existing_type=mysql.VARCHAR(length=64),
            comment='کد یکتا در هر کسب\u200cوکار',
            existing_nullable=False)
    op.create_index(op.f('ix_products_category_id'), 'products', ['category_id'], unique=False)
    op.create_index(op.f('ix_products_main_unit_id'), 'products', ['main_unit_id'], unique=False)
    op.create_index(op.f('ix_products_secondary_unit_id'), 'products', ['secondary_unit_id'], unique=False)
    op.create_index(op.f('ix_products_tax_type_id'), 'products', ['tax_type_id'], unique=False)
    op.create_index(op.f('ix_products_tax_unit_id'), 'products', ['tax_unit_id'], unique=False)
        # ### end Alembic commands ###

    # From: d3e84892c1c2_sync_person_type_enum_values_callable_.py (revision: d3e84892c1c2)
    # ### commands auto generated by Alembic - guarded for idempotency ###
    bind = op.get_bind()
    inspector = inspect(bind)
    existing_tables = set(inspector.get_table_names())

    if 'storage_configs' not in existing_tables:
            op.create_table('storage_configs',
            sa.Column('id', sa.String(length=36), nullable=False),
            sa.Column('name', sa.String(length=100), nullable=False),
            sa.Column('storage_type', sa.String(length=20), nullable=False),
            sa.Column('is_default', sa.Boolean(), nullable=False),
            sa.Column('is_active', sa.Boolean(), nullable=False),
            sa.Column('config_data', sa.JSON(), nullable=False),
            sa.Column('created_by', sa.Integer(), nullable=False),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
            sa.ForeignKeyConstraint(['created_by'], ['users.id'], ),
            sa.PrimaryKeyConstraint('id')
            )

    if 'file_storage' not in existing_tables:
            op.create_table('file_storage',
            sa.Column('id', sa.String(length=36), nullable=False),
            sa.Column('original_name', sa.String(length=255), nullable=False),
            sa.Column('stored_name', sa.String(length=255), nullable=False),
            sa.Column('file_path', sa.String(length=500), nullable=False),
            sa.Column('file_size', sa.Integer(), nullable=False),
            sa.Column('mime_type', sa.String(length=100), nullable=False),
            sa.Column('storage_type', sa.String(length=20), nullable=False),
            sa.Column('storage_config_id', sa.String(length=36), nullable=True),
            sa.Column('uploaded_by', sa.Integer(), nullable=False),
            sa.Column('module_context', sa.String(length=50), nullable=False),
            sa.Column('context_id', sa.String(length=36), nullable=True),
            sa.Column('developer_data', sa.JSON(), nullable=True),
            sa.Column('checksum', sa.String(length=64), nullable=True),
            sa.Column('is_active', sa.Boolean(), nullable=False),
            sa.Column('is_temporary', sa.Boolean(), nullable=False),
            sa.Column('is_verified', sa.Boolean(), nullable=False),
            sa.Column('verification_token', sa.String(length=100), nullable=True),
            sa.Column('last_verified_at', sa.DateTime(timezone=True), nullable=True),
            sa.Column('expires_at', sa.DateTime(timezone=True), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
            sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
            sa.ForeignKeyConstraint(['storage_config_id'], ['storage_configs.id'], ),
            sa.ForeignKeyConstraint(['uploaded_by'], ['users.id'], ),
            sa.PrimaryKeyConstraint('id')
            )

    if 'file_verifications' not in existing_tables:
            op.create_table('file_verifications',
            sa.Column('id', sa.String(length=36), nullable=False),
            sa.Column('file_id', sa.String(length=36), nullable=False),
            sa.Column('module_name', sa.String(length=50), nullable=False),
            sa.Column('verification_token', sa.String(length=100), nullable=False),
            sa.Column('verified_at', sa.DateTime(timezone=True), nullable=True),
            sa.Column('verified_by', sa.Integer(), nullable=True),
            sa.Column('verification_data', sa.JSON(), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
            sa.ForeignKeyConstraint(['file_id'], ['file_storage.id'], ),
            sa.ForeignKeyConstraint(['verified_by'], ['users.id'], ),
            sa.PrimaryKeyConstraint('id')
            )
        # Drop index if exists
    try:
            bind = op.get_bind()
            insp = inspect(bind)
            if 'fiscal_years' in insp.get_table_names():
            existing_indexes = {idx['name'] for idx in insp.get_indexes('fiscal_years')}
            if 'ix_fiscal_years_title' in existing_indexes:
            op.drop_index(op.f('ix_fiscal_years_title'), table_name='fiscal_years')
    except Exception:
        
    conn = op.get_bind()
    if _table_exists(conn, 'person_bank_accounts') and _column_exists(conn, 'person_bank_accounts', 'person_id'):
            op.alter_column('person_bank_accounts', 'person_id',
            existing_type=mysql.INTEGER(),
            comment=None,
            existing_comment='شناسه شخص',
            existing_nullable=False)

    if _table_exists(conn, 'persons'):
            if _column_exists(conn, 'persons', 'business_id'):
            op.alter_column('persons', 'business_id',
            existing_type=mysql.INTEGER(),
            comment=None,
            existing_comment='شناسه کسب و کار',
            existing_nullable=False)
            if _column_exists(conn, 'persons', 'code'):
            op.alter_column('persons', 'code',
            existing_type=mysql.INTEGER(),
            comment='کد یکتا در هر کسب و کار',
            existing_nullable=True)
            if _column_exists(conn, 'persons', 'person_types'):
            op.alter_column('persons', 'person_types',
            existing_type=mysql.TEXT(collation='utf8mb4_general_ci'),
            comment='لیست انواع شخص به صورت JSON',
            existing_nullable=True)
            if _column_exists(conn, 'persons', 'share_count'):
            op.alter_column('persons', 'share_count',
            existing_type=mysql.INTEGER(),
            comment='تعداد سهام (فقط برای سهامدار)',
            existing_nullable=True)
        # ### end Alembic commands ###


def downgrade() -> None:
    # برای downgrade باید تمام جداول را به ترتیب معکوس حذف کنیم
    # این کار پیچیده است و بهتر است از backup استفاده شود
    pass
