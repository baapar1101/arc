from __future__ import annotations

import json
from datetime import datetime, timedelta
from decimal import Decimal
from types import SimpleNamespace
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

from sqlalchemy import and_, cast
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.currency import Currency
from adapters.db.models.document import Document
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
from adapters.db.repositories.business_repo import BusinessRepository
from adapters.db.repositories.user_repo import UserRepository
from app.core.auth_dependency import AuthContext
from app.services.currency_quant import get_currency_quant_and_round
from app.services.document_line_fx_service import quantize_money
from app.services.invoice_service import (
    INVOICE_PURCHASE,
    INVOICE_PURCHASE_RETURN,
    INVOICE_SALES,
    INVOICE_SALES_RETURN,
)
from app.services.person_service import amount_in_document_currency_to_base

_STAT_INVOICE_TYPES = (
    INVOICE_SALES,
    INVOICE_SALES_RETURN,
    INVOICE_PURCHASE,
    INVOICE_PURCHASE_RETURN,
)


def get_business_dashboard_data(db: Session, business_id: int, ctx: AuthContext) -> Dict[str, Any]:
    """دریافت داده‌های داشبورد کسب و کار"""
    business_repo = BusinessRepository(db)
    business = business_repo.get_by_id(business_id)
    
    if not business:
        raise ValueError("کسب و کار یافت نشد")
    
    # بررسی دسترسی کاربر
    if not ctx.can_access_business(business_id):
        raise ValueError("دسترسی غیرمجاز")
    
    # دریافت اطلاعات کسب و کار
    business_info = _get_business_info(business, db)
    
    # دریافت آمار
    statistics = _get_business_statistics(business_id, db)
    
    # دریافت فعالیت‌های اخیر
    recent_activities = _get_recent_activities(business_id, db)
    
    return {
        "business_info": business_info,
        "statistics": statistics,
        "recent_activities": recent_activities
    }


def get_business_members(db: Session, business_id: int, ctx: AuthContext) -> Dict[str, Any]:
    """دریافت لیست اعضای کسب و کار"""
    if not ctx.can_access_business(business_id):
        raise ValueError("دسترسی غیرمجاز")
    
    permission_repo = BusinessPermissionRepository(db)
    user_repo = UserRepository(db)
    
    # دریافت دسترسی‌های کسب و کار
    permissions = permission_repo.get_business_users(business_id)
    
    members = []
    for permission in permissions:
        user = user_repo.get_by_id(permission.user_id)
        if user:
            members.append({
                "id": permission.id,
                "user_id": user.id,
                "first_name": user.first_name,
                "last_name": user.last_name,
                "email": user.email,
                "mobile": user.mobile,
                "role": _get_user_role(permission.business_permissions),
                "permissions": permission.business_permissions or {},
                "joined_at": permission.created_at.isoformat()
            })
    
    return {
        "items": members,
        "pagination": {
            "total": len(members),
            "page": 1,
            "per_page": len(members),
            "total_pages": 1,
            "has_next": False,
            "has_prev": False
        }
    }


def get_business_statistics(db: Session, business_id: int, ctx: AuthContext) -> Dict[str, Any]:
    """دریافت آمار تفصیلی کسب و کار"""
    if not ctx.can_access_business(business_id):
        raise ValueError("دسترسی غیرمجاز")
    
    # آمار فروش ماهانه (نمونه)
    sales_by_month = [
        {"month": "2024-01", "amount": 500000},
        {"month": "2024-02", "amount": 750000},
        {"month": "2024-03", "amount": 600000}
    ]
    
    # پرفروش‌ترین محصولات (نمونه)
    top_products = [
        {"name": "محصول A", "sales_count": 100, "revenue": 500000},
        {"name": "محصول B", "sales_count": 80, "revenue": 400000},
        {"name": "محصول C", "sales_count": 60, "revenue": 300000}
    ]
    
    # آمار فعالیت اعضا
    permission_repo = BusinessPermissionRepository(db)
    members = permission_repo.get_business_users(business_id)
    
    member_activity = {
        "active_today": len([m for m in members if m.created_at.date() == datetime.now().date()]),
        "active_this_week": len([m for m in members if m.created_at >= datetime.now() - timedelta(days=7)]),
        "total_members": len(members)
    }
    
    return {
        "sales_by_month": sales_by_month,
        "top_products": top_products,
        "member_activity": member_activity
    }


def _get_business_info(business: Business, db: Session) -> Dict[str, Any]:
    """دریافت اطلاعات کسب و کار"""
    permission_repo = BusinessPermissionRepository(db)
    member_count = len(permission_repo.get_business_users(business.id))
    
    return {
        "id": business.id,
        "name": business.name,
        "business_type": business.business_type.value,
        "business_field": business.business_field.value,
        "owner_id": business.owner_id,
        "address": business.address,
        "phone": business.phone,
        "mobile": business.mobile,
        "created_at": business.created_at.isoformat(),
        "member_count": member_count
    }


def _currency_payload(currency: Optional[Currency]) -> Optional[Dict[str, Any]]:
    if currency is None:
        return None
    return {
        "id": int(currency.id),
        "code": currency.code,
        "title": currency.title,
        "symbol": currency.symbol,
        "decimal_places": int(getattr(currency, "decimal_places", None) or 0),
    }


def _empty_statistics(
    *,
    currency: Optional[Currency] = None,
    active_members: int = 0,
    fiscal_year_id: Optional[int] = None,
) -> Dict[str, Any]:
    return {
        "total_sales": 0.0,
        "total_purchases": 0.0,
        "active_members": int(active_members),
        "recent_transactions": 0,
        "currency": _currency_payload(currency),
        "fiscal_year_id": fiscal_year_id,
    }


def _net_from_document(document: Any) -> Decimal:
    extra = getattr(document, "extra_info", None)
    if not isinstance(extra, dict):
        extra = {}
    totals = extra.get("totals")
    if not isinstance(totals, dict):
        totals = {}
    try:
        return Decimal(str(totals.get("net", 0) or 0))
    except Exception:
        return Decimal(0)


def _signed_net_for_type(document_type: str, net: Decimal) -> Tuple[Decimal, Decimal, int]:
    """برمی‌گرداند (فروش، خرید، تعداد فاکتور فروش). برگشت‌ها با علامت منفی در همان ستون."""
    if document_type == INVOICE_SALES:
        return net, Decimal(0), 1
    if document_type == INVOICE_SALES_RETURN:
        return -net, Decimal(0), 0
    if document_type == INVOICE_PURCHASE:
        return Decimal(0), net, 0
    if document_type == INVOICE_PURCHASE_RETURN:
        return Decimal(0), -net, 0
    return Decimal(0), Decimal(0), 0


def aggregate_invoice_totals_in_base(
    db: Optional[Session],
    documents: Sequence[Any],
    *,
    rate_cache: Optional[Dict[int, Decimal]] = None,
    base_currency_by_business: Optional[Dict[int, Optional[int]]] = None,
) -> Tuple[Decimal, Decimal, int]:
    """جمع فروش و خرید به ارز پایه با نرخ تسعیر سند (extra_info.fx سپس نرخ تاریخ سند)."""
    cache = rate_cache if rate_cache is not None else {}
    base_by_biz = base_currency_by_business if base_currency_by_business is not None else {}
    total_sales = Decimal(0)
    total_purchases = Decimal(0)
    sales_count = 0
    for doc in documents:
        if getattr(doc, "is_proforma", False):
            continue
        doc_type = str(getattr(doc, "document_type", "") or "")
        net = _net_from_document(doc)
        if net == 0:
            _sales_delta, _purchase_delta, count_delta = _signed_net_for_type(
                doc_type, Decimal(0)
            )
            sales_count += count_delta
            continue
        net_base = amount_in_document_currency_to_base(
            db,
            doc,
            net,
            rate_cache=cache,
            base_currency_by_business=base_by_biz,
        )
        sales_delta, purchase_delta, count_delta = _signed_net_for_type(doc_type, net_base)
        total_sales += sales_delta
        total_purchases += purchase_delta
        sales_count += count_delta
    return total_sales, total_purchases, sales_count


def _as_dict(value: Any) -> Optional[Dict[str, Any]]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip().startswith("{"):
        try:
            parsed = json.loads(value)
        except Exception:
            return None
        return parsed if isinstance(parsed, dict) else None
    return None


def _stat_docs_from_rows(rows: Iterable[Any]) -> List[Any]:
    docs: List[Any] = []
    for row in rows:
        totals = _as_dict(getattr(row, "totals", None))
        fx = _as_dict(getattr(row, "fx", None))
        extra: Dict[str, Any] = {}
        if totals is not None:
            extra["totals"] = totals
        if fx is not None:
            extra["fx"] = fx
        docs.append(
            SimpleNamespace(
                id=int(row.id),
                business_id=int(row.business_id),
                currency_id=int(row.currency_id) if row.currency_id is not None else None,
                document_type=row.document_type,
                document_date=row.document_date,
                registered_at=row.registered_at,
                is_proforma=bool(getattr(row, "is_proforma", False)),
                extra_info=extra,
            )
        )
    return docs


def _load_stat_invoice_docs(db: Session, business_id: int, fiscal_year_id: int) -> List[Any]:
    extra_jb = cast(Document.extra_info, JSONB)
    rows = (
        db.query(
            Document.id,
            Document.business_id,
            Document.currency_id,
            Document.document_type,
            Document.document_date,
            Document.registered_at,
            Document.is_proforma,
            extra_jb["totals"].label("totals"),
            extra_jb["fx"].label("fx"),
        )
        .filter(
            and_(
                Document.business_id == business_id,
                Document.fiscal_year_id == fiscal_year_id,
                Document.is_proforma.is_(False),
                Document.document_type.in_(_STAT_INVOICE_TYPES),
            )
        )
        .all()
    )
    return _stat_docs_from_rows(rows)


def _get_business_statistics(business_id: int, db: Session) -> Dict[str, Any]:
    """آمار واقعی سال مالی جاری: فروش/خرید به ارز پایه با تسعیر اسناد چندارزی."""
    permission_repo = BusinessPermissionRepository(db)
    active_members = len(permission_repo.get_business_users(business_id))

    business = db.get(Business, business_id)
    currency: Optional[Currency] = None
    if business is not None and business.default_currency_id:
        currency = db.get(Currency, int(business.default_currency_id))

    fy = (
        db.query(FiscalYear)
        .filter(
            and_(
                FiscalYear.business_id == business_id,
                FiscalYear.is_last.is_(True),
            )
        )
        .first()
    )
    if fy is None:
        return _empty_statistics(currency=currency, active_members=active_members)

    docs = _load_stat_invoice_docs(db, business_id, int(fy.id))
    total_sales, total_purchases, sales_count = aggregate_invoice_totals_in_base(
        db,
        docs,
        rate_cache={},
        base_currency_by_business={
            business_id: int(currency.id) if currency is not None else None
        },
    )

    quant = Decimal("1")
    round_on = True
    if currency is not None:
        quant, round_on = get_currency_quant_and_round(db, int(currency.id))
    total_sales = quantize_money(total_sales, quant, round_on=round_on)
    total_purchases = quantize_money(total_purchases, quant, round_on=round_on)

    return {
        "total_sales": float(total_sales),
        "total_purchases": float(total_purchases),
        "active_members": int(active_members),
        "recent_transactions": int(sales_count),
        "currency": _currency_payload(currency),
        "fiscal_year_id": int(fy.id),
    }


def _get_recent_activities(business_id: int, db: Session) -> List[Dict[str, Any]]:
    """دریافت فعالیت‌های اخیر"""
    # در اینجا می‌توانید فعالیت‌های واقعی را از جداول مربوطه دریافت کنید
    # فعلاً داده‌های نمونه برمی‌گردانیم
    return [
        {
            "id": 1,
            "title": "فروش جدید",
            "description": "فروش محصول A به مبلغ 100,000 تومان",
            "icon": "sell",
            "time_ago": "2 ساعت پیش"
        },
        {
            "id": 2,
            "title": "عضو جدید",
            "description": "احمد احمدی به تیم اضافه شد",
            "icon": "person_add",
            "time_ago": "5 ساعت پیش"
        },
        {
            "id": 3,
            "title": "گزارش ماهانه",
            "description": "گزارش فروش ماه ژانویه تولید شد",
            "icon": "assessment",
            "time_ago": "1 روز پیش"
        }
    ]


def _get_user_role(permissions: Optional[Dict[str, Any]]) -> str:
    """تعیین نقش کاربر بر اساس دسترسی‌ها"""
    if not permissions:
        return "عضو"
    
    # بررسی دسترسی‌های مختلف برای تعیین نقش
    if permissions.get("settings", {}).get("manage_users"):
        return "مدیر"
    elif permissions.get("sales", {}).get("write"):
        return "مدیر فروش"
    elif permissions.get("accounting", {}).get("write"):
        return "حسابدار"
    else:
        return "عضو"
