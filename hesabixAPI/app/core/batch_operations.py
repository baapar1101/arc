"""
بهینه‌سازی Batch Operations
برای انجام عملیات‌های حجیم به صورت batch
"""

from __future__ import annotations

import logging
from typing import List, Any, Callable, Optional, Iterator
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)


def batch_process(
    items: List[Any],
    batch_size: int = 100,
    processor: Optional[Callable] = None
) -> Iterator[List[Any]]:
    """
    تقسیم یک لیست به batch های کوچک‌تر
    
    Args:
        items: لیست آیتم‌ها
        batch_size: اندازه هر batch
        processor: تابع برای پردازش هر batch (اختیاری)
    
    Yields:
        هر batch از آیتم‌ها
    
    Example:
        for batch in batch_process(items, batch_size=50):
            db.bulk_insert_mappings(Model, batch)
    """
    for i in range(0, len(items), batch_size):
        batch = items[i:i + batch_size]
        if processor:
            processor(batch)
        yield batch


def bulk_insert_optimized(
    session: Session,
    model_class: Any,
    items: List[dict],
    batch_size: int = 100
) -> int:
    """
    Bulk insert بهینه‌سازی شده با batch processing
    
    Args:
        session: SQLAlchemy session
        model_class: کلاس model
        items: لیست dictionary های داده
        batch_size: اندازه هر batch
    
    Returns:
        تعداد آیتم‌های insert شده
    """
    total_inserted = 0
    
    try:
        for batch in batch_process(items, batch_size=batch_size):
            session.bulk_insert_mappings(model_class, batch)
            total_inserted += len(batch)
        
        session.commit()
        logger.info(f"Bulk inserted {total_inserted} items into {model_class.__name__}")
        return total_inserted
    except Exception as e:
        session.rollback()
        logger.error(f"Error in bulk insert: {e}", exc_info=True)
        raise


def bulk_update_optimized(
    session: Session,
    model_class: Any,
    items: List[dict],
    batch_size: int = 100,
    update_fields: Optional[List[str]] = None
) -> int:
    """
    Bulk update بهینه‌سازی شده با batch processing
    
    Args:
        session: SQLAlchemy session
        model_class: کلاس model
        items: لیست dictionary های داده (باید شامل primary key باشد)
        batch_size: اندازه هر batch
        update_fields: لیست فیلدهایی که باید update شوند (اگر None باشد همه فیلدها)
    
    Returns:
        تعداد آیتم‌های update شده
    """
    total_updated = 0
    
    try:
        for batch in batch_process(items, batch_size=batch_size):
            if update_fields:
                # فقط فیلدهای مشخص شده را update کن
                filtered_batch = [
                    {k: v for k, v in item.items() if k in update_fields or k in model_class.__table__.primary_key.columns.keys()}
                    for item in batch
                ]
                session.bulk_update_mappings(model_class, filtered_batch)
            else:
                session.bulk_update_mappings(model_class, batch)
            total_updated += len(batch)
        
        session.commit()
        logger.info(f"Bulk updated {total_updated} items in {model_class.__name__}")
        return total_updated
    except Exception as e:
        session.rollback()
        logger.error(f"Error in bulk update: {e}", exc_info=True)
        raise


def chunked_query(
    query,
    chunk_size: int = 1000
) -> Iterator[List[Any]]:
    """
    اجرای query به صورت chunked برای جلوگیری از memory overflow
    
    Args:
        query: SQLAlchemy query
        chunk_size: اندازه هر chunk
    
    Yields:
        هر chunk از نتایج
    
    Example:
        for chunk in chunked_query(db.query(Model).filter(...), chunk_size=500):
            process_chunk(chunk)
    """
    offset = 0
    while True:
        chunk = query.offset(offset).limit(chunk_size).all()
        if not chunk:
            break
        yield chunk
        offset += chunk_size
        
        # اگر chunk کوچکتر از chunk_size باشد، آخرین chunk است
        if len(chunk) < chunk_size:
            break

