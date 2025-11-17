"""
سرویس حذف خودکار فایل‌های کسب‌وکارهایی که grace period تمام شده
"""

from __future__ import annotations

from typing import Dict, Any, List
from datetime import datetime, timedelta

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from adapters.db.models.storage_plan import BusinessStorageSubscription
from adapters.db.models.file_storage import FileStorage
from app.services.file_storage_service import FileStorageService
import logging

logger = logging.getLogger(__name__)


def mark_files_for_deletion(
	db: Session,
) -> Dict[str, Any]:
	"""علامت‌گذاری فایل‌های کسب‌وکارهایی که grace period تمام شده"""
	now = datetime.utcnow()
	
	# دریافت کسب‌وکارهایی که grace_period_ends_at گذشته
	expired_businesses = db.query(BusinessStorageSubscription.business_id).filter(
		and_(
			BusinessStorageSubscription.grace_period_ends_at.isnot(None),
			BusinessStorageSubscription.grace_period_ends_at < now,
			BusinessStorageSubscription.status.in_(["expired", "cancelled"])
		)
	).distinct().all()
	
	business_ids = [b[0] for b in expired_businesses]
	
	if not business_ids:
		return {
			"marked_count": 0,
			"business_count": 0,
		}
	
	# علامت‌گذاری فایل‌های این کسب‌وکارها
	marked = db.query(FileStorage).filter(
		and_(
			FileStorage.business_id.in_(business_ids),
			FileStorage.deleted_at.is_(None),
			FileStorage.is_marked_for_deletion == False
		)
	).update({
		"is_marked_for_deletion": True,
		"marked_for_deletion_at": now
	}, synchronize_session=False)
	
	db.commit()
	
	logger.info(f"Marked {marked} files for deletion from {len(business_ids)} businesses")
	
	return {
		"marked_count": marked,
		"business_count": len(business_ids),
		"business_ids": business_ids,
	}


async def delete_marked_files(
	db: Session,
	days_after_mark: int = 7,
) -> Dict[str, Any]:
	"""حذف فایل‌های علامت‌گذاری شده (بعد از days_after_mark روز)"""
	cutoff_date = datetime.utcnow() - timedelta(days=days_after_mark)
	
	# دریافت فایل‌های علامت‌گذاری شده که زمان حذف آن‌ها رسیده
	files_to_delete = db.query(FileStorage).filter(
		and_(
			FileStorage.is_marked_for_deletion == True,
			FileStorage.marked_for_deletion_at.isnot(None),
			FileStorage.marked_for_deletion_at < cutoff_date,
			FileStorage.deleted_at.is_(None)
		)
	).all()
	
	deleted_count = 0
	failed_count = 0
	
	file_service = FileStorageService(db)
	
	for file_storage in files_to_delete:
		try:
			# حذف فایل از storage
			from uuid import UUID
			file_id = UUID(file_storage.id)
			await file_service.delete_file(file_id)
			deleted_count += 1
		except Exception as e:
			logger.error(f"Failed to delete file {file_storage.id}: {str(e)}")
			failed_count += 1
	
	logger.info(f"Deleted {deleted_count} files, {failed_count} failed")
	
	return {
		"deleted_count": deleted_count,
		"failed_count": failed_count,
		"total_marked": len(files_to_delete),
	}


async def cleanup_expired_files(
	db: Session,
) -> Dict[str, Any]:
	"""اجرای کامل فرآیند پاک‌سازی"""
	# مرحله 1: علامت‌گذاری
	mark_result = mark_files_for_deletion(db)
	
	# مرحله 2: حذف
	delete_result = delete_marked_files(db)
	
	return {
		"mark_result": mark_result,
		"delete_result": delete_result,
	}

