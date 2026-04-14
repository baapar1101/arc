"""
Background jobs برای سیستم AI
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta
from typing import List

from adapters.db.session import get_db_session
from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
from adapters.db.repositories.ai_chat_repository import AIChatSessionRepository
from adapters.db.models.ai_subscription import UserAISubscription
from adapters.db.models.ai_plan import AIPlanType

logger = logging.getLogger(__name__)


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
                
                # پیدا کردن اشتراک‌هایی که باید reset شوند
                subscriptions = repo.get_subscriptions_needing_reset()
                
                reset_count = 0
                for subscription in subscriptions:
                    try:
                        # Reset کردن tokens_used فقط برای پلن‌های ماهانه
                        if subscription.plan.plan_type in [AIPlanType.FREE, AIPlanType.SUBSCRIPTION]:
                            subscription.tokens_used = 0
                            # به‌روزرسانی period_start برای reset ماهانه
                            subscription.period_start = datetime.utcnow()
                            reset_count += 1
                        
                        # اگر subscription plan است، بررسی تمدید
                        if subscription.plan.plan_type == AIPlanType.SUBSCRIPTION:
                            # بررسی تاریخ انقضا
                            if subscription.period_end and subscription.period_end < datetime.utcnow():
                                # اشتراک منقضی شده - غیرفعال کردن
                                subscription.is_active = False
                                logger.info(
                                    f"Subscription {subscription.id} expired and deactivated"
                                )
                            else:
                                # تمدید خودکار اگر enabled باشد
                                if subscription.plan.auto_renew:
                                    # TODO: ایجاد invoice و شارژ کیف پول
                                    # فعلاً فقط reset می‌کنیم
                                    pass
                        
                    except Exception as e:
                        logger.error(
                            f"Error resetting subscription {subscription.id}: {e}",
                            exc_info=True
                        )
                        continue
                
                if reset_count > 0:
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
                
                # حذف جلسات قدیمی‌تر از 90 روز که هیچ پیامی ندارند
                cutoff_date = datetime.utcnow() - timedelta(days=90)
                
                deleted_count = repo.delete_old_empty_sessions(cutoff_date)
                
                # حذف جلسات قدیمی‌تر از 365 روز (حتی با پیام)
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
                
                # پیدا کردن اشتراک‌های در حال انقضا (7 روز آینده)
                expiring_soon = repo.get_subscriptions_expiring_soon(days=7)
                
                for subscription in expiring_soon:
                    try:
                        # اگر auto_renew فعال است
                        if subscription.plan.auto_renew and subscription.is_active:
                            # TODO: ایجاد invoice و شارژ کیف پول
                            # فعلاً فقط log می‌کنیم
                            logger.info(
                                f"Subscription {subscription.id} expiring soon "
                                f"(expires at {subscription.period_end})"
                            )
                        else:
                            # ارسال اعلان به کاربر
                            # TODO: ارسال notification
                            logger.info(
                                f"Subscription {subscription.id} will expire soon "
                                f"and auto_renew is disabled"
                            )
                    except Exception as e:
                        logger.error(
                            f"Error processing expiring subscription {subscription.id}: {e}",
                            exc_info=True
                        )
                
                # پیدا کردن اشتراک‌های منقضی شده
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
                    logger.info(f"Processed {len(expired)} expired subscriptions")
        except Exception as e:
            logger.error(f"Error in AI subscription check loop: {e}", exc_info=True)
        
        await asyncio.sleep(interval_seconds)

