"""جداول checks, check_reconciliations, check_reconciliation_items"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


def upgrade():
    # ایجاد enum types برای checks
    op.execute("CREATE TYPE check_type_enum AS ENUM ('RECEIVED', 'TRANSFERRED')")
    op.execute("CREATE TYPE check_status_enum AS ENUM ('RECEIVED_ON_HAND', 'TRANSFERRED_ISSUED', 'DEPOSITED', 'CLEARED', 'ENDORSED', 'RETURNED', 'BOUNCED', 'CANCELLED')")
    op.execute("CREATE TYPE check_holder_type_enum AS ENUM ('BUSINESS', 'BANK', 'PERSON')")

    # جدول checks
    op.create_table(
        'checks',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('type', mysql.ENUM('RECEIVED', 'TRANSFERRED', name='check_type'), nullable=False),
        sa.Column('person_id', sa.Integer(), nullable=True),
        sa.Column('issue_date', sa.DateTime(), nullable=False),
        sa.Column('due_date', sa.DateTime(), nullable=False),
        sa.Column('check_number', sa.String(length=50), nullable=False),
        sa.Column('sayad_code', sa.String(length=16), nullable=True),
        sa.Column('bank_name', sa.String(length=255), nullable=True),
        sa.Column('branch_name', sa.String(length=255), nullable=True),
        sa.Column('amount', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('status', mysql.ENUM('RECEIVED_ON_HAND', 'TRANSFERRED_ISSUED', 'DEPOSITED', 'CLEARED', 'ENDORSED', 'RETURNED', 'BOUNCED', 'CANCELLED', name='check_status'), nullable=True),
        sa.Column('status_at', sa.DateTime(), nullable=True),
        sa.Column('current_holder_type', mysql.ENUM('BUSINESS', 'BANK', 'PERSON', name='check_holder_type'), nullable=True),
        sa.Column('current_holder_id', sa.Integer(), nullable=True),
        sa.Column('last_action_document_id', sa.Integer(), nullable=True),
        sa.Column('developer_data', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['person_id'], ['persons.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['last_action_document_id'], ['documents.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'check_number', name='uq_checks_business_check_number'),
        sa.UniqueConstraint('business_id', 'sayad_code', name='uq_checks_business_sayad_code')
    )
    op.create_index(op.f('ix_checks_business_id'), 'checks', ['business_id'], unique=False)
    op.create_index(op.f('ix_checks_type'), 'checks', ['type'], unique=False)
    op.create_index(op.f('ix_checks_person_id'), 'checks', ['person_id'], unique=False)
    op.create_index(op.f('ix_checks_issue_date'), 'checks', ['issue_date'], unique=False)
    op.create_index(op.f('ix_checks_due_date'), 'checks', ['due_date'], unique=False)
    op.create_index(op.f('ix_checks_check_number'), 'checks', ['check_number'], unique=False)
    op.create_index(op.f('ix_checks_sayad_code'), 'checks', ['sayad_code'], unique=False)
    op.create_index(op.f('ix_checks_currency_id'), 'checks', ['currency_id'], unique=False)
    op.create_index(op.f('ix_checks_status'), 'checks', ['status'], unique=False)
    op.create_index(op.f('ix_checks_current_holder_type'), 'checks', ['current_holder_type'], unique=False)
    op.create_index(op.f('ix_checks_current_holder_id'), 'checks', ['current_holder_id'], unique=False)
    op.create_index(op.f('ix_checks_last_action_document_id'), 'checks', ['last_action_document_id'], unique=False)
    op.create_index('ix_checks_business_type', 'checks', ['business_id', 'type'], unique=False)
    op.create_index('ix_checks_business_person', 'checks', ['business_id', 'person_id'], unique=False)
    op.create_index('ix_checks_business_issue_date', 'checks', ['business_id', 'issue_date'], unique=False)
    op.create_index('ix_checks_business_due_date', 'checks', ['business_id', 'due_date'], unique=False)

    # جدول check_reconciliations
    op.create_table(
        'check_reconciliations',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('base_date', sa.DateTime(), nullable=False),
        sa.Column('calculated_average_days', sa.Numeric(precision=10, scale=2), nullable=False),
        sa.Column('calculated_date', sa.DateTime(), nullable=False),
        sa.Column('total_amount', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('check_count', sa.Integer(), nullable=False),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('description', sa.String(length=1000), nullable=True),
        sa.Column('created_by_user_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_check_reconciliations_business_id'), 'check_reconciliations', ['business_id'], unique=False)
    op.create_index(op.f('ix_check_reconciliations_created_at'), 'check_reconciliations', ['created_at'], unique=False)
    op.create_index('ix_check_reconciliations_business', 'check_reconciliations', ['business_id'], unique=False)
    op.create_index('ix_check_reconciliations_created_at', 'check_reconciliations', ['created_at'], unique=False)

    # جدول check_reconciliation_items
    op.create_table(
        'check_reconciliation_items',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('reconciliation_id', sa.Integer(), nullable=False),
        sa.Column('check_id', sa.Integer(), nullable=False),
        sa.Column('days_to_maturity', sa.Integer(), nullable=False),
        sa.Column('weighted_value', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['reconciliation_id'], ['check_reconciliations.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['check_id'], ['checks.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_check_reconciliation_items_reconciliation_id'), 'check_reconciliation_items', ['reconciliation_id'], unique=False)
    op.create_index(op.f('ix_check_reconciliation_items_check_id'), 'check_reconciliation_items', ['check_id'], unique=False)
    op.create_index('ix_check_reconciliation_items_reconciliation', 'check_reconciliation_items', ['reconciliation_id'], unique=False)
    op.create_index('ix_check_reconciliation_items_check', 'check_reconciliation_items', ['check_id'], unique=False)


def downgrade():
    op.drop_index('ix_check_reconciliation_items_check', table_name='check_reconciliation_items')
    op.drop_index('ix_check_reconciliation_items_reconciliation', table_name='check_reconciliation_items')
    op.drop_index(op.f('ix_check_reconciliation_items_check_id'), table_name='check_reconciliation_items')
    op.drop_index(op.f('ix_check_reconciliation_items_reconciliation_id'), table_name='check_reconciliation_items')
    op.drop_table('check_reconciliation_items')
    
    op.drop_index('ix_check_reconciliations_created_at', table_name='check_reconciliations')
    op.drop_index('ix_check_reconciliations_business', table_name='check_reconciliations')
    op.drop_index(op.f('ix_check_reconciliations_created_at'), table_name='check_reconciliations')
    op.drop_index(op.f('ix_check_reconciliations_business_id'), table_name='check_reconciliations')
    op.drop_table('check_reconciliations')
    
    op.drop_index('ix_checks_business_due_date', table_name='checks')
    op.drop_index('ix_checks_business_issue_date', table_name='checks')
    op.drop_index('ix_checks_business_person', table_name='checks')
    op.drop_index('ix_checks_business_type', table_name='checks')
    op.drop_index(op.f('ix_checks_last_action_document_id'), table_name='checks')
    op.drop_index(op.f('ix_checks_current_holder_id'), table_name='checks')
    op.drop_index(op.f('ix_checks_current_holder_type'), table_name='checks')
    op.drop_index(op.f('ix_checks_status'), table_name='checks')
    op.drop_index(op.f('ix_checks_currency_id'), table_name='checks')
    op.drop_index(op.f('ix_checks_sayad_code'), table_name='checks')
    op.drop_index(op.f('ix_checks_check_number'), table_name='checks')
    op.drop_index(op.f('ix_checks_due_date'), table_name='checks')
    op.drop_index(op.f('ix_checks_issue_date'), table_name='checks')
    op.drop_index(op.f('ix_checks_person_id'), table_name='checks')
    op.drop_index(op.f('ix_checks_type'), table_name='checks')
    op.drop_index(op.f('ix_checks_business_id'), table_name='checks')
    op.drop_table('checks')
    
    op.execute("DROP TYPE IF EXISTS check_holder_type_enum")
    op.execute("DROP TYPE IF EXISTS check_status_enum")
    op.execute("DROP TYPE IF EXISTS check_type_enum")

