"""Shared helpers for tenant-pinned MCP tools. extra_info stays out of schemas."""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any, Dict, Iterable, List, Optional


def mcp_schema(properties: Dict[str, Any], required: Optional[List[str]] = None) -> Dict[str, Any]:
    return {
        "type": "object",
        "properties": properties,
        "required": list(required or []),
        "additionalProperties": False,
    }


def mcp_raise(exc: BaseException) -> None:
    from app.core.responses import ApiError

    if isinstance(exc, ApiError):
        raise ValueError(exc.message) from exc
    raise exc


def mcp_run(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except Exception as exc:
        mcp_raise(exc)


def mcp_bid(context: Dict[str, Any]) -> int:
    return int(context["business_id"])


def mcp_db(context: Dict[str, Any]):
    return context["db"]


def mcp_uid(context: Dict[str, Any]) -> int:
    user = context.get("user_context")
    if user is None:
        raise ValueError("هویت کاربر موجود نیست")
    return int(user.get_user_id())


def mcp_can(context: Dict[str, Any], section: str, action: str) -> bool:
    user = context.get("user_context")
    if user is None or not hasattr(user, "has_business_permission"):
        return False
    return bool(user.has_business_permission(section, action))


def mcp_picked(args: Dict[str, Any], keys: Iterable[str]) -> Dict[str, Any]:
    return {k: v for k, v in args.items() if k in keys}


def mcp_jsonable(value: Any) -> Any:
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, dict):
        return {k: mcp_jsonable(v) for k, v in value.items()}
    if isinstance(value, list):
        return [mcp_jsonable(v) for v in value]
    return value


def mcp_unwrap(result: Any) -> Any:
    if isinstance(result, dict) and "data" in result:
        extra = set(result) - {"data", "message"}
        if not extra:
            return result["data"]
    return result


def mcp_commit(context: Dict[str, Any]) -> None:
    db = mcp_db(context)
    if hasattr(db, "commit"):
        db.commit()


def mcp_await(coro):
    import asyncio
    import concurrent.futures

    try:
        asyncio.get_running_loop()
    except RuntimeError:
        return asyncio.run(coro)
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        return pool.submit(asyncio.run, coro).result(timeout=300)


def mcp_translator():
    try:
        from app.core.i18n import Translator

        return Translator("fa")
    except Exception:
        class _T:
            def t(self, key, default="", **kwargs):
                return default or key

        return _T()
