"""صف OCR پیوست نامه، جدا از استخراج همزمان.

Revision ID: 20261110_000008_oa_letter_ocr_jobs
Revises: 20261110_000007_oa_letter_commercial_links
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000008_oa_letter_ocr_jobs"
down_revision = "20261110_000007_oa_letter_commercial_links"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.alter_column("oa_ocr_jobs", "document_version_id", existing_type=sa.Integer(), nullable=True)
	op.add_column("oa_ocr_jobs", sa.Column("letter_attachment_id", sa.Integer(), nullable=True))
	op.create_foreign_key(
		"fk_oa_ocr_jobs_letter_attachment",
		"oa_ocr_jobs",
		"oa_letter_attachments",
		["letter_attachment_id"],
		["id"],
		ondelete="CASCADE",
	)
	op.create_index("ix_oa_ocr_jobs_letter_attachment", "oa_ocr_jobs", ["letter_attachment_id"])


def downgrade() -> None:
	op.drop_index("ix_oa_ocr_jobs_letter_attachment", table_name="oa_ocr_jobs")
	op.drop_constraint("fk_oa_ocr_jobs_letter_attachment", "oa_ocr_jobs", type_="foreignkey")
	op.drop_column("oa_ocr_jobs", "letter_attachment_id")
	op.alter_column("oa_ocr_jobs", "document_version_id", existing_type=sa.Integer(), nullable=False)
