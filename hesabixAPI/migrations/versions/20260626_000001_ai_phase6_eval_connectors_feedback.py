"""فاز ۶ AI: ارزیابی، کانکتور، بازخورد پیام

Revision ID: 20260626_000001_ai_phase6_eval_connectors_feedback
Revises: 20260625_000001_ai_knowledge_embeddings
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260626_000001_ai_phase6_eval_connectors_feedback"
down_revision = "20260625_000001_ai_knowledge_embeddings"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_eval_cases",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("role", sa.String(50), nullable=False, server_default="user"),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="SET NULL"), nullable=True),
        sa.Column("user_message", sa.Text(), nullable=False),
        sa.Column("expected_substrings", sa.Text(), nullable=True),
        sa.Column("forbidden_substrings", sa.Text(), nullable=True),
        sa.Column("use_tools", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
    )

    op.create_table(
        "ai_eval_runs",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("status", sa.String(32), nullable=False, server_default="running"),
        sa.Column("total_cases", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("passed_cases", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("failed_cases", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
    )

    op.create_table(
        "ai_eval_results",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("run_id", sa.Integer(), sa.ForeignKey("ai_eval_runs.id", ondelete="CASCADE"), nullable=False),
        sa.Column("case_id", sa.Integer(), sa.ForeignKey("ai_eval_cases.id", ondelete="CASCADE"), nullable=False),
        sa.Column("passed", sa.Boolean(), nullable=False),
        sa.Column("response_text", sa.Text(), nullable=True),
        sa.Column("details_json", sa.Text(), nullable=True),
        sa.Column("latency_ms", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
    )
    op.create_index("ix_ai_eval_results_run_id", "ai_eval_results", ["run_id"])

    op.create_table(
        "ai_connectors",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(128), nullable=False),
        sa.Column("title", sa.String(512), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("http_method", sa.String(16), nullable=False, server_default="GET"),
        sa.Column("url", sa.Text(), nullable=False),
        sa.Column("headers_json", sa.Text(), nullable=True),
        sa.Column("body_template", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
    )
    op.create_index("ix_ai_connectors_business_id", "ai_connectors", ["business_id"])
    op.create_unique_constraint("uq_ai_connectors_business_name", "ai_connectors", ["business_id", "name"])

    op.create_table(
        "ai_message_feedback",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("message_id", sa.Integer(), sa.ForeignKey("ai_chat_messages.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("rating", sa.Integer(), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
    )
    op.create_unique_constraint("uq_ai_message_feedback_msg_user", "ai_message_feedback", ["message_id", "user_id"])


def downgrade() -> None:
    op.drop_table("ai_message_feedback")
    op.drop_constraint("uq_ai_connectors_business_name", "ai_connectors", type_="unique")
    op.drop_index("ix_ai_connectors_business_id", table_name="ai_connectors")
    op.drop_table("ai_connectors")
    op.drop_index("ix_ai_eval_results_run_id", table_name="ai_eval_results")
    op.drop_table("ai_eval_results")
    op.drop_table("ai_eval_runs")
    op.drop_table("ai_eval_cases")
