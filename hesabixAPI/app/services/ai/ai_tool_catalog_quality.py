"""Audit and quality score for Tool catalog metadata. Does not change ranking."""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from app.services.ai.ai_permission_policy import (
    ALLOWED_EMPTY_PERMISSION_POLICIES,
    permission_policy_for_name,
)
from app.services.ai.ai_tool_capability import TOOL_CAPABILITIES
from app.services.ai.ai_tool_manifest import get_manifest_entry, iter_manifest_names
from app.services.ai.ai_tool_spec import ToolSideEffect

_AI_DIR = Path(__file__).resolve().parent
_NAME_RE = re.compile(r'name\s*=\s*["\']([^"\']+)["\']')
_PERM_RE = re.compile(r"required_permissions\s*=\s*(\[[^\]]*\]|None)")
_READONLY_RE = re.compile(r"is_readonly\s*=\s*(True|False)")
_APPROVAL_RE = re.compile(r"requires_approval\s*=\s*(True|False)")
_RISK_RE = re.compile(r'risk_level\s*=\s*["\']([^"\']+)["\']')
_CATEGORY_RE = re.compile(r'category\s*=\s*["\']([^"\']+)["\']')
_BIZ_RE = re.compile(r"business_context_required\s*=\s*(True|False)")
_INTERNAL_RE = re.compile(r"is_agent_internal\s*=\s*(True|False)")
_DESC_IDENT_RE = re.compile(r"\bdescription\s*=\s*([A-Z][A-Z0-9_]+)\b")
_PAYLOAD_DESCRIPTIONS: Optional[Dict[str, str]] = None


def _payload_descriptions() -> Dict[str, str]:
    global _PAYLOAD_DESCRIPTIONS
    if _PAYLOAD_DESCRIPTIONS is None:
        from app.services.ai import ai_tool_payloads as payloads

        _PAYLOAD_DESCRIPTIONS = {
            key: " ".join(val.split())
            for key, val in vars(payloads).items()
            if key.endswith("_DESCRIPTION") and isinstance(val, str)
        }
    return _PAYLOAD_DESCRIPTIONS


def _function_blocks() -> List[str]:
    files = [_AI_DIR / "function_registry.py", *_AI_DIR.glob("ai_function_extensions*.py")]
    blocks: List[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        i = 0
        while True:
            j = text.find("AIFunction(", i)
            if j < 0:
                break
            depth = 0
            k = j + len("AIFunction")
            while k < len(text):
                if text[k] == "(":
                    depth += 1
                elif text[k] == ")":
                    depth -= 1
                    if depth == 0:
                        blocks.append(text[j:k + 1])
                        break
                k += 1
            i = k + 1
    return blocks


def parse_registered_tool_fields() -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    for block in _function_blocks():
        nm = _NAME_RE.search(block)
        if not nm:
            continue
        name = nm.group(1)
        perm_m = _PERM_RE.search(block)
        perms: Optional[List[str]]
        if perm_m is None:
            perms = None
        elif perm_m.group(1) in ("[]", "None"):
            perms = []
        else:
            perms = re.findall(r'["\']([^"\']+)["\']', perm_m.group(1))
        desc = _top_level_description(block)
        cat_m = _CATEGORY_RE.search(block)
        risk_m = _RISK_RE.search(block)
        ro_m = _READONLY_RE.search(block)
        ap_m = _APPROVAL_RE.search(block)
        biz_m = _BIZ_RE.search(block)
        int_m = _INTERNAL_RE.search(block)
        out[name] = {
            "required_permissions": perms,
            "description": desc,
            "category": cat_m.group(1) if cat_m else None,
            "risk_level": risk_m.group(1) if risk_m else "safe",
            "is_readonly": ro_m.group(1) == "True" if ro_m else True,
            "requires_approval": ap_m.group(1) == "True" if ap_m else False,
            "business_context_required": biz_m.group(1) != "False" if biz_m else True,
            "is_agent_internal": int_m.group(1) == "True" if int_m else False,
        }
    return out


def _top_level_description(block: str) -> str:
    """description سطح AIFunction، نه فیلدهای داخل parameters_schema."""
    schema_at = block.find("parameters_schema")
    head = block[: schema_at if schema_at >= 0 else len(block)]
    ident = _DESC_IDENT_RE.search(head)
    if ident:
        mapped = _payload_descriptions().get(ident.group(1))
        if mapped:
            return mapped
    m = re.search(r"\bdescription\s*=\s*", head)
    if not m:
        return ""
    section = head[m.end():]
    parts = re.findall(
        r'f?(?:"""([\s\S]*?)"""|\'([^\']+)\'|"([^"]+)")',
        section,
    )
    texts = []
    for a, b, c in parts:
        texts.append(" ".join((a or b or c).split()))
    return " ".join(t for t in texts if t).strip()


def metadata_quality_score(
    *,
    description: str,
    domains: Tuple[str, ...],
    capability: str,
    aliases: Tuple[str, ...],
    keywords: Tuple[str, ...],
    examples: Tuple[str, ...],
    permissions: Optional[List[str]],
    permission_policy: str,
    side_effect: str,
) -> int:
    score = 0
    desc = (description or "").strip()
    if len(desc) >= 40:
        score += 20
    elif len(desc) >= 16:
        score += 10
    if domains:
        score += 15
    if capability in TOOL_CAPABILITIES and "." in capability:
        score += 15
    if aliases:
        score += 10
    if keywords:
        score += 5
    if examples:
        score += 10
    if permissions:
        score += 15
    elif permission_policy in ALLOWED_EMPTY_PERMISSION_POLICIES:
        score += 15
    if side_effect:
        score += 10
    return min(100, score)


def audit_tool_row(name: str, parsed: Dict[str, Any]) -> Dict[str, Any]:
    entry = get_manifest_entry(name)
    perms = parsed.get("required_permissions")
    policy = permission_policy_for_name(
        name,
        required_permissions=perms,
        explicit=entry.permission_policy if entry else None,
    )
    desc = parsed.get("description") or ""
    domains = entry.domains if entry else ()
    capability = entry.capability if entry else ""
    aliases = entry.aliases if entry else ()
    keywords = entry.keywords if entry else ()
    examples = entry.examples if entry else ()
    side = entry.side_effect if entry else ""
    score = metadata_quality_score(
        description=desc,
        domains=domains,
        capability=capability,
        aliases=aliases,
        keywords=keywords,
        examples=examples,
        permissions=perms,
        permission_policy=policy,
        side_effect=side,
    )
    search = entry.search_text(name, desc) if entry else name
    perm_status = "assigned" if perms else (
        "explicit_empty" if policy in ALLOWED_EMPTY_PERMISSION_POLICIES else "missing"
    )
    return {
        "name": name,
        "manifest_exists": entry is not None,
        "description": desc,
        "domain": ",".join(domains),
        "capability": capability,
        "namespace": entry.namespace if entry else "",
        "aliases": aliases,
        "keywords": keywords,
        "examples": examples,
        "required_permissions": perms,
        "permission_status": perm_status,
        "permission_policy": policy,
        "side_effect": side,
        "intent_write": bool(entry.intent_write) if entry else False,
        "always_confirm": bool(entry.always_confirm) if entry else False,
        "risk_level": parsed.get("risk_level") or "safe",
        "is_readonly": parsed.get("is_readonly", True),
        "is_agent_internal": parsed.get("is_agent_internal", False),
        "tenant_policy": "session_business_id" if parsed.get("business_context_required", True) else "user_context",
        "enabled": bool(entry.enabled) if entry else True,
        "deprecated": bool(entry.deprecated) if entry else False,
        "version": entry.version if entry else "1",
        "search_text": search,
        "metadata_quality_score": score,
    }


def audit_catalog() -> List[Dict[str, Any]]:
    parsed = parse_registered_tool_fields()
    names = sorted(set(parsed) | set(iter_manifest_names()))
    return [audit_tool_row(name, parsed.get(name) or {}) for name in names]


def catalog_completeness(rows: Optional[List[Dict[str, Any]]] = None) -> Dict[str, int]:
    rows = rows if rows is not None else audit_catalog()
    return {
        "total": len(rows),
        "complete_metadata": sum(1 for row in rows if row["metadata_quality_score"] >= 70),
        "missing_permissions": sum(1 for row in rows if row["permission_status"] == "missing"),
        "missing_side_effect": sum(1 for row in rows if not row["side_effect"]),
        "missing_domain": sum(1 for row in rows if not row["domain"]),
        "missing_capability": sum(
            1 for row in rows if not row["capability"] or row["capability"] not in TOOL_CAPABILITIES
        ),
        "missing_description": sum(1 for row in rows if len(row["description"] or "") < 16),
        "missing_aliases": sum(1 for row in rows if not row["aliases"]),
        "missing_examples": sum(1 for row in rows if not row["examples"]),
        "missing_search_text": sum(1 for row in rows if not (row["search_text"] or "").strip()),
    }


MUTATING_SIDE_EFFECTS = frozenset({
    ToolSideEffect.WRITE.value,
    ToolSideEffect.DELETE.value,
    ToolSideEffect.EXECUTE.value,
    ToolSideEffect.EXPORT.value,
})
