from __future__ import annotations

import json
from datetime import datetime, timedelta
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

from adapters.db.models.ai_plan import AIPlan, AIPlanType
from adapters.db.models.ai_subscription import UserAISubscription
from app.core.responses import ApiError
from app.services.ai_plan_service import (
    detect_billing_period,
    extend_subscription_billing_period,
    get_renewal_amount,
    renew_ai_subscription,
)


def _plan(plan_type: str = AIPlanType.SUBSCRIPTION.value, monthly: int = 50_000) -> AIPlan:
    return AIPlan(
        code="pro",
        name="Pro",
        plan_type=plan_type,
        pricing_config=json.dumps(
            {
                "subscription": {
                    "monthly_price": monthly,
                    "yearly_price": monthly * 10,
                }
            },
            ensure_ascii=False,
        ),
        is_active=True,
        auto_renew=True,
    )


def _subscription(
    *,
    plan: AIPlan,
    period_days: int = 30,
    business_id: int = 92,
) -> UserAISubscription:
    start = datetime.utcnow() - timedelta(days=period_days + 1)
    end = start + timedelta(days=period_days)
    return UserAISubscription(
        id=1,
        user_id=10,
        business_id=business_id,
        plan_id=plan.id or 1,
        plan=plan,
        subscription_type="subscription",
        tokens_used=500,
        tokens_limit=10_000,
        period_start=start,
        period_end=end,
        expires_at=end,
        is_active=True,
        auto_renew=True,
    )


def test_detect_billing_period_monthly():
    sub = _subscription(plan=_plan(), period_days=30)
    assert detect_billing_period(sub) == "monthly"


def test_detect_billing_period_yearly():
    sub = _subscription(plan=_plan(), period_days=365)
    assert detect_billing_period(sub) == "yearly"


def test_get_renewal_amount():
    plan = _plan()
    assert get_renewal_amount(plan, "monthly") == Decimal("50000")
    assert get_renewal_amount(plan, "yearly") == Decimal("500000")


def test_extend_subscription_billing_period_resets_quota():
    plan = _plan()
    sub = _subscription(plan=plan)
    now = datetime.utcnow()
    extend_subscription_billing_period(sub, "monthly", now=now)
    assert sub.tokens_used == 0
    assert sub.period_start == now
    assert sub.period_end == now + timedelta(days=30)
    assert sub.expires_at == sub.period_end
    assert sub.is_active is True


def test_renew_ai_subscription_free_plan_extends_without_payment():
    plan = _plan(monthly=0)
    sub = _subscription(plan=plan)
    db = MagicMock()
    repo = MagicMock()
    repo.get_by_id_for_update.return_value = sub

    with patch(
        "app.services.ai_plan_service.AISubscriptionRepository",
        return_value=repo,
    ):
        result = renew_ai_subscription(db, sub.id)

    assert result["renewed"] is True
    assert result["amount"] == 0.0
    assert sub.tokens_used == 0
    db.commit.assert_called_once()


def test_renew_ai_subscription_charges_wallet_and_extends():
    plan = _plan(monthly=25_000)
    sub = _subscription(plan=plan)
    db = MagicMock()
    repo = MagicMock()
    repo.get_by_id_for_update.side_effect = [sub, sub]

    invoice = SimpleNamespace(id=99)
    payment = {"invoice_id": 99, "status": "paid"}

    with patch(
        "app.services.ai_plan_service.AISubscriptionRepository",
        return_value=repo,
    ), patch(
        "app.services.ai_plan_service.get_wallet_settings",
        return_value={"wallet_base_currency_id": 1},
    ), patch(
        "app.services.ai_plan_service.create_subscription_invoice",
        return_value=invoice,
    ) as create_invoice, patch(
        "app.services.ai_plan_service.pay_ai_invoice_from_wallet",
        return_value=payment,
    ) as pay_wallet:
        result = renew_ai_subscription(db, sub.id)

    assert result["renewed"] is True
    assert result["amount"] == 25000.0
    create_invoice.assert_called_once()
    pay_wallet.assert_called_once()
    assert sub.tokens_used == 0
    db.commit.assert_called_once()


def test_renew_ai_subscription_insufficient_funds_deactivates():
    plan = _plan(monthly=25_000)
    sub = _subscription(plan=plan)
    db = MagicMock()
    repo = MagicMock()
    repo.get_by_id_for_update.return_value = sub

    with patch(
        "app.services.ai_plan_service.AISubscriptionRepository",
        return_value=repo,
    ), patch(
        "app.services.ai_plan_service.get_wallet_settings",
        return_value={"wallet_base_currency_id": 1},
    ), patch(
        "app.services.ai_plan_service.create_subscription_invoice",
        return_value=SimpleNamespace(id=1),
    ), patch(
        "app.services.ai_plan_service.pay_ai_invoice_from_wallet",
        side_effect=ApiError("INSUFFICIENT_FUNDS", "موجودی کافی نیست", http_status=400),
    ):
        result = renew_ai_subscription(db, sub.id)

    assert result["renewed"] is False
    assert result["reason"] == "insufficient_funds"
    assert sub.is_active is False
    db.commit.assert_called_once()


def test_renew_skips_when_not_due():
    plan = _plan(monthly=0)
    sub = _subscription(plan=plan)
    sub.period_end = datetime.utcnow() + timedelta(days=10)
    db = MagicMock()
    repo = MagicMock()
    repo.get_by_id_for_update.return_value = sub

    with patch(
        "app.services.ai_plan_service.AISubscriptionRepository",
        return_value=repo,
    ):
        result = renew_ai_subscription(db, sub.id)

    assert result["renewed"] is False
    assert result["reason"] == "not_due"
