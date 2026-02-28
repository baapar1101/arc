# noqa: D100
"""
API endpoints برای CRM: فرایندها، مراحل، سرنخ، فرصت فروش، فعالیت
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Path, Body, Query, Request
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from adapters.db.session import get_db
from adapters.db.models.crm import (
    CrmProcessDefinition,
    CrmProcessStage,
    Lead,
    Deal,
    CrmActivity,
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
    DealCreate,
    DealUpdate,
    DealResponse,
    CrmActivityCreate,
    CrmActivityUpdate,
    CrmActivityResponse,
)
from adapters.db.models.person import Person, PersonType
from adapters.api.v1.schema_models.person import PersonCreateRequest
from app.services.person_service import create_person
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response, format_datetime_fields, ApiError

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
    from sqlalchemy import func
    total_leads = db.query(Lead).filter(Lead.business_id == business_id).count()
    converted_leads = db.query(Lead).filter(Lead.business_id == business_id, Lead.person_id.isnot(None)).count()
    total_deals = db.query(Deal).filter(Deal.business_id == business_id).count()
    deals_amount = db.query(func.coalesce(func.sum(Deal.amount), 0)).filter(Deal.business_id == business_id).scalar() or 0
    closed_deals = db.query(Deal).filter(Deal.business_id == business_id, Deal.closed_at.isnot(None)).count()
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
    "/businesses/{business_id}/reports/pipeline",
    summary="گزارش پایپلاین فروش",
    description="تعداد و مبلغ فرصت‌ها به تفکیک مرحله",
)
@require_business_access("business_id")
async def get_pipeline_report(
    request: Request,
    business_id: int = Path(..., gt=0),
    process_definition_id: Optional[int] = Query(None, description="شناسه فرایند پایپلاین"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    from sqlalchemy import func
    q = db.query(
        CrmProcessStage.id,
        CrmProcessStage.name,
        CrmProcessStage.order_index,
        func.count(Deal.id).label("deal_count"),
        func.coalesce(func.sum(Deal.amount), 0).label("total_amount"),
    ).outerjoin(Deal, and_(Deal.stage_id == CrmProcessStage.id, Deal.business_id == business_id))
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
    description="تعداد سرنخ به تفکیک مرحله",
)
@require_business_access("business_id")
async def get_lead_funnel_report(
    request: Request,
    business_id: int = Path(..., gt=0),
    process_definition_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    from sqlalchemy import func
    q = db.query(
        CrmProcessStage.id,
        CrmProcessStage.name,
        CrmProcessStage.order_index,
        func.count(Lead.id).label("lead_count"),
    ).outerjoin(Lead, and_(Lead.stage_id == CrmProcessStage.id, Lead.business_id == business_id))
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
    from sqlalchemy import func
    from adapters.db.models.user import User

    user_ids = set()
    lead_user_ids = db.query(Lead.assigned_to_user_id).filter(Lead.business_id == business_id, Lead.assigned_to_user_id.isnot(None)).distinct().all()
    deal_user_ids = db.query(Deal.assigned_to_user_id).filter(Deal.business_id == business_id, Deal.assigned_to_user_id.isnot(None)).distinct().all()
    act_user_ids = db.query(CrmActivity.created_by_user_id).filter(CrmActivity.business_id == business_id).distinct().all()
    for (uid,) in lead_user_ids:
        if uid:
            user_ids.add(uid)
    for (uid,) in deal_user_ids:
        if uid:
            user_ids.add(uid)
    for (uid,) in act_user_ids:
        user_ids.add(uid)

    # محدودیت دسترسی: کاربران بدون reports_team فقط عملکرد خود را می‌بینند
    restricted_to_self = False
    current_user_id = ctx.get_user_id()
    if current_user_id and not (ctx.is_superadmin() or ctx.is_business_owner(business_id) or ctx.has_business_permission("crm", "reports_team")):
        restricted_to_self = True
        user_ids = {uid for uid in user_ids if uid == current_user_id}
        if not user_ids:
            # کاربر در لیست نیست (سرنخ/فرصت/فعالیت ندارد)؛ فقط ردیف خودش با صفر
            user_ids = {current_user_id}

    if not user_ids:
        return success_response(data=[], restricted_to_self=restricted_to_self, request=request)

    users = db.query(User).filter(User.id.in_(user_ids)).all()
    user_map = {u.id: f"{(u.first_name or '')} {(u.last_name or '')}".strip() or str(u.id) for u in users}

    result = []
    for uid in user_ids:
        name = user_map.get(uid, str(uid))
        leads_cnt = db.query(func.count(Lead.id)).filter(Lead.business_id == business_id, Lead.assigned_to_user_id == uid).scalar() or 0
        converted_cnt = db.query(func.count(Lead.id)).filter(Lead.business_id == business_id, Lead.assigned_to_user_id == uid, Lead.person_id.isnot(None)).scalar() or 0
        deals_cnt = db.query(func.count(Deal.id)).filter(Deal.business_id == business_id, Deal.assigned_to_user_id == uid).scalar() or 0
        closed_cnt = db.query(func.count(Deal.id)).filter(Deal.business_id == business_id, Deal.assigned_to_user_id == uid, Deal.closed_at.isnot(None)).scalar() or 0
        amount = db.query(func.coalesce(func.sum(Deal.amount), 0)).filter(Deal.business_id == business_id, Deal.assigned_to_user_id == uid).scalar() or 0
        acts_cnt = db.query(func.count(CrmActivity.id)).filter(CrmActivity.business_id == business_id, CrmActivity.created_by_user_id == uid).scalar() or 0
        conv_rate = (converted_cnt / leads_cnt * 100) if leads_cnt else 0
        result.append({
            "user_id": uid,
            "user_name": name,
            "leads_count": leads_cnt,
            "converted_leads": converted_cnt,
            "conversion_rate": round(conv_rate, 1),
            "deals_count": deals_cnt,
            "closed_deals": closed_cnt,
            "total_amount": float(amount),
            "activities_count": acts_cnt,
        })
    result.sort(key=lambda x: (-x["total_amount"], -x["deals_count"]))
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
    q = db.query(CrmProcessDefinition).filter(CrmProcessDefinition.business_id == business_id)
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
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    q = db.query(Lead).filter(Lead.business_id == business_id)
    if process_definition_id:
        q = q.filter(Lead.process_definition_id == process_definition_id)
    if stage_id:
        q = q.filter(Lead.stage_id == stage_id)
    if assigned_to_user_id is not None:
        q = q.filter(Lead.assigned_to_user_id == assigned_to_user_id)
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
        extra_info=body.extra_info,
        created_by_user_id=ctx.get_user_id(),
    )
    db.add(lead)
    db.commit()
    db.refresh(lead)
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
    lead = db.query(Lead).filter(and_(Lead.id == lead_id, Lead.business_id == business_id)).first()
    if not lead:
        raise ApiError("NOT_FOUND", "سرنخ یافت نشد.", http_status=404)
    return success_response(data=_lead_to_dict(lead, request), request=request)


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
    lead = db.query(Lead).filter(and_(Lead.id == lead_id, Lead.business_id == business_id)).first()
    if not lead:
        raise ApiError("NOT_FOUND", "سرنخ یافت نشد.", http_status=404)
    if body.stage_id is not None:
        stage = db.query(CrmProcessStage).filter(
            and_(
                CrmProcessStage.id == body.stage_id,
                CrmProcessStage.process_definition_id == lead.process_definition_id,
            )
        ).first()
        if not stage:
            raise ApiError("NOT_FOUND", "مرحله یافت نشد.", http_status=404)
        lead.stage_id = body.stage_id
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
        lead.assigned_to_user_id = body.assigned_to_user_id
    if body.extra_info is not None:
        lead.extra_info = body.extra_info
    db.commit()
    db.refresh(lead)
    return success_response(data=_lead_to_dict(lead, request), request=request, message="CRM_LEAD_UPDATED")


@router.post(
    "/businesses/{business_id}/leads/{lead_id}/convert",
    summary="تبدیل سرنخ به مشتری",
    description="ایجاد شخص (مشتری) از سرنخ و اتصال آن به سرنخ",
)
@require_business_access("business_id")
async def convert_lead_to_customer(
    request: Request,
    business_id: int = Path(..., gt=0),
    lead_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
    from datetime import datetime
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
    db.commit()
    db.refresh(lead)
    return success_response(
        data={"lead": _lead_to_dict(lead, request), "person": result["data"]},
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
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    q = db.query(Deal).filter(Deal.business_id == business_id)
    if process_definition_id:
        q = q.filter(Deal.process_definition_id == process_definition_id)
    if stage_id:
        q = q.filter(Deal.stage_id == stage_id)
    if person_id:
        q = q.filter(Deal.person_id == person_id)
    if assigned_to_user_id is not None:
        q = q.filter(Deal.assigned_to_user_id == assigned_to_user_id)
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
        assigned_to_user_id=body.assigned_to_user_id,
        description=body.description,
        extra_info=body.extra_info,
        created_by_user_id=ctx.get_user_id(),
    )
    db.add(deal)
    db.commit()
    db.refresh(deal)
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
    deal = db.query(Deal).filter(and_(Deal.id == deal_id, Deal.business_id == business_id)).first()
    if not deal:
        raise ApiError("NOT_FOUND", "فرصت فروش یافت نشد.", http_status=404)
    return success_response(data=_deal_to_dict(deal, request), request=request)


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
    deal = db.query(Deal).filter(and_(Deal.id == deal_id, Deal.business_id == business_id)).first()
    if not deal:
        raise ApiError("NOT_FOUND", "فرصت فروش یافت نشد.", http_status=404)
    if body.stage_id is not None:
        stage = db.query(CrmProcessStage).filter(
            and_(
                CrmProcessStage.id == body.stage_id,
                CrmProcessStage.process_definition_id == deal.process_definition_id,
            )
        ).first()
        if not stage:
            raise ApiError("NOT_FOUND", "مرحله یافت نشد.", http_status=404)
        deal.stage_id = body.stage_id
    if body.code is not None and str(body.code).strip():
        code_val = str(body.code).strip()
        existing = db.query(Deal).filter(Deal.business_id == business_id, Deal.code == code_val, Deal.id != deal_id).first()
        if existing:
            raise ApiError("CRM_DEAL_CODE_EXISTS", f"فرصت فروش با کد {code_val} از قبل وجود دارد.", http_status=400)
        deal.code = code_val
    if body.title is not None:
        deal.title = body.title
    if body.amount is not None:
        deal.amount = body.amount
    if body.currency_id is not None:
        deal.currency_id = body.currency_id
    if body.probability_percent is not None:
        deal.probability_percent = body.probability_percent
    if body.expected_close_date is not None:
        deal.expected_close_date = body.expected_close_date
    if body.document_id is not None:
        deal.document_id = body.document_id
    if body.assigned_to_user_id is not None:
        deal.assigned_to_user_id = body.assigned_to_user_id
    if body.description is not None:
        deal.description = body.description
    if body.extra_info is not None:
        deal.extra_info = body.extra_info
    if body.closed_at is not None:
        deal.closed_at = body.closed_at
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
    deal_id: Optional[int] = Query(None),
    activity_type: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    q = db.query(CrmActivity).filter(CrmActivity.business_id == business_id)
    if person_id:
        q = q.filter(CrmActivity.person_id == person_id)
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
    person = db.query(Person).filter(and_(Person.id == body.person_id, Person.business_id == business_id)).first()
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
        person_id=body.person_id,
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
    activity = db.query(CrmActivity).filter(
        and_(CrmActivity.id == activity_id, CrmActivity.business_id == business_id)
    ).first()
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
