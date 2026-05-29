from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from app.services.legacy_import.archive import parse_legacy_archive
from app.services.legacy_import.client import LegacyApiClient
from app.services.legacy_import.mappers import mask_api_key, normalize_server_url
from app.services.legacy_import.preview_risks import compute_import_risks


@dataclass
class LegacyImportOptions:
    """User-selected import scope."""

    business_name_override: Optional[str] = None
    business_name_suffix: str = ""
    import_persons: bool = True
    import_products: bool = True
    import_banks: bool = True
    import_warehouses: bool = True
    import_documents: bool = True
    import_files: bool = True


def preview_legacy_import(
    server_url: str,
    api_key: str,
    *,
    download_archive: bool = True,
) -> Dict[str, Any]:
    client = LegacyApiClient(server_url, api_key)
    connection = client.test_connection()
    archive_size = 0
    counts: Dict[str, int] = {}
    manifest: Dict[str, Any] = {}
    import_risks: list[Dict[str, Any]] = []

    if download_archive:
        raw = client.download_archive()
        archive_size = len(raw)
        archive = parse_legacy_archive(raw)
        counts = archive.counts()
        manifest = archive.manifest
        import_risks = compute_import_risks(archive)

    biz = connection.get("business") or {}
    return {
        "server_url": normalize_server_url(server_url),
        "api_key_masked": mask_api_key(api_key),
        "legacy_business_id": connection.get("legacy_business_id"),
        "business_name": biz.get("name") or biz.get("legal_name"),
        "businesses_accessible": connection.get("businesses_count", 1),
        "archive_size_bytes": archive_size,
        "manifest": manifest,
        "counts": counts,
        "import_risks": import_risks,
        "warnings": [
            "کلید API فقط به یک کسب‌وکار در نسخه قدیم متصل است.",
            "داده‌های کیف پول، اشتراک AI و مارکت‌پلیس منتقل نمی‌شوند.",
        ],
    }
