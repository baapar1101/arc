"""پس‌زمینه: حذف رکورد دسترسی اعضایی که مهلت عضویتشان گذشته است."""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

from sqlalchemy import delete, select

from adapters.db.session import get_db_session
from adapters.db.models.business import Business
from adapters.db.models.business_permission import BusinessPermission
from app.core.cache import get_cache

logger = logging.getLogger(__name__)


def _revoke_expired_memberships() -> int:
	"""فقط ردیف‌های عضو غیرمالک؛ هرگز ردیف مربوط به owner_id همان کسب‌وکار حذف نمی‌شود."""
	with get_db_session() as db:
		now = datetime.utcnow()
		ids = list(
			db.execute(
				select(BusinessPermission.id)
				.join(Business, Business.id == BusinessPermission.business_id)
				.where(
					BusinessPermission.membership_expires_at.isnot(None),
					BusinessPermission.membership_expires_at <= now,
					BusinessPermission.user_id != Business.owner_id,
				)
			).scalars().all()
		)
		if not ids:
			return 0
		result = db.execute(delete(BusinessPermission).where(BusinessPermission.id.in_(ids)))
		db.commit()
		return int(result.rowcount or 0)


async def revoke_expired_business_memberships_loop(interval_minutes: int = 60) -> None:
	"""به‌صورت دوره‌ای اعضای منقضی را مثل حذف دستی از کسب‌وکار از جدول business_permissions حذف می‌کند."""
	interval_seconds = max(60, interval_minutes * 60)
	while True:
		try:
			removed = await asyncio.to_thread(_revoke_expired_memberships)
			if removed > 0:
				logger.info("Removed %s expired business membership row(s)", removed)
				cache = get_cache()
				if cache.enabled:
					try:
						cache.delete_pattern("user_businesses:*")
					except Exception as e:  # noqa: BLE001
						logger.warning("Failed to invalidate user_businesses cache after membership purge: %s", e)
		except Exception as e:  # noqa: BLE001
			logger.error("Error in revoke_expired_business_memberships_loop: %s", e, exc_info=True)
		await asyncio.sleep(interval_seconds)
