"""
ابزارهای حافظه بلندمدت دستیار AI.
"""
from __future__ import annotations

from typing import Any, Dict, TYPE_CHECKING

from app.services.ai.ai_memory_service import (
    append_to_memory,
    memory_to_dict,
    upsert_memory,
)
from app.services.ai.ai_memory_item_service import (
    list_memory_items,
    memory_item_to_dict,
    soft_delete_memory_item,
    upsert_memory_item,
)
from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry


def register_memory_functions(registry: "AIFunctionRegistry") -> None:
    create_handler = registry._create_handler  # noqa: SLF001

    def get_user_memory_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context["user_context"].get_user_id()
        from app.services.ai.ai_memory_service import get_memory

        row = get_memory(db, business_id, user_id)
        return memory_to_dict(row)

    def update_user_memory_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context["user_context"].get_user_id()
        mode = str(args.get("mode") or "append").strip().lower()
        content = str(args.get("content") or "").strip()
        structured_patch = args.get("structured")
        if not content and not structured_patch:
            raise ValueError("پارامتر content یا structured الزامی است")

        if mode == "replace" and content:
            row = upsert_memory(
                db,
                business_id,
                user_id,
                content,
                structured=structured_patch if isinstance(structured_patch, dict) else None,
            )
        elif structured_patch and isinstance(structured_patch, dict):
            from app.services.ai.ai_memory_service import upsert_structured_only

            if content:
                row = upsert_memory(
                    db,
                    business_id,
                    user_id,
                    content,
                    structured=structured_patch,
                )
            else:
                row = upsert_structured_only(db, business_id, user_id, structured_patch)
        else:
            row = append_to_memory(
                db,
                business_id,
                user_id,
                content,
                section_title=str(args.get("section_title") or "یادداشت دستیار"),
            )
        return {
            "success": True,
            "memory": memory_to_dict(row),
            "mode": mode,
        }

    registry.register(
        AIFunction(
            name="get_user_memory",
            description=(
                "خواندن حافظهٔ بلندمدت ترجیحات و اهداف کاربر برای این کسب‌وکار. "
                "قبل از پیشنهاد تغییر حافظه از این ابزار استفاده کن."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "business_id": {
                        "type": "integer",
                        "description": "شناسه کسب‌وکار (اختیاری — از context پر می‌شود)",
                    },
                },
            },
            handler=create_handler(get_user_memory_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="memory",
            is_readonly=True,
        )
    )

    registry.register(
        AIFunction(
            name="update_user_memory",
            description=(
                "به‌روزرسانی حافظهٔ بلندمدت کاربر (ترجیحات، اهداف، اصطلاحات). "
                "mode=append برای افزودن؛ mode=replace برای جایگزینی کامل. "
                "فقط حقایق پایدار را ذخیره کن، نه اعداد موقت یا دستور یک‌باره."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "content": {
                        "type": "string",
                        "description": "متن برای ذخیره در حافظه",
                    },
                    "mode": {
                        "type": "string",
                        "enum": ["append", "replace"],
                        "description": "append (پیش‌فرض) یا replace",
                    },
                    "section_title": {
                        "type": "string",
                        "description": "عنوان بخش هنگام append",
                    },
                    "business_id": {"type": "integer"},
                    "structured": {
                        "type": "object",
                        "description": "فیلدهای ساخت‌یافته اختیاری (هدف فروش، واحد پول، …)",
                    },
                },
            },
            handler=create_handler(update_user_memory_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="memory",
            is_readonly=False,
            requires_approval=True,
            risk_level="medium",
        )
    )

    def list_memory_items_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context["user_context"].get_user_id()
        category = args.get("category")
        limit = int(args.get("limit") or 40)
        rows = list_memory_items(
            db, business_id, user_id, category=category, limit=limit
        )
        return {
            "items": [memory_item_to_dict(r) for r in rows],
            "count": len(rows),
        }

    def upsert_memory_item_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context["user_context"].get_user_id()
        category = str(args.get("category") or "fact").strip().lower()
        content = str(args.get("content") or "").strip()
        if not content:
            raise ValueError("پارامتر content الزامی است")
        row = upsert_memory_item(
            db,
            business_id,
            user_id,
            item_key=args.get("item_key"),
            category=category,
            content=content,
            structured=args.get("structured") if isinstance(args.get("structured"), dict) else None,
            source="assistant",
            confidence=args.get("confidence"),
        )
        return {"success": True, "item": memory_item_to_dict(row)}

    def delete_memory_item_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context["user_context"].get_user_id()
        ok = soft_delete_memory_item(
            db,
            business_id,
            user_id,
            item_id=args.get("item_id"),
            item_key=args.get("item_key"),
        )
        if not ok:
            raise ValueError("آیتم حافظه یافت نشد")
        return {"success": True, "deleted": True}

    registry.register(
        AIFunction(
            name="list_memory_items",
            description="فهرست آیتم‌های حافظهٔ بلندمدت (ترجیحات، اصطلاحات، حقایق).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "business_id": {"type": "integer"},
                    "category": {
                        "type": "string",
                        "enum": ["fact", "term", "preference", "goal", "hint"],
                    },
                    "limit": {"type": "integer", "description": "حداکثر ۵۰"},
                },
            },
            handler=create_handler(list_memory_items_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="memory",
            is_readonly=True,
        )
    )

    registry.register(
        AIFunction(
            name="upsert_memory_item",
            description=(
                "ذخیره یا به‌روزرسانی یک آیتم حافظه (کلید یکتا). "
                "برای fact/term/preference بدون تأیید کاربر. goal نیاز تأیید دارد."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "item_key": {"type": "string", "description": "کلید یکتا (اختیاری)"},
                    "category": {
                        "type": "string",
                        "enum": ["fact", "term", "preference", "goal", "hint"],
                    },
                    "content": {"type": "string"},
                    "structured": {"type": "object"},
                    "confidence": {"type": "string", "enum": ["low", "medium", "high"]},
                    "business_id": {"type": "integer"},
                },
                "required": ["content"],
            },
            handler=create_handler(upsert_memory_item_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="memory",
            is_readonly=False,
            requires_approval=False,
            risk_level="safe",
        )
    )

    registry.register(
        AIFunction(
            name="delete_memory_item",
            description="حذف نرم یک آیتم حافظه با item_id یا item_key.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "item_id": {"type": "integer"},
                    "item_key": {"type": "string"},
                    "business_id": {"type": "integer"},
                },
            },
            handler=create_handler(delete_memory_item_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="memory",
            is_readonly=False,
            requires_approval=False,
            risk_level="safe",
        )
    )
