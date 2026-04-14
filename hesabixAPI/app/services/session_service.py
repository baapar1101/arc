from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy.orm import Session

from adapters.db.repositories.api_key_repo import ApiKeyRepository
from app.core.responses import ApiError
from app.utils.device_detection import parse_user_agent, format_device_name


def format_relative_time(dt: datetime | None) -> str:
	"""
	تبدیل datetime به فرمت نسبی فارسی
	
	مثال:
		- "2 ساعت پیش"
		- "3 روز پیش"
		- "همین الان"
	"""
	if not dt:
		return "هرگز"
	
	now = datetime.utcnow()
	diff = now - dt
	
	if diff.total_seconds() < 60:
		return "همین الان"
	elif diff.total_seconds() < 3600:
		minutes = int(diff.total_seconds() / 60)
		return f"{minutes} دقیقه پیش"
	elif diff.total_seconds() < 86400:
		hours = int(diff.total_seconds() / 3600)
		return f"{hours} ساعت پیش"
	elif diff.total_seconds() < 604800:
		days = int(diff.total_seconds() / 86400)
		return f"{days} روز پیش"
	elif diff.total_seconds() < 2592000:
		weeks = int(diff.total_seconds() / 604800)
		return f"{weeks} هفته پیش"
	else:
		months = int(diff.total_seconds() / 2592000)
		return f"{months} ماه پیش"


def list_user_sessions(db: Session, user_id: int, current_api_key_hash: str) -> list[dict]:
	"""
	لیست تمام session keys کاربر
	
	Args:
		db: Session دیتابیس
		user_id: شناسه کاربر
		current_api_key_hash: hash کلید API فعلی برای تشخیص session فعلی
	
	Returns:
		لیست session ها با اطلاعات کامل
	"""
	repo = ApiKeyRepository(db)
	sessions = repo.get_user_sessions(user_id)
	
	result = []
	for session in sessions:
		# تشخیص نام دستگاه
		device_info = parse_user_agent(session.user_agent)
		device_name = device_info.get("device_name") or format_device_name(
			session.user_agent,
			session.device_id
		)
		
		# تشخیص session فعلی
		is_current = session.key_hash == current_api_key_hash
		
		# آخرین استفاده
		last_used = session.last_used_at or session.created_at
		last_used_relative = format_relative_time(session.last_used_at)
		
		result.append({
			"id": session.id,
			"device_name": device_name,
			"device_id": session.device_id,
			"user_agent": session.user_agent,
			"ip": session.ip,
			"is_current": is_current,
			"created_at": session.created_at.isoformat() if session.created_at else None,
			"last_used_at": last_used.isoformat() if last_used else None,
			"last_used_relative": last_used_relative,
			"browser": device_info.get("browser"),
			"os": device_info.get("os"),
			"device_type": device_info.get("device_type"),
		})
	
	return result


def revoke_session(db: Session, user_id: int, session_id: int, current_api_key_hash: str) -> None:
	"""
	حذف یک session
	
	Args:
		db: Session دیتابیس
		user_id: شناسه کاربر
		session_id: شناسه session
		current_api_key_hash: hash کلید API فعلی
	
	Raises:
		ApiError: اگر session فعلی باشد یا یافت نشود
	"""
	repo = ApiKeyRepository(db)
	
	# بررسی اینکه session وجود دارد و متعلق به کاربر است
	from adapters.db.models.api_key import ApiKey
	from sqlalchemy import select
	stmt = select(ApiKey).where(
		ApiKey.id == session_id,
		ApiKey.user_id == user_id,
		ApiKey.key_type == "session"
	)
	session = db.execute(stmt).scalars().first()
	
	if not session:
		raise ApiError("NOT_FOUND", "Session یافت نشد", http_status=404)
	
	if session.revoked_at is not None:
		raise ApiError("BAD_REQUEST", "Session قبلاً حذف شده است", http_status=400)
	
	# بررسی اینکه session فعلی نباشد
	if session.key_hash == current_api_key_hash:
		raise ApiError("BAD_REQUEST", "نمی‌توانید session فعلی را حذف کنید", http_status=400)
	
	# حذف session
	success = repo.revoke_session(session_id, user_id)
	if not success:
		raise ApiError("INTERNAL_ERROR", "خطا در حذف session", http_status=500)
	
	# لاگ‌گیری logout
	try:
		from app.services.activity_log_service import log_user_activity
		log_user_activity(
			db=db,
			user_id=user_id,
			action="logout",
			description=f"خروج از سشن (Session ID: {session_id})",
			extra_info={
				"session_id": session_id,
				"device_id": session.device_id,
				"ip_address": session.ip
			}
		)
		db.commit()
	except Exception as e:
		import logging
		logger = logging.getLogger(__name__)
		logger.warning(f"Failed to log logout activity: {e}")


def revoke_other_sessions(db: Session, user_id: int, current_api_key_hash: str) -> int:
	"""
	حذف تمام session های دیگر (به جز فعلی)
	
	Args:
		db: Session دیتابیس
		user_id: شناسه کاربر
		current_api_key_hash: hash کلید API فعلی
	
	Returns:
		تعداد session های حذف شده
	"""
	repo = ApiKeyRepository(db)
	deleted_count = repo.revoke_other_sessions(user_id, current_api_key_hash)
	
	# لاگ‌گیری logout از همه سشن‌ها
	if deleted_count > 0:
		try:
			from app.services.activity_log_service import log_user_activity
			log_user_activity(
				db=db,
				user_id=user_id,
				action="logout_all",
				description=f"خروج از {deleted_count} سشن",
				extra_info={
					"deleted_count": deleted_count
				}
			)
			db.commit()
		except Exception as e:
			import logging
			logger = logging.getLogger(__name__)
			logger.warning(f"Failed to log logout_all activity: {e}")
	
	return deleted_count

