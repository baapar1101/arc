"""merge_heads_and_add_user_signature

Revision ID: a3a3a1b6669f
Revises: 20251110_100001_add_notification_templates_and_settings, 20251112_200001_add_credit_settings_and_installment_templates
Create Date: 2025-11-14 13:22:38.541150

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a3a3a1b6669f'
down_revision = ('20251110_100001_add_notification_templates_and_settings', '20251112_200001_add_credit_settings_and_installment_templates')
branch_labels = None
depends_on = None


def upgrade() -> None:
    # افزودن ستون امضای کاربر به جدول users (با چک کردن وجود قبلی برای جلوگیری از خطای تکراری)
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_columns = [col['name'] for col in inspector.get_columns('users')]
    if 'signature_file_id' not in existing_columns:
        op.add_column(
            'users',
            sa.Column('signature_file_id', sa.String(length=36), nullable=True),
        )


def downgrade() -> None:
    # حذف ستون امضای کاربر در صورت برگشت
    op.drop_column('users', 'signature_file_id')
