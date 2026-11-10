"""افزونه تدارکات: درخواست، استعلام، سفارش، بودجه و قرارداد.

Revision ID: 20261110_000001_procurement_plugin
Revises: 20261110_000002_crm_saved_views, 20261110_000002_oa_process_runtime
"""
from __future__ import annotations

import json

import sqlalchemy as sa
from alembic import op

from adapters.db.models.procurement import (
	ProcApproval,
	ProcBudget,
	ProcBudgetMovement,
	ProcCommitment,
	ProcContract,
	ProcContractLine,
	ProcCostCenter,
	ProcDelegation,
	ProcGuarantee,
	ProcInvoiceLink,
	ProcMatchLine,
	ProcOrder,
	ProcOrderLine,
	ProcPortalInvoice,
	ProcPrepayment,
	ProcReceipt,
	ProcReceiptLine,
	ProcReorderSuggestion,
	ProcRequisition,
	ProcRequisitionLine,
	ProcScore,
	ProcSettings,
	ProcShareLink,
	ProcSourcingBid,
	ProcSourcingBidLine,
	ProcSourcingEvent,
	ProcSourcingInvite,
	ProcSourcingLine,
	ProcSupplierDocument,
	ProcSupplierProfile,
)
from adapters.db.seed_data.notification_event_types_seed import (
	NOTIFICATION_EVENT_TYPES_ROWS,
	PROCUREMENT_EVENT_CODES,
)

revision = "20261110_000001_procurement_plugin"
down_revision = (
	"20261110_000002_crm_saved_views",
	"20261110_000002_oa_process_runtime",
)
branch_labels = None
depends_on = None

_TABLES = (
	ProcSettings.__table__,
	ProcCostCenter.__table__,
	ProcSupplierProfile.__table__,
	ProcSupplierDocument.__table__,
	ProcDelegation.__table__,
	ProcBudget.__table__,
	ProcBudgetMovement.__table__,
	ProcContract.__table__,
	ProcContractLine.__table__,
	ProcRequisition.__table__,
	ProcRequisitionLine.__table__,
	ProcSourcingEvent.__table__,
	ProcSourcingLine.__table__,
	ProcSourcingInvite.__table__,
	ProcSourcingBid.__table__,
	ProcSourcingBidLine.__table__,
	ProcOrder.__table__,
	ProcOrderLine.__table__,
	ProcCommitment.__table__,
	ProcReceipt.__table__,
	ProcReceiptLine.__table__,
	ProcInvoiceLink.__table__,
	ProcMatchLine.__table__,
	ProcGuarantee.__table__,
	ProcPrepayment.__table__,
	ProcScore.__table__,
	ProcShareLink.__table__,
	ProcPortalInvoice.__table__,
	ProcReorderSuggestion.__table__,
	ProcApproval.__table__,
)


def upgrade() -> None:
	bind = op.get_bind()
	for table in _TABLES:
		table.create(bind, checkfirst=True)
	insp = sa.inspect(bind)
	if "notification_event_types" not in insp.get_table_names():
		return
	rows = [row for row in NOTIFICATION_EVENT_TYPES_ROWS if row["code"] in PROCUREMENT_EVENT_CODES]
	for row in rows:
		bind.execute(
			sa.text(
				"""
				INSERT INTO notification_event_types (
					code, name, description, category, available_variables,
					default_sms_template, default_email_template, default_email_subject,
					is_active, requires_approval, created_at, updated_at
				) VALUES (
					:code, :name, :description, :category, CAST(:vars AS JSONB),
					:dst, :det, :des,
					true, false, NOW(), NOW()
				)
				ON CONFLICT (code) DO NOTHING
				"""
			),
			{
				"code": row["code"],
				"name": row["name"],
				"description": row.get("description"),
				"category": row.get("category"),
				"vars": json.dumps(row["available_variables"], ensure_ascii=False),
				"dst": row.get("default_sms_template"),
				"det": row.get("default_email_template"),
				"des": row.get("default_email_subject"),
			},
		)


def downgrade() -> None:
	bind = op.get_bind()
	insp = sa.inspect(bind)
	if "notification_event_types" in insp.get_table_names():
		for code in PROCUREMENT_EVENT_CODES:
			bind.execute(sa.text("DELETE FROM notification_event_types WHERE code = :c"), {"c": code})
	for table in reversed(_TABLES):
		table.drop(bind, checkfirst=True)
