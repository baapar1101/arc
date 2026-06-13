from __future__ import annotations

from typing import Optional, Dict, Any, List

from sqlalchemy.orm import Session

from adapters.db.models.ai_prompt import AIPrompt, PromptRole, PromptType
from adapters.db.repositories.ai_prompt_repository import AIPromptRepository
from adapters.db.seed_data.ai_default_prompts import (
    AI_DEFAULT_PROMPT_ROWS,
    AI_PROMPT_FALLBACKS,
    compose_user_chat_prompt,
)


def render_prompt_template(template: str, variables: Optional[Dict[str, Any]] = None) -> str:
    if not variables:
        return template
    result = template
    for key, value in variables.items():
        result = result.replace("{" + key + "}", str(value if value is not None else ""))
    return result


def get_prompt_by_key(
    db: Optional[Session],
    prompt_key: str,
    variables: Optional[Dict[str, Any]] = None,
) -> str:
    template = AI_PROMPT_FALLBACKS.get(prompt_key, "")
    if db is not None:
        repo = AIPromptRepository(db)
        row = repo.get_default_by_key(prompt_key)
        if row:
            template = row.content
    return render_prompt_template(template, variables)


def _compose_user_chat_prompt(db: Session) -> str:
    base = get_prompt_by_key(db, "chat.user.base")
    query_block = get_prompt_by_key(db, "chat.query_filter")
    visualization_block = get_prompt_by_key(db, "chat.visualization")
    workflow_block = get_prompt_by_key(db, "chat.workflow")
    return base + query_block + visualization_block + "\n\n" + workflow_block


def _get_hardcoded_role_prompt(role: PromptRole) -> str:
    if role == PromptRole.USER:
        return compose_user_chat_prompt()
    key = {
        PromptRole.OPERATOR: "chat.operator",
        PromptRole.ADMIN: "chat.admin",
    }.get(role)
    if key:
        return AI_PROMPT_FALLBACKS.get(key, "")
    return ""


def get_prompt(
    db: Session,
    role: PromptRole,
    user_id: Optional[int] = None,
    prompt_type: PromptType = PromptType.SYSTEM,
) -> str:
    """
    دریافت prompt با اولویت:
    1. Prompt شخصی کاربر (اگر user_id داده شده)
    2. Prompt پیش‌فرض سیستم از DB
    3. Prompt سخت‌کد شده
    """
    repo = AIPromptRepository(db)

    if user_id:
        user_prompt = repo.get_user_prompt(user_id, role, prompt_type)
        if user_prompt:
            return user_prompt.content

    if role == PromptRole.USER and prompt_type == PromptType.SYSTEM:
        has_db_parts = any(
            repo.get_default_by_key(key)
            for key in ("chat.user.base", "chat.query_filter", "chat.visualization", "chat.workflow")
        )
        if has_db_parts:
            return _compose_user_chat_prompt(db)

    role_key = {
        PromptRole.OPERATOR: "chat.operator",
        PromptRole.ADMIN: "chat.admin",
    }.get(role)
    if role_key:
        row = repo.get_default_by_key(role_key)
        if row:
            return row.content

    legacy = repo.get_default_prompt(role, prompt_type)
    if legacy and legacy.content:
        if role == PromptRole.USER and prompt_type == PromptType.SYSTEM:
            return legacy.content
        if role != PromptRole.USER:
            return legacy.content

    return _get_hardcoded_role_prompt(role)


def list_effective_default_prompts(
    db: Session,
    role: Optional[str] = None,
    category: Optional[str] = None,
) -> List[Dict[str, Any]]:
    repo = AIPromptRepository(db)
    db_rows = {
        row.prompt_key: row
        for row in repo.get_all_default_prompts(role=role, category=category)
    }

    result: List[Dict[str, Any]] = []
    for row_def in AI_DEFAULT_PROMPT_ROWS:
        if role and row_def["role"] != role:
            continue
        if category and row_def["category"] != category:
            continue

        prompt_key = row_def["prompt_key"]
        db_row = db_rows.get(prompt_key)
        content = db_row.content if db_row else AI_PROMPT_FALLBACKS[prompt_key]
        result.append(
            {
                "id": db_row.id if db_row else None,
                "prompt_key": prompt_key,
                "role": row_def["role"],
                "prompt_type": row_def["prompt_type"],
                "category": row_def["category"],
                "title": row_def["title"],
                "content": content,
                "is_default": True,
                "is_active": db_row.is_active if db_row else True,
                "source": "database" if db_row else "fallback",
                "created_at": db_row.created_at.isoformat() if db_row and db_row.created_at else None,
                "updated_at": db_row.updated_at.isoformat() if db_row and db_row.updated_at else None,
            }
        )
    return result


def create_user_prompt(
    db: Session,
    user_id: int,
    role: PromptRole,
    title: str,
    content: str,
    prompt_type: PromptType = PromptType.SYSTEM,
) -> AIPrompt:
    prompt = AIPrompt(
        prompt_key=f"user.{user_id}.{role.value}.{prompt_type.value}",
        role=role.value,
        prompt_type=prompt_type.value,
        category="personal",
        title=title,
        content=content,
        user_id=user_id,
        is_default=False,
        is_active=True,
    )
    db.add(prompt)
    db.commit()
    db.refresh(prompt)
    return prompt


def update_default_prompt_by_key(db: Session, prompt_key: str, content: str) -> AIPrompt:
    row_def = next((r for r in AI_DEFAULT_PROMPT_ROWS if r["prompt_key"] == prompt_key), None)
    if not row_def:
        raise ValueError(f"Unknown prompt key: {prompt_key}")

    repo = AIPromptRepository(db)
    prompt = repo.get_default_by_key(prompt_key)

    if prompt:
        prompt.content = content
        prompt.title = row_def["title"]
        prompt.role = row_def["role"]
        prompt.prompt_type = row_def["prompt_type"]
        prompt.category = row_def["category"]
    else:
        prompt = AIPrompt(
            prompt_key=prompt_key,
            role=row_def["role"],
            prompt_type=row_def["prompt_type"],
            category=row_def["category"],
            title=row_def["title"],
            content=content,
            user_id=None,
            is_default=True,
            is_active=True,
        )
        db.add(prompt)

    db.commit()
    db.refresh(prompt)
    return prompt


def update_default_prompt(
    db: Session,
    role: PromptRole,
    content: str,
    prompt_type: PromptType = PromptType.SYSTEM,
) -> AIPrompt:
    """به‌روزرسانی prompt پیش‌فرض بر اساس نقش (سازگاری عقب‌رو)"""
    if role == PromptRole.USER and prompt_type == PromptType.SYSTEM:
        return update_default_prompt_by_key(db, "chat.user.base", content)

    role_key = {
        PromptRole.OPERATOR: "chat.operator",
        PromptRole.ADMIN: "chat.admin",
    }.get(role)
    if not role_key:
        raise ValueError(f"Unsupported role for default prompt update: {role}")
    return update_default_prompt_by_key(db, role_key, content)


def delete_default_prompt_by_key(db: Session, prompt_key: str) -> None:
    repo = AIPromptRepository(db)
    prompt = repo.get_default_by_key(prompt_key)
    if prompt:
        db.delete(prompt)
        db.commit()


def reset_default_prompt_by_key(db: Session, prompt_key: str) -> Dict[str, Any]:
    delete_default_prompt_by_key(db, prompt_key)
    fallback = AI_PROMPT_FALLBACKS.get(prompt_key, "")
    row_def = next((r for r in AI_DEFAULT_PROMPT_ROWS if r["prompt_key"] == prompt_key), None)
    return {
        "prompt_key": prompt_key,
        "content": fallback,
        "source": "fallback",
        "title": row_def["title"] if row_def else prompt_key,
    }
