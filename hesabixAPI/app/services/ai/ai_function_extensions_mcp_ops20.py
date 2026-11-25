"""MCP leftovers: receipt/payment and expense/income document details."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema

DOC_ID = mcp_schema({"document_id": {"type": "integer", "minimum": 1}}, ["document_id"])


def _public_doc(data: dict) -> dict:
    out = mcp_jsonable(data)
    if isinstance(out, dict):
        out.pop("extra_info", None)
    return out


def get_receipt_payment_handler(args, context):
    from app.services.receipt_payment_service import get_receipt_payment

    data = mcp_run(get_receipt_payment, mcp_db(context), int(args["document_id"]))
    if not data or int(data.get("business_id") or 0) != mcp_bid(context):
        raise ValueError("سند دریافت/پرداخت در کسب‌وکار متصل یافت نشد")
    return _public_doc(data)


def get_expense_income_handler(args, context):
    from app.services.expense_income_service import get_expense_income

    data = mcp_run(get_expense_income, mcp_db(context), int(args["document_id"]))
    if not data or int(data.get("business_id") or 0) != mcp_bid(context):
        raise ValueError("سند هزینه/درآمد در کسب‌وکار متصل یافت نشد")
    dtype = str(data.get("document_type") or "")
    if dtype not in ("expense", "income"):
        raise ValueError("این سند هزینه یا درآمد نیست")
    return _public_doc(data)


def register_mcp_ops20_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(
        AIFunction(
            name="get_receipt_payment",
            description="جزئیات یک سند دریافت یا پرداخت متعلق به کسب‌وکار متصل؛ extra_info برنمی‌گردد.",
            parameters_schema=DOC_ID,
            handler=get_receipt_payment_handler,
            allowed_roles=roles,
            required_permissions=["receipts_payments.read"],
            category="financial",
            is_readonly=True,
        )
    )
    registry.register(
        AIFunction(
            name="get_expense_income",
            description="جزئیات یک سند هزینه یا درآمد متعلق به کسب‌وکار متصل؛ extra_info برنمی‌گردد.",
            parameters_schema=DOC_ID,
            handler=get_expense_income_handler,
            allowed_roles=roles,
            required_permissions=["expenses_income.view"],
            category="financial",
            is_readonly=True,
        )
    )
