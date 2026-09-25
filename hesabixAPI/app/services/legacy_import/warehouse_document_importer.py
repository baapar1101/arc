from __future__ import annotations

import logging
from collections import defaultdict
from decimal import Decimal
from typing import Any, Dict, List, TYPE_CHECKING

from app.core.responses import ApiError
from app.services.legacy_import.constants import LEGACY_DOC_TYPE_TO_INVOICE
from app.services.legacy_import.mappers import parse_legacy_date, safe_decimal
from app.services.legacy_sql.mappers import convert_warehouse_doc_type
from app.services.warehouse_service import create_manual_warehouse_document, post_warehouse_document

if TYPE_CHECKING:
    from app.services.legacy_import.archive import LegacyArchive
    from app.services.legacy_import.id_map import LegacyIdMap, LegacyImportStats

logger = logging.getLogger(__name__)

INVOICE_OLD_TYPES = frozenset(LEGACY_DOC_TYPE_TO_INVOICE.keys())


class LegacyApiWarehouseDocumentImporter:
    """انتقال storeroom_ticket/item از آرشیو API به حواله انبار."""

    def __init__(
        self,
        db,
        business_id: int,
        user_id: int,
        id_map: "LegacyIdMap",
        stats: "LegacyImportStats",
    ) -> None:
        self.db = db
        self.business_id = business_id
        self.user_id = user_id
        self.id_map = id_map
        self.stats = stats

    def import_all(self, archive: "LegacyArchive") -> None:
        items_by_ticket = self._items_by_ticket(archive)
        old_doc_types = {
            int(d["id"]): str(d.get("type") or "")
            for d in archive.data.get("hesabdari_docs.json") or []
            if d.get("id") is not None
        }
        tickets = list(archive.data.get("storeroom_tickets.json") or [])
        tickets.sort(key=lambda t: (str(t.get("date") or ""), int(t.get("id") or 0)))

        for ticket in tickets:
            try:
                self._import_ticket(ticket, items_by_ticket, old_doc_types)
            except ApiError as exc:
                self.stats.warehouse_tickets_skipped += 1
                msg = exc.detail.get("error", {}).get("message") if isinstance(exc.detail, dict) else str(exc)
                self.stats.add_warning(f"حواله #{ticket.get('code')}: {msg}")
            except Exception as exc:
                self.stats.warehouse_tickets_skipped += 1
                logger.exception("legacy_wh_ticket_failed ticket_id=%s", ticket.get("id"))
                self.stats.add_warning(f"حواله #{ticket.get('code')}: {exc}")

    def _items_by_ticket(self, archive: "LegacyArchive") -> Dict[int, List[Dict[str, Any]]]:
        index: Dict[int, List[Dict[str, Any]]] = defaultdict(list)
        for row in archive.data.get("storeroom_items.json") or []:
            tid = row.get("ticket_id")
            if tid is None:
                continue
            try:
                index[int(tid)].append(row)
            except (TypeError, ValueError):
                continue
        return dict(index)

    def _import_ticket(
        self,
        ticket: Dict[str, Any],
        items_by_ticket: Dict[int, List[Dict[str, Any]]],
        old_doc_types: Dict[int, str],
    ) -> None:
        try:
            old_ticket_id = int(ticket["id"])
        except (TypeError, ValueError):
            self.stats.warehouse_tickets_skipped += 1
            return

        old_wh_id = ticket.get("storeroom_id")
        new_wh_id = self.id_map.get("warehouses", old_wh_id)
        if not new_wh_id:
            self.stats.warehouse_tickets_skipped += 1
            return

        doc_type = convert_warehouse_doc_type(
            str(ticket.get("type") or ""),
            ticket.get("typeString") or ticket.get("type_string"),
        )
        if doc_type == "transfer":
            doc_type = "adjustment"

        lines: List[Dict[str, Any]] = []
        for item in items_by_ticket.get(old_ticket_id, []):
            product_id = self.id_map.get("products", item.get("commodity_id"))
            if not product_id:
                self.stats.warehouse_lines_skipped += 1
                continue
            qty = safe_decimal(item.get("count"))
            if qty <= 0:
                self.stats.warehouse_lines_skipped += 1
                continue
            line: Dict[str, Any] = {
                "product_id": int(product_id),
                "quantity": float(qty),
                "description": item.get("des"),
            }
            if doc_type in ("issue", "production_out"):
                line["warehouse_id"] = int(new_wh_id)
            else:
                line["warehouse_id"] = int(new_wh_id)
            lines.append(line)

        if not lines:
            self.stats.warehouse_tickets_skipped += 1
            return

        warehouse_id_from = None
        warehouse_id_to = None
        if doc_type in ("issue", "production_out"):
            warehouse_id_from = int(new_wh_id)
        elif doc_type in ("receipt", "production_in"):
            warehouse_id_to = int(new_wh_id)
        else:
            warehouse_id_to = int(new_wh_id)

        source_type = "manual"
        source_document_id = None
        old_doc_id = ticket.get("doc_id")
        if old_doc_id is not None:
            try:
                old_did = int(old_doc_id)
                new_src = self.id_map.get("documents", old_did)
                if new_src and old_doc_types.get(old_did, "") in INVOICE_OLD_TYPES:
                    source_type = "invoice"
                    source_document_id = int(new_src)
            except (TypeError, ValueError):
                pass

        payload = {
            "doc_type": doc_type,
            "document_date": parse_legacy_date(ticket.get("date")).isoformat(),
            "warehouse_id_from": warehouse_id_from,
            "warehouse_id_to": warehouse_id_to,
            "lines": lines,
            "description": ticket.get("des") or ticket.get("typeString"),
            "extra_info": {
                "source": "legacy_api",
                "legacy_import": True,
                "old_ticket_id": old_ticket_id,
                "old_code": ticket.get("code"),
            },
        }

        wh = create_manual_warehouse_document(
            self.db,
            self.business_id,
            self.user_id,
            payload,
        )
        if source_document_id is not None:
            wh.source_type = source_type
            wh.source_document_id = source_document_id
            self.db.flush()

        try:
            post_warehouse_document(
                self.db,
                wh.id,
                stock_exclude_warehouse_document_ids=[wh.id],
            )
        except Exception as exc:
            logger.warning(
                "legacy_wh_post_failed ticket_id=%s wh_id=%s: %s",
                old_ticket_id,
                wh.id,
                exc,
            )
            self.stats.add_warning(
                f"حواله #{ticket.get('code')}: ثبت نهایی انبار ناموفق — {exc}"
            )

        self.id_map.set("warehouse_tickets", old_ticket_id, int(wh.id))
        self.stats.warehouse_tickets_imported += 1
