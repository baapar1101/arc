from __future__ import annotations

from typing import Dict, Any, Optional, List
from decimal import Decimal
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
import json
import logging

from app.core.responses import ApiError
from adapters.db.models.ai_plan import AIPlan, AIPlanType
from adapters.db.models.ai_subscription import UserAISubscription, SubscriptionType
from adapters.db.models.ai_invoice import AIInvoice, AIInvoiceType
from adapters.db.repositories.ai_plan_repository import AIPlanRepository
from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
from app.services.ai.ai_invoice_service import create_subscription_invoice
from app.services.system_settings_service import get_wallet_settings

logger = logging.getLogger(__name__)


def create_plan(
    db: Session,
    code: str,
    name: str,
    plan_type: str,
    pricing_config: Dict[str, Any],
    usage_limits: Dict[str, Any],
    features: Dict[str, Any],
    description: Optional[str] = None
) -> AIPlan:
    """ایجاد پلن جدید"""
    repo = AIPlanRepository(db)
    
    # بررسی تکراری نبودن کد
    existing = repo.get_by_code(code)
    if existing:
        raise ApiError("DUPLICATE_PLAN_CODE", "کد پلن تکراری است", http_status=400)
    
    plan = AIPlan(
        code=code,
        name=name,
        description=description,
        plan_type=plan_type,
        pricing_config=json.dumps(pricing_config, ensure_ascii=False),
        usage_limits=json.dumps(usage_limits, ensure_ascii=False),
        features=json.dumps(features, ensure_ascii=False),
        is_active=True,
        auto_renew=False  # پیش‌فرض
    )
    
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return plan


def update_plan(
    db: Session,
    plan_id: int,
    name: Optional[str] = None,
    description: Optional[str] = None,
    pricing_config: Optional[Dict[str, Any]] = None,
    usage_limits: Optional[Dict[str, Any]] = None,
    features: Optional[Dict[str, Any]] = None,
    is_active: Optional[bool] = None
) -> AIPlan:
    """به‌روزرسانی پلن"""
    repo = AIPlanRepository(db)
    plan = repo.get_by_id(plan_id)
    
    if not plan:
        raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)
    
    if name is not None:
        plan.name = name
    if description is not None:
        plan.description = description
    if pricing_config is not None:
        plan.pricing_config = json.dumps(pricing_config, ensure_ascii=False)
    if usage_limits is not None:
        plan.usage_limits = json.dumps(usage_limits, ensure_ascii=False)
    if features is not None:
        plan.features = json.dumps(features, ensure_ascii=False)
    if is_active is not None:
        plan.is_active = is_active
    
    db.commit()
    db.refresh(plan)
    return plan


def subscribe_to_plan(
    db: Session,
    user_id: int,
    business_id: Optional[int],
    plan_id: int,
    period: str = "monthly"  # monthly, yearly
) -> Dict[str, Any]:
    """
    اشتراک به پلن
    - اگر subscription: ایجاد invoice و پرداخت
    - اگر free: فعال‌سازی مستقیم
    - اگر pay_as_go: فقط ثبت subscription
    """
    plan_repo = AIPlanRepository(db)
    plan = plan_repo.get_by_id(plan_id)
    
    if not plan or not plan.is_active:
        raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد یا غیرفعال است", http_status=404)
    
    # بررسی اشتراک فعال قبلی
    sub_repo = AISubscriptionRepository(db)
    existing = sub_repo.get_active_subscription(user_id, business_id)
    if existing:
        # غیرفعال کردن اشتراک قبلی
        existing.is_active = False
        db.flush()
    
    # تعیین نوع اشتراک
    if plan.plan_type == AIPlanType.FREE.value:
        subscription_type = SubscriptionType.FREE.value
        tokens_limit = json.loads(plan.usage_limits or "{}").get("monthly_tokens", 0)
        period_start = datetime.utcnow()
        period_end = None  # رایگان نامحدود است
    elif plan.plan_type == AIPlanType.SUBSCRIPTION.value:
        subscription_type = SubscriptionType.SUBSCRIPTION.value
        tokens_limit = json.loads(plan.usage_limits or "{}").get("monthly_tokens", 0)
        period_start = datetime.utcnow()
        if period == "monthly":
            period_end = period_start + timedelta(days=30)
        else:  # yearly
            period_end = period_start + timedelta(days=365)
    elif plan.plan_type == AIPlanType.PAY_AS_GO.value:
        subscription_type = SubscriptionType.PAY_AS_GO.value
        tokens_limit = None
        period_start = datetime.utcnow()
        period_end = None
    elif plan.plan_type == AIPlanType.HYBRID.value:
        subscription_type = SubscriptionType.SUBSCRIPTION.value
        tokens_limit = json.loads(plan.usage_limits or "{}").get("monthly_tokens", 0)
        period_start = datetime.utcnow()
        if period == "monthly":
            period_end = period_start + timedelta(days=30)
        else:
            period_end = period_start + timedelta(days=365)
    else:
        raise ApiError("INVALID_PLAN_TYPE", "نوع پلن نامعتبر است", http_status=400)
    
    # ایجاد اشتراک
    subscription = UserAISubscription(
        user_id=user_id,
        business_id=business_id,
        plan_id=plan_id,
        subscription_type=subscription_type,
        tokens_used=0,
        tokens_limit=tokens_limit,
        period_start=period_start,
        period_end=period_end,
        is_active=True,
        auto_renew=False
    )
    db.add(subscription)
    db.flush()
    
    # اگر subscription یا hybrid است، ایجاد invoice
    invoice = None
    if plan.plan_type in [AIPlanType.SUBSCRIPTION.value, AIPlanType.HYBRID.value]:
        pricing_config = json.loads(plan.pricing_config or "{}")
        subscription_config = pricing_config.get("subscription", {})
        
        if period == "monthly":
            amount = Decimal(str(subscription_config.get("monthly_price", 0)))
        else:
            amount = Decimal(str(subscription_config.get("yearly_price", 0)))
        
        if amount > 0:
            wallet_settings = get_wallet_settings(db)
            currency_id = wallet_settings.get("wallet_base_currency_id")
            if not currency_id:
                raise ApiError("CURRENCY_NOT_SET", "ارز پایه کیف پول تنظیم نشده است", http_status=400)
            
            invoice = create_subscription_invoice(
                db=db,
                subscription_id=subscription.id,
                business_id=business_id or 0,  # اگر business_id ندارد، 0 می‌گذاریم
                amount=amount,
                period=period,
                currency_id=currency_id
            )
    
    db.commit()
    
    return {
        "subscription": subscription,
        "invoice": invoice
    }

