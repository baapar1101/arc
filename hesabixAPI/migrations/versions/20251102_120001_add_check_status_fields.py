from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '20251102_120001_add_check_status_fields'
down_revision: Union[str, None] = '20251011_000901_add_checks_table'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    # افزودن ستون‌ها اگر وجود ندارند (سازگار با MySQL و PostgreSQL)
    columns = {c['name'] for c in inspector.get_columns('checks')}

    if 'status' not in columns:
        op.add_column('checks', sa.Column('status', sa.Enum(
            'RECEIVED_ON_HAND', 'TRANSFERRED_ISSUED', 'DEPOSITED', 'CLEARED', 'ENDORSED', 'RETURNED', 'BOUNCED', 'CANCELLED', name='check_status'
        ), nullable=True))
        try:
            op.create_index('ix_checks_business_status', 'checks', ['business_id', 'status'])
        except Exception:
            pass

    if 'status_at' not in columns:
        op.add_column('checks', sa.Column('status_at', sa.DateTime(), nullable=True))

    if 'current_holder_type' not in columns:
        op.add_column('checks', sa.Column('current_holder_type', sa.Enum('BUSINESS', 'BANK', 'PERSON', name='check_holder_type'), nullable=True))
        try:
            op.create_index('ix_checks_business_holder_type', 'checks', ['business_id', 'current_holder_type'])
        except Exception:
            pass

    if 'current_holder_id' not in columns:
        op.add_column('checks', sa.Column('current_holder_id', sa.Integer(), nullable=True))
        try:
            op.create_index('ix_checks_business_holder_id', 'checks', ['business_id', 'current_holder_id'])
        except Exception:
            pass

    if 'last_action_document_id' not in columns:
        op.add_column('checks', sa.Column('last_action_document_id', sa.Integer(), sa.ForeignKey('documents.id', ondelete='SET NULL'), nullable=True))

    if 'developer_data' not in columns:
        # MySQL و PostgreSQL هر دو از JSON پشتیبانی می‌کنند
        op.add_column('checks', sa.Column('developer_data', sa.JSON(), nullable=True))


def downgrade() -> None:
    # حذف ایندکس‌ها و ستون‌ها
    try:
        op.drop_index('ix_checks_business_status', table_name='checks')
    except Exception:
        pass
    try:
        op.drop_index('ix_checks_business_holder_type', table_name='checks')
    except Exception:
        pass
    try:
        op.drop_index('ix_checks_business_holder_id', table_name='checks')
    except Exception:
        pass

    for col in ['developer_data', 'last_action_document_id', 'current_holder_id', 'current_holder_type', 'status_at', 'status']:
        try:
            op.drop_column('checks', col)
        except Exception:
            pass

    # حذف انواع Enum فقط در پایگاه‌هایی که لازم است (PostgreSQL)
    # در MySQL نیازی به حذف نوع جداگانه نیست
    try:
        op.execute("DROP TYPE check_holder_type")
        op.execute("DROP TYPE check_status")
    except Exception:
        pass


