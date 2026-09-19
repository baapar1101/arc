"""documents performance indexes and pg_trgm search

Revision ID: 20260622_000002
Revises: 20260619_000003_ai_session_todos
Create Date: 2026-06-22

"""
from alembic import op


revision = "20260622_000002"
down_revision = "20260619_000003_ai_session_todos"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    op.create_index(
        "ix_documents_business_fiscal_type_date",
        "documents",
        ["business_id", "fiscal_year_id", "document_type", "document_date"],
        unique=False,
        postgresql_ops={"document_date": "DESC"},
    )
    op.create_index(
        "ix_documents_business_type_date",
        "documents",
        ["business_id", "document_type", "document_date"],
        unique=False,
        postgresql_ops={"document_date": "DESC"},
    )
    op.create_index("ix_documents_document_type", "documents", ["document_type"], unique=False)
    op.create_index("ix_documents_document_date", "documents", ["document_date"], unique=False)

    op.execute(
        """
        CREATE INDEX ix_documents_extra_info_person_id
        ON documents ((CAST(extra_info::jsonb->>'person_id' AS integer)))
        WHERE extra_info IS NOT NULL
        """
    )

    op.execute(
        """
        CREATE INDEX ix_documents_code_trgm
        ON documents USING gin (code gin_trgm_ops)
        """
    )
    op.execute(
        """
        CREATE INDEX ix_products_name_trgm
        ON products USING gin (name gin_trgm_ops)
        """
    )
    op.execute(
        """
        CREATE INDEX ix_products_code_trgm
        ON products USING gin (code gin_trgm_ops)
        """
    )
    op.execute(
        """
        CREATE INDEX ix_persons_alias_name_trgm
        ON persons USING gin (alias_name gin_trgm_ops)
        """
    )
    op.execute(
        """
        CREATE INDEX ix_persons_company_name_trgm
        ON persons USING gin (company_name gin_trgm_ops)
        WHERE company_name IS NOT NULL
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_persons_company_name_trgm")
    op.execute("DROP INDEX IF EXISTS ix_persons_alias_name_trgm")
    op.execute("DROP INDEX IF EXISTS ix_products_code_trgm")
    op.execute("DROP INDEX IF EXISTS ix_products_name_trgm")
    op.execute("DROP INDEX IF EXISTS ix_documents_code_trgm")
    op.execute("DROP INDEX IF EXISTS ix_documents_extra_info_person_id")
    op.drop_index("ix_documents_document_date", table_name="documents")
    op.drop_index("ix_documents_document_type", table_name="documents")
    op.drop_index("ix_documents_business_type_date", table_name="documents")
    op.drop_index("ix_documents_business_fiscal_type_date", table_name="documents")
