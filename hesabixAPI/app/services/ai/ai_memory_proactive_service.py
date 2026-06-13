"""پیشنهادها و هشدارهای proactive مرتبط با حافظه + بینش."""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext
from app.services.ai.ai_insight_service import get_business_insights_cached
from app.services.ai.ai_memory_service import get_memory, get_memory_content
from app.services.ai.ai_memory_structured import parse_structured, structured_to_prompt_block
from app.services.ai.prompt_service import get_prompt_by_key

logger = logging.getLogger(__name__)


def _goal_progress_alert(
    db: Session,
    insights: Dict[str, Any],
    structured: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
    goal = structured.get("sales_goal_monthly")
    if not goal or goal <= 0:
        return None

    kpis = insights.get("kpis") or {}
    sales_week = kpis.get("sales_last_7_days") or {}
    estimate_month = float(sales_week.get("total_net") or 0) * 4.33
    if estimate_month <= 0:
        return None

    pct = round((estimate_month / float(goal)) * 100, 1)
    if pct >= 100:
        level = "success"
        title = f"هدف فروش ماهانه ({goal:,.0f}) محقق شد"
        msg = f"فروش تخمینی ماه: ~{estimate_month:,.0f} ({pct}٪ از هدف)."
    elif pct < 50:
        level = "warning"
        title = "فاصله تا هدف فروش ماهانه"
        msg = f"تا هدف {goal:,.0f} حدود {pct}٪ پیشرفت دارید."
    else:
        return None

    return {
        "id": "memory_sales_goal",
        "level": level,
        "title": title,
        "message": msg,
        "action_prompt": get_prompt_by_key(db, "memory.goal_progress_action"),
        "source": "memory_insights",
    }


def get_memory_enriched_alerts(
    db: Session,
    business_id: int,
    ctx: AuthContext,
    base_alerts: Optional[List[Dict[str, Any]]] = None,
) -> List[Dict[str, Any]]:
    alerts: List[Dict[str, Any]] = list(base_alerts or [])
    seen_ids = {a.get("id") for a in alerts if a.get("id")}

    try:
        insights = get_business_insights_cached(db, business_id, ctx)
        row = get_memory(db, business_id, ctx.get_user_id())
        structured = parse_structured(row.structured if row else None)
        extra = _goal_progress_alert(db, insights, structured)
        if extra and extra["id"] not in seen_ids:
            alerts.append(extra)
    except Exception as exc:
        logger.warning("memory enriched alerts failed: %s", exc)

    return alerts[:8]


def get_memory_proactive_suggestions(
    db: Session,
    business_id: int,
    ctx: AuthContext,
) -> List[Dict[str, Any]]:
    suggestions: List[Dict[str, Any]] = []
    user_id = ctx.get_user_id()
    row = get_memory(db, business_id, user_id)
    content = get_memory_content(db, business_id, user_id)
    structured = parse_structured(row.structured if row else None)

    if not content.strip() and not structured_to_prompt_block(structured):
        suggestions.append(
            {
                "id": "fill_memory",
                "label": "تنظیم حافظه دستیار",
                "prompt": get_prompt_by_key(db, "memory.suggestion.fill"),
                "icon": "psychology",
                "kind": "memory",
            }
        )

    goal = structured.get("sales_goal_monthly")
    if goal and goal > 0:
        suggestions.append(
            {
                "id": "track_sales_goal",
                "label": "پیگیری هدف فروش",
                "prompt": get_prompt_by_key(
                    db,
                    "memory.suggestion.track_goal",
                    {"sales_goal": f"{goal:,.0f}"},
                ),
                "icon": "track_changes",
                "kind": "memory",
            }
        )

    return suggestions[:4]
