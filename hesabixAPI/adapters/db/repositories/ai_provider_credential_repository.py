from __future__ import annotations

from typing import List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_provider_credential import AIProviderCredential
from adapters.db.repositories.base_repo import BaseRepository


class AIProviderCredentialRepository(BaseRepository[AIProviderCredential]):
    def __init__(self, db: Session):
        super().__init__(db, AIProviderCredential)

    def get_by_provider(self, provider: str) -> Optional[AIProviderCredential]:
        return (
            self.db.query(self.model_class)
            .filter(self.model_class.provider == provider)
            .first()
        )

    def get_active_by_provider(self, provider: str) -> Optional[AIProviderCredential]:
        return (
            self.db.query(self.model_class)
            .filter(
                self.model_class.provider == provider,
                self.model_class.is_active == True,  # noqa: E712
            )
            .first()
        )

    def list_active(self) -> List[AIProviderCredential]:
        return (
            self.db.query(self.model_class)
            .filter(self.model_class.is_active == True)  # noqa: E712
            .order_by(self.model_class.provider.asc())
            .all()
        )
