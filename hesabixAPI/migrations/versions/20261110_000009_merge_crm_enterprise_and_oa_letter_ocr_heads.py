"""Merge CRM enterprise and OA letter OCR heads.

Revision ID: 20261110_000009_merge_crm_enterprise_and_oa_letter_ocr_heads
Revises: 20261110_000006_crm_enterprise, 20261110_000008_oa_letter_ocr_jobs
"""

from __future__ import annotations

revision = "20261110_000009_merge_crm_enterprise_and_oa_letter_ocr_heads"
down_revision = (
	"20261110_000006_crm_enterprise",
	"20261110_000008_oa_letter_ocr_jobs",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass
