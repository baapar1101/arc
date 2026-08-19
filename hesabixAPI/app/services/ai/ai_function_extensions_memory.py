"""
ابزارهای حافظهٔ واحد — فقط وقتی سوال از جنس خود حافظه است در allowlist می‌آیند.
یادگیری بین جلسات با کیوریتور است، نه با این ابزارها.
"""
from __future__ import annotations

from typing import Any, Dict, TYPE_CHECKING

from app.services.ai.ai_memory_service import (
    get_memory_payload,
    upsert_memory,
)
from app.services.ai.ai_memory_item_service import (
    memory_item_to_dict,
    soft_delete_memory_item,
    upsert_memory_item,
)
from app.services.ai.ai_memory_keys import canonical_kind
from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry

MEMORY_TOOL_NAMES = frozenset({
    "read_memory",
    "upsert_memory_entry",
    "delete_memory_entry",
})


def register_memory_functions(registry: "AIFunctionRegistry") -> None:
    create_handler = registry._create_handler  # noqa: SLF001

    def read_memory_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context["user_context"].get_user_id()
        return get_memory_payload(db, business_id, user_id)

    def upsert_memory_entry_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context["user_context"].get_user_id()
        content = str(args.get("content") or "").strip()
        if not content:
            raise ValueError("پارامتر content الزامی است")
        kind = canonical_kind(args.get("kind") or args.get("category"), default="context")
        if kind == "instruction":
            mode = str(args.get("mode") or "replace").strip().lower()
            if mode == "append":
                from app.services.ai.ai_memory_service import get_memory_content

                current = get_memory_content(db, business_id, user_id)
                merged = f"{current}\n{content}".strip() if current else content
                upsert_memory(db, business_id, user_id, merged)
            else:
                upsert_memory(db, business_id, user_id, content)
            return {
                "success": True,
                "kind": "instruction",
                "memory": get_memory_payload(db, business_id, user_id),
            }
        row = upsert_memory_item(
            db,
            business_id,
            user_id,
            item_key=args.get("item_key") or args.get("key"),
            category=kind,
            content=content,
            source="assistant",
            confidence=args.get("confidence"),
        )
        return {"success": True, "item": memory_item_to_dict(row)}

    def delete_memory_entry_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context["user_context"].get_user_id()
        item_key = args.get("item_key") or args.get("key")
        if item_key == "instruction" or args.get("kind") == "instruction":
            upsert_memory(db, business_id, user_id, "")
            return {"success": True, "deleted": True, "kind": "instruction"}
        ok = soft_delete_memory_item(
            db,
            business_id,
            user_id,
            item_id=args.get("item_id"),
            item_key=item_key,
        )
        if not ok:
            raise ValueError("آیتم حافظه یافت نشد")
        return {"success": True, "deleted": True}

    registry.register(
        AIFunction(
            name="read_memory",
            description=(
                "خواندن حافظهٔ پایدار کاربر در این کسب‌وکار: سیاست‌های همیشگی + هویت، "
                "ترجیح، زمینه، هدف و محدودیت. فقط وقتی کاربر دربارهٔ خود حافظه می‌پرسد."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "business_id": {"type": "integer"},
                },
            },
            handler=create_handler(read_memory_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="memory",
            is_readonly=True,
        )
    )

    registry.register(
        AIFunction(
            name="upsert_memory_entry",
            description=(
                "ذخیره یا به‌روزرسانی یک ورودی حافظه وقتی کاربر صریحاً می‌خواهد چیزی را "
                "به خاطر بسپاری یا سیاست همیشگی را عوض کند. kind=instruction برای سیاست‌ها؛ "
                "برای هویت/ترجیح/زمینه از کلید پایدار مثل identity.preferred_name استفاده کن. "
                "اعداد لحظه‌ای و خروجی tool ذخیره نکن."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "content": {"type": "string"},
                    "kind": {
                        "type": "string",
                        "enum": [
                            "instruction",
                            "identity",
                            "preference",
                            "context",
                            "goal",
                            "constraint",
                        ],
                    },
                    "item_key": {"type": "string"},
                    "mode": {
                        "type": "string",
                        "enum": ["append", "replace"],
                        "description": "فقط برای kind=instruction",
                    },
                    "confidence": {
                        "type": "string",
                        "enum": ["low", "medium", "high"],
                    },
                    "business_id": {"type": "integer"},
                },
                "required": ["content"],
            },
            handler=create_handler(upsert_memory_entry_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="memory",
            is_readonly=False,
            requires_approval=False,
            risk_level="medium",
        )
    )

    registry.register(
        AIFunction(
            name="delete_memory_entry",
            description="حذف یک ورودی حافظه با item_id یا item_key وقتی کاربر می‌خواهد فراموش شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "item_id": {"type": "integer"},
                    "item_key": {"type": "string"},
                    "kind": {"type": "string"},
                    "business_id": {"type": "integer"},
                },
            },
            handler=create_handler(delete_memory_entry_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="memory",
            is_readonly=False,
            requires_approval=False,
            risk_level="medium",
        )
    )
