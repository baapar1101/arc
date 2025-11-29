"""
Job برای ارسال ایمیل
"""

from __future__ import annotations

import logging
from typing import Any, Dict

logger = logging.getLogger(__name__)


def send_email_job(
    to_email: str,
    subject: str,
    body: str,
    html_body: str | None = None,
    config_id: int | None = None,
    **kwargs
) -> Dict[str, Any]:
    """
    ارسال ایمیل به صورت background job
    
    Args:
        to_email: آدرس ایمیل گیرنده
        subject: موضوع ایمیل
        body: محتوای ایمیل (plain text)
        html_body: محتوای HTML (اختیاری)
        config_id: شناسه تنظیمات ایمیل (اختیاری)
        **kwargs: سایر پارامترها
    
    Returns:
        نتیجه ارسال
    """
    try:
        from adapters.db.session import get_db_session
        from app.services.email_service import EmailService
        from datetime import datetime
        
        logger.info(f"Sending email to {to_email}: {subject}")
        
        with get_db_session() as db:
            email_service = EmailService(db)
            success = email_service.send_email(
                to=to_email,
                subject=subject,
                body=body,
                html_body=html_body,
                config_id=config_id
            )
            
            if not success:
                raise Exception("Email service returned False")
            
            result = {
                "success": True,
                "to": to_email,
                "subject": subject,
                "sent_at": datetime.now().isoformat(),
            }
            
            logger.info(f"Email sent successfully to {to_email}")
            return result
        
    except Exception as e:
        logger.error(f"Error sending email to {to_email}: {e}", exc_info=True)
        raise

