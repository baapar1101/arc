"""جداول file_storage, storage_configs, file_verifications"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


def upgrade():
    # جدول storage_configs (قبل از file_storage چون file_storage به آن وابسته است)
    op.create_table(
        'storage_configs',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('name', sa.String(length=100), nullable=False),
        sa.Column('storage_type', sa.String(length=20), nullable=False),
        sa.Column('is_default', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('config_data', sa.JSON(), nullable=False),
        sa.Column('created_by', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['created_by'], ['users.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id')
    )

    # جدول file_storage
    op.create_table(
        'file_storage',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('original_name', sa.String(length=255), nullable=False),
        sa.Column('stored_name', sa.String(length=255), nullable=False),
        sa.Column('file_path', sa.String(length=500), nullable=False),
        sa.Column('file_size', sa.Integer(), nullable=False),
        sa.Column('mime_type', sa.String(length=100), nullable=False),
        sa.Column('storage_type', sa.String(length=20), nullable=False),
        sa.Column('storage_config_id', sa.String(length=36), nullable=True),
        sa.Column('uploaded_by', sa.Integer(), nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=True),
        sa.Column('subscription_id', sa.Integer(), nullable=True),
        sa.Column('module_context', sa.String(length=50), nullable=False),
        sa.Column('context_id', sa.String(length=36), nullable=True),
        sa.Column('developer_data', sa.JSON(), nullable=True),
        sa.Column('checksum', sa.String(length=64), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('is_temporary', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('is_verified', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('verification_token', sa.String(length=100), nullable=True),
        sa.Column('last_verified_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('is_marked_for_deletion', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('marked_for_deletion_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['storage_config_id'], ['storage_configs.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['uploaded_by'], ['users.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_file_storage_business_id'), 'file_storage', ['business_id'], unique=False)
    op.create_index(op.f('ix_file_storage_subscription_id'), 'file_storage', ['subscription_id'], unique=False)

    # جدول file_verifications
    op.create_table(
        'file_verifications',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('file_id', sa.String(length=36), nullable=False),
        sa.Column('module_name', sa.String(length=50), nullable=False),
        sa.Column('verification_token', sa.String(length=100), nullable=False),
        sa.Column('verified_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('verified_by', sa.Integer(), nullable=True),
        sa.Column('verification_data', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['file_id'], ['file_storage.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['verified_by'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )


def downgrade():
    op.drop_table('file_verifications')
    
    op.drop_index(op.f('ix_file_storage_subscription_id'), table_name='file_storage')
    op.drop_index(op.f('ix_file_storage_business_id'), table_name='file_storage')
    op.drop_table('file_storage')
    
    op.drop_table('storage_configs')

