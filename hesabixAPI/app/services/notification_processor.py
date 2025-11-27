from __future__ import annotations

from datetime import datetime
from typing import List

from sqlalchemy import select, and_
from sqlalchemy.orm import Session

from adapters.db.models.notification import NotificationOutbox
from adapters.db.session import SessionLocal
from app.services.notification_service import NotificationService


class NotificationProcessor:
	def __init__(self, db: Session) -> None:
		self.db = db
		self.svc = NotificationService(db)

	def fetch_due(self, limit: int = 50) -> List[NotificationOutbox]:
		now = datetime.utcnow()
		stmt = select(NotificationOutbox).where(
			and_(
				NotificationOutbox.status == "failed",
				NotificationOutbox.next_attempt_at.is_not(None),
				NotificationOutbox.next_attempt_at <= now,
			)
		).limit(limit)
		return list(self.db.execute(stmt).scalars().all())

	def process_once(self) -> int:
		items = self.fetch_due(limit=50)
		count = 0
		for it in items:
			# re-send using preferred single channel
			try:
				self.svc.send(user_id=it.user_id, event_key=it.event_key, context=it.payload, preferred_channels=[it.channel], locale=it.locale)
				count += 1
			except Exception:
				# ignore; will be retried later
				pass
		return count


async def background_loop(interval_seconds: int = 30) -> None:
	import asyncio

	def _process_due_notifications() -> None:
		"""
		Run the potentially blocking notification resend logic in a worker thread
		so the main event loop stays responsive (SMTP sends are fully blocking).
		"""
		db = SessionLocal()
		try:
			processor = NotificationProcessor(db)
			processor.process_once()
		finally:
			db.close()

	while True:
		try:
			await asyncio.to_thread(_process_due_notifications)
		except Exception:
			# swallow errors to keep loop alive
			pass
		await asyncio.sleep(interval_seconds)


