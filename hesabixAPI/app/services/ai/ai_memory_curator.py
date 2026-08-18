"""کیوریتور حافظه: مدل سبک پس از هر پاسخ، بدون regex یادگیری."""
from __future__ import annotations

import json
import logging
import re
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from app.core.responses import ApiError
from app.services.ai.ai_constants import (
    AI_OPERATION_MEMORY_CURATE,
    MAX_MEMORY_ITEM_CONTENT_CHARS,
    MEMORY_CURATE_MAX_OPS,
    MEMORY_CURATE_MAX_TOKENS,
    MEMORY_CURATE_MIN_CONFIDENCE,
    MEMORY_CURATOR_AUTO_KINDS,
    MEMORY_KINDS,
)
from app.services.ai.ai_memory_item_service import (
    memory_item_to_dict,
    soft_delete_memory_item,
    upsert_memory_item,
)
from app.services.ai.ai_memory_keys import canonical_kind, is_stable_key, normalize_memory_key
from app.services.ai.ai_ops_metrics import log_ai_event
from app.services.ai.prompt_service import get_prompt_by_key

logger = logging.getLogger(__name__)

_SECRET_RE = re.compile(
    r"(api[_-]?key|secret|password|passwd|token|private[_-]?key|bearer)\s*[:=]\s*\S+",
    re.IGNORECASE,
)
_DOC_ID_RE = re.compile(
    r"^(?:فاکتور|سند|حواله|رسید|invoice|document)\s*#?\s*\d{2,}\s*$",
    re.IGNORECASE,
)
_AMOUNT_ONLY_RE = re.compile(
    r"^[\d٠-٩۰-۹,.\s]+(?:ریال|تومان|toman|rial)?\s*$",
    re.IGNORECASE,
)
_JSON_FENCE_RE = re.compile(r"```(?:json)?\s*(\{.*?\})\s*```", re.DOTALL | re.IGNORECASE)


def extract_json_object(text: str) -> Optional[Dict[str, Any]]:
    raw = (text or "").strip()
    if not raw:
        return None
    candidates: List[str] = []
    fenced = _JSON_FENCE_RE.search(raw)
    if fenced:
        candidates.append(fenced.group(1))
    candidates.append(raw)
    start = raw.find("{")
    end = raw.rfind("}")
    if start >= 0 and end > start:
        candidates.append(raw[start : end + 1])
    for cand in candidates:
        try:
            data = json.loads(cand)
        except json.JSONDecodeError:
            continue
        if isinstance(data, dict):
            return data
    return None


def parse_curator_ops(payload: Any) -> List[Dict[str, Any]]:
    if payload is None:
        return []
    if isinstance(payload, list):
        ops = payload
    elif isinstance(payload, dict):
        ops = payload.get("ops")
        if ops is None and payload.get("action"):
            ops = [payload]
        if not isinstance(ops, list):
            return []
    else:
        return []
    out: List[Dict[str, Any]] = []
    for item in ops:
        if isinstance(item, dict):
            out.append(item)
    return out[: MEMORY_CURATE_MAX_OPS + 4]


def _confidence_value(raw: Any) -> float:
    if raw is None:
        return 0.75
    if isinstance(raw, (int, float)):
        return float(raw)
    text = str(raw).strip().lower()
    mapping = {"high": 0.9, "medium": 0.7, "low": 0.4}
    if text in mapping:
        return mapping[text]
    try:
        return float(text)
    except ValueError:
        return 0.0


def validate_curator_op(op: Dict[str, Any]) -> Tuple[Optional[Dict[str, Any]], str]:
    """خروجی: (op نرمال‌شده, reason). reason خالی یعنی پذیرفته."""
    action = str(op.get("action") or "noop").strip().lower()
    if action in ("noop", "none", "skip"):
        return None, "noop"
    if action not in ("upsert", "update", "delete"):
        return None, "bad_action"

    kind = canonical_kind(op.get("kind") or op.get("category"), default="context")
    if kind not in MEMORY_KINDS:
        return None, "bad_kind"

    key = normalize_memory_key(
        op.get("key") or op.get("item_key"),
        kind=kind,
        content=str(op.get("content") or ""),
    )
    if action != "delete" and not is_stable_key(key) and key != "instruction":
        return None, "bad_key"

    user_explicit = bool(op.get("user_explicit") or op.get("actor") == "user_explicit")
    if kind == "instruction" and not user_explicit:
        return None, "instruction_not_explicit"
    if kind == "instruction" and key != "instruction":
        key = "instruction"

    if action == "delete":
        return (
            {"action": "delete", "key": key, "kind": kind, "user_explicit": user_explicit},
            "",
        )

    content = str(op.get("content") or "").strip()
    if not content:
        return None, "empty_content"
    if len(content) > MAX_MEMORY_ITEM_CONTENT_CHARS:
        content = content[:MAX_MEMORY_ITEM_CONTENT_CHARS]
    if _SECRET_RE.search(content):
        return None, "secret"
    if _DOC_ID_RE.match(content) or _AMOUNT_ONLY_RE.match(content):
        return None, "ephemeral"
    conf = _confidence_value(op.get("confidence"))
    if conf < MEMORY_CURATE_MIN_CONFIDENCE:
        return None, "low_confidence"
    if kind not in MEMORY_CURATOR_AUTO_KINDS and not user_explicit:
        return None, "kind_not_auto"

    return (
        {
            "action": action,
            "key": key,
            "kind": kind,
            "content": content,
            "confidence": conf,
            "user_explicit": user_explicit,
        },
        "",
    )


def apply_curator_ops(
    db: Session,
    business_id: int,
    user_id: int,
    ops: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    from app.services.ai.ai_memory_service import get_memory_content, upsert_memory

    applied: List[Dict[str, Any]] = []
    for raw in ops[:MEMORY_CURATE_MAX_OPS]:
        op, reason = validate_curator_op(raw)
        if not op:
            log_ai_event(
                "memory_curate_rejected",
                business_id=business_id,
                user_id=user_id,
                extra={"reason": reason},
            )
            continue
        action = op["action"]
        try:
            if action == "delete":
                if op["kind"] == "instruction" or op["key"] == "instruction":
                    upsert_memory(db, business_id, user_id, "")
                    applied.append({**op, "status": "deleted"})
                    continue
                ok = soft_delete_memory_item(
                    db, business_id, user_id, item_key=op["key"]
                )
                if ok:
                    applied.append({**op, "status": "deleted"})
                continue
            if op["kind"] == "instruction" or op["key"] == "instruction":
                current = get_memory_content(db, business_id, user_id)
                text = op["content"]
                if action == "update" and current:
                    text = f"{current}\n{text}".strip()
                upsert_memory(db, business_id, user_id, text)
                applied.append({**op, "status": "upserted"})
                continue
            row = upsert_memory_item(
                db,
                business_id,
                user_id,
                item_key=op["key"],
                category=op["kind"],
                content=op["content"],
                source="curator",
                confidence="high" if op["confidence"] >= 0.8 else "medium",
            )
            applied.append({**op, "status": "upserted", "item": memory_item_to_dict(row)})
        except Exception as exc:
            logger.warning("apply curator op failed: %s", exc)
            log_ai_event(
                "memory_curate_rejected",
                business_id=business_id,
                user_id=user_id,
                extra={"reason": "apply_error"},
            )
    return applied


def build_curator_user_payload(
    *,
    turns: List[Dict[str, str]],
    existing: List[Dict[str, Any]],
) -> str:
    mem_lines = []
    for item in existing[:40]:
        key = item.get("item_key") or ""
        kind = item.get("kind") or item.get("category") or ""
        content = (item.get("content") or "")[:120]
        mem_lines.append(f"- {key} [{kind}]: {content}")
    if not mem_lines:
        mem_lines.append("(empty)")
    turn_lines = []
    for msg in turns[-4:]:
        role = "USER" if msg.get("role") == "user" else "ASSISTANT"
        text = (msg.get("content") or "").strip().replace("\n", " ")[:800]
        if text:
            turn_lines.append(f"{role}: {text}")
    return (
        "Existing memory:\n"
        + "\n".join(mem_lines)
        + "\n\nRecent turns:\n"
        + "\n".join(turn_lines or ["(none)"])
        + "\n\nReturn JSON only."
    )


async def curate_memory_from_turns(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    turns: List[Dict[str, str]],
    existing: List[Dict[str, Any]],
    ai_service: Any,
) -> List[Dict[str, Any]]:
    """فراخوانی مدل light و اعمال patch. شکست نباید چت را خراب کند."""
    if not turns:
        return []
    user_has_text = any(
        (t.get("role") == "user" and (t.get("content") or "").strip()) for t in turns
    )
    assistant_has_text = any(
        (t.get("role") == "assistant" and (t.get("content") or "").strip()) for t in turns
    )
    if not user_has_text or not assistant_has_text:
        return []

    from app.services.ai.ai_memory_quota import can_use_memory_curate, record_memory_curate

    if not can_use_memory_curate(user_id, business_id):
        log_ai_event(
            "memory_curate_skipped",
            business_id=business_id,
            user_id=user_id,
            extra={"reason": "quota"},
        )
        return []

    if not getattr(ai_service, "config", None) or not ai_service.config.is_active:
        log_ai_event(
            "memory_curate_skipped",
            business_id=business_id,
            user_id=user_id,
            extra={"reason": "inactive"},
        )
        return []

    user_blob = " ".join(t.get("content") or "" for t in turns if t.get("role") == "user")
    ai_service.set_routing_context(
        operation=AI_OPERATION_MEMORY_CURATE,
        user_query=user_blob[:500],
        needs_tools=False,
    )
    try:
        availability = ai_service.check_availability(
            estimated_tokens=400,
            user_query=user_blob[:500],
        )
        if not availability.get("can_use"):
            log_ai_event(
                "memory_curate_skipped",
                business_id=business_id,
                user_id=user_id,
                extra={"reason": "availability"},
            )
            return []
    except Exception as exc:
        logger.debug("memory curate availability check failed: %s", exc)
        return []

    system = get_prompt_by_key(db, "aux.memory_curate")
    user_content = build_curator_user_payload(turns=turns, existing=existing)
    try:
        provider = ai_service._make_provider()  # noqa: SLF001
        model = ai_service.get_effective_model_api_id(
            operation=AI_OPERATION_MEMORY_CURATE,
            user_query=user_blob[:500],
        )
        response = provider.chat_completion(
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user_content},
            ],
            model=model,
            max_tokens=MEMORY_CURATE_MAX_TOKENS,
            temperature=0.1,
            tools=None,
        )
    except Exception as exc:
        logger.warning("memory curator provider failed: %s", exc)
        log_ai_event(
            "memory_curate_failed",
            business_id=business_id,
            user_id=user_id,
            extra={"reason": "provider"},
        )
        return []

    usage = response.get("usage") if isinstance(response, dict) else None
    if usage:
        try:
            ai_service._charge_and_log_usage(  # noqa: SLF001
                input_tokens=int(usage.get("input_tokens", 0) or 0),
                output_tokens=int(usage.get("output_tokens", 0) or 0),
                usage=usage,
                model_code=ai_service.get_effective_model_code(
                    operation=AI_OPERATION_MEMORY_CURATE,
                    user_query=user_blob[:500],
                ),
            )
        except ApiError as charge_exc:
            logger.warning("memory curator charge failed: %s", charge_exc)

    record_memory_curate(user_id, business_id)
    message = (response.get("message") or {}) if isinstance(response, dict) else {}
    raw_text = (message.get("content") or "").strip()
    parsed = extract_json_object(raw_text)
    ops = parse_curator_ops(parsed)
    if not ops:
        log_ai_event(
            "memory_curate_noop",
            business_id=business_id,
            user_id=user_id,
        )
        return []
    applied = apply_curator_ops(db, business_id, user_id, ops)
    log_ai_event(
        "memory_curate_applied" if applied else "memory_curate_noop",
        business_id=business_id,
        user_id=user_id,
        extra={"ops": len(applied)},
    )
    return applied
