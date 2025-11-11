from __future__ import annotations

from typing import Optional
from sqlalchemy.orm import Session

from app.services.email_service import EmailService
from adapters.db.repositories.user_repo import UserRepository


class EmailProvider:
	def __init__(self, db: Session) -> None:
		self.db = db
		self.email_service = EmailService(db)
		self.user_repo = UserRepository(db)

	def send(self, *, user_id: int, subject: str, body_text: str, body_html: Optional[str] = None) -> bool:
		user = self.user_repo.db.get(self.user_repo.model, user_id)
		if user is None or not getattr(user, "email", None):
			return False
		return self.email_service.send_email(
			to=user.email,  # type: ignore[arg-type]
			subject=subject,
			body=body_text,
			html_body=body_html,
		)


