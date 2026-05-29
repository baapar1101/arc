from __future__ import annotations

import json
import zipfile
from dataclasses import dataclass, field
from io import BytesIO
from typing import Any, Dict, List, Optional

from app.core.responses import ApiError
from app.services.legacy_import.constants import ARCHIVE_DATA_PREFIX, ARCHIVE_MANIFEST, ARCHIVE_TABLES
from app.services.legacy_import.mappers import extract_archive_counts


@dataclass
class LegacyArchive:
    """Parsed legacy backup/archive ZIP (v1 dataFormatVersion)."""

    raw_bytes: bytes
    manifest: Dict[str, Any]
    data: Dict[str, List[Dict[str, Any]]] = field(default_factory=dict)
    files: Dict[str, bytes] = field(default_factory=dict)

    @property
    def source_business_id(self) -> Optional[int]:
        for key in ("sourceBusinessId", "source_business_id", "businessId"):
            val = self.manifest.get(key)
            if val is not None:
                try:
                    return int(val)
                except (TypeError, ValueError):
                    pass
        rows = self.data.get("business.json") or []
        if rows and rows[0].get("id") is not None:
            return int(rows[0]["id"])
        return None

    @property
    def source_business_name(self) -> str:
        for key in ("sourceBusinessName", "source_business_name"):
            if self.manifest.get(key):
                return str(self.manifest[key])
        rows = self.data.get("business.json") or []
        if rows and rows[0].get("name"):
            return str(rows[0]["name"])
        return "کسب‌وکار"

    def counts(self) -> Dict[str, int]:
        return extract_archive_counts(self.data)

    def rows_by_doc_id(self) -> Dict[int, List[Dict[str, Any]]]:
        grouped: Dict[int, List[Dict[str, Any]]] = {}
        for row in self.data.get("hesabdari_rows.json") or []:
            doc_id = row.get("doc_id")
            if doc_id is None:
                continue
            grouped.setdefault(int(doc_id), []).append(row)
        return grouped


def parse_legacy_archive(zip_bytes: bytes) -> LegacyArchive:
    if not zip_bytes:
        raise ApiError("LEGACY_ARCHIVE_EMPTY", "آرشیو خالی است", http_status=400)
    try:
        zf = zipfile.ZipFile(BytesIO(zip_bytes), mode="r")
    except zipfile.BadZipFile as exc:
        raise ApiError(
            "LEGACY_ARCHIVE_INVALID",
            "فایل آرشیو نسخه قدیم معتبر نیست",
            http_status=400,
        ) from exc

    try:
        manifest = json.loads(zf.read(ARCHIVE_MANIFEST).decode("utf-8"))
    except KeyError as exc:
        raise ApiError(
            "LEGACY_ARCHIVE_INVALID",
            "manifest.json در آرشیو یافت نشد",
            http_status=400,
        ) from exc
    except json.JSONDecodeError as exc:
        raise ApiError(
            "LEGACY_ARCHIVE_INVALID",
            "manifest.json نامعتبر است",
            http_status=400,
        ) from exc

    data: Dict[str, List[Dict[str, Any]]] = {}
    for table in ARCHIVE_TABLES:
        path = f"{ARCHIVE_DATA_PREFIX}{table}"
        try:
            raw = zf.read(path).decode("utf-8")
        except KeyError:
            data[table] = []
            continue
        if not raw.strip():
            data[table] = []
            continue
        parsed = json.loads(raw)
        if isinstance(parsed, list):
            data[table] = parsed
        else:
            data[table] = []

    files: Dict[str, bytes] = {}
    for name in zf.namelist():
        if name.startswith("files/") and not name.endswith("/"):
            files[name] = zf.read(name)

    zf.close()
    return LegacyArchive(raw_bytes=zip_bytes, manifest=manifest, data=data, files=files)
