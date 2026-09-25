from __future__ import annotations

from typing import Any, Dict, List, TYPE_CHECKING

if TYPE_CHECKING:
    from app.services.legacy_import.archive import LegacyArchive
    from app.services.legacy_import.client import LegacyApiClient


def enrich_hesabdari_tables(
    archive: "LegacyArchive",
    *,
    legacy_client: "LegacyApiClient | None" = None,
) -> List[Dict[str, Any]]:
    """
    ادغام hesabdari_tables.json با refهای سطرهای آرشیو و در صورت امکان API.
    """
    tables: Dict[int, Dict[str, Any]] = {}
    for row in archive.data.get("hesabdari_tables.json") or []:
        rid = row.get("id")
        if rid is not None:
            tables[int(rid)] = dict(row)

    for row in archive.data.get("hesabdari_rows.json") or []:
        rid = row.get("ref_id")
        if rid is None:
            continue
        try:
            int_rid = int(rid)
        except (TypeError, ValueError):
            continue
        if int_rid not in tables:
            tables[int_rid] = {"id": int_rid, "type": "calc"}

    if legacy_client:
        _merge_refs_from_api_sample(archive, legacy_client, tables)

    return list(tables.values())


def _merge_refs_from_api_sample(
    archive: "LegacyArchive",
    client: "LegacyApiClient",
    tables: Dict[int, Dict[str, Any]],
) -> None:
    """یک نمونه سند cost/income را از API می‌خواند تا نام/نوع ref تکمیل شود."""
    sample_doc_id: int | None = None
    for doc in archive.data.get("hesabdari_docs.json") or []:
        if str(doc.get("type") or "") in ("cost", "income", "open_balance"):
            try:
                sample_doc_id = int(doc["id"])
                break
            except (TypeError, ValueError):
                continue
    if sample_doc_id is None:
        return
    try:
        detail = client.get_document_detail(sample_doc_id)
    except Exception:
        return
    for row in detail.get("rows") or []:
        ref = row.get("ref")
        if not isinstance(ref, dict):
            continue
        rid = ref.get("id")
        if rid is None:
            continue
        try:
            int_rid = int(rid)
        except (TypeError, ValueError):
            continue
        existing = tables.get(int_rid, {"id": int_rid})
        if ref.get("name"):
            existing["name"] = str(ref["name"]).strip()
        if ref.get("tableType"):
            existing["type"] = str(ref["tableType"]).strip()
        tables[int_rid] = existing
