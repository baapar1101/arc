"""قرارداد فراخوانی ابزار ثبت‌شده: (args, context) یا (db, **kwargs)."""
from __future__ import annotations

import inspect
from typing import Any, Callable, Dict

from app.services.ai.ai_constants import AI_LIST_TAKE_MAX


def handler_uses_args_context(service_func: Callable) -> bool:
    """آیا تابع با قرارداد ``(args, context)`` ثبت شده، نه ``(db, **kwargs)``."""
    try:
        params = list(inspect.signature(service_func).parameters.values())
    except (TypeError, ValueError):
        return False
    names = [
        p.name
        for p in params
        if p.kind
        in (
            inspect.Parameter.POSITIONAL_ONLY,
            inspect.Parameter.POSITIONAL_OR_KEYWORD,
        )
    ]
    if len(names) >= 2 and names[0] in {"args", "arguments"} and names[1] == "context":
        return True
    return False


def _clamp_take_fields(args: Dict[str, Any]) -> None:
    for key in ("take", "limit"):
        if key not in args or args[key] is None:
            continue
        try:
            args[key] = max(1, min(int(args[key]), AI_LIST_TAKE_MAX))
        except (TypeError, ValueError):
            args.pop(key, None)


def kwargs_for_old_style_handler(service_func: Callable, args: Dict[str, Any]) -> Dict[str, Any]:
    """فقط آرگومان‌هایی که تابع واقعاً می‌پذیرد — جلوگیری از unexpected keyword."""
    clean = {k: v for k, v in args.items() if k != "db"}
    try:
        params = inspect.signature(service_func).parameters
    except (TypeError, ValueError):
        return clean
    if any(p.kind == inspect.Parameter.VAR_KEYWORD for p in params.values()):
        return clean
    allowed = {
        name
        for name, p in params.items()
        if name != "db"
        and p.kind
        in (
            inspect.Parameter.POSITIONAL_ONLY,
            inspect.Parameter.POSITIONAL_OR_KEYWORD,
            inspect.Parameter.KEYWORD_ONLY,
        )
    }
    return {k: v for k, v in clean.items() if k in allowed}


def wrap_registry_service_func(service_func: Callable) -> Callable:
    """wrapper رجیستری: context را تزریق می‌کند و هر دو قرارداد handler را پشتیبانی می‌کند."""
    uses_args_context = handler_uses_args_context(service_func)

    def handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        db = context["db"]
        user_context = context["user_context"]

        from app.services.ai.ai_date_resolver import (
            calendar_type_from_context,
            enrich_tool_result_dates,
            normalize_query_dates,
        )

        calendar_type = calendar_type_from_context(context)
        context["calendar_type"] = calendar_type

        _date_keys = frozenset({
            "from_date", "to_date", "date_from", "date_to",
            "as_of_date", "document_date", "filters",
        })
        if any(k in args for k in _date_keys):
            try:
                normalized = normalize_query_dates(dict(args), calendar_type=calendar_type)
                args.update(normalized)
            except ValueError as exc:
                raise ValueError(str(exc)) from exc

        session_business_id = context.get("session_business_id")
        context_business_id = context.get("business_id")
        effective_business_id = session_business_id or context_business_id

        if "business_id" in args:
            provided_business_id = args.get("business_id")
            if provided_business_id != effective_business_id:
                import logging
                logging.getLogger(__name__).warning(
                    "AI attempted to use business_id %s but session has %s. "
                    "Using session business_id.",
                    provided_business_id,
                    effective_business_id,
                )
            args["business_id"] = effective_business_id
        elif effective_business_id:
            args["business_id"] = effective_business_id

        if args.get("business_id") and not user_context.can_access_business(args["business_id"]):
            raise PermissionError(
                f"User does not have access to business {args['business_id']}"
            )

        if "user_id" not in args:
            args["user_id"] = user_context.get_user_id()

        _clamp_take_fields(args)

        try:
            if uses_args_context:
                result = service_func(args, context)
            else:
                result = service_func(db=db, **kwargs_for_old_style_handler(service_func, args))
            return enrich_tool_result_dates(result, calendar_type=calendar_type)
        except Exception:
            try:
                db.rollback()
            except Exception:
                pass
            raise

    return handler
