from __future__ import annotations

from typing import Optional

from sqlalchemy.orm import Session

from adapters.db.models.business_ai_provider_config import BusinessAIProviderConfig
from adapters.db.repositories.base_repo import BaseRepository


class BusinessAIProviderConfigRepository(BaseRepository[BusinessAIProviderConfig]):
    def __init__(self, db: Session):
        super().__init__(db, BusinessAIProviderConfig)

    def get_by_business_id(self, business_id: int) -> Optional[BusinessAIProviderConfig]:
        return (
            self.db.query(self.model_class)
            .filter(self.model_class.business_id == int(business_id))
            .first()
        )
