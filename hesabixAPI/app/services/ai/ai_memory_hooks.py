"""
زمان‌بندی کیوریتور حافظه پس از چت — job پایدار بدون وابستگی به AuthContext درخواست.
"""
from __future__ import annotations

import asyncio
import logging
import threading
from typing import Any, Callable, Coroutine, List, Optional

logger = logging.getLogger(__name__)


def _recent_plain_turns(db_messages: List[Any], *, limit: int = 4) -> List[dict]:
    from app.services.ai.ai_history_summarizer import messages_from_db_rows

    rows = messages_from_db_rows(db_messages)
    turns: List[dict] = []
    for msg in rows:
        role = msg.get("role")
        if role not in ("user", "assistant"):
            continue
        content = (msg.get("content") or "").strip()
        if not content or content.startswith("{"):
            continue
        turns.append({"role": role, "content": content})
    return turns[-limit:]


def _spawn_async(factory: Callable[[], Coroutine[Any, Any, None]]) -> None:
    """Job جدا از loop درخواست تا پس از برگشت handler زنده بماند."""

    async def _guarded() -> None:
        try:
            await factory()
        except Exception as exc:
            logger.warning("background memory task failed: %s", exc)

    def _runner() -> None:
        try:
            asyncio.run(_guarded())
        except Exception as exc:
            logger.warning("memory curator thread failed: %s", exc)

    threading.Thread(target=_runner, daemon=True, name="ai-memory-curator").start()


def schedule_memory_update_after_chat(
    session_id: int,
    business_id: int,
    ctx: Any,
    *,
    force: bool = False,  # noqa: ARG001 — سازگاری با فراخوان‌های قبلی
    skip_if_empty: bool = True,
) -> None:
    """کیوریتور پس از هر پاسخ موفق (غیرمسدودکننده)."""
    try:
        user_id = int(ctx.get_user_id())
    except Exception:
        logger.warning("memory curator skipped: no user_id")
        return
    if not business_id or not session_id:
        return

    display_name = ""
    try:
        display_name = (ctx.get_user_name() or "").strip()
    except Exception:
        display_name = ""

    async def _task() -> None:
        from adapters.db.repositories.ai_chat_repository import AIChatMessageRepository
        from adapters.db.repositories.user_repo import UserRepository
        from adapters.db.session import get_db_session
        from app.core.auth_dependency import AuthContext
        from app.services.ai.ai_memory_curator import curate_memory_from_turns
        from app.services.ai.ai_memory_item_service import list_memory_items, memory_item_to_dict
        from app.services.ai.ai_memory_service import seed_profile_identity
        from app.services.ai.ai_service import AIService

        with get_db_session() as db:
            message_repo = AIChatMessageRepository(db)
            db_messages = message_repo.get_session_messages(session_id, limit=12)
            turns = _recent_plain_turns(db_messages)
            if skip_if_empty and (
                not turns
                or not any(t["role"] == "user" for t in turns)
                or not any(t["role"] == "assistant" and t["content"].strip() for t in turns)
            ):
                seed_profile_identity(db, int(business_id), user_id, display_name)
                return
            seed_profile_identity(db, int(business_id), user_id, display_name)
            user = UserRepository(db).get_by_id(user_id)
            if not user:
                return
            auth = AuthContext(
                user=user,
                api_key_id=0,
                db=db,
                business_id=int(business_id),
            )
            ai_service = AIService(db, auth, int(business_id))
            existing = [
                memory_item_to_dict(r)
                for r in list_memory_items(db, int(business_id), user_id, limit=40)
            ]
            from app.services.ai.ai_memory_service import get_memory_content

            instructions = get_memory_content(db, int(business_id), user_id)
            if instructions:
                existing.insert(
                    0,
                    {
                        "item_key": "instruction",
                        "kind": "instruction",
                        "content": instructions[:120],
                    },
                )
            await curate_memory_from_turns(
                db,
                business_id=int(business_id),
                user_id=user_id,
                turns=turns,
                existing=existing,
                ai_service=ai_service,
            )

    _spawn_async(_task)


def schedule_memory_update_on_session_delete(
    business_id: Optional[int],
    ctx: Any,
    session_id: int,
) -> None:
    if not business_id:
        return
    schedule_memory_update_after_chat(
        session_id,
        int(business_id),
        ctx,
        force=True,
        skip_if_empty=False,
    )
