from typing import Optional, List
from sqlalchemy.orm import Session
from adapters.db.models.ai_plan import AIPlan
from adapters.db.repositories.base_repo import BaseRepository


class AIPlanRepository(BaseRepository[AIPlan]):
    def __init__(self, db: Session):
        super().__init__(db, AIPlan)
    
    def get_by_code(self, code: str) -> Optional[AIPlan]:
        """دریافت پلن بر اساس کد"""
        return self.db.query(self.model_class).filter(
            self.model_class.code == code
        ).first()
    
    def get_active_plans(self) -> List[AIPlan]:
        """دریافت پلن‌های فعال"""
        return self.db.query(self.model_class).filter(
            self.model_class.is_active == True  # noqa: E712
        ).order_by(self.model_class.created_at.desc()).all()

