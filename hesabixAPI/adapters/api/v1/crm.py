# noqa: D100
"""
API endpoints برای CRM: فرایندها، مراحل، سرنخ، فرصت فروش، فعالیت
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Path, Body, Query, Request
from sqlalchemy.orm import Session, joinedload, selectinload
from sqlalchemy import and_, or_, text

from adapters.db.session import get_db
from adapters.db.models.crm import (
    CrmProcessDefinition,
    CrmProcessStage,
    Lead,
    Deal,
    CrmActivity,
    CrmChangeHistory,
)
from adapters.api.v1.schema_models.crm import (
    CrmProcessDefinitionCreate,
    CrmProcessDefinitionUpdate,
    CrmProcessDefinitionResponse,
    CrmProcessStageCreate,
    CrmProcessStageUpdate,
    CrmProcessStageResponse,
    LeadCreate,
    LeadUpdate,
    LeadResponse,
    LeadConvertRequest,
    DealCreate,
    DealUpdate,
    DealResponse,
    CrmActivityCreate,
    CrmActivityUpdate,
    CrmActivityResponse,
    CrmNoteTypeCreate,
    CrmNoteTypeUpdate,
    CrmNoteCreate,
    CrmNoteUpdate,
    CrmNoteCommentCreate,
)
from adapters.db.models.person import Person, PersonType
from adapters.api.v1.schema_models.person import PersonCreateRequest
from app.services.person_service import create_person
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.services import crm_calendar_note_service as crm_cal_notes

router = APIRouter(prefix="/crm", tags=["CRM"])


@router.get(
    "/businesses/{business_id}/summary",
    summary="خلاصه CRM",
    description="تعداد سرنخ‌ها، فرصت‌های فروش، مبلغ کل و نرخ تبدیل",
)
@require_business_access("business_id")
async def get_crm_summary(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    row = db.execute(
        text(
            """
            SELECT
              (SELECT COUNT(*) FROM crm_leads WHERE business_id = :bid) AS total_leads,
              (SELECT COUNT(*) FROM crm_leads WHERE business_id = :bid AND person_id IS NOT NULL) AS converted_leads,
              (SELECT COUNT(*) FROM crm_deals WHERE business_id = :bid) AS total_deals,
              (SELECT COALESCE(SUM(amount), 0) FROM crm_deals WHERE business_id = :bid) AS total_deals_amount,
              (SELECT COUNT(*) FROM crm_deals WHERE business_id = :bid AND closed_at IS NOT NULL) AS closed_deals
            """
        ),
        {"bid": business_id},
    ).mappings().first()
    total_leads = int(row["total_leads"] or 0) if row else 0
    converted_leads = int(row["converted_leads"] or 0) if row else 0
    total_deals = int(row["total_deals"] or 0) if row else 0
    deals_amount = float(row["total_deals_amount"] or 0) if row else 0.0
    closed_deals = int(row["closed_deals"] or 0) if row else 0
    conversion_rate = (converted_leads / total_leads * 100) if total_leads else 0
    data = {
        "total_leads": total_leads,
        "converted_leads": converted_leads,
        "conversion_rate": round(conversion_rate, 1),
        "total_deals": total_deals,
        "closed_deals": closed_deals,
        "total_deals_amount": float(deals_amount),
    }
    return success_response(data=data, request=request)


@router.get(
    "/businesses/{business_id}/follow-ups-today",
    summary="پیگیری‌های امروز",
    description="سرنخ‌ها و فرصت‌های فروش با یادآور پیگیری در امروز یا روزهای آینده (تا ۷ روز)",
)
@require_business_access("business_id")
async def get_follow_ups_today(
    request: Request,
    business_id: int = Path(..., gt=0),
    days_ahead: int = Query(7, ge=0, le=30, description="تعداد روزهای آینده"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    from datetime import datetime, timedelta
    start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=days_ahead)
    current_user_id = ctx.get_user_id()
    restrict_assignee = bool(
        current_user_id and not (ctx.is_superadmin() or ctx.is_business_owner(business_id))
    )
    q_leads = (
        db.query(Lead)
        .options(
            selectinload(Lead.stage),
            selectinload(Lead.assigned_to),
            selectinload(Lead.person),
            selectinload(Lead.created_by),
        )
        .filter(
            Lead.business_id == business_id,
            Lead.next_follow_up_at.isnot(None),
            Lead.next_follow_up_at >= start,
            Lead.next_follow_up_at <= end,
            Lead.person_id.is_(None),
        )
    )
    if restrict_assignee:
        q_leads = q_leads.filter(or_(Lead.assigned_to_user_id.is_(None), Lead.assigned_to_user_id == current_user_id))
    q_leads = q_leads.order_by(Lead.next_follow_up_at).limit(50)
    q_deals = (
        db.query(Deal)
        .options(
            selectinload(Deal.stage),
            selectinload(Deal.assigned_to),
            selectinload(Deal.person),
            selectinload(Deal.created_by),
        )
        .filter(
            Deal.business_id == business_id,
            Deal.closed_at.is_(None),
            Deal.next_follow_up_at.isnot(None),
            Deal.next_follow_up_at >= start,
            Deal.next_follow_up_at <= end,
        )
    )
    if restrict_assignee:
        q_deals = q_deals.filter(or_(Deal.assigned_to_user_id.is_(None), Deal.assigned_to_user_id == current_user_id))
    q_deals = q_deals.order_by(Deal.next_follow_up_at).limit(50)
    leads = q_leads.all()
    deals = q_deals.all()
    data = {
        "leads": [_lead_to_dict(l, request) for l in leads],
        "deals": [_deal_to_dict(d, request) for d in deals],
    }
    return success_response(data=data, request=request)


@router.get(
    "/businesses/{business_id}/reports/pipeline",
    summary="گزارش پایپلاین فروش",
    description="تعداد و مبلغ فرصت‌ها به تفکیک مرحله. با from_date و to_date فقط فرصت‌های ایجادشده در این بازه شمرده می‌شوند.",
)
@require_business_access("business_id")
async def get_pipeline_report(
    request: Request,
    business_id: int = Path(..., gt=0),
    process_definition_id: Optional[int] = Query(None, description="شناسه فرایند پایپلاین"),
    from_date: Optional[str] = Query(None, description="از تاریخ (YYYY-MM-DD) - فیلتر بر اساس created_at"),
    to_date: Optional[str] = Query(None, description="تا تاریخ (YYYY-MM-DD)"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    from sqlalchemy import func
    from datetime import datetime as dt
    deal_filter = and_(Deal.stage_id == CrmProcessStage.id, Deal.business_id == business_id)
    if from_date:
        try:
            fd = dt.strptime(from_date, "%Y-%m-%d").date()
            deal_filter = and_(deal_filter, func.date(Deal.created_at) >= fd)
        except ValueError:
            pass
    if to_date:
        try:
            td = dt.strptime(to_date, "%Y-%m-%d").date()
            deal_filter = and_(deal_filter, func.date(Deal.created_at) <= td)
        except ValueError:
            pass
    q = db.query(
        CrmProcessStage.id,
        CrmProcessStage.name,
        CrmProcessStage.order_index,
        func.count(Deal.id).label("deal_count"),
        func.coalesce(func.sum(Deal.amount), 0).label("total_amount"),
    ).outerjoin(Deal, deal_filter)
    q = q.join(CrmProcessDefinition, CrmProcessDefinition.id == CrmProcessStage.process_definition_id)
    q = q.filter(
        CrmProcessDefinition.business_id == business_id,
        CrmProcessDefinition.process_type == "sales_pipeline",
    )
    if process_definition_id:
        q = q.filter(CrmProcessDefinition.id == process_definition_id)
    q = q.group_by(CrmProcessStage.id, CrmProcessStage.name, CrmProcessStage.order_index)
    q = q.order_by(CrmProcessStage.order_index)
    rows = q.all()
    data = [
        {
            "stage_id": r.id,
            "stage_name": r.name,
            "order_index": r.order_index,
            "deal_count": r.deal_count,
            "total_amount": float(r.total_amount or 0),
        }
        for r in rows
    ]
    return success_response(data=data, request=request)


@router.get(
    "/businesses/{business_id}/reports/lead-funnel",
    summary="گزارش قیف سرنخ",
    description="تعداد سرنخ به تفکیک مرحله. با from_date و to_date فقط سرنخ‌های ایجادشده در این بازه شمرده می‌شوند.",
)
@require_business_access("business_id")
async def get_lead_funnel_report(
    request: Request,
    business_id: int = Path(..., gt=0),
    process_definition_id: Optional[int] = Query(None),
    from_date: Optional[str] = Query(None, description="از تاریخ (YYYY-MM-DD)"),
    to_date: Optional[str] = Query(None, description="تا تاریخ (YYYY-MM-DD)"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    from sqlalchemy import func
    from datetime import datetime as dt
    lead_filter = and_(Lead.stage_id == CrmProcessStage.id, Lead.business_id == business_id)
    if from_date:
        try:
            fd = dt.strptime(from_date, "%Y-%m-%d").date()
            lead_filter = and_(lead_filter, func.date(Lead.created_at) >= fd)
        except ValueError:
            pass
    if to_date:
        try:
            td = dt.strptime(to_date, "%Y-%m-%d").date()
            lead_filter = and_(lead_filter, func.date(Lead.created_at) <= td)
        except ValueError:
            pass
    q = db.query(
        CrmProcessStage.id,
        CrmProcessStage.name,
        CrmProcessStage.order_index,
        func.count(Lead.id).label("lead_count"),
    ).outerjoin(Lead, lead_filter)
    q = q.join(CrmProcessDefinition, CrmProcessDefinition.id == CrmProcessStage.process_definition_id)
    q = q.filter(
        CrmProcessDefinition.business_id == business_id,
        CrmProcessDefinition.process_type == "lead_funnel",
    )
    if process_definition_id:
        q = q.filter(CrmProcessDefinition.id == process_definition_id)
    q = q.group_by(CrmProcessStage.id, CrmProcessStage.name, CrmProcessStage.order_index)
    q = q.order_by(CrmProcessStage.order_index)
    rows = q.all()
    data = [
        {"stage_id": r.id, "stage_name": r.name, "order_index": r.order_index, "lead_count": r.lead_count}
        for r in rows
    ]
    return success_response(data=data, request=request)


@router.get(
    "/businesses/{business_id}/reports/lead-sources",
    summary="گزارش منبع سرنخ",
    description="تعداد سرنخ به تفکیک منبع",
)
@require_business_access("business_id")
async def get_lead_sources_report(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    from sqlalchemy import func
    q = (
        db.query(Lead.source_code, func.count(Lead.id).label("count"))
        .filter(Lead.business_id == business_id, Lead.source_code.isnot(None), Lead.source_code != "")
        .group_by(Lead.source_code)
    )
    rows = q.all()
    data = [{"source_code": r.source_code, "count": r.count} for r in rows]
    return success_response(data=data, request=request)


@router.get(
    "/businesses/{business_id}/reports/weighted-forecast",
    summary="پیش‌بینی درآمد (مبلغ موزون)",
    description="مجموع مبلغ فرصت‌های باز ضرب در احتمال موفقیت (پیش‌بینی درآمد مورد انتظار)",
)
@require_business_access("business_id")
async def get_weighted_forecast_report(
    request: Request,
    business_id: int = Path(..., gt=0),
    process_definition_id: Optional[int] = Query(None, description="فیلتر پایپلاین"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    from sqlalchemy import func
    from sqlalchemy.sql import case
    q = (
        db.query(
            func.coalesce(
                func.sum(Deal.amount * func.coalesce(Deal.probability_percent, 50) / 100),
                0,
            ).label("weighted_total"),
            func.count(Deal.id).label("deal_count"),
            func.coalesce(func.sum(Deal.amount), 0).label("total_amount"),
        )
        .filter(Deal.business_id == business_id, Deal.closed_at.is_(None))
    )
    if process_definition_id:
        q = q.filter(Deal.process_definition_id == process_definition_id)
    row = q.first()
    data = {
        "weighted_total": float(row.weighted_total or 0),
        "total_amount": float(row.total_amount or 0),
        "deal_count": row.deal_count or 0,
    }
    return success_response(data=data, request=request)


@router.get(
    "/businesses/{business_id}/reports/employee-performance",
    summary="گزارش عملکرد کارمندان",
    description="مقایسه عملکرد کارمندان بر اساس سرنخ، فرصت فروش و فعالیت",
)
@require_business_access("business_id")
async def get_employee_performance_report(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    user_ids: set[int] = set()
    for (uid,) in (
        db.query(Lead.assigned_to_user_id)
        .filter(Lead.business_id == business_id, Lead.assigned_to_user_id.isnot(None))
        .distinct()
        .all()
    ):
        if uid:
            user_ids.add(int(uid))
    for (uid,) in (
        db.query(Deal.assigned_to_user_id)
        .filter(Deal.business_id == business_id, Deal.assigned_to_user_id.isnot(None))
        .distinct()
        .all()
    ):
        if uid:
            user_ids.add(int(uid))
    for (uid,) in db.query(CrmActivity.created_by_user_id).filter(CrmActivity.business_id == business_id).distinct().all():
        user_ids.add(int(uid))

    restricted_to_self = False
    current_user_id = ctx.get_user_id()
    if current_user_id and not (
        ctx.is_superadmin()
        or ctx.is_business_owner(business_id)
        or ctx.has_business_permission("crm", "reports_team")
    ):
        restricted_to_self = True
        user_ids = {uid for uid in user_ids if uid == current_user_id}
        if not user_ids:
            user_ids = {int(current_user_id)}

    if not user_ids:
        return success_response(data=[], restricted_to_self=restricted_to_self, request=request)

    ids_sql = ",".join(str(int(x)) for x in sorted(user_ids))
    sql = text(
        f"""
        WITH u AS (SELECT unnest(ARRAY[{ids_sql}]::int[]) AS uid)
        SELECT u.uid AS user_id,
          usr.first_name AS first_name,
          usr.last_name AS last_name,
          (SELECT COUNT(*)::int FROM crm_leads l
            WHERE l.business_id = :bid AND l.assigned_to_user_id = u.uid) AS leads_count,
          (SELECT COUNT(*)::int FROM crm_leads l
            WHERE l.business_id = :bid AND l.assigned_to_user_id = u.uid AND l.person_id IS NOT NULL) AS converted_leads,
          (SELECT COUNT(*)::int FROM crm_deals d
            WHERE d.business_id = :bid AND d.assigned_to_user_id = u.uid) AS deals_count,
          (SELECT COUNT(*)::int FROM crm_deals d
            WHERE d.business_id = :bid AND d.assigned_to_user_id = u.uid AND d.closed_at IS NOT NULL) AS closed_deals,
          (SELECT COALESCE(SUM(d.amount), 0)::float FROM crm_deals d
            WHERE d.business_id = :bid AND d.assigned_to_user_id = u.uid) AS total_amount,
          (SELECT COUNT(*)::int FROM crm_activities a
            WHERE a.business_id = :bid AND a.created_by_user_id = u.uid) AS activities_count
        FROM u
        JOIN users usr ON usr.id = u.uid
        ORDER BY total_amount DESC NULLS LAST, deals_count DESC
        """
    )
    rows = db.execute(sql, {"bid": business_id}).mappings().all()
    result = []
    for r in rows:
        fn = (r.get("first_name") or "").strip()
        ln = (r.get("last_name") or "").strip()
        nm = f"{fn} {ln}".strip() or str(r["user_id"])
        lc = int(r["leads_count"] or 0)
        cc = int(r["converted_leads"] or 0)
        conv_rate = (cc / lc * 100) if lc else 0
        result.append(
            {
                "user_id": int(r["user_id"]),
                "user_name": nm,
                "leads_count": lc,
                "converted_leads": cc,
                "conversion_rate": round(conv_rate, 1),
                "deals_count": int(r["deals_count"] or 0),
                "closed_deals": int(r["closed_deals"] or 0),
                "total_amount": float(r["total_amount"] or 0),
                "activities_count": int(r["activities_count"] or 0),
            }
        )
    return success_response(data=result, restricted_to_self=restricted_to_self, request=request)


@router.get(
    "/businesses/{business_id}/reports/sales-trend",
    summary="روند فروش در زمان",
    description="تعداد و مبلغ فرصت‌های بسته‌شده در بازه زمانی",
)
@require_business_access("business_id")
async def get_sales_trend_report(
    request: Request,
    business_id: int = Path(..., gt=0),
    period: str = Query("month", description="day | week | month"),
    months: int = Query(6, ge=1, le=24, description="تعداد ماه گذشته"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    from sqlalchemy import func
    from datetime import datetime, timedelta

    end_dt = datetime.utcnow()
    start_dt = end_dt - timedelta(days=months * 31)

    try:
        q = (
            db.query(func.date(Deal.closed_at).label("period"), func.count(Deal.id).label("count"), func.coalesce(func.sum(Deal.amount), 0).label("amount"))
            .filter(
                Deal.business_id == business_id,
                Deal.closed_at.isnot(None),
                Deal.closed_at >= start_dt,
                Deal.closed_at <= end_dt,
            )
            .group_by(func.date(Deal.closed_at))
        )
        rows = q.all()
        raw_data = [{"period": str(r.period), "count": r.count, "amount": float(r.amount or 0)} for r in rows]
        if period == "month":
            by_month: Dict[str, Any] = {}
            for r in raw_data:
                p = r["period"]
                month_key = p[:7] if len(p) >= 7 else p
                if month_key not in by_month:
                    by_month[month_key] = {"period": month_key, "count": 0, "amount": 0}
                by_month[month_key]["count"] += r["count"]
                by_month[month_key]["amount"] += r["amount"]
            data = sorted(by_month.values(), key=lambda x: x["period"])
        else:
            data = sorted(raw_data, key=lambda x: x["period"])
    except Exception:
        q = (
            db.query(func.date(Deal.closed_at).label("period"), func.count(Deal.id).label("count"), func.coalesce(func.sum(Deal.amount), 0).label("amount"))
            .filter(Deal.business_id == business_id, Deal.closed_at.isnot(None))
            .group_by(func.date(Deal.closed_at))
        )
        rows = q.all()
        data = [{"period": str(r.period), "count": r.count, "amount": float(r.amount or 0)} for r in rows]
        data.sort(key=lambda x: x["period"])

    return success_response(data=data, request=request)


def _stage_to_dict(stage: CrmProcessStage, request: Request = None) -> Dict[str, Any]:
    d = {
        "id": stage.id,
        "process_definition_id": stage.process_definition_id,
        "stage_code": stage.stage_code,
        "name": stage.name,
        "order_index": stage.order_index,
        "color": stage.color,
        "is_win": stage.is_win,
        "is_lost": stage.is_lost,
        "allow_transition_to": stage.allow_transition_to,
        "created_at": stage.created_at.isoformat(),
        "updated_at": stage.updated_at.isoformat(),
    }
    if request:
        d = format_datetime_fields(d, request)
    return d


def _process_to_dict(p: CrmProcessDefinition, request: Request = None, include_stages: bool = True) -> Dict[str, Any]:
    d = {
        "id": p.id,
        "business_id": p.business_id,
        "process_type": p.process_type,
        "code": p.code,
        "name": p.name,
        "description": p.description,
        "is_default": p.is_default,
        "is_active": p.is_active,
        "created_at": p.created_at.isoformat(),
        "updated_at": p.updated_at.isoformat(),
        "created_by_user_id": p.created_by_user_id,
    }
    if include_stages and p.stages:
        d["stages"] = [_stage_to_dict(s, request) for s in p.stages]
    if request:
        d = format_datetime_fields(d, request)
    return d


def _log_crm_change(
    db: Session,
    business_id: int,
    entity_type: str,
    entity_id: int,
    field_name: str,
    old_value: Any,
    new_value: Any,
    user_id: int,
) -> None:
    """ثبت یک رکورد در تاریخچه تغییرات CRM."""
    if old_value == new_value:
        return
    old_s = str(old_value) if old_value is not None else ""
    new_s = str(new_value) if new_value is not None else ""
    if old_s == new_s:
        return
    rec = CrmChangeHistory(
        business_id=business_id,
        entity_type=entity_type,
        entity_id=entity_id,
        field_name=field_name,
        old_value=old_s[:4000] if len(old_s) > 4000 else old_s,
        new_value=new_s[:4000] if len(new_s) > 4000 else new_s,
        changed_by_user_id=user_id,
    )
    db.add(rec)


# --- فرایندها (Process Definitions) ---


@router.get(
    "/businesses/{business_id}/process-definitions",
    summary="لیست فرایندهای CRM",
    description="دریافت لیست فرایندهای تعریف‌شده برای کسب‌وکار (فانل سرنخ، pipeline فروش، انواع فعالیت)",
)
@require_business_access("business_id")
async def list_process_definitions(
    request: Request,
    business_id: int = Path(..., gt=0),
    process_type: Optional[str] = Query(None, description="فیلتر نوع: lead_funnel | sales_pipeline | activity_type | lead_source"),
    is_active: Optional[bool] = Query(None),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    q = (
        db.query(CrmProcessDefinition)
        .options(selectinload(CrmProcessDefinition.stages))
        .filter(CrmProcessDefinition.business_id == business_id)
    )
    if process_type:
        q = q.filter(CrmProcessDefinition.process_type == process_type)
    if is_active is not None:
        q = q.filter(CrmProcessDefinition.is_active == is_active)
    items = q.order_by(CrmProcessDefinition.process_type, CrmProcessDefinition.code).all()
    data = [_process_to_dict(p, request) for p in items]
    return success_response(data=data, request=request)


@router.post(
    "/businesses/{business_id}/process-definitions",
    summary="ایجاد فرایند CRM",
    description="تعریف فرایند جدید (فانل سرنخ یا pipeline فروش) با مراحل",
)
@require_business_access("business_id")
async def create_process_definition(
    request: Request,
    business_id: int = Path(..., gt=0),
    body: CrmProcessDefinitionCreate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    # یکتا بودن code در همان business و process_type
    existing = (
        db.query(CrmProcessDefinition)
        .filter(
            and_(
                CrmProcessDefinition.business_id == business_id,
                CrmProcessDefinition.process_type == body.process_type,
                CrmProcessDefinition.code == body.code,
            )
        )
        .first()
    )
    if existing:
        raise ApiError("CRM_PROCESS_CODE_EXISTS", f"فرایند با کد {body.code} از قبل وجود دارد.", http_status=400)
    proc = CrmProcessDefinition(
        business_id=business_id,
        process_type=body.process_type,
        code=body.code,
        name=body.name,
        description=body.description,
        is_default=body.is_default,
        is_active=body.is_active,
        created_by_user_id=ctx.get_user_id(),
    )
    db.add(proc)
    db.flush()
    for i, s in enumerate(body.stages or []):
        stage = CrmProcessStage(
            process_definition_id=proc.id,
            stage_code=s.stage_code,
            name=s.name,
            order_index=s.order_index,
            color=s.color,
            is_win=s.is_win,
            is_lost=s.is_lost,
            allow_transition_to=s.allow_transition_to,
        )
        db.add(stage)
    db.commit()
    db.refresh(proc)
    return success_response(data=_process_to_dict(proc, request), request=request, message="CRM_PROCESS_CREATED")


@router.get(
    "/businesses/{business_id}/process-definitions/{definition_id}",
    summary="جزئیات فرایند",
)
@require_business_access("business_id")
async def get_process_definition(
    request: Request,
    business_id: int = Path(..., gt=0),
    definition_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    proc = (
        db.query(CrmProcessDefinition)
        .filter(
            and_(
                CrmProcessDefinition.id == definition_id,
                CrmProcessDefinition.business_id == business_id,
            )
        )
        .first()
    )
    if not proc:
        raise ApiError("NOT_FOUND", "فرایند یافت نشد.", http_status=404)
    return success_response(data=_process_to_dict(proc, request), request=request)


@router.put(
    "/businesses/{business_id}/process-definitions/{definition_id}",
    summary="ویرایش فرایند",
)
@require_business_access("business_id")
async def update_process_definition(
    request: Request,
    business_id: int = Path(..., gt=0),
    definition_id: int = Path(..., gt=0),
    body: CrmProcessDefinitionUpdate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    proc = (
        db.query(CrmProcessDefinition)
        .filter(
            and_(
                CrmProcessDefinition.id == definition_id,
                CrmProcessDefinition.business_id == business_id,
            )
        )
        .first()
    )
    if not proc:
        raise ApiError("NOT_FOUND", "فرایند یافت نشد.", http_status=404)
    if body.name is not None:
        proc.name = body.name
    if body.description is not None:
        proc.description = body.description
    if body.is_default is not None:
        proc.is_default = body.is_default
    if body.is_active is not None:
        proc.is_active = body.is_active
    db.commit()
    db.refresh(proc)
    return success_response(data=_process_to_dict(proc, request), request=request, message="CRM_PROCESS_UPDATED")


@router.delete(
    "/businesses/{business_id}/process-definitions/{definition_id}",
    summary="حذف فرایند",
)
@require_business_access("business_id")
async def delete_process_definition(
    request: Request,
    business_id: int = Path(..., gt=0),
    definition_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    proc = (
        db.query(CrmProcessDefinition)
        .filter(
            and_(
                CrmProcessDefinition.id == definition_id,
                CrmProcessDefinition.business_id == business_id,
            )
        )
        .first()
    )
    if not proc:
        raise ApiError("NOT_FOUND", "فرایند یافت نشد.", http_status=404)
    # بررسی استفاده در Lead/Deal
    if db.query(Lead).filter(Lead.process_definition_id == definition_id).first():
        raise ApiError("CRM_PROCESS_IN_USE", "این فرایند در سرنخ‌ها استفاده شده و قابل حذف نیست.", http_status=400)
    if db.query(Deal).filter(Deal.process_definition_id == definition_id).first():
        raise ApiError("CRM_PROCESS_IN_USE", "این فرایند در فرصت‌های فروش استفاده شده و قابل حذف نیست.", http_status=400)
    db.delete(proc)
    db.commit()
    return success_response(message="CRM_PROCESS_DELETED", request=request)


# --- مراحل (Stages) ---


@router.get(
    "/businesses/{business_id}/process-definitions/{definition_id}/stages",
    summary="لیست مراحل یک فرایند",
)
@require_business_access("business_id")
async def list_stages(
    request: Request,
    business_id: int = Path(..., gt=0),
    definition_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    proc = (
        db.query(CrmProcessDefinition)
        .filter(
            and_(
                CrmProcessDefinition.id == definition_id,
                CrmProcessDefinition.business_id == business_id,
            )
        )
        .first()
    )
    if not proc:
        raise ApiError("NOT_FOUND", "فرایند یافت نشد.", http_status=404)
    stages = db.query(CrmProcessStage).filter(CrmProcessStage.process_definition_id == definition_id).order_by(CrmProcessStage.order_index).all()
    data = [_stage_to_dict(s, request) for s in stages]
    return success_response(data=data, request=request)


@router.post(
    "/businesses/{business_id}/process-definitions/{definition_id}/stages",
    summary="افزودن مرحله به فرایند",
)
@require_business_access("business_id")
async def create_stage(
    request: Request,
    business_id: int = Path(..., gt=0),
    definition_id: int = Path(..., gt=0),
    body: CrmProcessStageCreate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    proc = (
        db.query(CrmProcessDefinition)
        .filter(
            and_(
                CrmProcessDefinition.id == definition_id,
                CrmProcessDefinition.business_id == business_id,
            )
        )
        .first()
    )
    if not proc:
        raise ApiError("NOT_FOUND", "فرایند یافت نشد.", http_status=404)
    existing = (
        db.query(CrmProcessStage)
        .filter(
            and_(
                CrmProcessStage.process_definition_id == definition_id,
                CrmProcessStage.stage_code == body.stage_code,
            )
        )
        .first()
    )
    if existing:
        raise ApiError("CRM_STAGE_CODE_EXISTS", f"مرحله با کد {body.stage_code} از قبل وجود دارد.", http_status=400)
    stage = CrmProcessStage(
        process_definition_id=definition_id,
        stage_code=body.stage_code,
        name=body.name,
        order_index=body.order_index,
        color=body.color,
        is_win=body.is_win,
        is_lost=body.is_lost,
        allow_transition_to=body.allow_transition_to,
    )
    db.add(stage)
    db.commit()
    db.refresh(stage)
    return success_response(data=_stage_to_dict(stage, request), request=request, message="CRM_STAGE_CREATED")


@router.put(
    "/businesses/{business_id}/process-definitions/{definition_id}/stages/{stage_id}",
    summary="ویرایش مرحله",
)
@require_business_access("business_id")
async def update_stage(
    request: Request,
    business_id: int = Path(..., gt=0),
    definition_id: int = Path(..., gt=0),
    stage_id: int = Path(..., gt=0),
    body: CrmProcessStageUpdate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    proc = (
        db.query(CrmProcessDefinition)
        .filter(
            and_(
                CrmProcessDefinition.id == definition_id,
                CrmProcessDefinition.business_id == business_id,
            )
        )
        .first()
    )
    if not proc:
        raise ApiError("NOT_FOUND", "فرایند یافت نشد.", http_status=404)
    stage = (
        db.query(CrmProcessStage)
        .filter(
            and_(
                CrmProcessStage.id == stage_id,
                CrmProcessStage.process_definition_id == definition_id,
            )
        )
        .first()
    )
    if not stage:
        raise ApiError("NOT_FOUND", "مرحله یافت نشد.", http_status=404)
    if body.stage_code is not None:
        stage.stage_code = body.stage_code
    if body.name is not None:
        stage.name = body.name
    if body.order_index is not None:
        stage.order_index = body.order_index
    if body.color is not None:
        stage.color = body.color
    if body.is_win is not None:
        stage.is_win = body.is_win
    if body.is_lost is not None:
        stage.is_lost = body.is_lost
    if body.allow_transition_to is not None:
        stage.allow_transition_to = body.allow_transition_to
    db.commit()
    db.refresh(stage)
    return success_response(data=_stage_to_dict(stage, request), request=request, message="CRM_STAGE_UPDATED")


@router.delete(
    "/businesses/{business_id}/process-definitions/{definition_id}/stages/{stage_id}",
    summary="حذف مرحله",
)
@require_business_access("business_id")
async def delete_stage(
    request: Request,
    business_id: int = Path(..., gt=0),
    definition_id: int = Path(..., gt=0),
    stage_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    proc = (
        db.query(CrmProcessDefinition)
        .filter(
            and_(
                CrmProcessDefinition.id == definition_id,
                CrmProcessDefinition.business_id == business_id,
            )
        )
        .first()
    )
    if not proc:
        raise ApiError("NOT_FOUND", "فرایند یافت نشد.", http_status=404)
    stage = (
        db.query(CrmProcessStage)
        .filter(
            and_(
                CrmProcessStage.id == stage_id,
                CrmProcessStage.process_definition_id == definition_id,
            )
        )
        .first()
    )
    if not stage:
        raise ApiError("NOT_FOUND", "مرحله یافت نشد.", http_status=404)
    if db.query(Lead).filter(Lead.stage_id == stage_id).first():
        raise ApiError("CRM_STAGE_IN_USE", "این مرحله در سرنخ‌ها استفاده شده است.", http_status=400)
    if db.query(Deal).filter(Deal.stage_id == stage_id).first():
        raise ApiError("CRM_STAGE_IN_USE", "این مرحله در فرصت‌های فروش استفاده شده است.", http_status=400)
    db.delete(stage)
    db.commit()
    return success_response(message="CRM_STAGE_DELETED", request=request)


# --- سرنخ (Leads) ---


def _lead_to_dict(lead: Lead, request: Request = None) -> Dict[str, Any]:
    d = {
        "id": lead.id,
        "business_id": lead.business_id,
        "code": lead.code,
        "process_definition_id": lead.process_definition_id,
        "stage_id": lead.stage_id,
        "stage_name": lead.stage.name if lead.stage else None,
        "source_code": lead.source_code,
        "name": lead.name,
        "company_name": lead.company_name,
        "mobile": lead.mobile,
        "email": lead.email,
        "description": lead.description,
        "assigned_to_user_id": lead.assigned_to_user_id,
        "assigned_to_name": (
            f"{lead.assigned_to.first_name or ''} {lead.assigned_to.last_name or ''}".strip()
            if lead.assigned_to else None
        ),
        "next_follow_up_at": lead.next_follow_up_at.isoformat() if lead.next_follow_up_at else None,
        "person_id": lead.person_id,
        "person_name": lead.person.alias_name if lead.person else None,
        "converted_at": lead.converted_at.isoformat() if lead.converted_at else None,
        "created_at": lead.created_at.isoformat(),
        "updated_at": lead.updated_at.isoformat(),
        "created_by_user_id": lead.created_by_user_id,
        "created_by_name": (
            f"{lead.created_by.first_name or ''} {lead.created_by.last_name or ''}".strip()
            if lead.created_by else None
        ),
    }
    if request:
        d = format_datetime_fields(d, request)
    return d


@router.get(
    "/businesses/{business_id}/leads",
    summary="لیست سرنخ‌ها",
)
@require_business_access("business_id")
async def list_leads(
    request: Request,
    business_id: int = Path(..., gt=0),
    process_definition_id: Optional[int] = Query(None),
    stage_id: Optional[int] = Query(None),
    assigned_to_user_id: Optional[int] = Query(None),
    search: Optional[str] = Query(None, description="جستجو در نام، شرکت، موبایل، ایمیل"),
    from_date: Optional[str] = Query(None, description="از تاریخ ایجاد (YYYY-MM-DD)"),
    to_date: Optional[str] = Query(None, description="تا تاریخ ایجاد (YYYY-MM-DD)"),
    open_only: Optional[bool] = Query(None, description="فقط سرنخ تبدیل‌نشده"),
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    from datetime import datetime as dt
    from sqlalchemy import func as sa_func

    q = (
        db.query(Lead)
        .options(
            selectinload(Lead.stage),
            selectinload(Lead.assigned_to),
            selectinload(Lead.person),
            selectinload(Lead.created_by),
        )
        .filter(Lead.business_id == business_id)
    )
    if process_definition_id:
        q = q.filter(Lead.process_definition_id == process_definition_id)
    if stage_id:
        q = q.filter(Lead.stage_id == stage_id)
    if assigned_to_user_id is not None:
        q = q.filter(Lead.assigned_to_user_id == assigned_to_user_id)
    if open_only is True:
        q = q.filter(Lead.person_id.is_(None))
    if from_date:
        try:
            fd = dt.strptime(from_date, "%Y-%m-%d").date()
            q = q.filter(sa_func.date(Lead.created_at) >= fd)
        except ValueError:
            pass
    if to_date:
        try:
            td = dt.strptime(to_date, "%Y-%m-%d").date()
            q = q.filter(sa_func.date(Lead.created_at) <= td)
        except ValueError:
            pass
    if search and search.strip():
        term = f"%{search.strip()}%"
        q = q.filter(
            or_(
                Lead.name.ilike(term),
                Lead.company_name.ilike(term),
                Lead.mobile.ilike(term),
                Lead.email.ilike(term),
            )
        )
    total = q.count()
    items = q.order_by(Lead.created_at.desc()).offset((page - 1) * limit).limit(limit).all()
    data = [_lead_to_dict(lead, request) for lead in items]
    return success_response(
        data={"items": data, "total": total, "page": page, "limit": limit},
        request=request,
    )


@router.post(
    "/businesses/{business_id}/leads",
    summary="ایجاد سرنخ",
)
@require_business_access("business_id")
async def create_lead(
    request: Request,
    business_id: int = Path(..., gt=0),
    body: LeadCreate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    proc = (
        db.query(CrmProcessDefinition)
        .filter(
            and_(
                CrmProcessDefinition.id == body.process_definition_id,
                CrmProcessDefinition.business_id == business_id,
            )
        )
        .first()
    )
    if not proc:
        raise ApiError("NOT_FOUND", "فرایند یافت نشد.", http_status=404)
    stage = (
        db.query(CrmProcessStage)
        .filter(
            and_(
                CrmProcessStage.id == body.stage_id,
                CrmProcessStage.process_definition_id == body.process_definition_id,
            )
        )
        .first()
    )
    if not stage:
        raise ApiError("NOT_FOUND", "مرحله یافت نشد.", http_status=404)

    mobile_norm = (str(body.mobile).strip() if body.mobile else "") or None
    email_norm = (str(body.email).strip().lower() if body.email else "") or None
    if mobile_norm or email_norm:
        dup_parts = []
        if mobile_norm:
            dup_parts.append(Lead.mobile == mobile_norm)
        if email_norm:
            dup_parts.append(Lead.email == email_norm)
        dup = (
            db.query(Lead)
            .filter(Lead.business_id == business_id, Lead.person_id.is_(None), or_(*dup_parts))
            .first()
        )
        if dup:
            raise ApiError(
                "CRM_LEAD_DUPLICATE",
                "سرنخ فعال با همین موبایل یا ایمیل از قبل وجود دارد.",
                http_status=409,
            )

    from datetime import date
    from app.services.document_numbering_service import generate_document_code

    code_val: str
    if body.code and str(body.code).strip():
        code_val = str(body.code).strip()
        existing = db.query(Lead).filter(Lead.business_id == business_id, Lead.code == code_val).first()
        if existing:
            raise ApiError("CRM_LEAD_CODE_EXISTS", f"سرنخ با کد {code_val} از قبل وجود دارد.", http_status=400)
    else:
        code_val = generate_document_code(db, business_id, "crm_lead", date.today())

    lead = Lead(
        business_id=business_id,
        process_definition_id=body.process_definition_id,
        stage_id=body.stage_id,
        code=code_val,
        source_code=body.source_code,
        name=body.name,
        company_name=body.company_name,
        mobile=body.mobile,
        email=body.email,
        description=body.description,
        assigned_to_user_id=body.assigned_to_user_id,
        next_follow_up_at=body.next_follow_up_at,
        extra_info=body.extra_info,
        created_by_user_id=ctx.get_user_id(),
    )
    db.add(lead)
    db.commit()
    db.refresh(lead)
    try:
        from app.services.workflow.workflow_trigger_service import trigger_lead_created
        trigger_lead_created(
            db, business_id,
            lead_id=lead.id,
            process_definition_id=lead.process_definition_id,
            stage_id=lead.stage_id,
            name=lead.name,
            user_id=ctx.get_user_id(),
        )
    except Exception:
        pass
    return success_response(data=_lead_to_dict(lead, request), request=request, message="CRM_LEAD_CREATED")


@router.get(
    "/businesses/{business_id}/leads/{lead_id}",
    summary="جزئیات سرنخ",
)
@require_business_access("business_id")
async def get_lead(
    request: Request,
    business_id: int = Path(..., gt=0),
    lead_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    lead = (
        db.query(Lead)
        .options(
            selectinload(Lead.stage),
            selectinload(Lead.assigned_to),
            selectinload(Lead.person),
            selectinload(Lead.created_by),
        )
        .filter(and_(Lead.id == lead_id, Lead.business_id == business_id))
        .first()
    )
    if not lead:
        raise ApiError("NOT_FOUND", "سرنخ یافت نشد.", http_status=404)
    return success_response(data=_lead_to_dict(lead, request), request=request)


@router.get(
    "/businesses/{business_id}/leads/{lead_id}/history",
    summary="تاریخچه تغییرات سرنخ",
)
@require_business_access("business_id")
async def get_lead_history(
    request: Request,
    business_id: int = Path(..., gt=0),
    lead_id: int = Path(..., gt=0),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    lead = db.query(Lead).filter(and_(Lead.id == lead_id, Lead.business_id == business_id)).first()
    if not lead:
        raise ApiError("NOT_FOUND", "سرنخ یافت نشد.", http_status=404)
    rows = (
        db.query(CrmChangeHistory)
        .options(joinedload(CrmChangeHistory.changed_by))
        .filter(
            CrmChangeHistory.business_id == business_id,
            CrmChangeHistory.entity_type == "lead",
            CrmChangeHistory.entity_id == lead_id,
        )
        .order_by(CrmChangeHistory.changed_at.desc())
        .limit(limit)
        .all()
    )
    data = [
        {
            "id": r.id,
            "field_name": r.field_name,
            "old_value": r.old_value,
            "new_value": r.new_value,
            "changed_at": r.changed_at.isoformat(),
            "changed_by_user_id": r.changed_by_user_id,
            "changed_by_name": (
                f"{r.changed_by.first_name or ''} {r.changed_by.last_name or ''}".strip()
                if r.changed_by else str(r.changed_by_user_id)
            ),
        }
        for r in rows
    ]
    return success_response(data=data, request=request)


@router.put(
    "/businesses/{business_id}/leads/{lead_id}",
    summary="ویرایش سرنخ",
)
@require_business_access("business_id")
async def update_lead(
    request: Request,
    business_id: int = Path(..., gt=0),
    lead_id: int = Path(..., gt=0),
    body: LeadUpdate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    lead = (
        db.query(Lead)
        .options(
            selectinload(Lead.stage),
            selectinload(Lead.assigned_to),
            selectinload(Lead.person),
            selectinload(Lead.created_by),
        )
        .filter(and_(Lead.id == lead_id, Lead.business_id == business_id))
        .first()
    )
    if not lead:
        raise ApiError("NOT_FOUND", "سرنخ یافت نشد.", http_status=404)
    old_assigned_to_user_id = lead.assigned_to_user_id
    if body.stage_id is not None:
        stage = db.query(CrmProcessStage).filter(
            and_(
                CrmProcessStage.id == body.stage_id,
                CrmProcessStage.process_definition_id == lead.process_definition_id,
            )
        ).first()
        if not stage:
            raise ApiError("NOT_FOUND", "مرحله یافت نشد.", http_status=404)
        old_stage_name = (lead.stage.name if lead.stage else None) or str(lead.stage_id)
        old_stage_id = lead.stage_id
        lead.stage_id = body.stage_id
        _log_crm_change(db, business_id, "lead", lead_id, "stage_id", old_stage_name, stage.name, ctx.get_user_id())
        try:
            from app.services.workflow.workflow_trigger_service import trigger_lead_stage_changed
            trigger_lead_stage_changed(db, business_id, lead_id=lead_id, old_stage_id=old_stage_id, new_stage_id=body.stage_id, user_id=ctx.get_user_id())
        except Exception:
            pass
    if body.source_code is not None:
        lead.source_code = body.source_code
    if body.code is not None and str(body.code).strip():
        code_val = str(body.code).strip()
        existing = db.query(Lead).filter(Lead.business_id == business_id, Lead.code == code_val, Lead.id != lead_id).first()
        if existing:
            raise ApiError("CRM_LEAD_CODE_EXISTS", f"سرنخ با کد {code_val} از قبل وجود دارد.", http_status=400)
        lead.code = code_val
    if body.name is not None:
        lead.name = body.name
    if body.company_name is not None:
        lead.company_name = body.company_name
    if body.mobile is not None:
        lead.mobile = body.mobile
    if body.email is not None:
        lead.email = body.email
    if body.description is not None:
        lead.description = body.description
    if body.assigned_to_user_id is not None:
        new_assign = body.assigned_to_user_id
        if new_assign != old_assigned_to_user_id:
            lead.assigned_to_user_id = new_assign
            try:
                from app.services.workflow.workflow_trigger_service import trigger_lead_assigned

                trigger_lead_assigned(
                    db,
                    business_id,
                    lead_id=lead_id,
                    old_assigned_to_user_id=old_assigned_to_user_id,
                    new_assigned_to_user_id=new_assign,
                    user_id=ctx.get_user_id(),
                )
            except Exception:
                pass
    if body.next_follow_up_at is not None:
        lead.next_follow_up_at = body.next_follow_up_at
    if body.extra_info is not None:
        lead.extra_info = body.extra_info
    db.commit()
    db.refresh(lead)
    return success_response(data=_lead_to_dict(lead, request), request=request, message="CRM_LEAD_UPDATED")


@router.post(
    "/businesses/{business_id}/leads/{lead_id}/convert",
    summary="تبدیل سرنخ به مشتری",
    description="ایجاد شخص (مشتری) از سرنخ و اتصال آن به سرنخ. با ارسال create_deal می‌توان همزمان یک فرصت فروش ایجاد کرد.",
)
@require_business_access("business_id")
async def convert_lead_to_customer(
    request: Request,
    business_id: int = Path(..., gt=0),
    lead_id: int = Path(..., gt=0),
    body: LeadConvertRequest = Body(default=None),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    from datetime import datetime, date
    lead = db.query(Lead).filter(and_(Lead.id == lead_id, Lead.business_id == business_id)).first()
    if not lead:
        raise ApiError("NOT_FOUND", "سرنخ یافت نشد.", http_status=404)
    if lead.person_id is not None:
        raise ApiError("CRM_LEAD_ALREADY_CONVERTED", "این سرنخ قبلاً به مشتری تبدیل شده است.", http_status=400)
    alias = (lead.name or lead.company_name or "مشتری بدون نام").strip()
    if not alias:
        alias = "مشتری بدون نام"
    person_data = PersonCreateRequest(
        alias_name=alias[:255],
        first_name=lead.name,
        company_name=lead.company_name,
        mobile=lead.mobile,
        email=lead.email,
        person_types=[PersonType.CUSTOMER],
    )
    result = create_person(db, business_id, person_data)
    person = result.get("data")
    if not person or "id" not in person:
        raise ApiError("CRM_CONVERT_FAILED", "ایجاد مشتری از سرنخ ناموفق بود.", http_status=500)
    person_id = person["id"]
    lead.person_id = person_id
    lead.converted_at = datetime.utcnow()
    deal_data = None
    if body and body.create_deal:
        opt = body.create_deal
        proc = (
            db.query(CrmProcessDefinition)
            .filter(
                and_(
                    CrmProcessDefinition.id == opt.process_definition_id,
                    CrmProcessDefinition.business_id == business_id,
                    CrmProcessDefinition.process_type == "sales_pipeline",
                )
            )
            .first()
        )
        if not proc:
            raise ApiError("NOT_FOUND", "فرایند پایپلاین فروش یافت نشد.", http_status=404)
        stage = (
            db.query(CrmProcessStage)
            .filter(
                and_(
                    CrmProcessStage.id == opt.stage_id,
                    CrmProcessStage.process_definition_id == opt.process_definition_id,
                )
            )
            .first()
        )
        if not stage:
            raise ApiError("NOT_FOUND", "مرحله پایپلاین یافت نشد.", http_status=404)
        from app.services.document_numbering_service import generate_document_code
        code_val = generate_document_code(db, business_id, "crm_deal", date.today())
        new_deal = Deal(
            business_id=business_id,
            person_id=person_id,
            code=code_val,
            process_definition_id=opt.process_definition_id,
            stage_id=opt.stage_id,
            title=opt.title,
            amount=opt.amount,
            currency_id=opt.currency_id,
            probability_percent=opt.probability_percent,
            expected_close_date=opt.expected_close_date,
            assigned_to_user_id=opt.assigned_to_user_id or lead.assigned_to_user_id,
            description=opt.description,
            created_by_user_id=ctx.get_user_id(),
        )
        db.add(new_deal)
        db.flush()
        db.refresh(new_deal)
        deal_data = _deal_to_dict(new_deal, request)
    db.commit()
    db.refresh(lead)
    try:
        from app.services.workflow.workflow_trigger_service import trigger_lead_converted
        trigger_lead_converted(db, business_id, lead_id=lead_id, person_id=person_id, user_id=ctx.get_user_id())
    except Exception:
        pass
    out = {"lead": _lead_to_dict(lead, request), "person": result["data"]}
    if deal_data:
        out["deal"] = deal_data
    return success_response(
        data=out,
        request=request,
        message="CRM_LEAD_CONVERTED",
    )


@router.delete(
    "/businesses/{business_id}/leads/{lead_id}",
    summary="حذف سرنخ",
)
@require_business_access("business_id")
async def delete_lead(
    request: Request,
    business_id: int = Path(..., gt=0),
    lead_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    lead = db.query(Lead).filter(and_(Lead.id == lead_id, Lead.business_id == business_id)).first()
    if not lead:
        raise ApiError("NOT_FOUND", "سرنخ یافت نشد.", http_status=404)
    db.delete(lead)
    db.commit()
    return success_response(message="CRM_LEAD_DELETED", request=request)


# --- فرصت فروش (Deals) ---


def _deal_to_dict(deal: Deal, request: Request = None) -> Dict[str, Any]:
    d = {
        "id": deal.id,
        "business_id": deal.business_id,
        "code": deal.code,
        "person_id": deal.person_id,
        "person_name": deal.person.alias_name if deal.person else None,
        "process_definition_id": deal.process_definition_id,
        "stage_id": deal.stage_id,
        "stage_name": deal.stage.name if deal.stage else None,
        "title": deal.title,
        "amount": float(deal.amount),
        "currency_id": deal.currency_id,
        "probability_percent": deal.probability_percent,
        "expected_close_date": deal.expected_close_date.isoformat() if deal.expected_close_date else None,
        "next_follow_up_at": deal.next_follow_up_at.isoformat() if deal.next_follow_up_at else None,
        "closed_at": deal.closed_at.isoformat() if deal.closed_at else None,
        "document_id": deal.document_id,
        "assigned_to_user_id": deal.assigned_to_user_id,
        "assigned_to_name": (
            f"{deal.assigned_to.first_name or ''} {deal.assigned_to.last_name or ''}".strip()
            if deal.assigned_to else None
        ),
        "created_at": deal.created_at.isoformat(),
        "updated_at": deal.updated_at.isoformat(),
        "created_by_user_id": deal.created_by_user_id,
        "created_by_name": (
            f"{deal.created_by.first_name or ''} {deal.created_by.last_name or ''}".strip()
            if deal.created_by else None
        ),
    }
    if request:
        d = format_datetime_fields(d, request)
    return d


@router.get(
    "/businesses/{business_id}/deals",
    summary="لیست فرصت‌های فروش",
)
@require_business_access("business_id")
async def list_deals(
    request: Request,
    business_id: int = Path(..., gt=0),
    process_definition_id: Optional[int] = Query(None),
    stage_id: Optional[int] = Query(None),
    person_id: Optional[int] = Query(None),
    assigned_to_user_id: Optional[int] = Query(None),
    search: Optional[str] = Query(None, description="جستجو در عنوان، نام مشتری"),
    from_date: Optional[str] = Query(None, description="از تاریخ ایجاد (YYYY-MM-DD)"),
    to_date: Optional[str] = Query(None, description="تا تاریخ ایجاد (YYYY-MM-DD)"),
    open_only: Optional[bool] = Query(None, description="فقط فرصت‌های باز (بسته نشده)"),
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    from datetime import datetime as dt
    from sqlalchemy import func as sa_func

    q = (
        db.query(Deal)
        .options(
            selectinload(Deal.person),
            selectinload(Deal.stage),
            selectinload(Deal.assigned_to),
            selectinload(Deal.created_by),
        )
        .filter(Deal.business_id == business_id)
    )
    if process_definition_id:
        q = q.filter(Deal.process_definition_id == process_definition_id)
    if stage_id:
        q = q.filter(Deal.stage_id == stage_id)
    if person_id:
        q = q.filter(Deal.person_id == person_id)
    if assigned_to_user_id is not None:
        q = q.filter(Deal.assigned_to_user_id == assigned_to_user_id)
    if open_only is True:
        q = q.filter(Deal.closed_at.is_(None))
    if from_date:
        try:
            fd = dt.strptime(from_date, "%Y-%m-%d").date()
            q = q.filter(sa_func.date(Deal.created_at) >= fd)
        except ValueError:
            pass
    if to_date:
        try:
            td = dt.strptime(to_date, "%Y-%m-%d").date()
            q = q.filter(sa_func.date(Deal.created_at) <= td)
        except ValueError:
            pass
    if search and search.strip():
        term = f"%{search.strip()}%"
        q = q.join(Deal.person).filter(
            or_(
                Deal.title.ilike(term),
                Person.alias_name.ilike(term),
            )
        )
    total = q.count()
    items = q.order_by(Deal.updated_at.desc()).offset((page - 1) * limit).limit(limit).all()
    data = [_deal_to_dict(dl, request) for dl in items]
    return success_response(
        data={"items": data, "total": total, "page": page, "limit": limit},
        request=request,
    )


@router.post(
    "/businesses/{business_id}/deals",
    summary="ایجاد فرصت فروش",
)
@require_business_access("business_id")
async def create_deal(
    request: Request,
    business_id: int = Path(..., gt=0),
    body: DealCreate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    from adapters.db.models.person import Person
    person = db.query(Person).filter(and_(Person.id == body.person_id, Person.business_id == business_id)).first()
    if not person:
        raise ApiError("NOT_FOUND", "شخص (مشتری) یافت نشد.", http_status=404)
    proc = (
        db.query(CrmProcessDefinition)
        .filter(
            and_(
                CrmProcessDefinition.id == body.process_definition_id,
                CrmProcessDefinition.business_id == business_id,
            )
        )
        .first()
    )
    if not proc:
        raise ApiError("NOT_FOUND", "فرایند یافت نشد.", http_status=404)
    stage = (
        db.query(CrmProcessStage)
        .filter(
            and_(
                CrmProcessStage.id == body.stage_id,
                CrmProcessStage.process_definition_id == body.process_definition_id,
            )
        )
        .first()
    )
    if not stage:
        raise ApiError("NOT_FOUND", "مرحله یافت نشد.", http_status=404)

    from datetime import date
    from app.services.document_numbering_service import generate_document_code

    code_val: str
    if body.code and str(body.code).strip():
        code_val = str(body.code).strip()
        existing = db.query(Deal).filter(Deal.business_id == business_id, Deal.code == code_val).first()
        if existing:
            raise ApiError("CRM_DEAL_CODE_EXISTS", f"فرصت فروش با کد {code_val} از قبل وجود دارد.", http_status=400)
    else:
        code_val = generate_document_code(db, business_id, "crm_deal", date.today())

    deal = Deal(
        business_id=business_id,
        person_id=body.person_id,
        code=code_val,
        process_definition_id=body.process_definition_id,
        stage_id=body.stage_id,
        title=body.title,
        amount=body.amount,
        currency_id=body.currency_id,
        probability_percent=body.probability_percent,
        expected_close_date=body.expected_close_date,
        next_follow_up_at=body.next_follow_up_at,
        assigned_to_user_id=body.assigned_to_user_id,
        description=body.description,
        extra_info=body.extra_info,
        created_by_user_id=ctx.get_user_id(),
    )
    db.add(deal)
    db.commit()
    db.refresh(deal)
    try:
        from app.services.workflow.workflow_trigger_service import trigger_deal_created
        trigger_deal_created(
            db, business_id,
            deal_id=deal.id,
            process_definition_id=deal.process_definition_id,
            stage_id=deal.stage_id,
            person_id=deal.person_id,
            title=deal.title,
            amount=float(deal.amount),
            user_id=ctx.get_user_id(),
        )
    except Exception:
        pass
    return success_response(data=_deal_to_dict(deal, request), request=request, message="CRM_DEAL_CREATED")


@router.get(
    "/businesses/{business_id}/deals/{deal_id}",
    summary="جزئیات فرصت فروش",
)
@require_business_access("business_id")
async def get_deal(
    request: Request,
    business_id: int = Path(..., gt=0),
    deal_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    deal = (
        db.query(Deal)
        .options(
            selectinload(Deal.stage),
            selectinload(Deal.assigned_to),
            selectinload(Deal.person),
            selectinload(Deal.created_by),
        )
        .filter(and_(Deal.id == deal_id, Deal.business_id == business_id))
        .first()
    )
    if not deal:
        raise ApiError("NOT_FOUND", "فرصت فروش یافت نشد.", http_status=404)
    return success_response(data=_deal_to_dict(deal, request), request=request)


@router.get(
    "/businesses/{business_id}/deals/{deal_id}/history",
    summary="تاریخچه تغییرات فرصت فروش",
)
@require_business_access("business_id")
async def get_deal_history(
    request: Request,
    business_id: int = Path(..., gt=0),
    deal_id: int = Path(..., gt=0),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    deal = db.query(Deal).filter(and_(Deal.id == deal_id, Deal.business_id == business_id)).first()
    if not deal:
        raise ApiError("NOT_FOUND", "فرصت فروش یافت نشد.", http_status=404)
    rows = (
        db.query(CrmChangeHistory)
        .options(joinedload(CrmChangeHistory.changed_by))
        .filter(
            CrmChangeHistory.business_id == business_id,
            CrmChangeHistory.entity_type == "deal",
            CrmChangeHistory.entity_id == deal_id,
        )
        .order_by(CrmChangeHistory.changed_at.desc())
        .limit(limit)
        .all()
    )
    data = [
        {
            "id": r.id,
            "field_name": r.field_name,
            "old_value": r.old_value,
            "new_value": r.new_value,
            "changed_at": r.changed_at.isoformat(),
            "changed_by_user_id": r.changed_by_user_id,
            "changed_by_name": (
                f"{r.changed_by.first_name or ''} {r.changed_by.last_name or ''}".strip()
                if r.changed_by else str(r.changed_by_user_id)
            ),
        }
        for r in rows
    ]
    return success_response(data=data, request=request)


@router.put(
    "/businesses/{business_id}/deals/{deal_id}",
    summary="ویرایش فرصت فروش (شامل تغییر مرحله)",
)
@require_business_access("business_id")
async def update_deal(
    request: Request,
    business_id: int = Path(..., gt=0),
    deal_id: int = Path(..., gt=0),
    body: DealUpdate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    deal = (
        db.query(Deal)
        .options(
            selectinload(Deal.stage),
            selectinload(Deal.assigned_to),
            selectinload(Deal.person),
            selectinload(Deal.created_by),
        )
        .filter(and_(Deal.id == deal_id, Deal.business_id == business_id))
        .first()
    )
    if not deal:
        raise ApiError("NOT_FOUND", "فرصت فروش یافت نشد.", http_status=404)
    old_assigned_to_user_id = deal.assigned_to_user_id
    if body.stage_id is not None:
        stage = db.query(CrmProcessStage).filter(
            and_(
                CrmProcessStage.id == body.stage_id,
                CrmProcessStage.process_definition_id == deal.process_definition_id,
            )
        ).first()
        if not stage:
            raise ApiError("NOT_FOUND", "مرحله یافت نشد.", http_status=404)
        old_stage_name = (deal.stage.name if deal.stage else None) or str(deal.stage_id)
        old_stage_id = deal.stage_id
        deal.stage_id = body.stage_id
        _log_crm_change(db, business_id, "deal", deal_id, "stage_id", old_stage_name, stage.name, ctx.get_user_id())
        try:
            from app.services.workflow.workflow_trigger_service import trigger_deal_stage_changed
            trigger_deal_stage_changed(db, business_id, deal_id=deal_id, old_stage_id=old_stage_id, new_stage_id=body.stage_id, user_id=ctx.get_user_id())
        except Exception:
            pass
    if body.code is not None and str(body.code).strip():
        code_val = str(body.code).strip()
        existing = db.query(Deal).filter(Deal.business_id == business_id, Deal.code == code_val, Deal.id != deal_id).first()
        if existing:
            raise ApiError("CRM_DEAL_CODE_EXISTS", f"فرصت فروش با کد {code_val} از قبل وجود دارد.", http_status=400)
        deal.code = code_val
    if body.title is not None:
        deal.title = body.title
    if body.amount is not None:
        _log_crm_change(db, business_id, "deal", deal_id, "amount", str(deal.amount), str(body.amount), ctx.get_user_id())
        deal.amount = body.amount
    if body.currency_id is not None:
        deal.currency_id = body.currency_id
    if body.probability_percent is not None:
        deal.probability_percent = body.probability_percent
    if body.expected_close_date is not None:
        deal.expected_close_date = body.expected_close_date
    if body.next_follow_up_at is not None:
        deal.next_follow_up_at = body.next_follow_up_at
    if body.document_id is not None:
        deal.document_id = body.document_id
    if body.assigned_to_user_id is not None:
        new_assign = body.assigned_to_user_id
        if new_assign != old_assigned_to_user_id:
            deal.assigned_to_user_id = new_assign
            try:
                from app.services.workflow.workflow_trigger_service import trigger_deal_assigned

                trigger_deal_assigned(
                    db,
                    business_id,
                    deal_id=deal_id,
                    old_assigned_to_user_id=old_assigned_to_user_id,
                    new_assigned_to_user_id=new_assign,
                    user_id=ctx.get_user_id(),
                )
            except Exception:
                pass
    if body.description is not None:
        deal.description = body.description
    if body.extra_info is not None:
        deal.extra_info = body.extra_info
    if body.closed_at is not None:
        deal.closed_at = body.closed_at
        try:
            from app.services.workflow.workflow_trigger_service import trigger_deal_closed

            st = deal.stage
            is_win = bool(st and st.is_win)
            is_lost = bool(st and st.is_lost)
            trigger_deal_closed(
                db,
                business_id,
                deal_id=deal_id,
                amount=float(deal.amount),
                is_win=is_win,
                document_id=deal.document_id,
                user_id=ctx.get_user_id(),
                is_lost=is_lost,
            )
        except Exception:
            pass
    db.commit()
    db.refresh(deal)
    return success_response(data=_deal_to_dict(deal, request), request=request, message="CRM_DEAL_UPDATED")


@router.delete(
    "/businesses/{business_id}/deals/{deal_id}",
    summary="حذف فرصت فروش",
)
@require_business_access("business_id")
async def delete_deal(
    request: Request,
    business_id: int = Path(..., gt=0),
    deal_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    deal = db.query(Deal).filter(and_(Deal.id == deal_id, Deal.business_id == business_id)).first()
    if not deal:
        raise ApiError("NOT_FOUND", "فرصت فروش یافت نشد.", http_status=404)
    db.delete(deal)
    db.commit()
    return success_response(message="CRM_DEAL_DELETED", request=request)


# --- فعالیت (Activities) ---


def _activity_to_dict(a: CrmActivity, request: Request = None) -> Dict[str, Any]:
    d = {
        "id": a.id,
        "business_id": a.business_id,
        "person_id": a.person_id,
        "person_name": a.person.alias_name if getattr(a, "person", None) else None,
        "lead_id": a.lead_id,
        "lead_name": a.lead.name if getattr(a, "lead", None) else None,
        "code": a.code,
        "activity_type": a.activity_type,
        "subject": a.subject,
        "description": a.description,
        "activity_date": a.activity_date.isoformat(),
        "deal_id": a.deal_id,
        "created_by_user_id": a.created_by_user_id,
        "created_by_name": (
            f"{a.created_by.first_name or ''} {a.created_by.last_name or ''}".strip()
            if a.created_by else None
        ),
        "created_at": a.created_at.isoformat(),
        "updated_at": a.updated_at.isoformat(),
    }
    if request:
        d = format_datetime_fields(d, request)
    return d


@router.get(
    "/businesses/{business_id}/activities",
    summary="لیست فعالیت‌ها (با فیلتر شخص)",
)
@require_business_access("business_id")
async def list_activities(
    request: Request,
    business_id: int = Path(..., gt=0),
    person_id: Optional[int] = Query(None),
    lead_id: Optional[int] = Query(None, description="فیلتر بر اساس سرنخ"),
    deal_id: Optional[int] = Query(None),
    activity_type: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    q = (
        db.query(CrmActivity)
        .options(
            selectinload(CrmActivity.created_by),
            selectinload(CrmActivity.lead),
            selectinload(CrmActivity.person),
        )
        .filter(CrmActivity.business_id == business_id)
    )
    if person_id:
        q = q.filter(CrmActivity.person_id == person_id)
    if lead_id is not None:
        q = q.filter(CrmActivity.lead_id == lead_id)
    if deal_id:
        q = q.filter(CrmActivity.deal_id == deal_id)
    if activity_type:
        q = q.filter(CrmActivity.activity_type == activity_type)
    total = q.count()
    items = q.order_by(CrmActivity.activity_date.desc()).offset((page - 1) * limit).limit(limit).all()
    data = [_activity_to_dict(a, request) for a in items]
    return success_response(
        data={"items": data, "total": total, "page": page, "limit": limit},
        request=request,
    )


@router.post(
    "/businesses/{business_id}/activities",
    summary="ثبت فعالیت",
)
@require_business_access("business_id")
async def create_activity(
    request: Request,
    business_id: int = Path(..., gt=0),
    body: CrmActivityCreate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    from adapters.db.models.person import Person

    person_id_val: Optional[int] = body.person_id
    lead_id_val: Optional[int] = body.lead_id
    if not person_id_val and not lead_id_val:
        raise ApiError("CRM_ACTIVITY_PERSON_OR_LEAD", "یکی از person_id یا lead_id الزامی است.", http_status=400)
    if lead_id_val is not None:
        lead = db.query(Lead).filter(and_(Lead.id == lead_id_val, Lead.business_id == business_id)).first()
        if not lead:
            raise ApiError("NOT_FOUND", "سرنخ یافت نشد.", http_status=404)
        if lead.person_id and not person_id_val:
            person_id_val = int(lead.person_id)
    if person_id_val is not None:
        person = db.query(Person).filter(and_(Person.id == person_id_val, Person.business_id == business_id)).first()
        if not person:
            raise ApiError("NOT_FOUND", "شخص یافت نشد.", http_status=404)

    from datetime import date
    from app.services.document_numbering_service import generate_document_code

    code_val: str
    if body.code and str(body.code).strip():
        code_val = str(body.code).strip()
        existing = db.query(CrmActivity).filter(CrmActivity.business_id == business_id, CrmActivity.code == code_val).first()
        if existing:
            raise ApiError("CRM_ACTIVITY_CODE_EXISTS", f"فعالیت با کد {code_val} از قبل وجود دارد.", http_status=400)
    else:
        code_val = generate_document_code(db, business_id, "crm_activity", body.activity_date.date())

    activity = CrmActivity(
        business_id=business_id,
        person_id=person_id_val,
        lead_id=lead_id_val,
        code=code_val,
        activity_type=body.activity_type,
        subject=body.subject,
        description=body.description,
        activity_date=body.activity_date,
        deal_id=body.deal_id,
        created_by_user_id=ctx.get_user_id(),
        extra_info=body.extra_info,
    )
    db.add(activity)
    db.commit()
    db.refresh(activity)
    activity = (
        db.query(CrmActivity)
        .options(selectinload(CrmActivity.lead), selectinload(CrmActivity.created_by), selectinload(CrmActivity.person))
        .filter(CrmActivity.id == activity.id)
        .first()
    )
    try:
        from app.services.workflow.workflow_trigger_service import trigger_crm_activity_created

        trigger_crm_activity_created(db, business_id, activity.id, user_id=ctx.get_user_id())
    except Exception:
        pass
    return success_response(data=_activity_to_dict(activity, request), request=request, message="CRM_ACTIVITY_CREATED")


@router.get(
    "/businesses/{business_id}/activities/{activity_id}",
    summary="جزئیات فعالیت",
)
@require_business_access("business_id")
async def get_activity(
    request: Request,
    business_id: int = Path(..., gt=0),
    activity_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    activity = (
        db.query(CrmActivity)
        .options(
            selectinload(CrmActivity.lead),
            selectinload(CrmActivity.person),
            selectinload(CrmActivity.created_by),
        )
        .filter(and_(CrmActivity.id == activity_id, CrmActivity.business_id == business_id))
        .first()
    )
    if not activity:
        raise ApiError("NOT_FOUND", "فعالیت یافت نشد.", http_status=404)
    return success_response(data=_activity_to_dict(activity, request), request=request)


@router.put(
    "/businesses/{business_id}/activities/{activity_id}",
    summary="ویرایش فعالیت",
)
@require_business_access("business_id")
async def update_activity(
    request: Request,
    business_id: int = Path(..., gt=0),
    activity_id: int = Path(..., gt=0),
    body: CrmActivityUpdate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    activity = db.query(CrmActivity).filter(
        and_(CrmActivity.id == activity_id, CrmActivity.business_id == business_id)
    ).first()
    if not activity:
        raise ApiError("NOT_FOUND", "فعالیت یافت نشد.", http_status=404)
    if body.code is not None and str(body.code).strip():
        code_val = str(body.code).strip()
        existing = db.query(CrmActivity).filter(
            CrmActivity.business_id == business_id,
            CrmActivity.code == code_val,
            CrmActivity.id != activity_id,
        ).first()
        if existing:
            raise ApiError("CRM_ACTIVITY_CODE_EXISTS", f"فعالیت با کد {code_val} از قبل وجود دارد.", http_status=400)
        activity.code = code_val
    if body.activity_type is not None:
        activity.activity_type = body.activity_type
    if body.subject is not None:
        activity.subject = body.subject
    if body.description is not None:
        activity.description = body.description
    if body.activity_date is not None:
        activity.activity_date = body.activity_date
    if body.deal_id is not None:
        activity.deal_id = body.deal_id
    if body.extra_info is not None:
        activity.extra_info = body.extra_info
    db.commit()
    db.refresh(activity)
    return success_response(data=_activity_to_dict(activity, request), request=request, message="CRM_ACTIVITY_UPDATED")


@router.delete(
    "/businesses/{business_id}/activities/{activity_id}",
    summary="حذف فعالیت",
)
@require_business_access("business_id")
async def delete_activity(
    request: Request,
    business_id: int = Path(..., gt=0),
    activity_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    activity = db.query(CrmActivity).filter(
        and_(CrmActivity.id == activity_id, CrmActivity.business_id == business_id)
    ).first()
    if not activity:
        raise ApiError("NOT_FOUND", "فعالیت یافت نشد.", http_status=404)
    db.delete(activity)
    db.commit()
    return success_response(message="CRM_ACTIVITY_DELETED", request=request)


# --- یادداشت و تقویم CRM ---


def _crm_note_translator(request: Request):
    return getattr(request.state, "translator", None)


@router.get(
    "/businesses/{business_id}/note-types",
    summary="انواع یادداشت CRM",
)
@require_business_access("business_id")
async def list_crm_note_types(
    request: Request,
    business_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    lang = getattr(ctx, "language", None) or "fa"
    items = crm_cal_notes.list_note_types(db, business_id, lang)
    db.commit()
    return success_response(data={"items": format_datetime_fields(items, request)}, request=request)


@router.post(
    "/businesses/{business_id}/note-types",
    summary="ایجاد نوع یادداشت سفارشی",
)
@require_business_access("business_id")
async def create_crm_note_type(
    request: Request,
    business_id: int = Path(..., gt=0),
    body: CrmNoteTypeCreate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    lang = getattr(ctx, "language", None) or "fa"
    tr = _crm_note_translator(request)
    row = crm_cal_notes.create_note_type(
        db,
        business_id,
        code=body.code,
        title_i18n=dict(body.title_i18n),
        scheduling_mode=body.scheduling_mode,
        allow_comments=body.allow_comments,
        sort_order=body.sort_order,
        lang=lang,
        translator=tr,
    )
    db.commit()
    return success_response(data=format_datetime_fields(row, request), request=request, message="CRM_NOTE_TYPE_CREATED")


@router.patch(
    "/businesses/{business_id}/note-types/{type_id}",
    summary="ویرایش نوع یادداشت",
)
@require_business_access("business_id")
async def update_crm_note_type(
    request: Request,
    business_id: int = Path(..., gt=0),
    type_id: int = Path(..., gt=0),
    body: CrmNoteTypeUpdate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    lang = getattr(ctx, "language", None) or "fa"
    tr = _crm_note_translator(request)
    row = crm_cal_notes.update_note_type(
        db,
        business_id,
        type_id,
        title_i18n=body.title_i18n,
        scheduling_mode=body.scheduling_mode,
        allow_comments=body.allow_comments,
        is_active=body.is_active,
        sort_order=body.sort_order,
        lang=lang,
        translator=tr,
    )
    db.commit()
    return success_response(data=format_datetime_fields(row, request), request=request, message="CRM_NOTE_TYPE_UPDATED")


@router.delete(
    "/businesses/{business_id}/note-types/{type_id}",
    summary="حذف نوع یادداشت غیرسیستمی",
)
@require_business_access("business_id")
async def delete_crm_note_type(
    request: Request,
    business_id: int = Path(..., gt=0),
    type_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    tr = _crm_note_translator(request)
    crm_cal_notes.delete_note_type(db, business_id, type_id, tr)
    db.commit()
    return success_response(message="CRM_NOTE_TYPE_DELETED", request=request)


@router.get(
    "/businesses/{business_id}/notes",
    summary="لیست یادداشت‌های تقویم در بازه تاریخ",
)
@require_business_access("business_id")
async def list_crm_notes(
    request: Request,
    business_id: int = Path(..., gt=0),
    from_date: str = Query(..., description="YYYY-MM-DD میلادی"),
    to_date: str = Query(..., description="YYYY-MM-DD میلادی"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    from datetime import datetime as dt

    try:
        fd = dt.strptime(from_date, "%Y-%m-%d").date()
        td = dt.strptime(to_date, "%Y-%m-%d").date()
    except ValueError:
        raise ApiError("CRM_NOTE_DATE_RANGE_INVALID", "Invalid date range", translator=_crm_note_translator(request))
    lang = getattr(ctx, "language", None) or "fa"
    items = crm_cal_notes.list_notes(db, ctx, business_id, fd, td, lang)
    db.commit()
    return success_response(data={"items": format_datetime_fields(items, request)}, request=request)


@router.get(
    "/businesses/{business_id}/notes/{note_id}",
    summary="جزئیات یادداشت",
)
@require_business_access("business_id")
async def get_crm_note(
    request: Request,
    business_id: int = Path(..., gt=0),
    note_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    lang = getattr(ctx, "language", None) or "fa"
    data = crm_cal_notes.get_note(db, ctx, business_id, note_id, lang)
    db.commit()
    if not data:
        raise ApiError("CRM_NOTE_NOT_FOUND", "Not found", http_status=404, translator=_crm_note_translator(request))
    return success_response(data=format_datetime_fields(data, request), request=request)


@router.post(
    "/businesses/{business_id}/notes",
    summary="ایجاد یادداشت",
)
@require_business_access("business_id")
async def create_crm_note(
    request: Request,
    business_id: int = Path(..., gt=0),
    body: CrmNoteCreate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    tr = _crm_note_translator(request)
    note = crm_cal_notes.create_note(
        db,
        ctx,
        business_id,
        note_type_id=body.note_type_id,
        visibility=body.visibility,
        title=body.title,
        body=body.body,
        occurs_on=body.occurs_on,
        starts_at=body.starts_at,
        ends_at=body.ends_at,
        lead_id=body.lead_id,
        shared_user_ids=body.shared_user_ids,
        translator=tr,
    )
    db.commit()
    db.refresh(note)
    lang = getattr(ctx, "language", None) or "fa"
    data = crm_cal_notes.get_note(db, ctx, business_id, note.id, lang)
    return success_response(data=format_datetime_fields(data, request), request=request, message="CRM_NOTE_CREATED")


@router.patch(
    "/businesses/{business_id}/notes/{note_id}",
    summary="ویرایش یادداشت",
)
@require_business_access("business_id")
async def update_crm_note(
    request: Request,
    business_id: int = Path(..., gt=0),
    note_id: int = Path(..., gt=0),
    body: CrmNoteUpdate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    tr = _crm_note_translator(request)
    dump = body.model_dump(exclude_unset=True)
    if dump.get("clear_lead"):
        lead_field_set = True
        lead_val = None
    elif "lead_id" in dump:
        lead_field_set = True
        lead_val = dump.get("lead_id")
    else:
        lead_field_set = False
        lead_val = None
    note = crm_cal_notes.update_note(
        db,
        ctx,
        business_id,
        note_id,
        note_type_id=body.note_type_id,
        visibility=body.visibility,
        title=body.title,
        body=body.body,
        occurs_on=body.occurs_on,
        starts_at=body.starts_at,
        ends_at=body.ends_at,
        lead_id=lead_val,
        lead_field_set=lead_field_set,
        status=body.status,
        shared_user_ids=body.shared_user_ids,
        translator=tr,
    )
    db.commit()
    lang = getattr(ctx, "language", None) or "fa"
    data = crm_cal_notes.get_note(db, ctx, business_id, note.id, lang)
    return success_response(data=format_datetime_fields(data, request), request=request, message="CRM_NOTE_UPDATED")


@router.delete(
    "/businesses/{business_id}/notes/{note_id}",
    summary="حذف نرم یادداشت",
)
@require_business_access("business_id")
async def delete_crm_note(
    request: Request,
    business_id: int = Path(..., gt=0),
    note_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    tr = _crm_note_translator(request)
    crm_cal_notes.soft_delete_note(db, ctx, business_id, note_id, tr)
    db.commit()
    return success_response(message="CRM_NOTE_DELETED", request=request)


@router.get(
    "/businesses/{business_id}/notes/{note_id}/comments",
    summary="کامنت‌های یادداشت",
)
@require_business_access("business_id")
async def list_crm_note_comments(
    request: Request,
    business_id: int = Path(..., gt=0),
    note_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    lang = getattr(ctx, "language", None) or "fa"
    items = crm_cal_notes.list_comments(db, ctx, business_id, note_id, lang)
    db.commit()
    return success_response(data={"items": format_datetime_fields(items, request)}, request=request)


@router.post(
    "/businesses/{business_id}/notes/{note_id}/comments",
    summary="افزودن کامنت",
)
@require_business_access("business_id")
async def create_crm_note_comment(
    request: Request,
    business_id: int = Path(..., gt=0),
    note_id: int = Path(..., gt=0),
    body: CrmNoteCommentCreate = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    tr = _crm_note_translator(request)
    row = crm_cal_notes.add_comment(db, ctx, business_id, note_id, body.body, tr)
    db.commit()
    return success_response(data=format_datetime_fields(row, request), request=request, message="CRM_NOTE_COMMENT_CREATED")


@router.delete(
    "/businesses/{business_id}/notes/{note_id}/comments/{comment_id}",
    summary="حذف کامنت",
)
@require_business_access("business_id")
async def delete_crm_note_comment(
    request: Request,
    business_id: int = Path(..., gt=0),
    note_id: int = Path(..., gt=0),
    comment_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    tr = _crm_note_translator(request)
    crm_cal_notes.delete_comment(db, ctx, business_id, note_id, comment_id, tr)
    db.commit()
    return success_response(message="CRM_NOTE_COMMENT_DELETED", request=request)


@router.get(
    "/businesses/{business_id}/notes/{note_id}/audit",
    summary="تاریخچه audit یادداشت",
)
@require_business_access("business_id")
async def list_crm_note_audit(
    request: Request,
    business_id: int = Path(..., gt=0),
    note_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    tr = _crm_note_translator(request)
    items = crm_cal_notes.list_audit(db, ctx, business_id, note_id)
    db.commit()
    return success_response(data={"items": format_datetime_fields(items, request)}, request=request)


from adapters.api.v1.crm_chat import router as _crm_web_chat_router  # noqa: E402

router.include_router(_crm_web_chat_router)
