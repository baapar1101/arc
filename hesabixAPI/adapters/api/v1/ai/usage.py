from typing import Dict, Any, Optional, List
from fastapi import APIRouter, Depends, Request, Query, Path, Body
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, date

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from adapters.db.repositories.ai_usage_log_repository import AIUsageLogRepository
from adapters.db.repositories.ai_invoice_repository import AIInvoiceRepository
from adapters.api.v1.schemas import QueryInfo, FilterItem
from app.services.ai.ai_invoice_service import pay_ai_invoice_from_wallet

router = APIRouter(prefix="/ai/usage", tags=["ai-usage"])


@router.get("/stats", summary="آمار استفاده از AI")
async def get_usage_stats(
    request: Request,
    business_id: Optional[int] = None,
    start_date: Optional[str] = Query(None, description="تاریخ شروع (ISO format)"),
    end_date: Optional[str] = Query(None, description="تاریخ پایان (ISO format)"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت آمار استفاده از AI"""
    business_id = business_id or ctx.business_id
    
    if not business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    
    # بررسی دسترسی
    if not ctx.is_business_owner(business_id) and not ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "دسترسی به این اطلاعات ندارید", http_status=403)
    
    # پارس کردن تاریخ‌ها
    start = None
    end = None
    if start_date:
        start = datetime.fromisoformat(start_date.replace('Z', '+00:00'))
    if end_date:
        end = datetime.fromisoformat(end_date.replace('Z', '+00:00'))
    
    # اگر تاریخ مشخص نشده، 30 روز گذشته
    if not start:
        end = end or datetime.utcnow()
        start = end - timedelta(days=30)
    else:
        end = end or datetime.utcnow()
    
    repo = AIUsageLogRepository(db)
    
    # آمار کلی
    total_usage = repo.get_business_usage_stats(
        business_id=business_id,
        start_date=start,
        end_date=end
    )
    
    # آمار روزانه
    daily_usage = repo.get_daily_usage_stats(
        business_id=business_id,
        start_date=start,
        end_date=end
    )
    
    # آمار بر اساس مدل
    model_stats = repo.get_model_usage_stats(
        business_id=business_id,
        start_date=start,
        end_date=end
    )
    
    # تبدیل تاریخ‌ها به فرمت ISO string
    def format_date(d):
        """تبدیل تاریخ به ISO string"""
        if d is None:
            return None
        if isinstance(d, datetime):
            return d.isoformat()
        if isinstance(d, date):
            return d.isoformat()
        if isinstance(d, str):
            return d
        return str(d)
    
    return success_response({
        "period": {
            "start_date": start.isoformat() if start else None,
            "end_date": end.isoformat() if end else None
        },
        "total": {
            "total_tokens": int(total_usage.get("total_tokens", 0) or 0),
            "input_tokens": int(total_usage.get("input_tokens", 0) or 0),
            "output_tokens": int(total_usage.get("output_tokens", 0) or 0),
            "total_cost": float(total_usage.get("total_cost", 0) or 0),
            "total_requests": int(total_usage.get("total_requests", 0) or 0)
        },
        "daily": [
            {
                "date": format_date(day.get("date")),
                "tokens": int(day.get("tokens", 0) or 0),
                "cost": float(day.get("cost", 0) or 0),
                "requests": int(day.get("requests", 0) or 0)
            }
            for day in daily_usage
        ],
        "by_model": [
            {
                "model": str(model.get("model", "")),
                "tokens": int(model.get("tokens", 0) or 0),
                "cost": float(model.get("cost", 0) or 0),
                "requests": int(model.get("requests", 0) or 0)
            }
            for model in model_stats
        ]
    }, request)


@router.get("/logs", summary="لاگ استفاده از AI")
async def get_usage_logs(
    request: Request,
    business_id: Optional[int] = None,
    limit: int = Query(50, ge=1, le=100),
    skip: int = Query(0, ge=0),
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت لاگ استفاده از AI"""
    business_id = business_id or ctx.business_id
    
    if not business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    
    # بررسی دسترسی
    if not ctx.is_business_owner(business_id) and not ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "دسترسی به این اطلاعات ندارید", http_status=403)
    
    # پارس کردن تاریخ‌ها
    start = None
    end = None
    if start_date:
        start = datetime.fromisoformat(start_date.replace('Z', '+00:00'))
    if end_date:
        end = datetime.fromisoformat(end_date.replace('Z', '+00:00'))
    
    repo = AIUsageLogRepository(db)
    logs = repo.get_business_logs(
        business_id=business_id,
        start_date=start,
        end_date=end,
        limit=limit,
        skip=skip
    )
    
    result = []
    for log in logs:
        result.append({
            "id": log.id,
            "provider": log.provider,
            "model": log.model,
            "input_tokens": log.input_tokens,
            "output_tokens": log.output_tokens,
            "total_tokens": log.input_tokens + log.output_tokens,
            "cost": float(log.cost),
            "payment_method": log.payment_method,
            "wallet_transaction_id": log.wallet_transaction_id,
            "document_id": log.document_id,
            "created_at": log.created_at.isoformat() if log.created_at else None
        })
    
    return success_response(result, request)


@router.post("/logs/table", summary="جدول لاگ استفاده از AI")
async def get_usage_logs_table(
    request: Request,
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت لاگ استفاده از AI به صورت جدول با فیلتر پیشرفته"""
    business_id = payload.get("business_id") or ctx.business_id

    if not business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)

    if not ctx.is_business_owner(business_id) and not ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "دسترسی به این اطلاعات ندارید", http_status=403)

    # استخراج پارامترهای QueryInfo از payload
    query_payload: Dict[str, Any] = {}
    for field_name in QueryInfo.model_fields:
        if field_name in payload:
            query_payload[field_name] = payload[field_name]

    query_info = QueryInfo(**query_payload)

    # فیلتر پایه برای محدود کردن داده‌ها به کسب‌وکار فعلی
    filters = [FilterItem(property="business_id", operator="=", value=business_id)]
    if query_info.filters:
        filters.extend(query_info.filters)

    effective_query = QueryInfo(
        sort=query_info.sort,
        sort_by=query_info.sort_by or "created_at",
        sort_desc=query_info.sort_desc,
        take=query_info.take,
        skip=query_info.skip,
        search=query_info.search,
        search_fields=query_info.search_fields or ["model", "provider", "payment_method"],
        filters=filters,
    )

    repo = AIUsageLogRepository(db)
    items, total = repo.query_with_filters(effective_query)

    serialized: list[dict[str, Any]] = []
    total_input = 0
    total_output = 0
    total_cost = 0.0

    for log in items:
        input_tokens = log.input_tokens or 0
        output_tokens = log.output_tokens or 0
        cost_value = float(log.cost or 0)

        total_input += input_tokens
        total_output += output_tokens
        total_cost += cost_value

        serialized.append({
            "id": log.id,
            "business_id": log.business_id,
            "provider": log.provider,
            "model": log.model,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "total_tokens": input_tokens + output_tokens,
            "cost": cost_value,
            "payment_method": log.payment_method,
            "wallet_transaction_id": log.wallet_transaction_id,
            "document_id": log.document_id,
            "created_at": log.created_at,
        })

    limit = max(1, effective_query.take)
    page = (effective_query.skip // limit) + 1
    total_pages = (total + limit - 1) // limit

    summary = {
        "page_total_input_tokens": total_input,
        "page_total_output_tokens": total_output,
        "page_total_tokens": total_input + total_output,
        "page_total_cost": total_cost,
    }

    data = {
        "items": serialized,
        "pagination": {
            "total": total,
            "page": page,
            "per_page": limit,
            "total_pages": total_pages,
            "has_next": page < total_pages,
            "has_prev": page > 1,
        },
        "summary": summary,
        "query_info": {
            **effective_query.model_dump(),
            "business_id": business_id,
        },
    }

    return success_response(data, request)


@router.post("/daily/table", summary="آمار روزانه AI به صورت جدول")
async def get_daily_usage_table(
    request: Request,
    payload: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت آمار استفاده روزانه با قابلیت صفحه‌بندی و فیلتر"""
    business_id = payload.get("business_id") or ctx.business_id

    if not business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)

    if not ctx.is_business_owner(business_id) and not ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "دسترسی به این اطلاعات ندارید", http_status=403)

    start_date_str = payload.get("start_date")
    end_date_str = payload.get("end_date")

    def _parse_date(value: Optional[str]) -> Optional[datetime]:
        if not value:
            return None
        return datetime.fromisoformat(value.replace('Z', '+00:00'))

    start = _parse_date(start_date_str)
    end = _parse_date(end_date_str)

    if not start:
        end = end or datetime.utcnow()
        start = end - timedelta(days=30)
    else:
        end = end or datetime.utcnow()

    # استخراج QueryInfo
    query_payload: Dict[str, Any] = {}
    for field_name in QueryInfo.model_fields:
        if field_name in payload:
            query_payload[field_name] = payload[field_name]
    query_info = QueryInfo(**query_payload)

    # فیلترهای سفارشی برای تاریخ
    filter_start: Optional[date] = None
    filter_end: Optional[date] = None
    if query_info.filters:
        for f in query_info.filters:
            if f.property == "date":
                try:
                    filter_value = datetime.fromisoformat(str(f.value).replace('Z', '+00:00')).date()
                except Exception:
                    continue
                if f.operator in (">=", ">"):
                    filter_start = filter_value
                elif f.operator in ("<", "<="):
                    filter_end = filter_value

    repo = AIUsageLogRepository(db)
    daily_usage = repo.get_daily_usage_stats(
        business_id=business_id,
        start_date=start,
        end_date=end,
    )

    items: List[Dict[str, Any]] = []
    for entry in daily_usage:
        entry_date = entry.get("date")
        if isinstance(entry_date, datetime):
            entry_date_obj = entry_date.date()
        elif isinstance(entry_date, date):
            entry_date_obj = entry_date
        else:
            entry_date_obj = datetime.fromisoformat(str(entry_date)).date()

        row = {
            "date": entry_date_obj.isoformat(),
            "_date_obj": entry_date_obj,
            "tokens": int(entry.get("tokens", 0) or 0),
            "cost": float(entry.get("cost", 0) or 0),
            "requests": int(entry.get("requests", 0) or 0),
        }
        items.append(row)

    # اعمال فیلتر تاریخ
    if filter_start:
        items = [item for item in items if item["_date_obj"] >= filter_start]
    if filter_end:
        items = [item for item in items if item["_date_obj"] <= filter_end]

    effective_query = QueryInfo(
        sort=query_info.sort,
        sort_by=query_info.sort_by or "date",
        sort_desc=query_info.sort_desc,
        take=query_info.take,
        skip=query_info.skip,
        search=query_info.search,
        search_fields=query_info.search_fields,
        filters=query_info.filters,
    )

    # جستجو بر اساس تاریخ
    if effective_query.search:
        search_term = effective_query.search.lower()
        items = [item for item in items if search_term in item["date"].lower()]

    # مرتب‌سازی (در حافظه؛ چندستونه: فقط اولین سطح)
    sort_key = effective_query.sort_by or "date"
    reverse = bool(effective_query.sort_desc)
    if query_info.sort:
        try:
            sort_key = str(query_info.sort[0].by or sort_key)
            reverse = bool(query_info.sort[0].desc)
        except Exception:
            pass
    if sort_key == "tokens":
        items.sort(key=lambda x: x["tokens"], reverse=reverse)
    elif sort_key == "cost":
        items.sort(key=lambda x: x["cost"], reverse=reverse)
    elif sort_key == "requests":
        items.sort(key=lambda x: x["requests"], reverse=reverse)
    else:
        items.sort(key=lambda x: x["_date_obj"], reverse=reverse)

    total = len(items)
    limit = max(1, effective_query.take)
    start_index = effective_query.skip
    end_index = min(start_index + limit, total)
    page_items = items[start_index:end_index]

    # تلخیص صفحه
    page_total_tokens = sum(item["tokens"] for item in page_items)
    page_total_cost = sum(item["cost"] for item in page_items)
    page_total_requests = sum(item["requests"] for item in page_items)

    for item in page_items:
        item.pop("_date_obj", None)

    pagination = {
        "total": total,
        "page": (effective_query.skip // limit) + 1,
        "per_page": limit,
        "total_pages": (total + limit - 1) // limit,
        "has_next": end_index < total,
        "has_prev": effective_query.skip > 0,
    }

    data = {
        "items": page_items,
        "pagination": pagination,
        "summary": {
            "page_total_tokens": page_total_tokens,
            "page_total_cost": page_total_cost,
            "page_total_requests": page_total_requests,
        },
        "period": {
            "start_date": start.isoformat(),
            "end_date": end.isoformat() if end else None,
        },
        "query_info": {
            **effective_query.model_dump(),
            "business_id": business_id,
        },
    }

    return success_response(data, request)


@router.get("/invoices", summary="لیست فاکتورهای AI")
async def get_ai_invoices(
    request: Request,
    business_id: Optional[int] = None,
    invoice_type: Optional[str] = Query(None, description="نوع فاکتور: subscription, usage, renewal"),
    limit: int = Query(50, ge=1, le=100),
    skip: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت لیست فاکتورهای AI"""
    business_id = business_id or ctx.business_id
    
    if not business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    
    # بررسی دسترسی
    if not ctx.is_business_owner(business_id) and not ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "دسترسی به این اطلاعات ندارید", http_status=403)
    
    repo = AIInvoiceRepository(db)
    invoices = repo.get_business_invoices(
        business_id=business_id,
        invoice_type=invoice_type,
        limit=limit,
        skip=skip
    )
    
    result = []
    for invoice in invoices:
        result.append({
            "id": invoice.id,
            "invoice_type": invoice.invoice_type,
            "amount": float(invoice.amount),
            "currency": invoice.currency,
            "status": invoice.status,
            "wallet_transaction_id": invoice.wallet_transaction_id,
            "document_id": invoice.document_id,
            "plan_id": invoice.plan_id,
            "subscription_id": invoice.subscription_id,
            "created_at": invoice.created_at.isoformat() if invoice.created_at else None,
            "paid_at": invoice.paid_at.isoformat() if invoice.paid_at else None
        })
    
    return success_response(result, request)


@router.get("/invoices/{invoice_id}", summary="جزئیات فاکتور AI")
async def get_ai_invoice_details(
    invoice_id: int = Path(...),
    request: Request = None,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """دریافت جزئیات یک فاکتور AI"""
    repo = AIInvoiceRepository(db)
    invoice = repo.get_by_id(invoice_id)
    
    if not invoice:
        raise ApiError("INVOICE_NOT_FOUND", "فاکتور یافت نشد", http_status=404)
    
    # بررسی دسترسی
    if not ctx.is_business_owner(invoice.business_id) and not ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "دسترسی به این فاکتور ندارید", http_status=403)
    
    return success_response({
        "id": invoice.id,
        "invoice_type": invoice.invoice_type,
        "amount": float(invoice.amount),
        "currency": invoice.currency,
        "status": invoice.status,
        "wallet_transaction_id": invoice.wallet_transaction_id,
        "document_id": invoice.document_id,
        "plan_id": invoice.plan_id,
        "subscription_id": invoice.subscription_id,
        "metadata": invoice.metadata,
        "created_at": invoice.created_at.isoformat() if invoice.created_at else None,
        "paid_at": invoice.paid_at.isoformat() if invoice.paid_at else None
    }, request)


@router.post(
    "/invoices/{invoice_id}/pay",
    summary="پرداخت صورتحساب AI از کیف پول",
    description="برای فاکتورهای در وضعیت issued (مثلاً قبل از اصلاح خودکار subscribe)",
)
async def post_pay_ai_invoice(
    request: Request,
    invoice_id: int = Path(...),
    business_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    business_id = business_id or ctx.business_id
    if not business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if not ctx.is_business_owner(business_id) and not ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "دسترسی به این عملیات ندارید", http_status=403)
    data = pay_ai_invoice_from_wallet(
        db=db,
        business_id=int(business_id),
        invoice_id=invoice_id,
        user_id=ctx.get_user_id(),
    )
    return success_response(data, request, "صورتحساب با موفقیت پرداخت شد")

