# noqa: D100
"""
API endpoints برای دستیار AI در CRM: خلاصه سرنخ/فرصت، پیشنهاد متن فعالیت، پیشنهاد احتمال موفقیت
"""
from __future__ import annotations

from typing import Dict, Any, Optional
import logging

from fastapi import APIRouter, Depends, Path, Body, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from adapters.db.session import get_db
from adapters.db.models.crm import Lead, Deal, CrmActivity
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response, ApiError
from app.services.ai.ai_service import AIService
from app.services.ai.prompt_service import get_prompt_by_key
from app.services.ai.ai_crm_parse import parse_probability_percent
from app.services.ai.ai_channel_policy import (
    CHANNEL_CRM,
    CHANNEL_CRM_READ_TOOLS,
    CHANNEL_ITERATION_CAP,
    filter_tools_by_allowlist,
)
from app.services.ai.ai_untrusted import wrap_untrusted_block
from app.services.ai.ai_channel_stream import iter_channel_assist_sse
from app.services.ai.ai_stream_helpers import sse_response_headers

router = APIRouter(prefix="/ai/crm", tags=["AI-CRM"])
logger = logging.getLogger(__name__)


def _tool_names_from_response(response: Dict[str, Any]) -> list:
    names: list = []
    for item in response.get("_function_calls") or []:
        if isinstance(item, dict) and item.get("name"):
            names.append(str(item["name"]))
    return names


async def _run_crm_assist(
    ai_service: AIService,
    messages: list,
    *,
    user_query: str,
    feature: str,
    extra: Dict[str, Any],
) -> Dict[str, Any]:
    catalog = ai_service.get_available_functions(
        session_business_id=ai_service.business_id,
        user_query=user_query,
        execution_mode="analyzer",
        channel="crm",
    )
    tools = filter_tools_by_allowlist(catalog, CHANNEL_CRM_READ_TOOLS)
    response = await ai_service.chat_completion(
        messages,
        tools=tools,
        use_function_calling=True,
        execution_mode="analyzer",
        approve_writes=False,
        user_query=user_query,
        session_business_id=ai_service.business_id,
        iteration_cap=CHANNEL_ITERATION_CAP[CHANNEL_CRM],
    )
    usage = response.get("usage") or {}
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    charge_result = ai_service.check_quota_and_charge(input_tokens, output_tokens)
    ai_service.log_usage(
        provider=ai_service.config.provider if ai_service.config else "openai",
        model=ai_service.config.model_name if ai_service.config else "gpt-4",
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cost=charge_result.get("cost", 0),
        payment_method=charge_result.get("payment_method", "free"),
        wallet_transaction_id=charge_result.get("wallet_transaction_id"),
        document_id=charge_result.get("document_id"),
        context={"feature": feature, **extra},
    )
    response["_charge"] = {
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "total_tokens": input_tokens + output_tokens,
    }
    return response


def _assist_fields(response: Dict[str, Any]) -> Dict[str, Any]:
    citations = response.get("citations") or []
    if not isinstance(citations, list):
        citations = []
    return {
        "tools_used": _tool_names_from_response(response),
        "citations": citations,
    }


def _charge_usage(response: Dict[str, Any]) -> Dict[str, Any]:
    return dict(response.get("_charge") or {})


def _crm_stream_response(
    ai_service: AIService,
    messages: list,
    *,
    user_query: str,
    result_field: str,
    feature: str,
    extra: Dict[str, Any],
) -> StreamingResponse:
    catalog = ai_service.get_available_functions(
        session_business_id=ai_service.business_id,
        user_query=user_query,
        execution_mode="analyzer",
        channel="crm",
    )
    tools = filter_tools_by_allowlist(catalog, CHANNEL_CRM_READ_TOOLS)
    return StreamingResponse(
        iter_channel_assist_sse(
            ai_service,
            messages,
            tools=tools,
            user_query=user_query,
            iteration_cap=CHANNEL_ITERATION_CAP[CHANNEL_CRM],
            result_field=result_field,
            feature=feature,
            extra=extra,
        ),
        media_type="text/event-stream",
        headers=sse_response_headers(),
    )


def _lead_context(lead: Lead) -> str:
    """ساخت متن خلاصه سرنخ برای AI"""
    from app.services.ai.ai_untrusted import mask_email, mask_phone

    parts = [
        f"سرنخ #{lead.id}:",
        f"نام: {lead.name or '-'}",
        f"شرکت: {lead.company_name or '-'}",
        f"موبایل: {mask_phone(lead.mobile)}",
        f"ایمیل: {mask_email(lead.email)}",
        f"مرحله: {lead.stage.name if lead.stage else '-'}",
        f"منبع: {lead.source_code or '-'}",
    ]
    if lead.description:
        parts.append(f"توضیحات: {lead.description[:500]}")
    return "\n".join(parts)


def _deal_context(deal: Deal) -> str:
    """ساخت متن خلاصه فرصت فروش برای AI"""
    parts = [
        f"فرصت #{deal.id}:",
        f"عنوان: {deal.title}",
        f"مشتری: {deal.person.alias_name if deal.person else '-'}",
        f"مبلغ: {deal.amount:,.0f}",
        f"مرحله: {deal.stage.name if deal.stage else '-'}",
        f"احتمال: {deal.probability_percent or '-'}%",
        f"تاریخ سررسید: {deal.expected_close_date or '-'}",
    ]
    if deal.description:
        parts.append(f"توضیحات: {deal.description[:500]}")
    return "\n".join(parts)


def _activities_context(activities: list) -> str:
    """ساخت متن خلاصه فعالیت‌ها برای AI"""
    if not activities:
        return "فعالیتی ثبت نشده است."
    lines = []
    for a in activities[:10]:
        lines.append(f"- {a.activity_type}: {a.subject or a.description or '-'} ({a.activity_date})")
    return "\n".join(lines)


@router.post(
    "/businesses/{business_id}/summarize-lead",
    summary="خلاصه و پیشنهاد مرحله بعد برای سرنخ",
)
@require_business_access("business_id")
async def summarize_lead(
    business_id: int = Path(..., gt=0),
    lead_id: int = Body(..., embed=True),
    stream: bool = Query(False, description="استریم SSE به‌جای JSON"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    """دریافت خلاصه AI و پیشنهاد مرحله بعد برای یک سرنخ"""
    lead = db.query(Lead).filter(
        and_(Lead.id == lead_id, Lead.business_id == business_id)
    ).first()
    if not lead:
        raise ApiError("NOT_FOUND", "سرنخ یافت نشد.", http_status=404)

    ai_service = AIService(db, ctx, business_id=business_id)
    availability = ai_service.check_availability(estimated_tokens=800)
    if not availability["can_use"]:
        raise ApiError(
            availability.get("reason", "AI_UNAVAILABLE"),
            availability.get("details", {}).get("message", "امکان استفاده از AI وجود ندارد"),
            http_status=400,
            extra_data=availability.get("details", {}),
        )

    lead_text = wrap_untrusted_block(
        "crm", _lead_context(lead), title=f"lead-{lead.id}"
    )
    act_q = db.query(CrmActivity).filter(CrmActivity.business_id == business_id)
    if lead.person_id:
        act_q = act_q.filter(
            or_(
                CrmActivity.person_id == lead.person_id,
                CrmActivity.lead_id == lead.id,
            )
        )
    else:
        act_q = act_q.filter(CrmActivity.lead_id == lead.id)
    activities = act_q.order_by(CrmActivity.activity_date.desc()).limit(10).all()
    activities_text = wrap_untrusted_block(
        "crm", _activities_context(activities), title=f"lead-{lead.id}-activities"
    )

    system_prompt = get_prompt_by_key(db, "crm.summarize_lead")

    user_content = f"""اطلاعات سرنخ:
{lead_text}

فعالیت‌های اخیر:
{activities_text}

لطفاً خلاصه و پیشنهاد مرحله بعد را بنویسید. در صورت نیاز از ابزارهای CRM فقط‌خواندنی استفاده کنید."""

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_content},
    ]
    if stream:
        return _crm_stream_response(
            ai_service,
            messages,
            user_query=lead.name or f"lead {lead.id}",
            result_field="summary",
            feature="crm_summarize_lead",
            extra={"lead_id": lead_id},
        )
    response = await _run_crm_assist(
        ai_service,
        messages,
        user_query=lead.name or f"lead {lead.id}",
        feature="crm_summarize_lead",
        extra={"lead_id": lead_id},
    )

    return success_response(
        data={
            "summary": response["message"]["content"],
            "usage": _charge_usage(response),
            **_assist_fields(response),
        },
    )


@router.post(
    "/businesses/{business_id}/summarize-deal",
    summary="خلاصه و پیشنهاد مرحله بعد برای فرصت فروش",
)
@require_business_access("business_id")
async def summarize_deal(
    business_id: int = Path(..., gt=0),
    deal_id: int = Body(..., embed=True),
    stream: bool = Query(False, description="استریم SSE به‌جای JSON"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    """دریافت خلاصه AI و پیشنهاد مرحله بعد برای یک فرصت فروش"""
    deal = db.query(Deal).filter(
        and_(Deal.id == deal_id, Deal.business_id == business_id)
    ).first()
    if not deal:
        raise ApiError("NOT_FOUND", "فرصت فروش یافت نشد.", http_status=404)

    ai_service = AIService(db, ctx, business_id=business_id)
    availability = ai_service.check_availability(estimated_tokens=800)
    if not availability["can_use"]:
        raise ApiError(
            availability.get("reason", "AI_UNAVAILABLE"),
            availability.get("details", {}).get("message", "امکان استفاده از AI وجود ندارد"),
            http_status=400,
            extra_data=availability.get("details", {}),
        )

    deal_text = wrap_untrusted_block(
        "crm", _deal_context(deal), title=f"deal-{deal.id}"
    )
    activities = (
        db.query(CrmActivity)
        .filter(CrmActivity.deal_id == deal_id, CrmActivity.business_id == business_id)
        .order_by(CrmActivity.activity_date.desc())
        .limit(10)
        .all()
    )
    activities_text = wrap_untrusted_block(
        "crm", _activities_context(activities), title=f"deal-{deal.id}-activities"
    )

    system_prompt = get_prompt_by_key(db, "crm.summarize_deal")

    user_content = f"""اطلاعات فرصت:
{deal_text}

فعالیت‌های اخیر:
{activities_text}

لطفاً خلاصه و پیشنهاد مرحله بعد را بنویسید. در صورت نیاز از ابزارهای CRM فقط‌خواندنی استفاده کنید."""

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_content},
    ]
    if stream:
        return _crm_stream_response(
            ai_service,
            messages,
            user_query=deal.title or f"deal {deal.id}",
            result_field="summary",
            feature="crm_summarize_deal",
            extra={"deal_id": deal_id},
        )
    response = await _run_crm_assist(
        ai_service,
        messages,
        user_query=deal.title or f"deal {deal.id}",
        feature="crm_summarize_deal",
        extra={"deal_id": deal_id},
    )

    return success_response(
        data={
            "summary": response["message"]["content"],
            "usage": _charge_usage(response),
            **_assist_fields(response),
        },
    )


@router.post(
    "/businesses/{business_id}/suggest-activity-text",
    summary="پیشنهاد متن فعالیت (تماس، ایمیل، جلسه، یادداشت)",
)
@require_business_access("business_id")
async def suggest_activity_text(
    business_id: int = Path(..., gt=0),
    person_id: int = Body(..., embed=True),
    activity_type: str = Body("note", embed=True),
    deal_id: Optional[int] = Body(None, embed=True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    """پیشنهاد متن برای فعالیت CRM بر اساس شخص و فرصت فروش"""
    from adapters.db.models.person import Person

    person = db.query(Person).filter(
        and_(Person.id == person_id, Person.business_id == business_id)
    ).first()
    if not person:
        raise ApiError("NOT_FOUND", "شخص یافت نشد.", http_status=404)

    deal = None
    if deal_id:
        deal = db.query(Deal).filter(
            and_(Deal.id == deal_id, Deal.business_id == business_id)
        ).first()

    ai_service = AIService(db, ctx, business_id=business_id)
    availability = ai_service.check_availability(estimated_tokens=600)
    if not availability["can_use"]:
        raise ApiError(
            availability.get("reason", "AI_UNAVAILABLE"),
            availability.get("details", {}).get("message", "امکان استفاده از AI وجود ندارد"),
            http_status=400,
            extra_data=availability.get("details", {}),
        )

    from app.services.ai.ai_untrusted import mask_email, mask_phone

    person_info = (
        f"شخص: {person.alias_name}، تلفن: {mask_phone(person.phone)}، "
        f"ایمیل: {mask_email(person.email)}"
    )
    deal_info = ""
    if deal:
        deal_info = f"\nفرصت فروش: {deal.title}، مبلغ: {deal.amount:,.0f}"

    type_desc = {"call": "تماس تلفنی", "email": "ایمیل", "meeting": "جلسه", "note": "یادداشت"}.get(
        activity_type, "یادداشت"
    )

    system_prompt = get_prompt_by_key(
        db,
        "crm.suggest_activity",
        {"activity_type_label": type_desc},
    )

    user_content = f"""اطلاعات:
{wrap_untrusted_block("crm", person_info + deal_info, title=f"person-{person_id}")}

نوع فعالیت: {type_desc}

پیشنهاد متن:"""

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_content},
    ]
    response = await _run_crm_assist(
        ai_service,
        messages,
        user_query=f"{type_desc} {person.alias_name or ''}".strip(),
        feature="crm_suggest_activity_text",
        extra={"person_id": person_id},
    )

    return success_response(
        data={
            "suggested_text": response["message"]["content"],
            **_assist_fields(response),
        }
    )


@router.post(
    "/businesses/{business_id}/suggest-deal-probability",
    summary="پیشنهاد احتمال موفقیت فرصت فروش",
)
@require_business_access("business_id")
async def suggest_deal_probability(
    business_id: int = Path(..., gt=0),
    deal_id: int = Body(..., embed=True),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
    """پیشنهاد احتمال موفقیت (۰-۱۰۰) برای فرصت فروش"""
    deal = db.query(Deal).filter(
        and_(Deal.id == deal_id, Deal.business_id == business_id)
    ).first()
    if not deal:
        raise ApiError("NOT_FOUND", "فرصت فروش یافت نشد.", http_status=404)

    ai_service = AIService(db, ctx, business_id=business_id)
    availability = ai_service.check_availability(estimated_tokens=400)
    if not availability["can_use"]:
        raise ApiError(
            availability.get("reason", "AI_UNAVAILABLE"),
            availability.get("details", {}).get("message", "امکان استفاده از AI وجود ندارد"),
            http_status=400,
            extra_data=availability.get("details", {}),
        )

    deal_text = wrap_untrusted_block(
        "crm", _deal_context(deal), title=f"deal-{deal.id}"
    )
    system_prompt = get_prompt_by_key(db, "crm.suggest_deal_probability")

    user_content = f"""اطلاعات فرصت:
{deal_text}

احتمال موفقیت پیشنهادی (۰-۱۰۰):"""

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_content},
    ]
    response = await _run_crm_assist(
        ai_service,
        messages,
        user_query=deal.title or f"deal {deal.id} probability",
        feature="crm_suggest_deal_probability",
        extra={"deal_id": deal_id},
    )

    raw = (response["message"]["content"] or "").strip()
    probability = parse_probability_percent(raw)
    return success_response(
        data={
            "probability_percent": probability,
            "parse_failed": probability is None,
            **_assist_fields(response),
        }
    )
