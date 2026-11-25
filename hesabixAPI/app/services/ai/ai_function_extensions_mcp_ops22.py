"""MCP leftover: invoice delete-preview JSON (no extra_info dump)."""
from __future__ import annotations

from decimal import Decimal

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_schema

INV_ID = mcp_schema({"invoice_id": {"type": "integer", "minimum": 1}}, ["invoice_id"])


def get_invoice_delete_info_handler(args, context):
    from adapters.db.models.document import Document
    from adapters.db.models.document_line import DocumentLine
    from app.services.invoice_service import SUPPORTED_INVOICE_TYPES

    db = mcp_db(context)
    bid = mcp_bid(context)
    invoice_id = int(args["invoice_id"])
    doc = db.query(Document).filter(Document.id == invoice_id, Document.business_id == bid).first()
    if not doc or doc.document_type not in SUPPORTED_INVOICE_TYPES:
        raise ValueError("فاکتور در کسب‌وکار متصل پیدا نشد")
    extra_info = doc.extra_info or {}
    links = extra_info.get("links") or {}
    is_in_tax_workspace = bool(extra_info.get("tax_workspace"))
    tax_status = extra_info.get("tax_status", "")
    has_installments = bool(extra_info.get("installment_plan"))
    installment_info = None
    if has_installments:
        plan = extra_info.get("installment_plan", {}) or {}
        schedule = plan.get("schedule", []) or []
        installment_info = {"count": len(schedule), "total_amount": plan.get("principal_total", 0)}
    receipt_payment_document_ids = links.get("receipt_payment_document_ids") or []
    receipt_payment_info = []
    if receipt_payment_document_ids:
        related_docs = db.query(Document).filter(
            Document.business_id == bid,
            Document.id.in_(receipt_payment_document_ids),
        ).all()
        for rp_doc in related_docs:
            total_amount = Decimal(0)
            lines = db.query(DocumentLine).filter(DocumentLine.document_id == rp_doc.id).all()
            for line in lines:
                debit = Decimal(str(line.debit or 0))
                credit = Decimal(str(line.credit or 0))
                total_amount += max(debit, credit)
            receipt_payment_info.append({
                "id": rp_doc.id,
                "code": rp_doc.code,
                "type": rp_doc.document_type,
                "amount": float(total_amount),
                "is_zero": total_amount == Decimal(0),
            })
    warehouse_document_ids = links.get("warehouse_document_ids") or []
    warehouse_info = []
    if warehouse_document_ids:
        from adapters.db.models.warehouse_document import WarehouseDocument

        warehouse_docs = db.query(WarehouseDocument).filter(
            WarehouseDocument.business_id == bid,
            WarehouseDocument.id.in_(warehouse_document_ids),
        ).all()
        for wd in warehouse_docs:
            status = getattr(wd, "status", None)
            warehouse_info.append({
                "id": wd.id,
                "code": getattr(wd, "code", ""),
                "status": status,
                "is_finalized": status == "finalized",
            })
    return mcp_jsonable({
        "invoice_id": invoice_id,
        "invoice_code": doc.code,
        "is_in_tax_workspace": is_in_tax_workspace,
        "tax_status": tax_status,
        "has_installments": has_installments,
        "installment_info": installment_info,
        "receipt_payment_documents": receipt_payment_info,
        "warehouse_documents": warehouse_info,
    })


def register_mcp_ops22_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(
        AIFunction(
            name="get_invoice_delete_info",
            description="پیش‌نمایش وابستگی‌های حذف فاکتور: کارپوشه مودیان، اقساط، دریافت/پرداخت و حواله انبار. extra_info خام برنمی‌گردد.",
            parameters_schema=INV_ID,
            handler=get_invoice_delete_info_handler,
            allowed_roles=roles,
            required_permissions=["invoices.read"],
            category="invoices",
            is_readonly=True,
        )
    )
