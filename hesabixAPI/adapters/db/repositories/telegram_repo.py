from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional, List
import secrets

from sqlalchemy import select, and_, or_
from sqlalchemy.orm import Session

from adapters.db.models.telegram import TelegramLinkToken, TelegramAISession
from adapters.db.repositories.base_repo import BaseRepository


class TelegramRepository:
	def __init__(self, db: Session) -> None:
		self.db = db

	def create_link_token(self, *, user_id: int, ttl_seconds: int, created_ip: str | None, user_agent: str | None) -> TelegramLinkToken:
		token = secrets.token_urlsafe(32)
		expires_at = datetime.utcnow() + timedelta(seconds=ttl_seconds)
		obj = TelegramLinkToken(
			user_id=user_id,
			token=token,
			expires_at=expires_at,
			created_ip=created_ip,
			user_agent=user_agent,
		)
		self.db.add(obj)
		self.db.commit()
		self.db.refresh(obj)
		return obj

	def get_by_token(self, token: str) -> Optional[TelegramLinkToken]:
		stmt = select(TelegramLinkToken).where(TelegramLinkToken.token == token)
		return self.db.execute(stmt).scalars().first()

	def mark_used(self, obj: TelegramLinkToken) -> None:
		obj.used_at = datetime.utcnow()
		self.db.add(obj)
		self.db.commit()
		self.db.refresh(obj)


class TelegramAISessionRepository(BaseRepository[TelegramAISession]):
	"""Repository برای مدیریت جلسات تلگرام AI"""
	
	def __init__(self, db: Session):
		super().__init__(db, TelegramAISession)
	
	def get_active_session(
		self,
		user_id: int,
		chat_id: int
	) -> Optional[TelegramAISession]:
		"""دریافت جلسه فعال کاربر در چت تلگرام"""
		return self.db.query(self.model_class).filter(
			and_(
				self.model_class.user_id == user_id,
				self.model_class.chat_id == chat_id,
				self.model_class.is_active == True  # noqa: E712
			)
		).order_by(self.model_class.updated_at.desc()).first()
	
	def get_user_sessions(
		self,
		user_id: int,
		chat_id: int,
		limit: int = 50,
		skip: int = 0
	) -> List[TelegramAISession]:
		"""دریافت تمام جلسات کاربر در چت تلگرام"""
		return self.db.query(self.model_class).filter(
			and_(
				self.model_class.user_id == user_id,
				self.model_class.chat_id == chat_id
			)
		).order_by(self.model_class.updated_at.desc()).offset(skip).limit(limit).all()
	
	def create_or_update_session(
		self,
		user_id: int,
		chat_id: int,
		session_id: Optional[int] = None,
		business_id: Optional[int] = None
	) -> TelegramAISession:
		"""ایجاد یا به‌روزرسانی جلسه"""
		# غیرفعال کردن جلسات قبلی
		self.db.query(self.model_class).filter(
			and_(
				self.model_class.user_id == user_id,
				self.model_class.chat_id == chat_id,
				self.model_class.is_active == True  # noqa: E712
			)
		).update({"is_active": False})
		
		# ایجاد یا به‌روزرسانی جلسه
		if session_id:
			# بررسی وجود جلسه با این session_id
			existing = self.db.query(self.model_class).filter(
				and_(
					self.model_class.user_id == user_id,
					self.model_class.chat_id == chat_id,
					self.model_class.session_id == session_id
				)
			).first()
			
			if existing:
				existing.is_active = True
				existing.business_id = business_id
				existing.updated_at = datetime.utcnow()
				self.db.add(existing)
				self.db.commit()
				self.db.refresh(existing)
				return existing
		
		# ایجاد جلسه جدید
		new_session = TelegramAISession(
			user_id=user_id,
			chat_id=chat_id,
			session_id=session_id,
			business_id=business_id,
			is_active=True
		)
		self.db.add(new_session)
		self.db.commit()
		self.db.refresh(new_session)
		return new_session
	
	def deactivate_session(
		self,
		user_id: int,
		chat_id: int,
		session_id: Optional[int] = None
	) -> bool:
		"""غیرفعال کردن جلسه"""
		query = self.db.query(self.model_class).filter(
			and_(
				self.model_class.user_id == user_id,
				self.model_class.chat_id == chat_id
			)
		)
		
		if session_id:
			query = query.filter(self.model_class.session_id == session_id)
		else:
			query = query.filter(self.model_class.is_active == True)  # noqa: E712
		
		updated = query.update({"is_active": False, "updated_at": datetime.utcnow()})
		self.db.commit()
		return updated > 0


