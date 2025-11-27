"""جداول business_print_settings, business_permissions"""
from alembic import op
import sqlalchemy as sa


def upgrade():
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


def downgrade():
    op.drop_index(op.f('ix_business_permissions_user_id'), table_name='business_permissions')
    op.drop_index(op.f('ix_business_permissions_business_id'), table_name='business_permissions')
    op.drop_table('business_permissions')
    
    op.drop_index(op.f('ix_business_print_settings_document_type'), table_name='business_print_settings')
    op.drop_index(op.f('ix_business_print_settings_business_id'), table_name='business_print_settings')
    op.drop_table('business_print_settings')

