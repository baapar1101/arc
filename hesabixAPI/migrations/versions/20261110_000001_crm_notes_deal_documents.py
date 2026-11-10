"""یادداشت CRM روی شخص و فرصت، و پیوند چندسند به فرصت فروش.

Revision ID: 20261110_000001_crm_notes_deal_documents
Revises: 20261107_000001_pay_page_requests
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000001_crm_notes_deal_documents"
down_revision = "20261107_000001_pay_page_requests"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = set(inspector.get_table_names())
    if "crm_notes" in tables:
        columns = {col["name"] for col in inspector.get_columns("crm_notes")}
        if "person_id" not in columns:
            op.add_column(
                "crm_notes",
                sa.Column("person_id", sa.Integer(), sa.ForeignKey("persons.id", ondelete="SET NULL"), nullable=True),
            )
            op.create_index("ix_crm_notes_person_id", "crm_notes", ["person_id"])
        if "deal_id" not in columns:
            op.add_column(
                "crm_notes",
                sa.Column("deal_id", sa.Integer(), sa.ForeignKey("crm_deals.id", ondelete="SET NULL"), nullable=True),
            )
            op.create_index("ix_crm_notes_deal_id", "crm_notes", ["deal_id"])
    if "crm_deal_documents" not in tables:
        op.create_table(
            "crm_deal_documents",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
            sa.Column("deal_id", sa.Integer(), sa.ForeignKey("crm_deals.id", ondelete="CASCADE"), nullable=False),
            sa.Column("document_id", sa.Integer(), sa.ForeignKey("documents.id", ondelete="CASCADE"), nullable=False),
            sa.Column("role", sa.String(length=20), nullable=False),
            sa.Column("created_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("deal_id", "document_id", name="uq_crm_deal_documents_deal_document"),
        )
        op.create_index("idx_crm_deal_documents_business_deal", "crm_deal_documents", ["business_id", "deal_id"])
        op.create_index("ix_crm_deal_documents_document_id", "crm_deal_documents", ["document_id"])
        op.execute(
            """
            INSERT INTO crm_deal_documents (business_id, deal_id, document_id, role, created_at)
            SELECT d.business_id,
                   d.id,
                   d.document_id,
                   CASE WHEN COALESCE(doc.is_proforma, false) THEN 'proforma' ELSE 'invoice' END,
                   CURRENT_TIMESTAMP
            FROM crm_deals d
            JOIN documents doc ON doc.id = d.document_id
            WHERE d.document_id IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1
                    FROM crm_deal_documents existing
                    WHERE existing.deal_id = d.id
                      AND existing.document_id = d.document_id
              )
            """
        )


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = set(inspector.get_table_names())
    if "crm_deal_documents" in tables:
        op.drop_index("ix_crm_deal_documents_document_id", table_name="crm_deal_documents")
        op.drop_index("idx_crm_deal_documents_business_deal", table_name="crm_deal_documents")
        op.drop_table("crm_deal_documents")
    if "crm_notes" in tables:
        columns = {col["name"] for col in inspector.get_columns("crm_notes")}
        if "deal_id" in columns:
            op.drop_index("ix_crm_notes_deal_id", table_name="crm_notes")
            op.drop_column("crm_notes", "deal_id")
        if "person_id" in columns:
            op.drop_index("ix_crm_notes_person_id", table_name="crm_notes")
            op.drop_column("crm_notes", "person_id")
