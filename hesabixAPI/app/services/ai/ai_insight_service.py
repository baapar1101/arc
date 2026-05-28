"""
موتور بینش AI — KPI و هشدارهای از پیش‌محاسبه‌شده برای تزریق به prompt و UI.
"""
from __future__ import annotations

import json
import logging
import time
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, func
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from app.core.auth_dependency import AuthContext
from app.services.invoice_service import INVOICE_SALES

logger = logging.getLogger(__name__)

# کش درون‌پردازه‌ای بینش برای prompt (کلید: business_id, user_id)
_insights_prompt_cache: dict[tuple[int, int], tuple[float, Dict[str, Any]]] = {}


def _safe_float(value: Any) -> float:
    try:
        if value is None:
            return 0.0
        if isinstance(value, Decimal):
            return float(value)
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _invoice_net_total(doc: Document) -> float:
    extra = doc.extra_info if isinstance(doc.extra_info, dict) else {}
    totals = extra.get("totals") if isinstance(extra.get("totals"), dict) else {}
    net = totals.get("net") or totals.get("gross") or 0
    return _safe_float(net)


def _sales_in_range(
    db: Session,
    business_id: int,
    date_from: date,
    date_to: date,
) -> Dict[str, Any]:
    q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == INVOICE_SALES,
            Document.is_proforma == False,  # noqa: E712
            Document.document_date >= date_from,
            Document.document_date <= date_to,
        )
    )
    docs = q.all()
    total_net = sum(_invoice_net_total(d) for d in docs)
    return {"count": len(docs), "total_net": round(total_net, 2)}


def _weekly_sales_series(
    db: Session,
    business_id: int,
    weeks: int = 4,
) -> List[Dict[str, Any]]:
    today = date.today()
    series: List[Dict[str, Any]] = []
    for i in range(weeks - 1, -1, -1):
        end = today - timedelta(days=7 * i)
        start = end - timedelta(days=6)
        stats = _sales_in_range(db, business_id, start, end)
        series.append(
            {
                "label": f"{start.isoformat()} تا {end.isoformat()}",
                "short_label": f"هفته {weeks - i}",
                "total_net": stats["total_net"],
                "count": stats["count"],
            }
        )
    return series


def _debtors_snapshot(db: Session, business_id: int, ctx: AuthContext) -> Dict[str, Any]:
    try:
        from app.services.person_service import get_debtors_report

        report = get_debtors_report(
            db=db,
            business_id=business_id,
            take=5,
            skip=0,
            min_balance=1,
        )
        summary = report.get("summary") or {}
        items = report.get("items") or []
        top = []
        for row in items[:3]:
            if not isinstance(row, dict):
                continue
            top.append(
                {
                    "name": row.get("name") or row.get("alias_name") or "—",
                    "balance": _safe_float(row.get("balance")),
                }
            )
        return {
            "total_count": int(summary.get("total_count") or 0),
            "total_debt": _safe_float(summary.get("total_debt")),
            "top": top,
        }
    except Exception as exc:
        logger.warning("debtors insight failed: %s", exc)
        return {"total_count": 0, "total_debt": 0.0, "top": [], "error": str(exc)}


def _low_stock_snapshot(db: Session, business_id: int) -> Dict[str, Any]:
    try:
        from app.services.warehouse_service import get_warehouse_stock_report

        report = get_warehouse_stock_report(
            db,
            business_id,
            {"include_zero": False},
        )
        items = report.get("items") or []
        low: List[Dict[str, Any]] = []
        for row in items:
            if not isinstance(row, dict):
                continue
            stock = _safe_float(row.get("stock") or row.get("quantity"))
            reorder = _safe_float(row.get("reorder_point") or row.get("min_stock"))
            if reorder > 0 and stock <= reorder:
                low.append(
                    {
                        "product_name": row.get("product_name") or row.get("name"),
                        "stock": stock,
                        "reorder_point": reorder,
                    }
                )
            elif stock <= 0:
                low.append(
                    {
                        "product_name": row.get("product_name") or row.get("name"),
                        "stock": stock,
                        "reorder_point": reorder,
                    }
                )
        low.sort(key=lambda x: x.get("stock", 0))
        return {"count": len(low), "items": low[:5]}
    except Exception as exc:
        logger.warning("inventory insight failed: %s", exc)
        return {"count": 0, "items": [], "error": str(exc)}


def get_business_insights_cached(
    db: Session,
    business_id: int,
    ctx: AuthContext,
    *,
    ttl_sec: float | None = None,
) -> Dict[str, Any]:
    """بینش با کش کوتاه‌مدت برای کاهش queryهای تکراری در prompt."""
    from app.services.ai.ai_constants import INSIGHTS_CACHE_TTL_SEC

    if not ctx.can_access_business(business_id):
        return {"error": "FORBIDDEN"}

    user_id = int(ctx.get_user_id() or 0)
    cache_key = (int(business_id), user_id)
    ttl = ttl_sec if ttl_sec is not None else float(INSIGHTS_CACHE_TTL_SEC)
    now = time.monotonic()
    cached = _insights_prompt_cache.get(cache_key)
    if cached and (now - cached[0]) < ttl:
        return cached[1]

    data = get_business_insights(db, business_id, ctx)
    _insights_prompt_cache[cache_key] = (now, data)
    return data


def get_business_insights(
    db: Session,
    business_id: int,
    ctx: AuthContext,
) -> Dict[str, Any]:
    """بسته کامل بینش برای API و prompt."""
    if not ctx.can_access_business(business_id):
        return {"error": "FORBIDDEN"}

    today = date.today()
    week_ago = today - timedelta(days=6)
    prev_week_start = today - timedelta(days=13)
    prev_week_end = today - timedelta(days=7)

    sales_today = _sales_in_range(db, business_id, today, today)
    sales_week = _sales_in_range(db, business_id, week_ago, today)
    sales_prev_week = _sales_in_range(db, business_id, prev_week_start, prev_week_end)
    weekly_series = _weekly_sales_series(db, business_id, weeks=4)

    week_change_pct: Optional[float] = None
    if sales_prev_week["total_net"] > 0:
        week_change_pct = round(
            ((sales_week["total_net"] - sales_prev_week["total_net"]) / sales_prev_week["total_net"])
            * 100,
            1,
        )

    debtors = _debtors_snapshot(db, business_id, ctx)
    inventory = _low_stock_snapshot(db, business_id)

    alerts: List[Dict[str, str]] = []

    # هشدار کالاهای کم‌موجود
    if inventory.get("count", 0) > 0:
        items_preview = ", ".join(
            i.get("product_name", "") for i in (inventory.get("items") or [])[:3]
        )
        alerts.append(
            {
                "level": "warning",
                "title": f"{inventory['count']} کالای کم‌موجود",
                "message": items_preview or f"{inventory['count']} کالا کم‌موجود یا ناموجود است.",
                "action_prompt": "لیست کامل کالاهای کم‌موجود انبار را با جزئیات نشان بده.",
            }
        )

    # هشدار بدهکاران
    total_debt = debtors.get("total_debt", 0)
    if total_debt > 0:
        top_debtor = (debtors.get("top") or [{}])[0]
        top_name = top_debtor.get("name", "")
        alerts.append(
            {
                "level": "info",
                "title": "بدهکاران",
                "message": f"مجموع بدهی: {total_debt:,.0f}" + (f" — بیشترین: {top_name}" if top_name else ""),
                "action_prompt": "لیست بدهکاران کسب‌وکار با مانده‌حساب را نشان بده.",
            }
        )

    # هشدار افت فروش هفتگی
    if week_change_pct is not None and week_change_pct < -15:
        alerts.append(
            {
                "level": "warning",
                "title": "افت فروش هفتگی",
                "message": f"فروش هفتگی {week_change_pct}% کاهش یافته.",
                "action_prompt": "تحلیل کن چرا فروش این هفته کاهش داشته و پیشنهادات بهبود بده.",
            }
        )
    elif week_change_pct is not None and week_change_pct > 15:
        alerts.append(
            {
                "level": "success",
                "title": "رشد فروش هفتگی",
                "message": f"فروش هفتگی {week_change_pct}% رشد داشته.",
                "action_prompt": "تحلیل کن کدام محصولات یا مشتریان بیشترین سهم در رشد فروش این هفته داشتند.",
            }
        )

    # هشدار فروش صفر امروز
    if sales_today.get("count", 0) == 0:
        today_weekday = date.today().weekday()
        if today_weekday < 5:  # روزهای کاری (شنبه تا چهارشنبه)
            alerts.append(
                {
                    "level": "warning",
                    "title": "هنوز فروشی ثبت نشده",
                    "message": "امروز هیچ فاکتور فروشی ثبت نشده است.",
                    "action_prompt": "بررسی کن چه محصولاتی را باید امروز به مشتریان پیشنهاد داد.",
                }
            )

    chart_spec = {
        "type": "bar",
        "title": "فروش ۴ هفته اخیر",
        "labels": [w["short_label"] for w in weekly_series],
        "values": [w["total_net"] for w in weekly_series],
        "unit": "مبلغ خالص",
    }

    return {
        "generated_at": datetime.utcnow().isoformat(),
        "business_id": business_id,
        "kpis": {
            "sales_today": sales_today,
            "sales_last_7_days": sales_week,
            "sales_prev_7_days": sales_prev_week,
            "week_over_week_change_percent": week_change_pct,
            "debtors": debtors,
            "low_stock": inventory,
        },
        "alerts": alerts,
        "charts": [chart_spec],
        "weekly_sales": weekly_series,
    }


def format_insights_for_prompt(
    insights: Dict[str, Any],
    *,
    db: Any = None,
    business_id: Optional[int] = None,
    user_id: Optional[int] = None,
) -> str:
    """متن فشرده برای system prompt."""
    if insights.get("error"):
        return ""

    kpis = insights.get("kpis") or {}
    sales_today = kpis.get("sales_today") or {}
    sales_week = kpis.get("sales_last_7_days") or {}
    debtors = kpis.get("debtors") or {}
    inventory = kpis.get("low_stock") or {}
    wow = kpis.get("week_over_week_change_percent")

    lines = [
        "\n\n--- داده‌های لحظه‌ای کسب‌وکار (برای تحلیل؛ در صورت نیاز با tool تأیید کن) ---",
        f"فروش امروز: {sales_today.get('count', 0)} فاکتور، مبلغ خالص {sales_today.get('total_net', 0):,.0f}",
        f"فروش ۷ روز اخیر: {sales_week.get('count', 0)} فاکتور، مبلغ خالص {sales_week.get('total_net', 0):,.0f}",
    ]
    if wow is not None:
        lines.append(f"تغییر فروش هفتگی نسبت به هفته قبل: {wow}%")
    lines.append(
        f"بدهکاران: {debtors.get('total_count', 0)} نفر، مجموع بدهی {debtors.get('total_debt', 0):,.0f}"
    )
    if debtors.get("top"):
        for d in debtors["top"]:
            lines.append(f"  - {d.get('name')}: {d.get('balance', 0):,.0f}")
    lines.append(f"کالاهای کم‌موجود: {inventory.get('count', 0)}")
    for item in (inventory.get("items") or [])[:3]:
        lines.append(
            f"  - {item.get('product_name')}: موجودی {item.get('stock')}"
        )
    alerts = insights.get("alerts") or []
    if alerts:
        lines.append("هشدارها:")
        for a in alerts:
            lines.append(f"  • {a.get('message')}")
    charts = insights.get("charts") or []
    if charts:
        try:
            chart_json = json.dumps(charts[0], ensure_ascii=False)
            lines.append("نمودار پیشنهادی برای کپی در پاسخ:")
            lines.append(f"```chart\n{chart_json}\n```")
        except (TypeError, ValueError):
            pass

    if db is not None and business_id is not None and user_id is not None:
        try:
            from app.services.ai.ai_memory_service import format_memory_goal_hint_for_insights

            hint = format_memory_goal_hint_for_insights(db, int(business_id), int(user_id), insights)
            if hint:
                lines.append(hint)
        except Exception as exc:
            logger.debug("memory goal hint for insights skipped: %s", exc)

    return "\n".join(lines)


def get_dynamic_suggestions(
    db: Session,
    business_id: int,
    ctx: AuthContext,
) -> List[Dict[str, Any]]:
    """پیشنهادهای شروع گفتگو بر اساس وضعیت واقعی کسب‌وکار."""
    base = [
        {
            "label": "خلاصه وضعیت امروز",
            "prompt": "با توجه به داده‌های لحظه‌ای، خلاصه وضعیت مالی امروز کسب‌وکارم را بده.",
            "icon": "dashboard",
        },
        {
            "label": "راهنمای ثبت فاکتور",
            "prompt": "گام‌به‌گام نحوه ثبت فاکتور فروش در حسابیکس را توضیح بده.",
            "icon": "receipt",
        },
    ]

    try:
        insights = get_business_insights(db, business_id, ctx)
    except Exception:
        return base

    kpis = insights.get("kpis") or {}
    dynamic: List[Dict[str, Any]] = []

    sales_week = kpis.get("sales_last_7_days") or {}
    if sales_week.get("total_net", 0) > 0:
        dynamic.append(
            {
                "label": "تحلیل فروش هفتگی",
                "prompt": "فروش ۷ روز اخیر را تحلیل کن و روند را با نمودار نشان بده.",
                "icon": "trending_up",
            }
        )

    debtors = kpis.get("debtors") or {}
    if debtors.get("total_count", 0) > 0:
        dynamic.append(
            {
                "label": "پیگیری بدهکاران",
                "prompt": "مهم‌ترین بدهکاران و پیشنهاد پیگیری را ارائه کن.",
                "icon": "people",
            }
        )

    inventory = kpis.get("low_stock") or {}
    if inventory.get("count", 0) > 0:
        dynamic.append(
            {
                "label": "هشدار موجودی",
                "prompt": "کالاهای کم‌موجود را لیست کن و پیشنهاد سفارش مجدد بده.",
                "icon": "inventory",
            }
        )

    wow = kpis.get("week_over_week_change_percent")
    if wow is not None and wow < -10:
        dynamic.append(
            {
                "label": "علت افت فروش",
                "prompt": "چرا فروش هفتگی افت کرده؟ علل محتمل و اقدامات اصلاحی را بگو.",
                "icon": "warning",
            }
        )

    seen_labels = set()
    merged: List[Dict[str, Any]] = []
    for item in dynamic + base:
        label = item["label"]
        if label in seen_labels:
            continue
        seen_labels.add(label)
        merged.append(item)
        if len(merged) >= 6:
            break
    return merged


def get_proactive_alerts(
    db: Session,
    business_id: int,
    ctx: AuthContext,
) -> List[Dict[str, Any]]:
    """
    هشدارهای ساخت‌یافته برای بنر UI (بدون نیاز به ارسال پیام).
    """
    try:
        insights = get_business_insights(db, business_id, ctx)
    except Exception as exc:
        logger.warning("proactive alerts failed: %s", exc)
        return []

    if insights.get("error"):
        return []

    alerts: List[Dict[str, Any]] = []
    for a in insights.get("alerts") or []:
        alerts.append(
            {
                "id": f"insight_{len(alerts)}",
                "level": a.get("level", "info"),
                "title": a.get("message", ""),
                "message": a.get("message", ""),
                "action_prompt": None,
            }
        )

    kpis = insights.get("kpis") or {}
    sales_today = kpis.get("sales_today") or {}
    sales_week = kpis.get("sales_last_7_days") or {}
    debtors = kpis.get("debtors") or {}
    inventory = kpis.get("low_stock") or {}

    if sales_today.get("count", 0) == 0 and sales_week.get("total_net", 0) > 0:
        alerts.append(
            {
                "id": "no_sales_today",
                "level": "info",
                "title": "امروز هنوز فاکتور فروشی ثبت نشده",
                "message": "در ۷ روز اخیر فروش داشته‌اید؛ وضعیت امروز را بررسی کنید.",
                "action_prompt": "وضعیت فروش امروز را با فروش هفتگی مقایسه کن.",
            }
        )

    if debtors.get("total_debt", 0) > 50_000_000:
        alerts.append(
            {
                "id": "high_receivables",
                "level": "warning",
                "title": "بدهی مشتریان بالا است",
                "message": f"مجموع بدهی: {debtors.get('total_debt', 0):,.0f}",
                "action_prompt": "لیست بدهکاران مهم و پیشنهاد پیگیری را بده.",
            }
        )

    if inventory.get("count", 0) >= 3:
        alerts.append(
            {
                "id": "critical_stock",
                "level": "warning",
                "title": f"{inventory['count']} کالا نیاز به تأمین دارد",
                "message": "موجودی چند کالا به نقطه سفارش رسیده یا تمام شده.",
                "action_prompt": "کالاهای کم‌موجود را اولویت‌بندی و پیشنهاد سفارش بده.",
            }
        )

    wow = kpis.get("week_over_week_change_percent")
    if wow is not None and wow > 25:
        alerts.append(
            {
                "id": "sales_surge",
                "level": "success",
                "title": "رشد قوی فروش هفتگی",
                "message": f"فروش هفتگی {wow}% نسبت به هفته قبل رشد کرده.",
                "action_prompt": "علت رشد فروش را تحلیل کن.",
            }
        )

    dedup: List[Dict[str, Any]] = []
    seen: set[str] = set()
    for item in alerts:
        key = item.get("id") or item.get("title")
        if key in seen:
            continue
        seen.add(str(key))
        dedup.append(item)
    return dedup[:8]
