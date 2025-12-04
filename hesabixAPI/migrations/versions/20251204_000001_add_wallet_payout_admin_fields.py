"""add wallet payout admin fields

Revision ID: 20251204_000001
Revises: 20251203_000001
Create Date: 2025-12-04 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251204_000001'
down_revision = '20251203_000001'
branch_labels = None
depends_on = None


def upgrade():
    # بررسی وجود ستون‌ها قبل از اضافه کردن
    connection = op.get_bind()
    inspector = sa.inspect(connection)
    columns = [col['name'] for col in inspector.get_columns('wallet_payouts')]
    indexes = [idx['name'] for idx in inspector.get_indexes('wallet_payouts')]
    foreign_keys = [fk['name'] for fk in inspector.get_foreign_keys('wallet_payouts')]
    
    # اضافه کردن فیلد document_id
    if 'document_id' not in columns:
        op.add_column(
            'wallet_payouts',
            sa.Column('document_id', sa.Integer(), nullable=True)
        )
    
    # اضافه کردن فیلد settlement_date
    if 'settlement_date' not in columns:
        op.add_column(
            'wallet_payouts',
            sa.Column('settlement_date', sa.DateTime(), nullable=True)
        )
    
    # اضافه کردن فیلد bank_tracking_code
    if 'bank_tracking_code' not in columns:
        op.add_column(
            'wallet_payouts',
            sa.Column('bank_tracking_code', sa.String(length=100), nullable=True)
        )
    
    # اضافه کردن فیلد settlement_note
    if 'settlement_note' not in columns:
        op.add_column(
            'wallet_payouts',
            sa.Column('settlement_note', sa.Text(), nullable=True)
        )
    
    # ایجاد ایندکس
    if 'ix_wallet_payouts_document_id' not in indexes:
        op.create_index(
            'ix_wallet_payouts_document_id',
            'wallet_payouts',
            ['document_id'],
            unique=False
        )
    
    # ایجاد foreign key
    if 'fk_wallet_payouts_document_id_documents' not in foreign_keys:
        op.create_foreign_key(
            'fk_wallet_payouts_document_id_documents',
            'wallet_payouts',
            'documents',
            ['document_id'],
            ['id'],
            ondelete='SET NULL'
        )


def downgrade():
    op.drop_constraint(
        'fk_wallet_payouts_document_id_documents',
        'wallet_payouts',
        type_='foreignkey'
    )
    op.drop_index('ix_wallet_payouts_document_id', table_name='wallet_payouts')
    op.drop_column('wallet_payouts', 'settlement_note')
    op.drop_column('wallet_payouts', 'bank_tracking_code')
    op.drop_column('wallet_payouts', 'settlement_date')
    op.drop_column('wallet_payouts', 'document_id')

