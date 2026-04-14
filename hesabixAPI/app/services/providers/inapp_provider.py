from __future__ import annotations

from typing import Optional
from sqlalchemy.orm import Session

# For minimal integration we rely on announcements or future in-app system.
from app.services.realtime import realtime_manager


class InAppProvider:
	def __init__(self, db: Session) -> None:
		self.db = db

	def notify(self, *, user_id: int, title: str, body: str, level: str = "info") -> bool:
		# Optionally push realtime message
		try:
			import anyio
			anyio.from_thread.run(realtime_manager.send_to_user, user_id, {"type": "notification", "title": title, "body": body, "level": level})
		except Exception:
			pass
		return True


