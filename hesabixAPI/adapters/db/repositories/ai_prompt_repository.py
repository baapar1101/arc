from typing import Optional, List
from sqlalchemy.orm import Session
from sqlalchemy import and_
from adapters.db.models.ai_prompt import AIPrompt, PromptRole, PromptType
from adapters.db.repositories.base_repo import BaseRepository


class AIPromptRepository(BaseRepository[AIPrompt]):
    def __init__(self, db: Session):
        super().__init__(db, AIPrompt)

    def get_default_by_key(self, prompt_key: str) -> Optional[AIPrompt]:
        return self.db.query(self.model_class).filter(
            and_(
                self.model_class.prompt_key == prompt_key,
                self.model_class.is_default == True,  # noqa: E712
                self.model_class.user_id == None,  # noqa: E711
                self.model_class.is_active == True,  # noqa: E712
            )
        ).first()

    def get_default_prompt(
        self,
        role: PromptRole,
        prompt_type: PromptType = PromptType.SYSTEM,
    ) -> Optional[AIPrompt]:
        """دریافت prompt پیش‌فرض بر اساس نقش (سازگاری عقب‌رو)"""
        return self.db.query(self.model_class).filter(
            and_(
                self.model_class.role == role.value,
                self.model_class.prompt_type == prompt_type.value,
                self.model_class.is_default == True,  # noqa: E712
                self.model_class.user_id == None,  # noqa: E711
                self.model_class.is_active == True,  # noqa: E712
            )
        ).first()

    def get_user_prompt(
        self,
        user_id: int,
        role: PromptRole,
        prompt_type: PromptType = PromptType.SYSTEM,
    ) -> Optional[AIPrompt]:
        return self.db.query(self.model_class).filter(
            and_(
                self.model_class.user_id == user_id,
                self.model_class.role == role.value,
                self.model_class.prompt_type == prompt_type.value,
                self.model_class.is_active == True,  # noqa: E712
            )
        ).first()

    def get_user_prompts(self, user_id: int) -> List[AIPrompt]:
        return self.db.query(self.model_class).filter(
            and_(
                self.model_class.user_id == user_id,
                self.model_class.is_active == True,  # noqa: E712
            )
        ).order_by(self.model_class.created_at.desc()).all()

    def get_all_default_prompts(
        self,
        role: Optional[str] = None,
        category: Optional[str] = None,
    ) -> List[AIPrompt]:
        query = self.db.query(self.model_class).filter(
            and_(
                self.model_class.is_default == True,  # noqa: E712
                self.model_class.user_id == None,  # noqa: E711
                self.model_class.is_active == True,  # noqa: E712
            )
        )
        if role:
            query = query.filter(self.model_class.role == role)
        if category:
            query = query.filter(self.model_class.category == category)
        return query.order_by(self.model_class.category, self.model_class.prompt_key).all()
