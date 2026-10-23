"""Bounded MCP bulk upserts for receipts/payments and expense/income documents."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.function_registry import AIRole, AIFunction

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
_MAX_ITEMS = 25


def _payload_schema(source: Dict[str, Any]) -> Dict[str, Any]:
    # Preserve the canonical AI field definitions and exclude arbitrary service fields.
    properties = dict(source.get("properties") or {})
    properties.pop("business_id", None)
    return {"type": "object", "properties": properties, "additionalProperties": False}


def _make_schema(source: Dict[str, Any], id_description: str) -> Dict[str, Any]:
    return {
        "type": "object",
        "properties": {
            "items": {
                "type": "array", "minItems": 1, "maxItems": _MAX_ITEMS,
                "items": {
                    "type": "object",
                    "properties": {
                        "client_ref": {"type": "string", "maxLength": 120},
                        "document_id": {"type": "integer", "minimum": 1, "description": id_description},
                        "payload": _payload_schema(source),
                    },
                    "required": ["payload"],
                    "additionalProperties": False,
                },
            }
        },
        "required": ["items"],
        "additionalProperties": False,
    }


def _bulk_handler(service_name: str, payload_builder_name: str, *, create_type: str):
    def handler(args: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
        from app.services.ai import ai_tool_payloads

        db = context["db"]
        business_id = int(context["business_id"])
        auth_context = context["user_context"]
        builder = getattr(ai_tool_payloads, payload_builder_name)
        update_builder_name = payload_builder_name.replace("build_create_", "build_update_", 1)
        update_builder = getattr(ai_tool_payloads, update_builder_name)
        normalized = []
        prep_errors = []
        original_indexes = []
        for index, item in enumerate(args["items"]):
            payload = dict(item["payload"])
            try:
                # The update builder omits document_type; the integration service
                # verifies the target's actual type and tenant before updating.
                selected_builder = update_builder if item.get("document_id") else builder
                clean = selected_builder(payload, db=db, business_id=business_id)
                normalized.append({
                    "client_ref": item.get("client_ref"),
                    "document_id": item.get("document_id"),
                    "payload": clean,
                })
                original_indexes.append(index)
            except (TypeError, ValueError, KeyError) as exc:
                prep_errors.append({
                    "index": index,
                    "client_ref": item.get("client_ref"),
                    "status": "failed",
                    "document_id": item.get("document_id"),
                    "error_code": "INVALID_PAYLOAD",
                    "message": str(exc),
                })

        results = list(prep_errors)
        if normalized:
            service_module = (
                "app.services.receipt_payment_bulk_upsert_service"
                if create_type == "receipt"
                else "app.services.expense_income_bulk_upsert_service"
            )
            service = __import__(service_module, fromlist=[service_name])
            result = getattr(service, service_name)(
                db, business_id, auth_context, {"items": normalized}
            )
            for compact_index, row in enumerate(result.get("results") or []):
                row = dict(row)
                if compact_index < len(original_indexes):
                    row["index"] = original_indexes[compact_index]
                results.append(row)
        results.sort(key=lambda row: int(row.get("index", 0)))
        summary = {
            "total": len(args["items"]),
            "created": sum(row.get("status") == "created" for row in results),
            "updated": sum(row.get("status") == "updated" for row in results),
            "failed": sum(row.get("status") == "failed" for row in results),
        }
        return {"results": results, "summary": summary}

    return handler


def register_mcp_bulk_financial_functions(registry) -> None:
    from app.services.ai.ai_tool_payloads import (
        CREATE_EXPENSE_INCOME_PARAMETERS_SCHEMA,
        CREATE_RECEIPT_PAYMENT_PARAMETERS_SCHEMA,
        CREATE_EXPENSE_INCOME_DESCRIPTION,
        CREATE_RECEIPT_PAYMENT_DESCRIPTION,
    )

    definitions = [
        (
            "bulk_upsert_receipts_payments",
            "receipts_payments.write",
            "receipt_payment",
            CREATE_RECEIPT_PAYMENT_PARAMETERS_SCHEMA,
            CREATE_RECEIPT_PAYMENT_DESCRIPTION,
            "bulk_upsert_receipts_payments_integration",
            "build_create_receipt_payment_payload",
            "receipt",
            "دریافت و پرداخت",
        ),
        (
            "bulk_upsert_expense_income",
            "expenses_income.write",
            "expense_income",
            CREATE_EXPENSE_INCOME_PARAMETERS_SCHEMA,
            CREATE_EXPENSE_INCOME_DESCRIPTION,
            "bulk_upsert_expense_income_integration",
            "build_create_expense_income_payload",
            "expense",
            "هزینه و درآمد",
        ),
    ]
    for name, permission, category, payload_schema, description, service, builder, kind, label in definitions:
        registry.register(AIFunction(
            name=name,
            description=(
                f"ثبت یا ویرایش گروهی حداکثر {_MAX_ITEMS} سند {label}. "
                "هر آیتم payload هم‌ساخت ابزار تک‌سندی است؛ document_id را فقط برای ویرایش بفرست. "
                "دسترسی افزودن/ویرایش هر مورد در کسب‌وکار متصل بررسی می‌شود. "
                "خطای یک مورد بقیه را متوقف نمی‌کند. نیاز به تأیید. " + description
            ),
            parameters_schema=_make_schema(payload_schema, "شناسه سند برای ویرایش؛ حذف شود تا سند جدید ساخته شود"),
            handler=_bulk_handler(service, builder, create_type=kind),
            allowed_roles=_ROLES,
            required_permissions=[permission],
            category=category,
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        ))

    def bulk_delete_expense_income(args: Dict[str, Any], context: Dict[str, Any]):
        from adapters.db.models.document import Document
        from app.core.permissions import has_business_permission_for_business
        from app.services.expense_income_service import delete_multiple_expense_income

        db, business_id, ctx = context["db"], int(context["business_id"]), context["user_context"]
        ids = [int(value) for value in args["document_ids"]]
        if len(set(ids)) != len(ids):
            raise ValueError("document_ids نباید شناسهٔ تکراری داشته باشد")
        docs = db.query(Document).filter(
            Document.id.in_(ids), Document.business_id == business_id,
            Document.document_type.in_(["expense", "income"]),
        ).all()
        if len(docs) != len(ids):
            raise ValueError("همهٔ اسناد باید هزینه/درآمد و متعلق به کسب‌وکار متصل باشند")
        if not has_business_permission_for_business(ctx, db, business_id, "expenses_income", "delete"):
            raise ValueError("مجوز expenses_income.delete برای حذف گروهی لازم است")
        if not delete_multiple_expense_income(db, ids):
            raise ValueError("حذف گروهی انجام نشد")
        return {"deleted_count": len(ids), "document_ids": ids}

    registry.register(AIFunction(
        name="bulk_delete_expense_income",
        description="حذف حداکثر ۱۰۰ سند هزینه/درآمد متعلق به کسب‌وکار متصل؛ همهٔ شناسه‌ها و مجوز حذف پیش از اجرا بررسی می‌شوند. عملیات برگشت‌ناپذیر و نیازمند تأیید است.",
        parameters_schema={
            "type": "object", "properties": {"document_ids": {
                "type": "array", "minItems": 1, "maxItems": 100, "uniqueItems": True,
                "items": {"type": "integer", "minimum": 1},
            }}, "required": ["document_ids"], "additionalProperties": False,
        },
        handler=bulk_delete_expense_income,
        allowed_roles=_ROLES,
        required_permissions=["expenses_income.delete"],
        category="financial",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
