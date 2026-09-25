from __future__ import annotations

import asyncio
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from app.services.realtime import realtime_manager


class InAppProvider:
	def __init__(self, db: Session) -> None:
		self.db = db

	def push_realtime(
		self,
		*,
		user_id: int,
		title: str,
		body: str,
		level: str = "info",
		announcement_id: Optional[int] = None,
		deep_link: Optional[str] = None,
		ticket_id: Optional[int] = None,
		event_key: Optional[str] = None,
	) -> bool:
		payload: Dict[str, Any] = {"type": "notification", "title": title, "body": body, "level": level}
		if announcement_id is not None:
			payload["announcement_id"] = announcement_id
		if deep_link:
			payload["deep_link"] = deep_link
		if ticket_id is not None:
			payload["ticket_id"] = ticket_id
		if event_key:
			payload["event_key"] = event_key
		try:
			import anyio

			anyio.from_thread.run(realtime_manager.send_to_user, user_id, payload)
		except Exception:
			# Fallback for contexts where anyio thread portal is unavailable.
			try:
				asyncio.run(realtime_manager.send_to_user(user_id, payload))
			except Exception:
				pass
		return True


