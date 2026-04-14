"""
Query Timeout Management
برای مدیریت timeout در query های طولانی
"""

from __future__ import annotations

import logging
from contextlib import contextmanager
from typing import Optional, Generator

from sqlalchemy.orm import Session
from sqlalchemy import text, event
from sqlalchemy.pool import Pool

from app.core.settings import get_settings

logger = logging.getLogger(__name__)


@contextmanager
def query_timeout(
    session: Session,
    timeout_seconds: Optional[int] = None
) -> Generator[Session, None, None]:
    """
    Context manager برای تنظیم timeout برای query ها
    
    Args:
        session: SQLAlchemy session
        timeout_seconds: Timeout به ثانیه (اگر None باشد از settings استفاده می‌شود)
    
    Example:
        with query_timeout(db, timeout_seconds=10):
            result = db.query(Model).all()
    """
    if timeout_seconds is None:
        settings = get_settings()
        timeout_seconds = getattr(settings, 'query_timeout_seconds', 30)
    
    try:
        # تنظیم timeout برای PostgreSQL (به میلی‌ثانیه)
        session.execute(text(f"SET SESSION statement_timeout = {timeout_seconds * 1000}"))
        yield session
    except Exception as e:
        logger.warning(f"Error setting query timeout: {e}")
        yield session
    finally:
        try:
            # بازگرداندن timeout به حالت پیش‌فرض
            session.execute(text("SET SESSION statement_timeout = 0"))
        except Exception:
            pass


def set_query_timeout(session: Session, timeout_seconds: int) -> None:
    """
    تنظیم timeout برای یک session
    
    Args:
        session: SQLAlchemy session
        timeout_seconds: Timeout به ثانیه
    """
    try:
        session.execute(text(f"SET SESSION statement_timeout = {timeout_seconds * 1000}"))
    except Exception as e:
        logger.warning(f"Error setting query timeout: {e}")


def reset_query_timeout(session: Session) -> None:
    """
    بازگرداندن timeout به حالت پیش‌فرض
    
    Args:
        session: SQLAlchemy session
    """
    try:
        session.execute(text("SET SESSION statement_timeout = 0"))
    except Exception as e:
        logger.warning(f"Error resetting query timeout: {e}")


@event.listens_for(Pool, "connect")
def set_connection_timeout(dbapi_conn, connection_record):
    """
    Event listener برای تنظیم timeout در سطح connection
    """
    try:
        settings = get_settings()
        timeout_seconds = getattr(settings, 'query_timeout_seconds', 30)
        
        # تنظیم timeout برای PostgreSQL connection
        with dbapi_conn.cursor() as cursor:
            cursor.execute(f"SET SESSION statement_timeout = {timeout_seconds * 1000}")
    except Exception as e:
        logger.warning(f"Error setting connection timeout: {e}")

