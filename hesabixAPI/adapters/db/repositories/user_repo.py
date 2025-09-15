from __future__ import annotations

from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from adapters.db.models.user import User


class UserRepository:
	def __init__(self, db: Session) -> None:
		self.db = db

	def get_by_email(self, email: str) -> Optional[User]:
		stmt = select(User).where(User.email == email)
		return self.db.execute(stmt).scalars().first()

	def get_by_mobile(self, mobile: str) -> Optional[User]:
		stmt = select(User).where(User.mobile == mobile)
		return self.db.execute(stmt).scalars().first()

	def create(self, *, email: str | None, mobile: str | None, password_hash: str, first_name: str | None, last_name: str | None) -> User:
		user = User(email=email, mobile=mobile, password_hash=password_hash, first_name=first_name, last_name=last_name)
		self.db.add(user)
		self.db.commit()
		self.db.refresh(user)
		return user


