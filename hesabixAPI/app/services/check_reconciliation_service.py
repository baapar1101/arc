from __future__ import annotations

from typing import Any, Dict, List, Optional
from datetime import datetime, timedelta
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from adapters.db.models.check import Check, CheckReconciliation, CheckReconciliationItem, CheckStatus
from adapters.db.models.currency import Currency
from adapters.db.models.person import Person
from app.core.responses import ApiError


def _parse_iso(dt: str | datetime) -> datetime:
    """تبدیل تاریخ ISO به datetime"""
    if isinstance(dt, datetime):
        return dt
    try:
        return datetime.fromisoformat(str(dt).replace('Z', '+00:00'))
    except Exception:
        raise ApiError("INVALID_DATE", f"Invalid date: {dt}", http_status=400)


def calculate_checks_reconciliation(
    db: Session,
    business_id: int,
    check_ids: List[int],
    base_date: datetime | str,
    currency_id: Optional[int] = None
) -> Dict[str, Any]:
    """
    محاسبه راس چک‌ها
    
    فرمول: راس = (مجموع (مبلغ × تعداد روز تا سررسید)) / مجموع مبالغ
    
    Args:
        db: جلسه دیتابیس
        business_id: شناسه کسب‌وکار
        check_ids: لیست شناسه چک‌ها
        base_date: تاریخ مبنا (معمولاً تاریخ امروز)
        currency_id: فیلتر بر اساس ارز (اختیاری)
    
    Returns:
        {
            "average_days": 28.75,
            "calculated_date": datetime,
            "total_amount": 8000000,
            "check_count": 3,
            "items": [
                {
                    "check_id": 1,
                    "check_number": "123",
                    "amount": 3000000,
                    "due_date": datetime,
                    "days_to_maturity": 20,
                    "weighted_value": 60000000
                },
                ...
            ]
        }
    """
    if not check_ids or len(check_ids) < 2:
        raise ApiError("INSUFFICIENT_CHECKS", "حداقل 2 چک برای محاسبه راس لازم است", http_status=400)
    
    base_date_dt = _parse_iso(base_date)
    
    # بارگذاری چک‌ها
    query = db.query(Check).filter(
        and_(
            Check.business_id == business_id,
            Check.id.in_(check_ids)
        )
    )
    
    if currency_id:
        query = query.filter(Check.currency_id == currency_id)
    
    checks = query.all()
    
    if len(checks) != len(check_ids):
        raise ApiError("CHECKS_NOT_FOUND", "برخی چک‌ها پیدا نشدند", http_status=404)
    
    # بررسی ارز یکسان
    currency_ids = {c.currency_id for c in checks}
    if len(currency_ids) > 1:
        raise ApiError("MIXED_CURRENCIES", "تمام چک‌ها باید ارز یکسان داشته باشند", http_status=400)
    
    currency_id = checks[0].currency_id
    
    # بررسی وضعیت چک‌ها (چک‌های پاس شده یا ابطال شده قابل محاسبه نیستند)
    invalid_statuses = [CheckStatus.CLEARED, CheckStatus.CANCELLED]
    invalid_checks = [c for c in checks if c.status in invalid_statuses]
    if invalid_checks:
        check_numbers = [c.check_number for c in invalid_checks]
        raise ApiError(
            "INVALID_CHECK_STATUS",
            f"چک‌های پاس شده یا ابطال شده قابل محاسبه نیستند: {', '.join(check_numbers)}",
            http_status=400
        )
    
    # محاسبه راس
    total_weighted = Decimal(0)
    total_amount = Decimal(0)
    items: List[Dict[str, Any]] = []
    
    for check in checks:
        amount = Decimal(str(check.amount))
        days_to_maturity = (check.due_date - base_date_dt).days
        
        # بررسی اینکه تاریخ سررسید بعد از تاریخ مبنا باشد
        if days_to_maturity < 0:
            raise ApiError(
                "INVALID_DUE_DATE",
                f"تاریخ سررسید چک {check.check_number} قبل از تاریخ مبنا است",
                http_status=400
            )
        
        weighted_value = amount * Decimal(str(days_to_maturity))
        total_weighted += weighted_value
        total_amount += amount
        
        items.append({
            "check_id": check.id,
            "check_number": check.check_number,
            "person_name": check.person.alias_name if check.person else None,
            "amount": float(amount),
            "due_date": check.due_date.isoformat(),
            "days_to_maturity": days_to_maturity,
            "weighted_value": float(weighted_value),
        })
    
    if total_amount == 0:
        raise ApiError("ZERO_AMOUNT", "مجموع مبالغ چک‌ها نمی‌تواند صفر باشد", http_status=400)
    
    average_days = float(total_weighted / total_amount)
    calculated_date = base_date_dt + timedelta(days=average_days)
    
    return {
        "average_days": round(average_days, 2),
        "calculated_date": calculated_date.isoformat(),
        "total_amount": float(total_amount),
        "check_count": len(checks),
        "currency_id": currency_id,
        "base_date": base_date_dt.isoformat(),
        "items": items,
    }


def create_reconciliation(
    db: Session,
    business_id: int,
    user_id: int,
    data: Dict[str, Any]
) -> Dict[str, Any]:
    """
    ایجاد و ذخیره جلسه راس‌گیری
    
    Args:
        db: جلسه دیتابیس
        business_id: شناسه کسب‌وکار
        user_id: شناسه کاربر
        data: {
            "name": "نام جلسه",
            "check_ids": [1, 2, 3],
            "base_date": "2024-01-15T00:00:00",
            "description": "توضیحات اختیاری"
        }
    
    Returns:
        اطلاعات جلسه راس‌گیری ایجاد شده
    """
    name = str(data.get("name", "")).strip()
    if not name:
        raise ApiError("NAME_REQUIRED", "نام جلسه راس‌گیری الزامی است", http_status=400)
    
    check_ids = data.get("check_ids", [])
    if not isinstance(check_ids, list) or len(check_ids) < 2:
        raise ApiError("INSUFFICIENT_CHECKS", "حداقل 2 چک برای محاسبه راس لازم است", http_status=400)
    
    base_date = _parse_iso(data.get("base_date"))
    description = (str(data.get("description", "")).strip() or None) if data.get("description") else None
    
    # محاسبه راس
    calculation_result = calculate_checks_reconciliation(
        db, business_id, check_ids, base_date
    )
    
    currency_id = calculation_result["currency_id"]
    
    # ایجاد رکورد راس‌گیری
    reconciliation = CheckReconciliation(
        business_id=business_id,
        name=name,
        base_date=base_date,
        calculated_average_days=calculation_result["average_days"],
        calculated_date=_parse_iso(calculation_result["calculated_date"]),
        total_amount=calculation_result["total_amount"],
        check_count=calculation_result["check_count"],
        currency_id=currency_id,
        description=description,
        created_by_user_id=user_id,
    )
    
    db.add(reconciliation)
    db.flush()
    
    # ایجاد آیتم‌های راس‌گیری
    for item in calculation_result["items"]:
        reconciliation_item = CheckReconciliationItem(
            reconciliation_id=reconciliation.id,
            check_id=item["check_id"],
            days_to_maturity=item["days_to_maturity"],
            weighted_value=item["weighted_value"],
        )
        db.add(reconciliation_item)
    
    db.commit()
    db.refresh(reconciliation)
    
    return reconciliation_to_dict(db, reconciliation)


def get_reconciliation_by_id(db: Session, reconciliation_id: int) -> Optional[Dict[str, Any]]:
    """دریافت جلسه راس‌گیری بر اساس شناسه"""
    reconciliation = db.query(CheckReconciliation).filter(
        CheckReconciliation.id == reconciliation_id
    ).first()
    
    return reconciliation_to_dict(db, reconciliation) if reconciliation else None


def list_reconciliations(
    db: Session,
    business_id: int,
    query: Dict[str, Any]
) -> Dict[str, Any]:
    """لیست جلسات راس‌گیری"""
    q = db.query(CheckReconciliation).filter(
        CheckReconciliation.business_id == business_id
    )
    
    # جستجو
    if query.get("search") and query.get("search_fields"):
        term = f"%{query['search']}%"
        conditions = []
        for f in query["search_fields"]:
            if f == "name":
                conditions.append(CheckReconciliation.name.ilike(term))
        if conditions:
            from sqlalchemy import or_
            q = q.filter(or_(*conditions))
    
    # مرتب‌سازی
    sort_by = query.get("sort_by") or "created_at"
    sort_desc = bool(query.get("sort_desc", True))
    col = getattr(CheckReconciliation, sort_by, CheckReconciliation.created_at)
    q = q.order_by(col.desc() if sort_desc else col.asc())
    
    # صفحه‌بندی
    skip = int(query.get("skip", 0))
    take = int(query.get("take", 20))
    total = q.count()
    items = q.offset(skip).limit(take).all()
    
    return {
        "items": [reconciliation_to_dict(db, i) for i in items],
        "pagination": {
            "total": total,
            "page": (skip // take) + 1,
            "per_page": take,
            "total_pages": (total + take - 1) // take,
            "has_next": skip + take < total,
            "has_prev": skip > 0,
        },
        "query_info": query,
    }


def delete_reconciliation(db: Session, reconciliation_id: int) -> bool:
    """حذف جلسه راس‌گیری"""
    reconciliation = db.query(CheckReconciliation).filter(
        CheckReconciliation.id == reconciliation_id
    ).first()
    
    if not reconciliation:
        raise ApiError("RECONCILIATION_NOT_FOUND", "جلسه راس‌گیری پیدا نشد", http_status=404)
    
    db.delete(reconciliation)
    db.commit()
    return True


def reconciliation_to_dict(db: Session, obj: Optional[CheckReconciliation]) -> Optional[Dict[str, Any]]:
    """تبدیل مدل به دیکشنری"""
    if obj is None:
        return None
    
    # بارگذاری آیتم‌ها
    items = db.query(CheckReconciliationItem).filter(
        CheckReconciliationItem.reconciliation_id == obj.id
    ).all()
    
    currency_title = None
    try:
        c = db.query(Currency).filter(Currency.id == obj.currency_id).first()
        currency_title = c.title or c.code if c else None
    except Exception:
        pass
    
    items_data = []
    for item in items:
        check = db.query(Check).filter(Check.id == item.check_id).first()
        items_data.append({
            "id": item.id,
            "check_id": item.check_id,
            "check_number": check.check_number if check else None,
            "person_name": check.person.alias_name if check and check.person else None,
            "amount": float(check.amount) if check else 0,
            "due_date": check.due_date.isoformat() if check else None,
            "days_to_maturity": item.days_to_maturity,
            "weighted_value": float(item.weighted_value),
        })
    
    return {
        "id": obj.id,
        "business_id": obj.business_id,
        "name": obj.name,
        "base_date": obj.base_date.isoformat(),
        "calculated_average_days": float(obj.calculated_average_days),
        "calculated_date": obj.calculated_date.isoformat(),
        "total_amount": float(obj.total_amount),
        "check_count": obj.check_count,
        "currency_id": obj.currency_id,
        "currency": currency_title,
        "description": obj.description,
        "created_by_user_id": obj.created_by_user_id,
        "created_at": obj.created_at.isoformat(),
        "updated_at": obj.updated_at.isoformat(),
        "items": items_data,
    }

