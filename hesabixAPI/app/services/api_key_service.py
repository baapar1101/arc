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
			"ip": row.ip,
			"user_agent": row.user_agent,
			"created_at": row.created_at.isoformat() if row.created_at else None,
			"expires_at": row.expires_at.isoformat() if row.expires_at else None,
			"last_used_at": row.last_used_at.isoformat() if row.last_used_at else None,
			"revoked_at": row.revoked_at.isoformat() if row.revoked_at else None,
			"is_active": row.revoked_at is None and (row.expires_at is None or row.expires_at > datetime.utcnow()),
		})
	return items


def create_personal_key(db: Session, user_id: int, name: str | None, scopes: str | None, expires_at: Optional[datetime], ip_whitelist: str | None = None) -> tuple[int, str]:
	api_key, key_hash = generate_api_key(prefix="hsx_")
	repo = ApiKeyRepository(db)
	# استفاده از ip_whitelist برای ذخیره لیست IP های مجاز (JSON string)
	obj = repo.create_session_key(user_id=user_id, key_hash=key_hash, device_id=None, user_agent=None, ip=ip_whitelist, expires_at=expires_at)
	obj.key_type = "personal"
	obj.name = name
	obj.scopes = scopes
	db.add(obj)
	db.commit()
	return obj.id, api_key


def update_api_key(db: Session, user_id: int, key_id: int, name: str | None = None, scopes: str | None = None, expires_at: Optional[datetime] = None, ip_whitelist: str | None = None) -> None:
	from adapters.db.models.api_key import ApiKey
	from app.core.responses import ApiError
	obj = db.get(ApiKey, key_id)
	if not obj or obj.user_id != user_id or obj.key_type != "personal":
		raise ApiError("NOT_FOUND", "Key not found", http_status=404)
	if obj.revoked_at is not None:
		raise ApiError("BAD_REQUEST", "Cannot update revoked key", http_status=400)
	
	if name is not None:
		obj.name = name
	if scopes is not None:
		obj.scopes = scopes
	if expires_at is not None:
		obj.expires_at = expires_at
	if ip_whitelist is not None:
		obj.ip = ip_whitelist
	
	db.add(obj)
	db.commit()


def revoke_key(db: Session, user_id: int, key_id: int) -> None:
	from adapters.db.models.api_key import ApiKey
	obj = db.get(ApiKey, key_id)
	if not obj or obj.user_id != user_id:
		from app.core.responses import ApiError
		raise ApiError("NOT_FOUND", "Key not found", http_status=404)
	obj.revoked_at = datetime.utcnow()
	db.add(obj)
	db.commit()


