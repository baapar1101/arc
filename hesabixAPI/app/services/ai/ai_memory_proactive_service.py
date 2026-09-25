"""پیشنهادهای مرتبط با حافظه (نسخهٔ دو لایه)."""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext
from app.services.ai.ai_memory_service import get_memory_content
from app.services.ai.ai_memory_item_service import count_active_items
from app.services.ai.prompt_service import get_prompt_by_key

logger = logging.getLogger(__name__)


def get_memory_enriched_alerts(
    db: Session,
    business_id: int,
    ctx: AuthContext,
    base_alerts: Optional[List[Dict[str, Any]]] = None,
) -> List[Dict[str, Any]]:
    """هشدارهای هدف ساخت‌یافته حذف شدند — فقط alerts پایه."""
    return list(base_alerts or [])[:8]


def get_memory_proactive_suggestions(
    db: Session,
    business_id: int,
    ctx: AuthContext,
) -> List[Dict[str, Any]]:
    suggestions: List[Dict[str, Any]] = []
    user_id = ctx.get_user_id()
    instructions = get_memory_content(db, business_id, user_id)
    learned = 0
    try:
        learned = count_active_items(db, business_id, user_id)
    except Exception:
        pass

    if not instructions.strip() and learned == 0:
        suggestions.append(
            {
                "id": "fill_memory",
                "label": "تنظیم حافظه دستیار",
                "prompt": get_prompt_by_key(db, "memory.suggestion.fill"),
                "icon": "psychology",
                "kind": "memory",
            }
        )

    return suggestions[:4]
