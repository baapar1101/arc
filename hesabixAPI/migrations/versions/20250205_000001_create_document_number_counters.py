"""create document_number_counters table

Revision ID: 20250205_000001_create_document_number_counters
Revises: 023c8d2d2222
Create Date: 2025-11-24 13:20:00.000000
"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "20250205_000001_create_document_number_counters"
down_revision = "023c8d2d2222"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "document_number_counters",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("document_type", sa.String(length=50), nullable=False),
        sa.Column("date_bucket", sa.String(length=32), nullable=False, server_default="GLOBAL"),
        sa.Column("last_number", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index(
        "ix_doc_number_counter_business",
        "document_number_counters",
        ["business_id"],
    )
    op.create_index(
        "ix_doc_number_counter_document_type",
        "document_number_counters",
        ["document_type"],
    )
    op.create_unique_constraint(
        "uq_doc_number_counter_bucket",
        "document_number_counters",
        ["business_id", "document_type", "date_bucket"],
    )


def downgrade() -> None:
    op.drop_constraint("uq_doc_number_counter_bucket", "document_number_counters", type_="unique")
    op.drop_index("ix_doc_number_counter_document_type", table_name="document_number_counters")
    op.drop_index("ix_doc_number_counter_business", table_name="document_number_counters")
    op.drop_table("document_number_counters")


