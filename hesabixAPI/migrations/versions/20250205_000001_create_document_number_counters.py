"""create document_number_counters table

Revision ID: 20250205_000001_create_document_number_counters
Revises: 023c8d2d2222
Create Date: 2025-11-24 13:20:00.000000

Note: This migration was created on 2025-02-05 but depends on a merge head (023c8d2d2222) created on 2025-11-22.
This is intentional as it was merged after the merge head was created.

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "20250205_000001_create_document_number_counters"
down_revision = "023c8d2d2222"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    table_exists = "document_number_counters" in inspector.get_table_names()

    if not table_exists:
        op.create_table(
            "document_number_counters",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column(
                "business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
            ),
            sa.Column("document_type", sa.String(length=50), nullable=False),
            sa.Column("date_bucket", sa.String(length=32), nullable=False, server_default="GLOBAL"),
            sa.Column("last_number", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        )

    existing_indexes = set()
    existing_uniques = set()
    if table_exists:
        existing_indexes = {index["name"] for index in inspector.get_indexes("document_number_counters")}
        existing_uniques = {uc["name"] for uc in inspector.get_unique_constraints("document_number_counters")}

    if not table_exists or "ix_doc_number_counter_business" not in existing_indexes:
        op.create_index(
            "ix_doc_number_counter_business",
            "document_number_counters",
            ["business_id"],
        )
    if not table_exists or "ix_doc_number_counter_document_type" not in existing_indexes:
        op.create_index(
            "ix_doc_number_counter_document_type",
            "document_number_counters",
            ["document_type"],
        )
    if not table_exists or "uq_doc_number_counter_bucket" not in existing_uniques:
        op.create_unique_constraint(
            "uq_doc_number_counter_bucket",
            "document_number_counters",
            ["business_id", "document_type", "date_bucket"],
        )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())
    
    if "document_number_counters" in tables:
        existing_indexes = {index["name"] for index in inspector.get_indexes("document_number_counters")}
        existing_uniques = {uc["name"] for uc in inspector.get_unique_constraints("document_number_counters")}
        
        if "uq_doc_number_counter_bucket" in existing_uniques:
            try:
                op.drop_constraint("uq_doc_number_counter_bucket", "document_number_counters", type_="unique")
            except Exception:
                pass
        if "ix_doc_number_counter_document_type" in existing_indexes:
            try:
                op.drop_index("ix_doc_number_counter_document_type", table_name="document_number_counters")
            except Exception:
                pass
        if "ix_doc_number_counter_business" in existing_indexes:
            try:
                op.drop_index("ix_doc_number_counter_business", table_name="document_number_counters")
            except Exception:
                pass
        try:
            op.drop_table("document_number_counters")
        except Exception:
            pass


