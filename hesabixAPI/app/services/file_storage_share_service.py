"""ایجاد و مدیریت لینک‌های اشتراک فایل ذخیره‌سازی کسب‌وکار."""

from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from sqlalchemy import and_, desc
from sqlalchemy.orm import Session

from adapters.db.models.file_storage import FileStorage, FileStorageShare
from app.core.responses import ApiError
from app.core.security import hash_password, verify_password
from app.services.storage_share_access_token import create_storage_share_access_token
from app.services.system_settings_service import resolve_public_app_base_url_for_public_links


def _hash_share_token(raw_token: str) -> str:
	return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def _utcnow() -> datetime:
	return datetime.now(timezone.utc)


def _get_file_for_business(db: Session, business_id: int, file_id: str) -> FileStorage:
	row = (
		db.query(FileStorage)
		.filter(
			and_(
				FileStorage.id == file_id,
				FileStorage.business_id == business_id,
				FileStorage.deleted_at.is_(None),
			)
		)
		.first()
	)
	if not row:
		raise ApiError("FILE_NOT_FOUND", "فایل یافت نشد", http_status=404)
	return row


def create_share(
	db: Session,
	business_id: int,
	file_id: str,
	user_id: int,
	password: Optional[str] = None,
	expires_in_days: Optional[int] = 30,
) -> dict[str, Any]:
	_get_file_for_business(db, business_id, file_id)
	if expires_in_days is not None and (expires_in_days < 1 or expires_in_days > 365):
		raise ApiError("VALIDATION_ERROR", "انقضا باید بین ۱ تا ۳۶۵ روز باشد یا خالی (بدون انقضا)", http_status=422)

	raw = secrets.token_urlsafe(32)
	th = _hash_share_token(raw)
	pwd_hash = hash_password(password.strip()) if password and password.strip() else None
	expires_at = None
	if expires_in_days is not None:
		expires_at = _utcnow() + timedelta(days=int(expires_in_days))

	row = FileStorageShare(
		file_storage_id=file_id,
		business_id=business_id,
		token_hash=th,
		password_hash=pwd_hash,
		expires_at=expires_at,
		created_by=user_id,
	)
	db.add(row)
	db.commit()
	db.refresh(row)

	base = resolve_public_app_base_url_for_public_links(db).rstrip("/")
	public_url: Optional[str] = None
	if base:
		public_url = f"{base}/public/storage-file/{raw}"

	return {
		"share_id": row.id,
		"token": raw,
		"public_url": public_url,
		"expires_at": row.expires_at.isoformat() if row.expires_at else None,
		"has_password": bool(row.password_hash),
	}


def list_shares_for_file(db: Session, business_id: int, file_id: str) -> list[dict[str, Any]]:
	_get_file_for_business(db, business_id, file_id)
	rows = (
		db.query(FileStorageShare)
		.filter(
			and_(
				FileStorageShare.file_storage_id == file_id,
				FileStorageShare.business_id == business_id,
			)
		)
		.order_by(desc(FileStorageShare.created_at))
		.all()
	)
	out: list[dict[str, Any]] = []
	for r in rows:
		out.append(
			{
				"id": r.id,
				"created_at": r.created_at.isoformat() if r.created_at else None,
				"expires_at": r.expires_at.isoformat() if r.expires_at else None,
				"revoked_at": r.revoked_at.isoformat() if r.revoked_at else None,
				"has_password": bool(r.password_hash),
				"access_count": r.access_count or 0,
				"last_access_at": r.last_access_at.isoformat() if r.last_access_at else None,
				"is_active": r.revoked_at is None and (r.expires_at is None or r.expires_at > _utcnow()),
			}
		)
	return out


def list_shares_for_business(
	db: Session,
	business_id: int,
	page: int = 1,
	limit: int = 50,
	only_active: bool = False,
) -> dict[str, Any]:
	q = db.query(FileStorageShare).filter(FileStorageShare.business_id == business_id)
	if only_active:
		q = q.filter(
			and_(
				FileStorageShare.revoked_at.is_(None),
				(FileStorageShare.expires_at.is_(None)) | (FileStorageShare.expires_at > _utcnow()),
			)
		)
	total = q.count()
	offset = (page - 1) * limit
	rows = q.order_by(desc(FileStorageShare.created_at)).offset(offset).limit(limit).all()
	items: list[dict[str, Any]] = []
	for r in rows:
		f = db.query(FileStorage).filter(FileStorage.id == r.file_storage_id).first()
		items.append(
			{
				"id": r.id,
				"file_id": r.file_storage_id,
				"file_name": f.original_name if f else None,
				"created_at": r.created_at.isoformat() if r.created_at else None,
				"expires_at": r.expires_at.isoformat() if r.expires_at else None,
				"revoked_at": r.revoked_at.isoformat() if r.revoked_at else None,
				"has_password": bool(r.password_hash),
				"access_count": r.access_count or 0,
				"is_active": r.revoked_at is None and (r.expires_at is None or r.expires_at > _utcnow()),
			}
		)
	return {
		"items": items,
		"pagination": {
			"page": page,
			"limit": limit,
			"total_count": total,
			"total_pages": (total + limit - 1) // limit if limit else 1,
		},
	}


def revoke_share(db: Session, business_id: int, share_id: int) -> None:
	row = (
		db.query(FileStorageShare)
		.filter(and_(FileStorageShare.id == share_id, FileStorageShare.business_id == business_id))
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "لینک اشتراک یافت نشد", http_status=404)
	row.revoked_at = _utcnow()
	db.commit()


def revoke_all_for_business(db: Session, business_id: int) -> int:
	now = _utcnow()
	count = (
		db.query(FileStorageShare)
		.filter(
			and_(
				FileStorageShare.business_id == business_id,
				FileStorageShare.revoked_at.is_(None),
			)
		)
		.update({"revoked_at": now}, synchronize_session=False)
	)
	db.commit()
	return int(count or 0)


def update_share(
	db: Session,
	business_id: int,
	share_id: int,
	password: Optional[str] = None,
	clear_password: bool = False,
	expires_in_days: Optional[int] = None,
	set_expires: bool = False,
) -> dict[str, Any]:
	row = (
		db.query(FileStorageShare)
		.filter(and_(FileStorageShare.id == share_id, FileStorageShare.business_id == business_id))
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "لینک اشتراک یافت نشد", http_status=404)
	if clear_password:
		row.password_hash = None
	elif password is not None:
		if not password.strip():
			raise ApiError("VALIDATION_ERROR", "رمز خالی مجاز نیست", http_status=422)
		row.password_hash = hash_password(password.strip())

	if set_expires:
		if expires_in_days is None:
			row.expires_at = None
		else:
			if expires_in_days < 1 or expires_in_days > 365:
				raise ApiError("VALIDATION_ERROR", "انقضا باید بین ۱ تا ۳۶۵ روز باشد یا null برای بدون انقضا", http_status=422)
			row.expires_at = _utcnow() + timedelta(days=int(expires_in_days))

	db.commit()
	db.refresh(row)
	return {
		"id": row.id,
		"expires_at": row.expires_at.isoformat() if row.expires_at else None,
		"has_password": bool(row.password_hash),
	}


def get_share_by_public_token(db: Session, raw_token: str) -> FileStorageShare | None:
	if not raw_token or len(raw_token) < 16:
		return None
	th = _hash_share_token(raw_token.strip())
	return db.query(FileStorageShare).filter(FileStorageShare.token_hash == th).first()


def assert_share_usable(share: FileStorageShare) -> None:
	if share.revoked_at is not None:
		raise ApiError("SHARE_REVOKED", "این لینک غیرفعال شده است", http_status=410)
	if share.expires_at is not None and share.expires_at <= _utcnow():
		raise ApiError("SHARE_EXPIRED", "این لینک منقضی شده است", http_status=410)


def unlock_share(db: Session, raw_token: str, password: Optional[str]) -> dict[str, Any]:
	share = get_share_by_public_token(db, raw_token)
	if not share:
		raise ApiError("NOT_FOUND", "لینک نامعتبر است", http_status=404)
	assert_share_usable(share)
	f = db.query(FileStorage).filter(FileStorage.id == share.file_storage_id).first()
	if not f or f.deleted_at is not None:
		raise ApiError("FILE_NOT_FOUND", "فایل دیگر در دسترس نیست", http_status=404)

	if share.password_hash:
		if not password or not verify_password(password, share.password_hash):
			raise ApiError("INVALID_PASSWORD", "رمز نادرست است", http_status=401)
		access = create_storage_share_access_token(share.id, ttl_seconds=6 * 3600)
		return {"access_token": access, "expires_in_seconds": 6 * 3600}

	return {"access_token": None, "expires_in_seconds": 0}


def touch_share_access(db: Session, share: FileStorageShare) -> None:
	share.access_count = int(share.access_count or 0) + 1
	share.last_access_at = _utcnow()
	db.add(share)
	db.commit()
