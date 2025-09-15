from __future__ import annotations

from typing import Optional

from fastapi import Depends, Header
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.repositories.api_key_repo import ApiKeyRepository
from adapters.db.models.user import User
from app.core.security import hash_api_key
from app.core.responses import ApiError


class AuthContext:
	def __init__(self, user: User, api_key_id: int) -> None:
		self.user = user
		self.api_key_id = api_key_id


def get_current_user(authorization: Optional[str] = Header(default=None), db: Session = Depends(get_db)) -> AuthContext:
	if not authorization or not authorization.startswith("ApiKey "):
		raise ApiError("UNAUTHORIZED", "Missing or invalid API key", http_status=401)

	api_key = authorization[len("ApiKey ") :].strip()
	key_hash = hash_api_key(api_key)
	repo = ApiKeyRepository(db)
	obj = repo.get_by_hash(key_hash)
	if not obj or obj.revoked_at is not None:
		raise ApiError("UNAUTHORIZED", "Invalid API key", http_status=401)

	from adapters.db.models.user import User
	user = db.get(User, obj.user_id)
	if not user or not user.is_active:
		raise ApiError("UNAUTHORIZED", "Invalid API key", http_status=401)

	return AuthContext(user=user, api_key_id=obj.id)


