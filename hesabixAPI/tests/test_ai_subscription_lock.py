from unittest.mock import MagicMock, patch

from app.services.ai.ai_service import AIService


def test_check_quota_and_charge_locks_subscription_row():
    db = MagicMock()
    ctx = MagicMock()
    ctx.can_access_support_operator.return_value = False
    ctx.is_superadmin.return_value = False
    ctx.get_user_id.return_value = 1

    plan = MagicMock()
    plan.plan_type = "free"

    subscription = MagicMock()
    subscription.id = 42
    subscription.is_active = True
    subscription.tokens_used = 0
    subscription.tokens_limit = 1000
    subscription.plan = plan

    locked = MagicMock()
    locked.id = 42
    locked.is_active = True
    locked.tokens_used = 0
    locked.tokens_limit = 1000
    locked.plan = plan

    repo = MagicMock()
    repo.get_active_subscription.return_value = subscription
    repo.get_by_id_for_update.return_value = locked

    with patch(
        "adapters.db.repositories.ai_subscription_repository.AISubscriptionRepository",
        return_value=repo,
    ), patch(
        "adapters.db.repositories.ai_config_repository.AIConfigRepository"
    ) as config_repo_cls:
        config_repo_cls.return_value.get_active_config.return_value = MagicMock(
            is_active=True
        )
        service = AIService(db, ctx, business_id=92)
        service.check_quota_and_charge(10, 5)

    repo.get_by_id_for_update.assert_called_once_with(42)
    assert service.subscription is locked
    db.commit.assert_called_once()
