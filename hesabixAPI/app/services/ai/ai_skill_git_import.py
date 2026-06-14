"""
Import مهارت از مخزن GitHub (ZIP archive — بدون git clone).
"""
from __future__ import annotations

import io
import logging
import re
import zipfile
from dataclasses import dataclass
from typing import Optional, Tuple
from urllib.parse import urlparse

import httpx

from app.services.ai.ai_skill_parser import extract_skill_from_zip

logger = logging.getLogger(__name__)

MAX_GIT_ZIP_BYTES = 12 * 1024 * 1024
DOWNLOAD_TIMEOUT = 45.0

_GITHUB_HOSTS = frozenset({"github.com", "www.github.com"})
_TREE_RE = re.compile(
    r"^https?://(?:www\.)?github\.com/([^/]+)/([^/]+)/tree/([^/]+)(?:/(.*))?$",
    re.I,
)
_BLOB_RE = re.compile(
    r"^https?://(?:www\.)?github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$",
    re.I,
)
_REPO_RE = re.compile(
    r"^https?://(?:www\.)?github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$",
    re.I,
)


@dataclass
class GitHubSkillRef:
    owner: str
    repo: str
    branch: str
    subpath: str
    source_url: str


def parse_github_skill_url(url: str) -> GitHubSkillRef:
    raw = (url or "").strip()
    if not raw:
        raise ValueError("GIT_URL_REQUIRED")

    m = _TREE_RE.match(raw)
    if m:
        owner, repo, branch, sub = m.groups()
        return GitHubSkillRef(
            owner=owner,
            repo=repo.removesuffix(".git"),
            branch=branch,
            subpath=(sub or "").strip("/"),
            source_url=raw,
        )

    m = _BLOB_RE.match(raw)
    if m:
        owner, repo, branch, path = m.groups()
        sub = path.rsplit("/", 1)[0] if "/" in path else ""
        return GitHubSkillRef(
            owner=owner,
            repo=repo.removesuffix(".git"),
            branch=branch,
            subpath=sub.strip("/"),
            source_url=raw,
        )

    m = _REPO_RE.match(raw)
    if m:
        owner, repo = m.groups()
        return GitHubSkillRef(
            owner=owner,
            repo=repo.removesuffix(".git"),
            branch="main",
            subpath="",
            source_url=raw,
        )

    parsed = urlparse(raw)
    if parsed.hostname not in _GITHUB_HOSTS:
        raise ValueError("GIT_URL_UNSUPPORTED_HOST")
    raise ValueError("GIT_URL_INVALID")


def _github_zipball_url(ref: GitHubSkillRef) -> str:
    return f"https://codeload.github.com/{ref.owner}/{ref.repo}/zip/refs/heads/{ref.branch}"


def _find_skill_md_in_zip(data: bytes, subpath: str) -> bytes:
    """استخراج ZIP مهارت از آرشیو مخزن."""
    if len(data) > MAX_GIT_ZIP_BYTES:
        raise ValueError("GIT_ZIP_TOO_LARGE")
    try:
        outer = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        raise ValueError("GIT_ZIP_INVALID")

    # ریشهٔ استخراج‌شده: owner-repo-branch/
    root_prefix = ""
    for name in outer.namelist():
        if name.endswith("/") and name.count("/") == 1:
            root_prefix = name
            break

    skill_dir = subpath.strip("/")
    candidates: list[tuple[int, str]] = []
    for name in outer.namelist():
        norm = name.replace("\\", "/")
        if not norm.lower().endswith("skill.md"):
            continue
        rel = norm[len(root_prefix) :] if root_prefix and norm.startswith(root_prefix) else norm
        if skill_dir:
            if not rel.startswith(skill_dir + "/") and rel != skill_dir + "/SKILL.md":
                if f"/{skill_dir}/" not in "/" + rel:
                    continue
        candidates.append((len(rel), name))

    if not candidates:
        raise ValueError("SKILL_MD_NOT_FOUND")

    candidates.sort(key=lambda x: x[0])
    best_name = candidates[0][1]
    skill_md = outer.read(best_name)

    # ساخت ZIP کوچک برای extract_skill_from_zip
    folder = best_name.rsplit("/", 1)[0]
    slug = folder.rsplit("/", 1)[-1] if "/" in folder else folder.rstrip("/")
    if not slug or slug.lower() == "skill.md":
        slug = "imported-skill"

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(f"{slug}/SKILL.md", skill_md)
        prefix = folder + "/"
        for name in outer.namelist():
            if name == best_name:
                continue
            if name.startswith(prefix) and not name.endswith("/"):
                rel = name[len(prefix) :]
                if rel.startswith(("scripts/", "references/", "assets/")) or rel.lower() == "hesabix.compat.yaml":
                    try:
                        zf.writestr(f"{slug}/{rel}", outer.read(name))
                    except KeyError:
                        pass
    return buf.getvalue()


def fetch_skill_zip_from_github(url: str) -> Tuple[bytes, GitHubSkillRef]:
    ref = parse_github_skill_url(url)
    zip_url = _github_zipball_url(ref)
    try:
        with httpx.Client(timeout=DOWNLOAD_TIMEOUT, follow_redirects=True) as client:
            resp = client.get(zip_url)
            resp.raise_for_status()
            data = resp.content
    except httpx.HTTPError as exc:
        logger.warning("GitHub download failed: %s", exc)
        raise ValueError("GIT_DOWNLOAD_FAILED") from exc

    skill_zip = _find_skill_md_in_zip(data, ref.subpath)
    return skill_zip, ref


def import_skill_from_git_url(url: str) -> Tuple[bytes, GitHubSkillRef]:
    """دانلود و بسته‌بندی مهارت — خروجی ZIP استاندارد agentskills.io."""
    skill_zip, ref = fetch_skill_zip_from_github(url)
    # validate
    extract_skill_from_zip(skill_zip)
    return skill_zip, ref
