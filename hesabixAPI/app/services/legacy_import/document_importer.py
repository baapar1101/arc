from __future__ import annotations

import logging
from decimal import Decimal
from typing import Any, Dict, List, Optional, TYPE_CHECKING

from sqlalchemy.orm import Session

from app.core.responses import ApiError
from app.services.invoice_service import create_invoice
from app.services.expense_income_service import create_expense_income
from app.services.legacy_import.constants import (
    LEGACY_DOC_TYPE_SKIP_MESSAGES,
    LEGACY_DOC_TYPE_TO_EXPENSE_INCOME,
    LEGACY_DOC_TYPE_TO_INVOICE,
    LEGACY_DOC_TYPE_TO_RECEIPT_PAYMENT,
)
from app.services.legacy_import.document_rows import build_receipt_payment_lines, row_amount
from app.services.legacy_import.expense_income_rows import (
    build_expense_income_payload,
    normalize_api_document_rows,
)
from app.services.legacy_import.legacy_chart_resolver import LegacyChartResolver
from app.services.legacy_import.id_map import LegacyIdMap, LegacyImportStats
from app.services.legacy_import.mappers import parse_legacy_date, safe_decimal
from app.services.receipt_payment_service import create_receipt_payment
from app.services.transfer_service import create_transfer

if TYPE_CHECKING:
    from app.services.legacy_import.archive import LegacyArchive
    from app.services.legacy_import.client import LegacyApiClient

logger = logging.getLogger(__name__)


class LegacyDocumentImporter:
    """Import hesabdari documents using domain services (single DB transaction)."""

    def __init__(
        self,
        db: Session,
        business_id: int,
        user_id: int,
        currency_id: int,
        id_map: LegacyIdMap,
        stats: LegacyImportStats,
        *,
        legacy_client: "LegacyApiClient | None" = None,
    ) -> None:
        self.db = db
        self.business_id = business_id
        self.user_id = user_id
        self.currency_id = currency_id
        self.id_map = id_map
        self.stats = stats
        self._legacy_client = legacy_client

    def import_all(self, archive: "LegacyArchive") -> None:
        docs = archive.data.get("hesabdari_docs.json") or []
        rows_by_doc = archive.rows_by_doc_id()
        chart = LegacyChartResolver(
            self.db,
            self.business_id,
            archive.data.get("hesabdari_tables.json") or [],
        )
        # Stable order: older docs first by date string then id
        docs_sorted = sorted(
            docs,
            key=lambda d: (str(d.get("date") or ""), int(d.get("id") or 0)),
        )
        for doc in docs_sorted:
            doc_type = str(doc.get("type") or "").strip()
            doc_id = doc.get("id")
            try:
                if doc_type in LEGACY_DOC_TYPE_TO_INVOICE:
                    self._import_invoice(doc, rows_by_doc.get(int(doc_id), []))
                elif doc_type in LEGACY_DOC_TYPE_TO_RECEIPT_PAYMENT:
                    self._import_receipt_payment(doc, rows_by_doc.get(int(doc_id), []))
                elif doc_type == "transfer":
                    self._import_transfer(doc, rows_by_doc.get(int(doc_id), []))
                elif doc_type in LEGACY_DOC_TYPE_TO_EXPENSE_INCOME:
                    self._import_expense_income(
                        doc,
                        rows_by_doc.get(int(doc_id), []),
                        chart=chart,
                    )
                elif doc_type in LEGACY_DOC_TYPE_SKIP_MESSAGES:
                    self.stats.documents_skipped += 1
                    self.stats.add_warning(
                        f"سند {doc_type} #{doc.get('code')}: {LEGACY_DOC_TYPE_SKIP_MESSAGES[doc_type]}"
                    )
                else:
                    self.stats.documents_skipped += 1
                    self.stats.add_warning(
                        f"نوع سند '{doc_type}' (کد {doc.get('code')}) در انتقال API پشتیبانی نمی‌شود"
                    )
            except ApiError as exc:
                self.stats.documents_skipped += 1
                msg = exc.detail.get("error", {}).get("message") if isinstance(exc.detail, dict) else str(exc)
                self.stats.add_warning(
                    f"سند {doc_type} #{doc.get('code')}: {msg}"
                )
            except Exception as exc:
                self.stats.documents_skipped += 1
                logger.exception("legacy_doc_import_failed doc_id=%s", doc_id)
                self.stats.add_warning(
                    f"سند {doc_type} #{doc.get('code')}: {exc}"
                )

    def _import_invoice(self, doc: Dict[str, Any], rows: List[Dict[str, Any]]) -> None:
        invoice_type = LEGACY_DOC_TYPE_TO_INVOICE[str(doc["type"])]
        person_id = self._resolve_person_for_doc(doc, rows)
        if not person_id:
            raise ApiError("LEGACY_DOC_NO_PERSON", "شخص سند یافت نشد", http_status=400)

        lines = self._build_invoice_lines(rows)
        if not lines:
            raise ApiError("LEGACY_DOC_NO_LINES", "اقلام فاکتور یافت نشد", http_status=400)

        document_date = parse_legacy_date(doc.get("date"))
        payload: Dict[str, Any] = {
            "invoice_type": invoice_type,
            "document_date": document_date.isoformat(),
            "currency_id": self.currency_id,
            "person_id": person_id,
            "description": doc.get("des") or None,
            "lines": lines,
            "extra_info": {
                "post_inventory": False,
                "auto_post_warehouse": False,
                "legacy_import": True,
                "legacy_doc_id": doc.get("id"),
                "legacy_doc_code": doc.get("code"),
            },
        }
        result = create_invoice(
            self.db,
            self.business_id,
            self.user_id,
            payload,
            commit=False,
            skip_post_commit_hooks=True,
        )
        new_doc_id = (result.get("data") or {}).get("id") or result.get("id")
        if doc.get("id") is not None and new_doc_id:
            self.id_map.set("documents", int(doc["id"]), int(new_doc_id))
        self.stats.documents_imported += 1

    def _import_receipt_payment(self, doc: Dict[str, Any], rows: List[Dict[str, Any]]) -> None:
        document_type = LEGACY_DOC_TYPE_TO_RECEIPT_PAYMENT[str(doc["type"])]

        person_lines, account_lines = build_receipt_payment_lines(
            rows,
            id_map=self.id_map,
            doc_amount=doc.get("amount"),
        )

        if not person_lines:
            walk_in = self.id_map.walk_in_person_id
            if walk_in:
                amt = safe_decimal(doc.get("amount"))
                if amt <= 0:
                    for r in rows:
                        a = row_amount(r)
                        if a > 0:
                            amt = a
                            break
                if amt > 0:
                    person_lines = [
                        {
                            "person_id": int(walk_in),
                            "amount": float(amt),
                            "description": doc.get("des"),
                        }
                    ]

        if not person_lines:
            raise ApiError("LEGACY_DOC_NO_PERSON", "شخص سند یافت نشد", http_status=400)
        if not account_lines:
            raise ApiError("LEGACY_DOC_NO_BANK", "حساب بانکی/صندوق برای سند یافت نشد", http_status=400)

        payload = {
            "document_type": document_type,
            "document_date": parse_legacy_date(doc.get("date")).isoformat(),
            "currency_id": self.currency_id,
            "description": doc.get("des"),
            "person_lines": person_lines,
            "account_lines": account_lines,
            "extra_info": {"legacy_import": True, "legacy_doc_id": doc.get("id")},
        }
        create_receipt_payment(
            self.db,
            self.business_id,
            self.user_id,
            payload,
            commit=False,
        )
        if doc.get("id"):
            self.stats.documents_imported += 1

    def _import_transfer(self, doc: Dict[str, Any], rows: List[Dict[str, Any]]) -> None:
        bank_rows = [r for r in rows if r.get("bank_id")]
        if len(bank_rows) < 1:
            self.stats.documents_skipped += 1
            self.stats.add_warning(f"انتقال #{doc.get('code')}: حساب بانکی یافت نشد")
            return
        amount = safe_decimal(doc.get("amount"))
        if amount <= 0:
            amount = safe_decimal(bank_rows[0].get("bs") or bank_rows[0].get("bd"))
        src_bank = self.id_map.get("bank_accounts", bank_rows[0].get("bank_id"))
        dst_bank = None
        if len(bank_rows) >= 2:
            dst_bank = self.id_map.get("bank_accounts", bank_rows[1].get("bank_id"))
        if not src_bank or not dst_bank:
            # Need two banks; skip if only one side mapped
            self.stats.documents_skipped += 1
            self.stats.add_warning(
                f"انتقال #{doc.get('code')}: نیاز به دو حساب بانکی قابل نگاشت"
            )
            return
        payload = {
            "document_date": parse_legacy_date(doc.get("date")).isoformat(),
            "currency_id": self.currency_id,
            "amount": float(amount),
            "description": doc.get("des"),
            "source": {"type": "bank", "id": src_bank},
            "destination": {"type": "bank", "id": dst_bank},
            "extra_info": {"legacy_import": True},
        }
        create_transfer(
            self.db,
            self.business_id,
            self.user_id,
            payload,
            commit=False,
        )
        self.stats.documents_imported += 1

    def _import_expense_income(
        self,
        doc: Dict[str, Any],
        rows: List[Dict[str, Any]],
        *,
        chart: LegacyChartResolver,
    ) -> None:
        doc_type = str(doc.get("type") or "").strip()
        document_type = LEGACY_DOC_TYPE_TO_EXPENSE_INCOME[doc_type]

        item_lines, counterparty_lines = build_expense_income_payload(
            doc_type,
            rows,
            chart=chart,
            id_map=self.id_map,
            doc_amount=doc.get("amount"),
        )

        if (not item_lines or not counterparty_lines) and self._legacy_client and doc.get("id"):
            try:
                detail = self._legacy_client.get_document_detail(int(doc["id"]))
                api_rows = normalize_api_document_rows(detail.get("rows") or [])
                if api_rows:
                    item_lines, counterparty_lines = build_expense_income_payload(
                        doc_type,
                        api_rows,
                        chart=chart,
                        id_map=self.id_map,
                        doc_amount=doc.get("amount"),
                    )
            except ApiError:
                raise
            except Exception as exc:
                logger.warning(
                    "legacy_expense_income_api_rows_failed doc_id=%s: %s",
                    doc.get("id"),
                    exc,
                )

        if not item_lines:
            raise ApiError(
                "LEGACY_DOC_NO_EXPENSE_LINES",
                "سطر حساب هزینه/درآمد یافت نشد",
                http_status=400,
            )
        if not counterparty_lines:
            raise ApiError(
                "LEGACY_DOC_NO_COUNTERPARTY",
                "طرف‌حساب سند (بانک/شخص) یافت نشد",
                http_status=400,
            )

        payload: Dict[str, Any] = {
            "document_type": document_type,
            "document_date": parse_legacy_date(doc.get("date")).isoformat(),
            "currency_id": self.currency_id,
            "description": doc.get("des") or None,
            "item_lines": item_lines,
            "counterparty_lines": counterparty_lines,
            "extra_info": {
                "legacy_import": True,
                "legacy_doc_id": doc.get("id"),
                "legacy_doc_code": doc.get("code"),
                "legacy_doc_type": doc_type,
            },
        }
        result = create_expense_income(
            self.db,
            self.business_id,
            self.user_id,
            payload,
            commit=False,
            skip_post_commit_hooks=True,
        )
        new_doc_id = (result.get("data") or {}).get("id") or result.get("id")
        if doc.get("id") is not None and new_doc_id:
            self.id_map.set("documents", int(doc["id"]), int(new_doc_id))
        self.stats.documents_imported += 1

    def _resolve_person_from_rows(self, rows: List[Dict[str, Any]]) -> Optional[int]:
        for r in rows:
            pid = self.id_map.get("persons", r.get("person_id"))
            if pid:
                return int(pid)
        return None

    def _resolve_person_for_doc(
        self, doc: Dict[str, Any], rows: List[Dict[str, Any]]
    ) -> Optional[int]:
        header_pid = doc.get("person_id") or doc.get("personId")
        if header_pid is not None:
            mapped = self.id_map.get("persons", header_pid)
            if mapped:
                return int(mapped)
        found = self._resolve_person_from_rows(rows)
        if found:
            return found
        for r in rows:
            if r.get("person_id") is not None:
                mapped = self.id_map.get("persons", r.get("person_id"))
                if mapped:
                    return int(mapped)
        if self.id_map.walk_in_person_id:
            return int(self.id_map.walk_in_person_id)
        if self.id_map.persons:
            return int(next(iter(self.id_map.persons.values())))
        return None

    def _build_invoice_lines(self, rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        lines: List[Dict[str, Any]] = []
        for r in rows:
            cid = r.get("commodity_id")
            if not cid:
                continue
            product_id = self.id_map.get("products", cid)
            if not product_id:
                continue
            qty = safe_decimal(r.get("commdityCount") or r.get("commodity_count") or 1)
            if qty <= 0:
                qty = Decimal("1")
            line_total = safe_decimal(r.get("bs") or r.get("bd"))
            unit_price = line_total / qty if qty else line_total
            lines.append(
                {
                    "product_id": product_id,
                    "quantity": float(qty),
                    "unit_price": float(unit_price),
                    "discount": 0,
                    "tax_percent": 0,
                    "extra_info": {"legacy_import": True},
                }
            )
        return lines
