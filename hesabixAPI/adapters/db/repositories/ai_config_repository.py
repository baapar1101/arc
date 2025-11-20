from typing import Optional
from sqlalchemy.orm import Session
from adapters.db.models.ai_config import AIConfig
from adapters.db.repositories.base_repo import BaseRepository


class AIConfigRepository(BaseRepository[AIConfig]):
    def __init__(self, db: Session):
        super().__init__(db, AIConfig)
    
    def get_active_config(self) -> Optional[AIConfig]:
        """دریافت تنظیمات فعال AI"""
        return self.db.query(self.model_class).filter(
            self.model_class.is_active == True  # noqa: E712
        ).first()

