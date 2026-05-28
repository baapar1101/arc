"""بستهٔ سرویس‌های AI — importهای سنگین به‌صورت lazy تا circular import نشود."""
from __future__ import annotations

from typing import TYPE_CHECKING

__all__ = ["registry", "AIFunction", "AIRole", "AIService"]


def __getattr__(name: str):
    if name == "registry":
        from app.services.ai.function_registry import registry

        return registry
    if name == "AIFunction":
        from app.services.ai.function_registry import AIFunction

        return AIFunction
    if name == "AIRole":
        from app.services.ai.function_registry import AIRole

        return AIRole
    if name == "AIService":
        from app.services.ai.ai_service import AIService

        return AIService
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")

