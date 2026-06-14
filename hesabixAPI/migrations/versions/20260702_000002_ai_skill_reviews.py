"""AI skill reviews

Revision ID: 20260702_000002_ai_skill_reviews
Revises: 20260702_000001_ai_skills
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260702_000002_ai_skill_reviews"
down_revision = "20260702_000001_ai_skills"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_skill_reviews",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("package_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("rating", sa.Integer(), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["package_id"], ["ai_skill_packages.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_ai_skill_reviews_package_id"), "ai_skill_reviews", ["package_id"], unique=False)
    op.create_index(op.f("ix_ai_skill_reviews_user_id"), "ai_skill_reviews", ["user_id"], unique=False)
    op.create_index("ix_ai_skill_review_pkg_user", "ai_skill_reviews", ["package_id", "user_id"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_ai_skill_review_pkg_user", table_name="ai_skill_reviews")
    op.drop_index(op.f("ix_ai_skill_reviews_user_id"), table_name="ai_skill_reviews")
    op.drop_index(op.f("ix_ai_skill_reviews_package_id"), table_name="ai_skill_reviews")
    op.drop_table("ai_skill_reviews")
