"""رکورد سند، نسخه و صف OCR اتوماسیون اداری.

Revision ID: 20261110_000003_oa_documents
Revises: 20261110_000002_oa_process_runtime
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000003_oa_documents"
down_revision = "20261110_000002_oa_process_runtime"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"oa_documents",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("title", sa.String(length=500), nullable=False),
		sa.Column("confidentiality", sa.String(length=32), nullable=False),
		sa.Column("letter_id", sa.Integer(), nullable=True),
		sa.Column("current_version_id", sa.Integer(), nullable=True),
		sa.Column("reference_no", sa.String(length=120), nullable=True),
		sa.Column("search_text", sa.Text(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["letter_id"], ["oa_letters.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_documents_business_id", "oa_documents", ["business_id"])
	op.create_table(
		"oa_document_versions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("document_id", sa.Integer(), nullable=False),
		sa.Column("version_no", sa.Integer(), nullable=False),
		sa.Column("file_storage_id", sa.String(length=36), nullable=False),
		sa.Column("extracted_text", sa.Text(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["document_id"], ["oa_documents.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["file_storage_id"], ["file_storage.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("document_id", "version_no", name="uq_oa_document_versions_no"),
	)
	op.create_index("ix_oa_document_versions_document_id", "oa_document_versions", ["document_id"])
	op.create_table(
		"oa_ocr_jobs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("document_version_id", sa.Integer(), nullable=False),
		sa.Column("status", sa.String(length=16), nullable=False),
		sa.Column("error", sa.String(length=500), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("finished_at", sa.DateTime(), nullable=True),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["document_version_id"], ["oa_document_versions.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_ocr_jobs_status", "oa_ocr_jobs", ["status"])
	op.create_table(
		"oa_extraction_suggestions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("document_id", sa.Integer(), nullable=False),
		sa.Column("version_id", sa.Integer(), nullable=False),
		sa.Column("field_key", sa.String(length=32), nullable=False),
		sa.Column("suggested_value", sa.String(length=500), nullable=False),
		sa.Column("status", sa.String(length=16), nullable=False),
		sa.Column("confirmed_by_user_id", sa.Integer(), nullable=True),
		sa.Column("confirmed_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["document_id"], ["oa_documents.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["version_id"], ["oa_document_versions.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["confirmed_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_extraction_suggestions_document_id", "oa_extraction_suggestions", ["document_id"])


def downgrade() -> None:
	op.drop_index("ix_oa_extraction_suggestions_document_id", table_name="oa_extraction_suggestions")
	op.drop_table("oa_extraction_suggestions")
	op.drop_index("ix_oa_ocr_jobs_status", table_name="oa_ocr_jobs")
	op.drop_table("oa_ocr_jobs")
	op.drop_index("ix_oa_document_versions_document_id", table_name="oa_document_versions")
	op.drop_table("oa_document_versions")
	op.drop_index("ix_oa_documents_business_id", table_name="oa_documents")
	op.drop_table("oa_documents")
