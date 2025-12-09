"""add projects table

Revision ID: 20251205_000001
Revises: 20251204_000002
Create Date: 2025-12-05 10:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision = '20251205_000001'
down_revision = '20251204_000002'
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Create projects table (idempotent)
	from sqlalchemy import inspect
	
	bind = op.get_bind()
	inspector = inspect(bind)
	
	# بررسی وجود جدول قبل از ایجاد (idempotent)
	if 'projects' not in inspector.get_table_names():
		op.create_table(
		'projects',
		sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
		sa.Column('business_id', sa.Integer(), nullable=False),
		sa.Column('code', sa.String(50), nullable=False),
		sa.Column('name', sa.String(255), nullable=False),
		sa.Column('description', sa.Text(), nullable=True),
		sa.Column('status', sa.String(20), nullable=False, server_default='active'),
		sa.Column('start_date', sa.Date(), nullable=True),
		sa.Column('end_date', sa.Date(), nullable=True),
		sa.Column('budget', sa.Numeric(18, 2), nullable=True),
		sa.Column('currency_id', sa.Integer(), nullable=True),
		sa.Column('manager_user_id', sa.Integer(), nullable=True),
		sa.Column('person_id', sa.Integer(), nullable=True),
		sa.Column('extra_info', sa.JSON(), nullable=True),
		sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
		sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
		sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
		sa.Column('created_by_user_id', sa.Integer(), nullable=False),
		sa.PrimaryKeyConstraint('id'),
		sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
		sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='SET NULL'),
		sa.ForeignKeyConstraint(['manager_user_id'], ['users.id'], ondelete='SET NULL'),
		sa.ForeignKeyConstraint(['person_id'], ['persons.id'], ondelete='SET NULL'),
		sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='RESTRICT'),
		sa.UniqueConstraint('business_id', 'code', name='uq_projects_business_code'),
		mysql_charset='utf8mb4',
		mysql_collate='utf8mb4_unicode_ci'
	)
	
		# Create indexes (idempotent)
		existing_indexes = [idx['name'] for idx in inspector.get_indexes('projects')]
		if 'ix_projects_business_id' not in existing_indexes:
			op.create_index('ix_projects_business_id', 'projects', ['business_id'])
		if 'ix_projects_code' not in existing_indexes:
			op.create_index('ix_projects_code', 'projects', ['code'])
		if 'ix_projects_name' not in existing_indexes:
			op.create_index('ix_projects_name', 'projects', ['name'])
		if 'ix_projects_currency_id' not in existing_indexes:
			op.create_index('ix_projects_currency_id', 'projects', ['currency_id'])
		if 'ix_projects_manager_user_id' not in existing_indexes:
			op.create_index('ix_projects_manager_user_id', 'projects', ['manager_user_id'])
		if 'ix_projects_person_id' not in existing_indexes:
			op.create_index('ix_projects_person_id', 'projects', ['person_id'])
		if 'ix_projects_created_by_user_id' not in existing_indexes:
			op.create_index('ix_projects_created_by_user_id', 'projects', ['created_by_user_id'])
	
	# Add project_id column to documents table (idempotent)
	doc_columns = [col['name'] for col in inspector.get_columns('documents')]
	if 'project_id' not in doc_columns:
		op.add_column('documents', sa.Column('project_id', sa.Integer(), nullable=True))
	
	# Add foreign key and index (idempotent)
	doc_fks = [fk['name'] for fk in inspector.get_foreign_keys('documents')]
	if 'fk_documents_project_id' not in doc_fks:
		op.create_foreign_key('fk_documents_project_id', 'documents', 'projects', ['project_id'], ['id'], ondelete='SET NULL')
	
	doc_indexes = [idx['name'] for idx in inspector.get_indexes('documents')]
	if 'ix_documents_project_id' not in doc_indexes:
		op.create_index('ix_documents_project_id', 'documents', ['project_id'])


def downgrade() -> None:
	# Remove project_id from documents
	op.drop_index('ix_documents_project_id', 'documents')
	op.drop_constraint('fk_documents_project_id', 'documents', type_='foreignkey')
	op.drop_column('documents', 'project_id')
	
	# Drop indexes
	op.drop_index('ix_projects_created_by_user_id', 'projects')
	op.drop_index('ix_projects_person_id', 'projects')
	op.drop_index('ix_projects_manager_user_id', 'projects')
	op.drop_index('ix_projects_currency_id', 'projects')
	op.drop_index('ix_projects_name', 'projects')
	op.drop_index('ix_projects_code', 'projects')
	op.drop_index('ix_projects_business_id', 'projects')
	
	# Drop table
	op.drop_table('projects')

