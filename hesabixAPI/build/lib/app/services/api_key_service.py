from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy.orm import Session

from adapters.db.repositories.api_key_repo import ApiKeyRepository
from app.core.security import generate_api_key


def list_personal_keys(db: Session, user_id: int) -> list[dict]:
	repo = ApiKeyRepository(db)
	from adapters.db.models.api_key import ApiKey
	stmt = db.query(ApiKey).filter(ApiKey.user_id == user_id, ApiKey.key_type == "personal")
	items: list[dict] = []
	for row in stmt.all():
		items.append({
			"id": row.id,
			"name": row.name,
			"scopes": row.scopes,
			"created_at": row.created_at,
			"expires_at": row.expires_at,
			"revoked_at": row.revoked_at,
		})
	return items


def create_personal_key(db: Session, user_id: int, name: str | None, scopes: str | None, expires_at: Optional[datetime]) -> tuple[int, str]:
	api_key, key_hash = generate_api_key(prefix="ak_personal_")
	repo = ApiKeyRepository(db)
	obj = repo.create_session_key(user_id=user_id, key_hash=key_hash, device_id=None, user_agent=None, ip=None, expires_at=expires_at)
	obj.key_type = "personal"
	obj.name = name
	obj.scopes = scopes
	db.add(obj)
	db.commit()
	return obj.id, api_key


def revoke_key(db: Session, user_id: int, key_id: int) -> None:
	from adapters.db.models.api_key import ApiKey
	obj = db.get(ApiKey, key_id)
	if not obj or obj.user_id != user_id:
		from app.core.responses import ApiError
		raise ApiError("NOT_FOUND", "Key not found", http_status=404)
	obj.revoked_at = datetime.utcnow()
	db.add(obj)
	db.commit()


