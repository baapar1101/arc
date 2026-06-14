"""
Parse و validate فایل SKILL.md مطابق agentskills.io (بدون وابستگی PyYAML).
"""
from __future__ import annotations

import base64
import io
import re
import zipfile
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

MAX_SKILL_SLUG_LEN = 64
MAX_DESCRIPTION_LEN = 1024
MAX_SKILL_BODY_CHARS = 80_000
MAX_BUNDLE_FILE_CHARS = 50_000
MAX_BUNDLE_FILES = 80
MAX_ZIP_BYTES = 10 * 1024 * 1024

_SKILL_SLUG_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$")
_MANIFEST_NAMES = frozenset({"skill.md", "SKILL.md"})


@dataclass
class ParsedSkill:
    skill_slug: str
    description: str
    skill_body: str
    frontmatter: Dict[str, str] = field(default_factory=dict)
    allowed_tool_names: List[str] = field(default_factory=list)
    bundle_files: Dict[str, Dict[str, str]] = field(default_factory=dict)
    has_scripts: bool = False
    has_references: bool = False
    has_assets: bool = False


@dataclass
class CompatibilityReport:
    runtime_mode: str = "portable"
    instruction_only: bool = True
    has_scripts: bool = False
    has_references: bool = False
    has_assets: bool = False
    scripts_warning: Optional[str] = None
    anthropic_prebuilt: bool = False
    score: int = 100
    warnings: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "runtime_mode": self.runtime_mode,
            "instruction_only": self.instruction_only,
            "has_scripts": self.has_scripts,
            "has_references": self.has_references,
            "has_assets": self.has_assets,
            "scripts_warning": self.scripts_warning,
            "anthropic_prebuilt": self.anthropic_prebuilt,
            "score": self.score,
            "warnings": self.warnings,
        }


def _parse_frontmatter_block(raw: str) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for line in raw.splitlines():
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        key = key.strip()
        val = val.strip()
        if val.startswith('"') and val.endswith('"'):
            val = val[1:-1]
        elif val.startswith("'") and val.endswith("'"):
            val = val[1:-1]
        if key:
            out[key] = val
    return out


def split_skill_md(content: str) -> Tuple[Dict[str, str], str]:
    text = (content or "").lstrip("\ufeff")
    if not text.startswith("---"):
        return {}, text
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}, text
    fm = _parse_frontmatter_block(parts[1])
    body = parts[2].lstrip("\n")
    return fm, body


def validate_skill_slug(slug: str) -> Optional[str]:
    s = (slug or "").strip().lower()
    if not s or len(s) > MAX_SKILL_SLUG_LEN:
        return "SKILL_SLUG_LENGTH_INVALID"
    if "--" in s or s.startswith("-") or s.endswith("-"):
        return "SKILL_SLUG_FORMAT_INVALID"
    if not _SKILL_SLUG_RE.match(s):
        return "SKILL_SLUG_FORMAT_INVALID"
    if s in ("anthropic", "claude"):
        return "SKILL_SLUG_RESERVED"
    return None


def validate_description(desc: str) -> Optional[str]:
    d = (desc or "").strip()
    if not d:
        return "SKILL_DESCRIPTION_REQUIRED"
    if len(d) > MAX_DESCRIPTION_LEN:
        return "SKILL_DESCRIPTION_TOO_LONG"
    return None


def parse_allowed_tools(frontmatter: Dict[str, str]) -> List[str]:
    raw = frontmatter.get("allowed-tools") or frontmatter.get("allowed_tools") or ""
    if not raw.strip():
        return []
    # agentskills.io: space-separated; Hesabix native may use comma
    parts = re.split(r"[\s,]+", raw.strip())
    out: List[str] = []
    for p in parts:
        p = p.strip()
        if not p:
            continue
        # Claude Code tools like Bash(git:*) — نگه‌داری برای گزارش؛ map در فاز ۲
        if "(" in p:
            continue
        if p not in out:
            out.append(p)
    return out[:48]


def parse_skill_md(content: str) -> ParsedSkill:
    fm, body = split_skill_md(content)
    slug = (fm.get("name") or "").strip().lower()
    desc = (fm.get("description") or "").strip()
    err_slug = validate_skill_slug(slug)
    if err_slug:
        raise ValueError(err_slug)
    err_desc = validate_description(desc)
    if err_desc:
        raise ValueError(err_desc)
    body = body[:MAX_SKILL_BODY_CHARS]
    return ParsedSkill(
        skill_slug=slug,
        description=desc,
        skill_body=body,
        frontmatter=fm,
        allowed_tool_names=parse_allowed_tools(fm),
    )


def parse_compat_yaml(content: str) -> Dict[str, Any]:
    """Parse ساده hesabix.compat.yaml (زیرمجموعه YAML)."""
    out: Dict[str, Any] = {}
    if not content:
        return out
    current_list_key: Optional[str] = None
    for line in content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("- ") and current_list_key:
            out.setdefault(current_list_key, []).append(stripped[2:].strip())
            continue
        if ":" in stripped:
            key, _, val = stripped.partition(":")
            key = key.strip()
            val = val.strip()
            if not val:
                current_list_key = key
                out.setdefault(key, [])
                continue
            current_list_key = None
            if val.startswith('"') and val.endswith('"'):
                val = val[1:-1]
            out[key] = val
    return out


def build_compatibility_report(parsed: ParsedSkill) -> CompatibilityReport:
    report = CompatibilityReport(
        has_scripts=parsed.has_scripts,
        has_references=parsed.has_references,
        has_assets=parsed.has_assets,
        instruction_only=not parsed.has_scripts,
    )
    if parsed.has_scripts:
        report.scripts_warning = (
            "این مهارت شامل scripts/ است. در حالت Portable اجرا نمی‌شوند؛ "
            "برای اجرای کامل از مدل Claude و Native Anthropic Runtime استفاده کنید."
        )
        report.score = max(40, report.score - 25)
        report.warnings.append("has_scripts")
    if parsed.has_references or parsed.has_assets:
        report.warnings.append("has_bundled_resources")
        report.score = max(50, report.score - 5)
    return report


def merge_compat_into_report(parsed: ParsedSkill, compat: Dict[str, Any]) -> CompatibilityReport:
    report = build_compatibility_report(parsed)
    mode = str(compat.get("runtime_mode") or "").strip().lower()
    if mode in ("portable", "anthropic_native", "hybrid"):
        report.runtime_mode = mode
    if mode == "anthropic_native":
        report.anthropic_prebuilt = True
        report.score = min(report.score, 90)
    warnings = compat.get("warnings")
    if isinstance(warnings, list):
        report.warnings.extend(str(w) for w in warnings[:10])
    elif isinstance(warnings, str) and warnings:
        report.warnings.append(warnings)
    tool_mappings = compat.get("tool_mappings")
    if isinstance(tool_mappings, list):
        for item in tool_mappings:
            if isinstance(item, dict):
                hesabix = item.get("hesabix")
                if isinstance(hesabix, list):
                    for t in hesabix:
                        if t and t not in parsed.allowed_tool_names:
                            parsed.allowed_tool_names.append(str(t))
    return report


def _normalize_zip_path(name: str) -> str:
    return name.replace("\\", "/").lstrip("./")


def extract_skill_from_zip(data: bytes) -> ParsedSkill:
    if len(data) > MAX_ZIP_BYTES:
        raise ValueError("SKILL_ZIP_TOO_LARGE")
    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        raise ValueError("SKILL_ZIP_INVALID")

    manifest_path: Optional[str] = None
    prefix = ""
    for name in zf.namelist():
        norm = _normalize_zip_path(name)
        if norm.endswith("/"):
            continue
        base = norm.rsplit("/", 1)[-1]
        if base in _MANIFEST_NAMES or base.lower() == "skill.md":
            manifest_path = norm
            if "/" in norm:
                prefix = norm.rsplit("/", 1)[0] + "/"
            break

    if not manifest_path:
        raise ValueError("SKILL_MD_NOT_FOUND")

    try:
        skill_md_bytes = zf.read(manifest_path)
    except KeyError:
        raise ValueError("SKILL_MD_NOT_FOUND")

    skill_md = skill_md_bytes.decode("utf-8-sig", errors="replace")
    parsed = parse_skill_md(skill_md)

    bundle: Dict[str, Dict[str, str]] = {}
    count = 0
    for name in zf.namelist():
        norm = _normalize_zip_path(name)
        if norm.endswith("/") or norm == manifest_path:
            continue
        if prefix and not norm.startswith(prefix):
            continue
        rel = norm[len(prefix) :] if prefix and norm.startswith(prefix) else norm
        if not rel or rel.lower() == "skill.md":
            continue
        if count >= MAX_BUNDLE_FILES:
            break
        try:
            raw = zf.read(name)
        except KeyError:
            continue
        if rel.startswith("scripts/"):
            parsed.has_scripts = True
        elif rel.startswith("references/"):
            parsed.has_references = True
        elif rel.startswith("assets/"):
            parsed.has_assets = True
        if rel.lower() == "hesabix.compat.yaml":
            try:
                compat_text = raw.decode("utf-8")
                compat = parse_compat_yaml(compat_text)
                bundle[rel] = {"encoding": "utf-8", "content": compat_text}
            except UnicodeDecodeError:
                pass
            count += 1
            continue
        # متن یا base64 برای باینری
        try:
            text = raw.decode("utf-8")
            if len(text) > MAX_BUNDLE_FILE_CHARS:
                text = text[:MAX_BUNDLE_FILE_CHARS] + "\n… [کوتاه شد]"
            bundle[rel] = {"encoding": "utf-8", "content": text}
        except UnicodeDecodeError:
            if len(raw) > 256 * 1024:
                continue
            bundle[rel] = {
                "encoding": "base64",
                "content": base64.b64encode(raw).decode("ascii"),
            }
        count += 1

    parsed.bundle_files = bundle
    compat_raw = (bundle.get("hesabix.compat.yaml") or {}).get("content")
    if compat_raw:
        compat = parse_compat_yaml(str(compat_raw))
        merge_compat_into_report(parsed, compat)
    return parsed


def compose_skill_md(
    *,
    skill_slug: str,
    description: str,
    skill_body: str,
    allowed_tool_names: Optional[List[str]] = None,
) -> str:
    lines = [
        "---",
        f"name: {skill_slug}",
        f"description: {description}",
    ]
    if allowed_tool_names:
        lines.append(f"allowed-tools: {' '.join(allowed_tool_names)}")
    lines.extend(["---", "", skill_body.strip(), ""])
    return "\n".join(lines)
