"""ابزارهای spawn / await / cancel برای subagent موقت (AGT-06)."""
from __future__ import annotations

from typing import Any, Dict, TYPE_CHECKING

from app.services.ai.ai_constants import MAX_SUBAGENT_ITERATIONS, MAX_SUBAGENTS_PER_PARENT
from app.services.ai.ai_subagent import SUBAGENT_TOOL_NAMES
from app.services.ai.function_registry import AIFunction, AIRole

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry


def register_subagent_functions(registry: "AIFunctionRegistry") -> None:
    create_handler = registry._create_handler  # noqa: SLF001

    def spawn_subagent_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        return {
            "ok": False,
            "error": "SPAWN_REQUIRES_ASYNC",
            "message": "spawn_subagent فقط از مسیر async حلقهٔ ایجنت اجرا می‌شود.",
        }

    def await_subagent_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        return {
            "ok": False,
            "error": "AWAIT_REQUIRES_ASYNC",
            "message": "await_subagent فقط از مسیر async حلقهٔ ایجنت اجرا می‌شود.",
        }

    def cancel_subagent_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.ai.ai_subagent import cancel_subagent_sync

        return cancel_subagent_sync(
            args.get("subagent_id") or args.get("id"),
            session_id=context.get("session_id"),
        )

    registry.register(
        AIFunction(
            name="spawn_subagent",
            description=(
                "یک زیر-ایجنت فقط‌خواندنی برای یک حوزهٔ جدا (مثلاً فروش یا موجودی) بساز. "
                f"حداکثر {MAX_SUBAGENTS_PER_PARENT} فرزند همزمان و {MAX_SUBAGENT_ITERATIONS} نوبت ابزار. "
                "فقط برای سوال چنددامنه‌ای؛ سوال ساده را خودت با ابزار مستقیم جواب بده. "
                "tool_allowlist را با نام ابزارهای read همان حوزه پر کن. نوشتن در فرزند ممنوع است."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "goal": {
                        "type": "string",
                        "description": "هدف مشخص زیر-ایجنت به فارسی",
                    },
                    "tool_allowlist": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "نام ابزارهای read مجاز برای فرزند",
                    },
                    "max_iterations": {
                        "type": "integer",
                        "description": f"سقف نوبت ابزار فرزند (حداکثر {MAX_SUBAGENT_ITERATIONS})",
                    },
                    "wait": {
                        "type": "boolean",
                        "description": "صبر تا اتمام (پیش‌فرض true). اگر false، بعداً await_subagent بزن",
                    },
                },
                "required": ["goal"],
            },
            handler=create_handler(spawn_subagent_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="agent",
            is_readonly=True,
            requires_approval=False,
            risk_level="safe",
            is_agent_internal=True,
        )
    )

    registry.register(
        AIFunction(
            name="await_subagent",
            description="منتظر اتمام یک subagent که با wait=false ساخته شده باش.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "subagent_id": {
                        "type": "string",
                        "description": "شناسه برگشتی spawn_subagent",
                    },
                },
                "required": ["subagent_id"],
            },
            handler=create_handler(await_subagent_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="agent",
            is_readonly=True,
            requires_approval=False,
            risk_level="safe",
            is_agent_internal=True,
        )
    )

    registry.register(
        AIFunction(
            name="cancel_subagent",
            description="قطع یک subagent در حال اجرا تا دیگر توکن مصرف نکند.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "subagent_id": {
                        "type": "string",
                        "description": "شناسه زیر-ایجنت",
                    },
                },
                "required": ["subagent_id"],
            },
            handler=create_handler(cancel_subagent_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="agent",
            is_readonly=True,
            requires_approval=False,
            risk_level="safe",
            is_agent_internal=True,
        )
    )


__all__ = ["register_subagent_functions", "SUBAGENT_TOOL_NAMES"]
