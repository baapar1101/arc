from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.sql import table, column
from sqlalchemy import String, Integer

# revision identifiers, used by Alembic.
revision = "20250916_000002"
down_revision = "20250915_000001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add columns (referral_code nullable for backfill, then set NOT NULL)
    op.add_column("users", sa.Column("referral_code", sa.String(length=32), nullable=True))
    op.add_column("users", sa.Column("referred_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True))

    # Backfill referral_code for existing users with unique random strings
    bind = op.get_bind()
    users_tbl = sa.table("users", sa.column("id", sa.Integer), sa.column("referral_code", sa.String))

    # Fetch all user ids
    res = bind.execute(sa.text("SELECT id FROM users"))
    user_ids = [row[0] for row in res]

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


def downgrade() -> None:
    op.drop_index("ix_users_referral_code", table_name="users")
    op.drop_column("users", "referred_by_user_id")
    op.drop_column("users", "referral_code")


