"""
Background jobs برای سیستم AI
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta

from adapters.db.session import get_db_session
from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
from adapters.db.repositories.ai_chat_repository import AIChatSessionRepository
from adapters.db.models.ai_plan import AIPlanType
from app.services.ai_plan_service import renew_ai_subscription
from app.services.ai.ai_quota_helpers import has_token_cap, reset_monthly_quota

logger = logging.getLogger(__name__)

_PLANS_WITH_MONTHLY_QUOTA = {
    AIPlanType.FREE.value,
    AIPlanType.SUBSCRIPTION.value,
    AIPlanType.HYBRID.value,
}


async def ai_quota_reset_loop(interval_hours: int = 24) -> None:
    """
    Background loop برای reset کردن سهمیه ماهانه
    هر interval_hours ساعت یکبار اجرا می‌شود
    """
    interval_seconds = interval_hours * 3600
    
    while True:
        try:
            with get_db_session() as db:
                repo = AISubscriptionRepository(db)
                
                subscriptions = repo.get_subscriptions_needing_reset()
                
                reset_count = 0
                for subscription in subscriptions:
                    try:
                        if not subscription.plan:
                            continue
                        plan_type = subscription.plan.plan_type
                        if plan_type not in _PLANS_WITH_MONTHLY_QUOTA:
                            continue
                        if not has_token_cap(subscription.tokens_limit):
                            continue

                        reset_monthly_quota(subscription)
                        reset_count += 1
                        
                    except Exception as e:
                        logger.error(
                            f"Error resetting subscription {subscription.id}: {e}",
                            exc_info=True
                        )
                        continue

                if reset_count > 0:
                    db.commit()
                    logger.info(f"Reset {reset_count} AI subscriptions")
        except Exception as e:
            logger.error(f"Error in AI quota reset loop: {e}", exc_info=True)
        
        await asyncio.sleep(interval_seconds)


async def ai_chat_cleanup_loop(interval_hours: int = 24) -> None:
    """
    Background loop برای پاک‌سازی جلسات چت قدیمی
    هر interval_hours ساعت یکبار اجرا می‌شود
    """
    interval_seconds = interval_hours * 3600
    
    while True:
        try:
            with get_db_session() as db:
                repo = AIChatSessionRepository(db)
                
                cutoff_date = datetime.utcnow() - timedelta(days=90)
                
                deleted_count = repo.delete_old_empty_sessions(cutoff_date)
                
                old_cutoff = datetime.utcnow() - timedelta(days=365)
                old_deleted = repo.delete_old_sessions(old_cutoff)
                
                total_deleted = deleted_count + old_deleted
                
                if total_deleted > 0:
                    logger.info(
                        f"Deleted {deleted_count} empty and {old_deleted} old chat sessions "
                        f"(total: {total_deleted})"
                    )
        except Exception as e:
            logger.error(f"Error in AI chat cleanup loop: {e}", exc_info=True)
        
        await asyncio.sleep(interval_seconds)


async def ai_subscription_check_loop(interval_hours: int = 6) -> None:
    """
    Background loop برای بررسی و تمدید اشتراک‌های AI
    هر interval_hours ساعت یکبار اجرا می‌شود
    """
    interval_seconds = interval_hours * 3600
    
    while True:
        try:
            with get_db_session() as db:
                repo = AISubscriptionRepository(db)
                
                expiring_soon = repo.get_subscriptions_expiring_soon(days=7)
                
                for subscription in expiring_soon:
                    try:
                        if not subscription.plan:
                            continue
                        if subscription.auto_renew and subscription.is_active:
                            logger.info(
                                "AI subscription %s expiring at %s (auto_renew enabled)",
                                subscription.id,
                                subscription.period_end,
                            )
                        else:
                            logger.info(
                                "AI subscription %s expiring at %s (auto_renew disabled)",
                                subscription.id,
                                subscription.period_end,
                            )
                    except Exception as e:
                        logger.error(
                            f"Error processing expiring subscription {subscription.id}: {e}",
                            exc_info=True
                        )

                renewed_count = 0
                failed_renewals = 0
                due_for_renewal = repo.get_subscriptions_due_for_auto_renew()
                for subscription in due_for_renewal:
                    try:
                        result = renew_ai_subscription(db, subscription.id)
                        if result.get("renewed"):
                            renewed_count += 1
                        else:
                            failed_renewals += 1
                            logger.info(
                                "AI subscription %s auto-renew skipped: %s",
                                subscription.id,
                                result.get("reason"),
                            )
                    except Exception as e:
                        failed_renewals += 1
                        logger.error(
                            "Error auto-renewing AI subscription %s: %s",
                            subscription.id,
                            e,
                            exc_info=True,
                        )

                if renewed_count or failed_renewals:
                    logger.info(
                        "AI auto-renew batch: renewed=%s failed=%s",
                        renewed_count,
                        failed_renewals,
                    )
                
                expired = repo.get_expired_subscriptions()
                
                for subscription in expired:
                    try:
                        if subscription.is_active:
                            subscription.is_active = False
                            logger.info(f"Deactivated expired subscription {subscription.id}")
                    except Exception as e:
                        logger.error(
                            f"Error deactivating expired subscription {subscription.id}: {e}",
                            exc_info=True
                        )
                
                if expired:
                    db.commit()
                    logger.info(f"Processed {len(expired)} expired subscriptions")
        except Exception as e:
            logger.error(f"Error in AI subscription check loop: {e}", exc_info=True)
        
        await asyncio.sleep(interval_seconds)


async def ai_eval_schedule_loop(interval_seconds: int = 60) -> None:
    """بررسی cron ارزیابی خودکار AI."""
    from app.services.ai.ai_eval_schedule_service import run_scheduled_eval_if_due

    while True:
        try:
            with get_db_session() as db:
                result = await run_scheduled_eval_if_due(db)
                if result.get("fired"):
                    logger.info(
                        "AI scheduled eval completed run_id=%s pass_rate=%s",
                        result.get("run_id"),
                        result.get("pass_rate"),
                    )
                db.commit()
        except Exception as e:
            logger.error("AI eval schedule loop error: %s", e, exc_info=True)
        await asyncio.sleep(max(30, int(interval_seconds)))
