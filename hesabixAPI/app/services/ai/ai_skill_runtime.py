"""
Runtime مهارت‌ها — progressive disclosure و فیلتر ابزار (فاز ۱: Portable).
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import AbstractSet, Dict, List, Optional, Set

from sqlalchemy.orm import Session

from adapters.db.models.ai_skill import AISkillInstall
from app.services.ai.ai_skill_service import list_installed

MAX_METADATA_SKILLS = 32
MAX_ACTIVATED_SKILLS = 3
MAX_ACTIVATED_BODY_CHARS = 12_000


@dataclass
class SkillMetadata:
    install_id: int
    package_id: int
    skill_slug: str
    description: str
    allowed_tool_names: List[str]
    source_type: str
    anthropic_skill_id: Optional[str]


def _tokenize(text: str) -> List[str]:
    if not text:
        return []
    parts = re.findall(r"[\w\u0600-\u06FF]+", text.lower())
    return [p for p in parts if len(p) >= 2][:32]


def list_enabled_metadata(db: Session, business_id: int) -> List[SkillMetadata]:
    installs = list_installed(db, business_id, enabled_only=True)
    out: List[SkillMetadata] = []
    for inst in installs[:MAX_METADATA_SKILLS]:
        pkg = inst.package
        if not pkg:
            continue
        out.append(
            SkillMetadata(
                install_id=inst.id,
                package_id=pkg.id,
                skill_slug=pkg.skill_slug,
                description=pkg.description or "",
                allowed_tool_names=list(pkg.allowed_tool_names or []),
                source_type=pkg.source_type or "portable",
                anthropic_skill_id=pkg.anthropic_skill_id,
            )
        )
    return out


def select_skills_for_query(
    user_query: str,
    metadata: List[SkillMetadata],
    *,
    forced_slugs: Optional[List[str]] = None,
) -> List[SkillMetadata]:
    if not metadata:
        return []
    if forced_slugs:
        forced = {s.strip().lower() for s in forced_slugs if s}
        return [m for m in metadata if m.skill_slug in forced][:MAX_ACTIVATED_SKILLS]

    q_tokens = set(_tokenize(user_query))
    if not q_tokens:
        return []

    scored: List[tuple[int, SkillMetadata]] = []
    for m in metadata:
        desc_tokens = set(_tokenize(m.description))
        slug_tokens = set(_tokenize(m.skill_slug.replace("-", " ")))
        overlap = len(q_tokens & desc_tokens) + len(q_tokens & slug_tokens) * 2
        if overlap > 0:
            scored.append((overlap, m))

    scored.sort(key=lambda x: -x[0])
    return [m for _, m in scored[:MAX_ACTIVATED_SKILLS]]


def format_skills_metadata_for_prompt(metadata: List[SkillMetadata]) -> str:
    if not metadata:
        return ""
    lines = ["\n\n## مهارت‌های فعال (Agent Skills — metadata)", ""]
    for m in metadata:
        lines.append(f"- **{m.skill_slug}**: {m.description}")
    lines.append(
        "\nاگر سوال کاربر با description یکی از مهارت‌ها همخوان است، "
        "دستورالعمل همان مهارت را در بخش بعدی دنبال کن."
    )
    return "\n".join(lines)


def format_activated_skills_for_prompt(
    db: Session,
    activated: List[SkillMetadata],
) -> str:
    if not activated:
        return ""
    from adapters.db.models.ai_skill import AISkillPackage

    parts: List[str] = ["\n\n## مهارت‌های فعال‌شده (دستورالعمل)"]
    total = 0
    for m in activated:
        pkg = db.get(AISkillPackage, m.package_id)
        if not pkg or not pkg.skill_body:
            continue
        body = pkg.skill_body.strip()
        budget = MAX_ACTIVATED_BODY_CHARS - total
        if budget <= 0:
            break
        if len(body) > budget:
            body = body[:budget] + "\n… [مهارت کوتاه شد]"
        parts.append(f"\n### مهارت: {m.skill_slug}\n\n{body}")
        total += len(body)
    return "".join(parts)


def collect_allowed_tool_names(
    activated: List[SkillMetadata],
    all_registry_names: AbstractSet[str],
) -> Optional[Set[str]]:
    """اگر مهارت فعال‌شده allowed_tool دارد، intersection با registry."""
    if not activated:
        return None
    names: Set[str] = set()
    for m in activated:
        for t in m.allowed_tool_names:
            if t in all_registry_names:
                names.add(t)
    if not names:
        return None
    return names


def get_runtime_skill_context(
    db: Session,
    business_id: int,
    user_query: str,
    *,
    forced_skill_slugs: Optional[List[str]] = None,
) -> Dict[str, object]:
    metadata = list_enabled_metadata(db, business_id)
    activated = select_skills_for_query(
        user_query, metadata, forced_slugs=forced_skill_slugs
    )
    return {
        "metadata": metadata,
        "activated": activated,
        "metadata_prompt": format_skills_metadata_for_prompt(metadata),
        "activated_prompt": format_activated_skills_for_prompt(db, activated),
        "anthropic_skill_ids": [
            m.anthropic_skill_id
            for m in activated
            if m.anthropic_skill_id and m.source_type == "anthropic_prebuilt"
        ],
    }
