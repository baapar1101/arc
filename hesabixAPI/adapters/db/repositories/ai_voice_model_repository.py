from __future__ import annotations

from typing import List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_voice_model import AIVoiceModel, AIVoicePolicy, BusinessAIVoiceSettings
from adapters.db.repositories.base_repo import BaseRepository


class AIVoiceModelRepository(BaseRepository[AIVoiceModel]):
	def __init__(self, db: Session):
		super().__init__(db, AIVoiceModel)

	def get_by_code(self, code: str) -> Optional[AIVoiceModel]:
		return (
			self.db.query(self.model_class)
			.filter(self.model_class.code == str(code).strip())
			.first()
		)

	def get_all_ordered(self) -> List[AIVoiceModel]:
		return (
			self.db.query(self.model_class)
			.order_by(
				self.model_class.kind.asc(),
				self.model_class.sort_order.asc(),
				self.model_class.id.asc(),
			)
			.all()
		)

	def get_active(self, *, kind: Optional[str] = None) -> List[AIVoiceModel]:
		q = self.db.query(self.model_class).filter(self.model_class.is_active.is_(True))
		if kind:
			q = q.filter(self.model_class.kind == kind)
		return q.order_by(self.model_class.sort_order.asc(), self.model_class.id.asc()).all()

	def get_default(self, kind: str) -> Optional[AIVoiceModel]:
		return (
			self.db.query(self.model_class)
			.filter(
				self.model_class.kind == kind,
				self.model_class.is_active.is_(True),
				self.model_class.is_default.is_(True),
			)
			.order_by(self.model_class.sort_order.asc())
			.first()
		)


class AIVoicePolicyRepository:
	def __init__(self, db: Session):
		self.db = db

	def get_or_create(self) -> AIVoicePolicy:
		row = self.db.query(AIVoicePolicy).order_by(AIVoicePolicy.id.asc()).first()
		if row:
			return row
		row = AIVoicePolicy(allow_cloud_audio=False)
		self.db.add(row)
		self.db.flush()
		return row


class BusinessAIVoiceSettingsRepository:
	def __init__(self, db: Session):
		self.db = db

	def get_by_business(self, business_id: int) -> Optional[BusinessAIVoiceSettings]:
		return (
			self.db.query(BusinessAIVoiceSettings)
			.filter(BusinessAIVoiceSettings.business_id == int(business_id))
			.first()
		)

	def get_or_create(self, business_id: int) -> BusinessAIVoiceSettings:
		row = self.get_by_business(business_id)
		if row:
			return row
		row = BusinessAIVoiceSettings(business_id=int(business_id), allow_cloud_audio=False)
		self.db.add(row)
		self.db.flush()
		return row
