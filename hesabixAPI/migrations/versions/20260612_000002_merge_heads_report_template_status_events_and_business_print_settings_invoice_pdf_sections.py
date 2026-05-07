"""Merge heads: report_template_status_events + business_print_settings_invoice_pdf_sections

Revision ID: 20260612_000002_merge_heads_report_template_status_events_and_business_print_settings_invoice_pdf_sections
Revises: 20260611_000002_report_template_status_events, 20260612_000001_business_print_settings_invoice_pdf_sections
Create Date: 2026-06-12

"""

from __future__ import annotations

from alembic import op  # noqa: F401

revision = "20260612_000002_merge_heads_report_template_status_events_and_business_print_settings_invoice_pdf_sections"
down_revision = (
	"20260611_000002_report_template_status_events",
	"20260612_000001_business_print_settings_invoice_pdf_sections",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass
