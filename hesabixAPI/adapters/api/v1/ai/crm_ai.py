# noqa: D100
"""
API endpoints برای دستیار AI در CRM: خلاصه سرنخ/فرصت، پیشنهاد متن فعالیت، پیشنهاد احتمال موفقیت
"""
from __future__ import annotations

from typing import Dict, Any, Optional
import logging

from fastapi import APIRouter, Depends, Path, Body
from sqlalchemy.orm import Session
from sqlalchemy import and_

from adapters.db.session import get_db
from adapters.db.models.crm import Lead, Deal, CrmActivity
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response, ApiError
from app.services.ai.ai_service import AIService

router = APIRouter(prefix="/ai/crm", tags=["AI-CRM"])
logger = logging.getLogger(__name__)


def _lead_context(lead: Lead) -> str:
    """ساخت متن خلاصه سرنخ برای AI"""
    parts = [
        f"سرنخ #{lead.id}:",
        f"نام: {lead.name or '-'}",
        f"شرکت: {lead.company_name or '-'}",
        f"موبایل: {lead.mobile or '-'}",
        f"ایمیل: {lead.email or '-'}",
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

    lead_text = _lead_context(lead)
    activities = (
        db.query(CrmActivity)
        .filter(CrmActivity.person_id == lead.person_id, CrmActivity.business_id == business_id)
        .order_by(CrmActivity.activity_date.desc())
        .limit(5)
        .all()
    )
    activities_text = _activities_context(activities)

    system_prompt = """شما دستیار فروش CRM هستید. بر اساس اطلاعات سرنخ و فعالیت‌ها، یک خلاصه کوتاه (۲-۳ جمله) و یک پیشنهاد برای مرحله بعد (مثلاً تماس تلفنی، ارسال پیشنهاد، جلسه حضوری) ارائه دهید. پاسخ را به صورت متن ساده و بدون فرمت خاص بنویسید."""

    user_content = f"""اطلاعات سرنخ:
{lead_text}

فعالیت‌های اخیر:
{activities_text}

لطفاً خلاصه و پیشنهاد مرحله بعد را بنویسید."""

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_content},
    ]
    response = await ai_service.chat_completion(messages, use_function_calling=False)

    usage = response.get("usage", {})
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
        context={"feature": "crm_summarize_lead", "lead_id": lead_id},
    )

    return success_response(
        data={
            "summary": response["message"]["content"],
            "usage": {
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "total_tokens": input_tokens + output_tokens,
            },
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

    deal_text = _deal_context(deal)
    activities = (
        db.query(CrmActivity)
        .filter(CrmActivity.deal_id == deal_id, CrmActivity.business_id == business_id)
        .order_by(CrmActivity.activity_date.desc())
        .limit(5)
        .all()
    )
    activities_text = _activities_context(activities)

    system_prompt = """شما دستیار فروش CRM هستید. بر اساس اطلاعات فرصت فروش و فعالیت‌ها، یک خلاصه کوتاه (۲-۳ جمله) و یک پیشنهاد برای مرحله بعد ارائه دهید. پاسخ را به صورت متن ساده بنویسید."""

    user_content = f"""اطلاعات فرصت:
{deal_text}

فعالیت‌های اخیر:
{activities_text}

لطفاً خلاصه و پیشنهاد مرحله بعد را بنویسید."""

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_content},
    ]
    response = await ai_service.chat_completion(messages, use_function_calling=False)

    usage = response.get("usage", {})
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
        context={"feature": "crm_summarize_deal", "deal_id": deal_id},
    )

    return success_response(
        data={
            "summary": response["message"]["content"],
            "usage": {
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "total_tokens": input_tokens + output_tokens,
            },
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

    person_info = f"شخص: {person.alias_name}، تلفن: {person.phone or '-'}، ایمیل: {person.email or '-'}"
    deal_info = ""
    if deal:
        deal_info = f"\nفرصت فروش: {deal.title}، مبلغ: {deal.amount:,.0f}"

    type_desc = {"call": "تماس تلفنی", "email": "ایمیل", "meeting": "جلسه", "note": "یادداشت"}.get(
        activity_type, "یادداشت"
    )

    system_prompt = f"""شما دستیار CRM هستید. بر اساس اطلاعات شخص و فرصت فروش، یک متن کوتاه و حرفه‌ای برای ثبت فعالیت از نوع «{type_desc}» پیشنهاد دهید. متن را مستقیم بنویسید بدون مقدمه."""

    user_content = f"""اطلاعات:
{person_info}{deal_info}

نوع فعالیت: {type_desc}

پیشنهاد متن:"""

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_content},
    ]
    response = await ai_service.chat_completion(messages, use_function_calling=False)

    usage = response.get("usage", {})
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
        context={"feature": "crm_suggest_activity_text", "person_id": person_id},
    )

    return success_response(data={"suggested_text": response["message"]["content"]})


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

    deal_text = _deal_context(deal)
    system_prompt = """شما دستیار فروش CRM هستید. بر اساس مرحله فعلی، مبلغ، تاریخ سررسید و توضیحات فرصت فروش، یک عدد بین ۰ تا ۱۰۰ به عنوان احتمال موفقیت پیشنهاد دهید. فقط عدد را برگردانید، بدون توضیح اضافه."""

    user_content = f"""اطلاعات فرصت:
{deal_text}

احتمال موفقیت پیشنهادی (۰-۱۰۰):"""

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_content},
    ]
    response = await ai_service.chat_completion(messages, use_function_calling=False)

    usage = response.get("usage", {})
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
        context={"feature": "crm_suggest_deal_probability", "deal_id": deal_id},
    )

    raw = response["message"]["content"].strip()
    probability = 50
    for part in raw.replace(",", "").split():
        try:
            n = int(part)
            if 0 <= n <= 100:
                probability = n
                break
        except ValueError:
            continue

    return success_response(data={"probability_percent": probability})
