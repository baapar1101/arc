from __future__ import annotations

from typing import Dict, Any, Optional
from fastapi import APIRouter, Depends, Request, Query, Path
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, date

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from adapters.db.repositories.ai_usage_log_repository import AIUsageLogRepository
from adapters.db.repositories.ai_invoice_repository import AIInvoiceRepository

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

