"""
فراخوانی پس‌زمینه برای به‌روزرسانی حافظه بلندمدت پس از چت.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Any, List, Optional

from app.core.auth_dependency import AuthContext
from app.services.ai.ai_constants import AUTO_SUMMARIZE_USER_MESSAGE_INTERVAL
from app.services.ai.ai_history_summarizer import messages_from_db_rows
from app.services.ai.ai_memory_service import (
    AUTO_SUMMARIZE_MIN_MESSAGES,
    maybe_auto_summarize_session,
)

logger = logging.getLogger(__name__)


def count_user_messages(db_messages: List[Any]) -> int:
    n = 0
    for msg in db_messages:
        role = msg.role if isinstance(msg.role, str) else getattr(msg.role, "value", str(msg.role))
        if role == "user":
            n += 1
    return n


def should_run_memory_update(db_messages: List[Any], *, force: bool = False) -> bool:
    if force:
        return len(db_messages) >= AUTO_SUMMARIZE_MIN_MESSAGES
    user_count = count_user_messages(db_messages)
    if user_count < AUTO_SUMMARIZE_MIN_MESSAGES:
        return False
    if user_count % AUTO_SUMMARIZE_USER_MESSAGE_INTERVAL != 0:
        return False
    return True


def schedule_memory_update_after_chat(
    session_id: int,
    business_id: int,
    ctx: AuthContext,
    *,
    force: bool = False,
) -> None:
    """به‌روزرسانی حافظه در پس‌زمینه (غیرمسدودکننده)."""

    async def _task() -> None:
        try:
            from adapters.db.repositories.ai_chat_repository import AIChatMessageRepository
            from adapters.db.session import get_db_session

            with get_db_session() as db:
                message_repo = AIChatMessageRepository(db)
                db_messages = message_repo.get_session_messages(session_id, limit=80)
                if not should_run_memory_update(db_messages, force=force):
                    return
                llm_messages = messages_from_db_rows(db_messages)
                updated = await maybe_auto_summarize_session(
                    db,
                    business_id,
                    ctx.get_user_id(),
                    llm_messages,
                )
                if updated:
                    logger.info(
                        "AI memory updated in background: session=%s business=%s",
                        session_id,
                        business_id,
                    )
        except Exception as exc:
            logger.warning(
                "Background memory update failed for session %s: %s",
                session_id,
                exc,
            )

    asyncio.create_task(_task())


def schedule_memory_update_on_session_delete(
    business_id: Optional[int],
    ctx: AuthContext,
    session_id: int,
) -> None:
    """قبل از حذف session، یک‌بار حافظه را به‌روز کن."""
    if not business_id:
        return
    schedule_memory_update_after_chat(
        session_id,
        int(business_id),
        ctx,
        force=True,
    )
