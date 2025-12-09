"""
Worker برای پردازش خودکار صف بررسی قالب‌های نوتیفیکیشن

این worker به صورت مداوم صف را چک می‌کند و قالب‌های جدید را با AI بررسی می‌کند
"""
import asyncio
import logging
from datetime import datetime
from typing import Optional

from sqlalchemy.orm import Session

from adapters.db.session import get_db_session
from adapters.db.repositories.business_notification_repo import (
    NotificationModerationQueueRepository,
    BusinessNotificationTemplateRepository
)
from adapters.db.models.business_notification import (
    NotificationModerationQueue,
    BusinessNotificationTemplate
)
from app.services.ai_moderation_service import AIContentModerationService

logger = logging.getLogger(__name__)


class NotificationModerationWorker:
    """
    Worker برای بررسی خودکار قالب‌ها
    """
    
    def __init__(self, db: Session):
        self.db = db
        self.ai_service = AIContentModerationService()
        self.queue_repo = NotificationModerationQueueRepository(db)
        self.template_repo = BusinessNotificationTemplateRepository(db)
    
    async def process_queue(self, max_items: int = 10):
        """
        پردازش صف
        
        Args:
            max_items: حداکثر تعداد آیتم برای پردازش در هر بار
        """
        logger.info("شروع پردازش صف moderation...")
        
        # دریافت آیتم‌های pending
        pending_items = self.queue_repo.get_pending(status='pending', limit=max_items)
        
        if not pending_items:
            logger.info("هیچ آیتمی در صف نیست")
            return
        
        logger.info(f"{len(pending_items)} آیتم برای بررسی یافت شد")
        
        for item in pending_items:
            try:
                await self.process_item(item)
            except Exception as e:
                logger.error(f"خطا در پردازش آیتم {item.id}: {e}", exc_info=True)
                
                # به‌روزرسانی وضعیت به خطا
                try:
                    self.queue_repo.update(item, {
                        "status": "pending",  # باز می‌گردد به pending برای تلاش مجدد
                        "ai_suggestions": f"خطا در بررسی: {str(e)}"
                    })
                    self.db.commit()
                except:
                    self.db.rollback()
    
    async def process_item(self, queue_item: NotificationModerationQueue):
        """بررسی یک قالب"""
        logger.info(f"بررسی قالب {queue_item.template_id}...")
        
        # دریافت قالب
        template = self.template_repo.get_by_id(queue_item.template_id)
        if not template:
            logger.error(f"قالب {queue_item.template_id} یافت نشد")
            return
        
        # به‌روزرسانی وضعیت به "ai_reviewing"
        self.queue_repo.update(queue_item, {
            "status": "ai_reviewing"
        })
        self.db.commit()
        
        # بررسی با AI
        result = await self.ai_service.review_template(
            content=template.body,
            subject=template.subject,
            event_type=template.event_type
        )
        
        logger.info(
            f"نتیجه بررسی: decision={result.decision}, "
            f"confidence={result.confidence}, flags={len(result.flags)}"
        )
        
        # به‌روزرسانی صف
        queue_update = {
            "status": "ai_reviewed",
            "ai_decision": result.decision,
            "ai_confidence": result.confidence,
            "ai_flags": result.flags,
            "ai_suggestions": result.suggestions,
            "ai_reviewed_at": datetime.utcnow()
        }
        
        # به‌روزرسانی قالب
        template_update = {
            "ai_confidence_score": result.confidence,
            "ai_review_notes": result.suggestions
        }
        
        # تصمیم‌گیری براساس نتیجه
        if result.decision == "approve" and result.confidence > 90:
            # تایید خودکار
            logger.info(f"تایید خودکار قالب {template.id} (confidence={result.confidence})")
            
            queue_update["status"] = "completed"
            queue_update["completed_at"] = datetime.utcnow()
            
            template_update.update({
                "status": "approved",
                "approval_status": "ai_approved",
                "approved_by_ai": True,
                "is_active": True,
                "approved_at": datetime.utcnow()
            })
            
        elif result.decision == "reject":
            # رد خودکار
            logger.info(f"رد خودکار قالب {template.id} (confidence={result.confidence})")
            
            queue_update["status"] = "completed"
            queue_update["completed_at"] = datetime.utcnow()
            
            template_update.update({
                "status": "rejected",
                "approval_status": "rejected",
                "is_active": False,
                "rejection_reason": "\n".join(result.flags),
                "rejected_at": datetime.utcnow()
            })
            
        else:
            # نیاز به بررسی مدیر
            logger.info(f"قالب {template.id} نیاز به بررسی مدیر دارد")
            
            queue_update["status"] = "admin_reviewing"
            queue_update["priority"] = 10  # اولویت بالا برای مدیر
            
            template_update.update({
                "status": "pending_approval"
            })
        
        # اعمال تغییرات
        self.queue_repo.update(queue_item, queue_update)
        self.template_repo.update(template, template_update)
        self.db.commit()
        
        logger.info(f"✅ بررسی قالب {template.id} تکمیل شد")


async def run_worker_once():
    """
    اجرای یک بار Worker
    
    برای استفاده در background jobs
    """
    with get_db_session() as db:
        try:
            worker = NotificationModerationWorker(db)
            await worker.process_queue(max_items=10)
        except Exception as e:
            logger.error(f"خطا در worker: {e}", exc_info=True)


async def run_worker_loop(interval_seconds: int = 60):
    """
    اجرای مداوم Worker
    
    Args:
        interval_seconds: فاصله زمانی بین هر اجرا (ثانیه)
    
    این loop در background اجرا می‌شود و قابل مشاهده در Monitoring Panel است
    """
    logger.info(
        f"🚀 شروع Notification Moderation Worker (interval={interval_seconds}s) - "
        f"قابل مدیریت از /user/profile/system-settings/monitoring"
    )
    
    iteration = 0
    
    while True:
        try:
            iteration += 1
            logger.debug(f"Worker iteration #{iteration}")
            await run_worker_once()
        except Exception as e:
            logger.error(f"خطا در loop worker iteration #{iteration}: {e}", exc_info=True)
        
        await asyncio.sleep(interval_seconds)


if __name__ == "__main__":
    # اجرای worker به صورت مداوم
    logging.basicConfig(level=logging.INFO)
    asyncio.run(run_worker_loop(interval_seconds=60))

