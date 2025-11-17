from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "20250115_000001_add_ping_pong_scores_table"
down_revision: Union[str, None] = "20251114_000010_add_business_print_settings"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if "ping_pong_scores" not in inspector.get_table_names():
        op.create_table(
            "ping_pong_scores",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column(
                "user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("score", sa.Integer(), nullable=False),
            sa.Column("survival_time", sa.Integer(), nullable=False, comment="زمان زنده ماندن به ثانیه"),
            sa.Column("hero_mode_uses", sa.Integer(), nullable=False, server_default=sa.text("0"), comment="تعداد استفاده از حالت قهرمان"),
            sa.Column("difficulty_level", sa.Float(), nullable=False, server_default=sa.text("1.0"), comment="آخرین سطح سختی"),
            sa.Column(
                "played_at",
                sa.DateTime(),
                nullable=False,
                server_default=sa.func.now(),
            ),
            sa.Column(
                "created_at",
                sa.DateTime(),
                nullable=False,
                server_default=sa.func.now(),
            ),
        )
        try:
            op.create_index(
                "ix_ping_pong_scores_user_id",
                "ping_pong_scores",
                ["user_id"],
            )
            op.create_index(
                "ix_ping_pong_scores_score",
                "ping_pong_scores",
                ["score"],
            )
            op.create_index(
                "ix_ping_pong_scores_played_at",
                "ping_pong_scores",
                ["played_at"],
            )
            # Index for user_id and score combined (for leaderboard queries)
            op.create_index(
                "ix_ping_pong_user_score",
                "ping_pong_scores",
                ["user_id", "score"],
            )
        except Exception:
            # ایندکس‌ها اختیاری هستند؛ در صورت خطا ادامه می‌دهیم
            pass


def downgrade() -> None:
    try:
        op.drop_index("ix_ping_pong_user_score", table_name="ping_pong_scores")
        op.drop_index("ix_ping_pong_scores_played_at", table_name="ping_pong_scores")
        op.drop_index("ix_ping_pong_scores_score", table_name="ping_pong_scores")
        op.drop_index("ix_ping_pong_scores_user_id", table_name="ping_pong_scores")
    except Exception:
        pass
    try:
        op.drop_table("ping_pong_scores")
    except Exception:
        pass

