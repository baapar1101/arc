from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

# revision identifiers, used by Alembic.
revision = '20250927_000020_add_share_count_and_shareholder_type'
down_revision = '20250927_000019_seed_accounts_chart'
branch_labels = None
depends_on = None


def upgrade() -> None:
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


def downgrade() -> None:
	with op.batch_alter_table('persons') as batch_op:
		batch_op.drop_column('share_count')

    # بازگردانی ENUM بدون مقدار سهامدار
	op.execute(
		"""
		ALTER TABLE persons 
		MODIFY COLUMN person_type 
        ENUM('مشتری','بازاریاب','کارمند','تامین‌کننده','همکار','فروشنده') NOT NULL
		"""
	)


