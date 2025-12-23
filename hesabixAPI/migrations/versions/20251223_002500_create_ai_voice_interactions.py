"""create ai_voice_interactions table

Revision ID: 20251223_002500_create_ai_voice_interactions
Revises: 20251223_001905
Create Date: 2025-12-23 00:25:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "20251223_002500_create_ai_voice_interactions"
down_revision: Union[str, None] = "20251223_001905"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
	bind = op.get_bind()
	inspector = sa.inspect(bind)
	tables = set(inspector.get_table_names())
	if "ai_voice_interactions" in tables:
		return

	op.create_table(
		"ai_voice_interactions",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
		sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="SET NULL"), nullable=True),
		sa.Column("ai_session_id", sa.Integer(), sa.ForeignKey("ai_chat_sessions.id", ondelete="SET NULL"), nullable=True),
		sa.Column("consent", sa.Boolean(), nullable=False, server_default=sa.text("0")),
		sa.Column("input_transcript", sa.Text(), nullable=True),
		sa.Column("input_audio_path", sa.Text(), nullable=True),
		sa.Column("assistant_text", sa.Text(), nullable=True),
		sa.Column("assistant_audio_path", sa.Text(), nullable=True),
		sa.Column("stt_model", sa.String(length=255), nullable=True),
		sa.Column("tts_engine", sa.String(length=64), nullable=True),
		sa.Column("tts_model", sa.String(length=255), nullable=True),
		sa.Column("rating", sa.Integer(), nullable=True),
		sa.Column("feedback_text", sa.Text(), nullable=True),
		sa.Column("meta_json", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
	)

	op.create_index("ix_ai_voice_interactions_user_id", "ai_voice_interactions", ["user_id"])
	op.create_index("ix_ai_voice_interactions_business_id", "ai_voice_interactions", ["business_id"])
	op.create_index("ix_ai_voice_interactions_ai_session_id", "ai_voice_interactions", ["ai_session_id"])
	op.create_index("ix_ai_voice_interactions_created_at", "ai_voice_interactions", ["created_at"])


def downgrade() -> None:
	bind = op.get_bind()
	inspector = sa.inspect(bind)
	tables = set(inspector.get_table_names())
	if "ai_voice_interactions" not in tables:
		return
	op.drop_index("ix_ai_voice_interactions_created_at", table_name="ai_voice_interactions")
	op.drop_index("ix_ai_voice_interactions_ai_session_id", table_name="ai_voice_interactions")
	op.drop_index("ix_ai_voice_interactions_business_id", table_name="ai_voice_interactions")
	op.drop_index("ix_ai_voice_interactions_user_id", table_name="ai_voice_interactions")
	op.drop_table("ai_voice_interactions")


