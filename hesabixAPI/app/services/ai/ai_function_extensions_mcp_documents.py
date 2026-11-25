"""MCP tools for the accounting-documents page: manual journal write cycle."""
from __future__ import annotations

from typing import Any, Dict, List

_MAX_BULK = 100
_MAX_LINES = 200


def _schema(properties: Dict[str, Any], required: list[str]) -> Dict[str, Any]:
    return {
        "type": "object",
        "properties": properties,
        "required": required,
        "additionalProperties": False,
    }


def _line_schema(*, update: bool = False) -> Dict[str, Any]:
    properties: Dict[str, Any] = {
        "account_id": {
            "type": "integer",
            "minimum": 1,
            "description": "شناسه سرفصل از list_accounts",
        },
        "person_id": {"type": ["integer", "null"], "minimum": 1},
        "product_id": {"type": ["integer", "null"], "minimum": 1},
        "bank_account_id": {"type": ["integer", "null"], "minimum": 1},
        "cash_register_id": {"type": ["integer", "null"], "minimum": 1},
        "petty_cash_id": {"type": ["integer", "null"], "minimum": 1},
        "check_id": {"type": ["integer", "null"], "minimum": 1},
        "quantity": {"type": ["number", "null"]},
        "debit": {"type": "number", "minimum": 0, "description": "بدهکار؛ با credit هر دو صفر نباشد"},
        "credit": {"type": "number", "minimum": 0, "description": "بستانکار؛ با debit هر دو صفر نباشد"},
        "description": {"type": ["string", "null"], "maxLength": 500},
    }
    if update:
        properties["id"] = {
            "type": "integer",
            "minimum": 1,
            "description": "شناسه سطر موجود برای ویرایش",
        }
    return {
        "type": "object",
        "properties": properties,
        "required": ["account_id"],
        "additionalProperties": False,
    }


def _raise_service(exc: BaseException) -> None:
    from app.core.responses import ApiError

    if isinstance(exc, ApiError):
        raise ValueError(exc.message) from exc
    raise exc


def _current_fiscal_year(db, business_id: int):
    from adapters.db.models.fiscal_year import FiscalYear

    fy = (
        db.query(FiscalYear)
        .filter(FiscalYear.business_id == business_id, FiscalYear.is_last == True)  # noqa: E712
        .first()
    )
    if not fy:
        raise ValueError(
            "سال مالی جاری برای این کسب‌وکار یافت نشد. ابتدا سال مالی ایجاد/فعال کنید."
        )
    return fy


def _tenant_document(db, business_id: int, document_id: int):
    from adapters.db.models.document import Document

    doc = (
        db.query(Document)
        .filter(Document.id == int(document_id), Document.business_id == int(business_id))
        .first()
    )
    if not doc:
        raise ValueError("سند در کسب‌وکار متصل پیدا نشد")
    return doc


def _require_delete_permission(ctx, db, business_id: int) -> None:
    from app.core.permissions import has_business_permission_for_business

    if not has_business_permission_for_business(
        ctx, db, business_id, "accounting_documents", "delete"
    ):
        raise ValueError("مجوز accounting_documents.delete برای حذف سند لازم است")


CREATE_MANUAL_DOCUMENT_SCHEMA = _schema(
    {
        "code": {
            "type": ["string", "null"],
            "maxLength": 50,
            "description": "کد سند؛ اگر خالی باشد خودکار تولید می‌شود",
        },
        "document_date": {"type": "string", "format": "date", "description": "تاریخ سند"},
        "currency_id": {"type": "integer", "minimum": 1, "description": "شناسه ارز از list_currencies"},
        "is_proforma": {"type": "boolean", "description": "پیش‌نویس/پیش‌فاکتور؛ پیش‌فرض false"},
        "description": {"type": ["string", "null"], "maxLength": 1000},
        "project_id": {"type": ["integer", "null"], "minimum": 1},
        "lines": {
            "type": "array",
            "minItems": 2,
            "maxItems": _MAX_LINES,
            "items": _line_schema(),
        },
    },
    ["document_date", "currency_id", "lines"],
)
UPDATE_MANUAL_DOCUMENT_SCHEMA = _schema(
    {
        "document_id": {"type": "integer", "minimum": 1},
        "code": {"type": ["string", "null"], "maxLength": 50},
        "document_date": {"type": "string", "format": "date"},
        "currency_id": {"type": "integer", "minimum": 1},
        "is_proforma": {"type": "boolean"},
        "description": {"type": ["string", "null"], "maxLength": 1000},
        "project_id": {"type": ["integer", "null"], "minimum": 1},
        "lines": {
            "type": "array",
            "minItems": 2,
            "maxItems": _MAX_LINES,
            "items": _line_schema(update=True),
        },
    },
    ["document_id"],
)
DELETE_MANUAL_DOCUMENT_SCHEMA = _schema(
    {"document_id": {"type": "integer", "minimum": 1}},
    ["document_id"],
)
BULK_DELETE_MANUAL_DOCUMENTS_SCHEMA = _schema(
    {
        "document_ids": {
            "type": "array",
            "minItems": 1,
            "maxItems": _MAX_BULK,
            "uniqueItems": True,
            "items": {"type": "integer", "minimum": 1},
        }
    },
    ["document_ids"],
)
TYPES_SUMMARY_SCHEMA = _schema({}, [])


def _line_amount(lines: List[Dict[str, Any]]) -> float:
    debit = sum(float(line.get("debit") or 0) for line in lines)
    credit = sum(float(line.get("credit") or 0) for line in lines)
    return max(abs(debit), abs(credit))


def _unique_ids(raw: List[Any], *, field: str) -> List[int]:
    ids = [int(value) for value in raw]
    if len(ids) != len(set(ids)):
        raise ValueError(f"{field} نباید شناسهٔ تکراری داشته باشد")
    return ids


def get_document_types_summary_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    from app.services.document_service import get_document_types_summary

    summary = get_document_types_summary(context["db"], int(context["business_id"]))
    counts = {str(key): int(value) for key, value in (summary or {}).items()}
    return {"summary": counts, "total": sum(counts.values())}


def create_manual_document_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.document_monetization_service import ensure_document_policy_allows_creation
    from app.services.document_service import create_manual_document

    db = context["db"]
    business_id = int(context["business_id"])
    user_id = int(context["user_context"].get_user_id())
    fy = _current_fiscal_year(db, business_id)
    lines = list(args.get("lines") or [])
    try:
        ensure_document_policy_allows_creation(
            db,
            business_id,
            document_type="manual",
            document_date=args.get("document_date"),
            amount=_line_amount(lines),
        )
        return create_manual_document(
            db,
            business_id,
            int(fy.id),
            user_id,
            {
                "code": args.get("code"),
                "document_date": args.get("document_date"),
                "currency_id": args.get("currency_id"),
                "is_proforma": bool(args.get("is_proforma", False)),
                "description": args.get("description"),
                "lines": lines,
                "project_id": args.get("project_id"),
            },
        )
    except Exception as exc:
        _raise_service(exc)


def update_manual_document_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.document_service import update_manual_document

    db = context["db"]
    business_id = int(context["business_id"])
    document_id = int(args["document_id"])
    doc = _tenant_document(db, business_id, document_id)
    if getattr(doc, "document_type", None) != "manual":
        raise ValueError(
            "فقط اسناد دستی (manual) قابل ویرایش هستند. اسناد خودکار را از منبع اصلی ویرایش کنید."
        )
    fy = _current_fiscal_year(db, business_id)
    doc_fy = getattr(doc, "fiscal_year_id", None)
    if doc_fy is not None and int(doc_fy) != int(fy.id):
        raise ValueError("ویرایش سند فقط در سال مالی جاری مجاز است.")
    data = {key: value for key, value in args.items() if key != "document_id"}
    try:
        return update_manual_document(db, document_id, data)
    except Exception as exc:
        _raise_service(exc)


def delete_manual_document_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    from app.services.document_service import delete_document

    db = context["db"]
    business_id = int(context["business_id"])
    document_id = int(args["document_id"])
    _require_delete_permission(context["user_context"], db, business_id)
    doc = _tenant_document(db, business_id, document_id)
    if getattr(doc, "document_type", None) != "manual":
        raise ValueError(
            "فقط اسناد دستی (manual) قابل حذف هستند. اسناد خودکار را از منبع اصلی حذف کنید."
        )
    try:
        success = delete_document(db, document_id)
    except Exception as exc:
        _raise_service(exc)
    return {"deleted": bool(success), "document_id": document_id}


def bulk_delete_manual_documents_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    from adapters.db.models.document import Document
    from app.core.responses import ApiError
    from app.services.document_service import delete_document

    db = context["db"]
    business_id = int(context["business_id"])
    ids = _unique_ids(args["document_ids"], field="document_ids")
    _require_delete_permission(context["user_context"], db, business_id)
    docs = (
        db.query(Document)
        .filter(Document.id.in_(ids), Document.business_id == business_id)
        .all()
    )
    found = {int(doc.id): doc for doc in docs}
    if len(found) != len(ids):
        raise ValueError("همهٔ شناسه‌ها باید متعلق به کسب‌وکار متصل باشند")

    deleted_ids: List[int] = []
    errors: List[Dict[str, Any]] = []
    skipped_auto: List[Dict[str, Any]] = []
    for doc_id in ids:
        doc = found[doc_id]
        if getattr(doc, "document_type", None) != "manual":
            skipped_auto.append(
                {
                    "id": doc_id,
                    "type": getattr(doc, "document_type", None),
                    "code": getattr(doc, "code", None),
                }
            )
            continue
        try:
            delete_document(db, doc_id)
            deleted_ids.append(doc_id)
        except ApiError as exc:
            errors.append({"id": doc_id, "error": exc.message})
        except Exception as exc:
            errors.append({"id": doc_id, "error": str(exc)})
    return {
        "deleted_count": len(deleted_ids),
        "deleted_ids": deleted_ids,
        "total_requested": len(ids),
        "errors": errors,
        "skipped_auto_documents": skipped_auto,
    }


def register_mcp_document_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(
        AIFunction(
            name="get_document_types_summary",
            description=(
                "خلاصهٔ تعداد اسناد کسب‌وکار متصل به تفکیک نوع (manual، invoice_sales، "
                "receipt، expense و غیره). فقط خواندنی است."
            ),
            parameters_schema=TYPES_SUMMARY_SCHEMA,
            handler=get_document_types_summary_handler,
            allowed_roles=roles,
            required_permissions=["accounting_documents.view"],
            category="accounting",
            is_readonly=True,
        )
    )
    registry.register(
        AIFunction(
            name="create_manual_document",
            description=(
                "ثبت سند حسابداری دستی متوازن در سال مالی جاری کسب‌وکار متصل. "
                "حداقل دو سطر با account_id از list_accounts؛ مجموع بدهکار باید برابر بستانکار باشد. "
                "سرفصل تفضیل اختیاری: person_id، product_id، bank_account_id، cash_register_id، "
                "petty_cash_id، check_id. extra_info پذیرفته نمی‌شود. نیاز به تأیید."
            ),
            parameters_schema=CREATE_MANUAL_DOCUMENT_SCHEMA,
            handler=create_manual_document_handler,
            allowed_roles=roles,
            required_permissions=["accounting_documents.write"],
            category="accounting",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )
    registry.register(
        AIFunction(
            name="update_manual_document",
            description=(
                "ویرایش سند دستی متعلق به کسب‌وکار متصل و فقط در سال مالی جاری. "
                "اسناد خودکار (فاکتور، دریافت، هزینه و غیره) رد می‌شوند. "
                "اگر lines ارسال شود جایگزین کامل سطرهاست و حداقل دو سطر متوازن لازم است. نیاز به تأیید."
            ),
            parameters_schema=UPDATE_MANUAL_DOCUMENT_SCHEMA,
            handler=update_manual_document_handler,
            allowed_roles=roles,
            required_permissions=["accounting_documents.write"],
            category="accounting",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )
    registry.register(
        AIFunction(
            name="delete_manual_document",
            description=(
                "حذف یک سند دستی متعلق به کسب‌وکار متصل. اسناد خودکار رد می‌شوند. "
                "عملیات برگشت‌ناپذیر و نیازمند تأیید است."
            ),
            parameters_schema=DELETE_MANUAL_DOCUMENT_SCHEMA,
            handler=delete_manual_document_handler,
            allowed_roles=roles,
            required_permissions=["accounting_documents.delete"],
            category="accounting",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )
    registry.register(
        AIFunction(
            name="bulk_delete_manual_documents",
            description=(
                f"حذف حداکثر {_MAX_BULK} سند دستی متعلق به کسب‌وکار متصل. "
                "اگر حتی یک شناسه خارج از این کسب‌وکار باشد کل درخواست رد می‌شود. "
                "اسناد خودکار نادیده گرفته می‌شوند. عملیات برگشت‌ناپذیر و نیازمند تأیید است."
            ),
            parameters_schema=BULK_DELETE_MANUAL_DOCUMENTS_SCHEMA,
            handler=bulk_delete_manual_documents_handler,
            allowed_roles=roles,
            required_permissions=["accounting_documents.delete"],
            category="accounting",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )
