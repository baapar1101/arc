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
from app.services.legacy_import.invoice_settlement import (
    INVOICE_LINKED_RECEIPT_PAYMENT_TYPES,
    append_receipt_payment_to_invoice,
    apply_related_docs_to_link_map,
    resolve_linked_invoice_legacy_code,
)
from app.services.legacy_import.legacy_chart_resolver import LegacyChartResolver
from app.services.legacy_import.id_map import LegacyIdMap, LegacyImportStats
from app.services.legacy_import.mappers import parse_legacy_date, safe_decimal
from app.services.receipt_payment_service import create_receipt_payment
from app.services.transfer_service import create_transfer
from app.services.legacy_import.table_enrichment import enrich_hesabdari_tables

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
        self._rp_to_invoice_code: Dict[str, str] = {}

    def import_all(self, archive: "LegacyArchive") -> None:
        docs = archive.data.get("hesabdari_docs.json") or []
        rows_by_doc = archive.rows_by_doc_id()
        tables = enrich_hesabdari_tables(
            archive,
            legacy_client=self._legacy_client,
        )
        chart = LegacyChartResolver(
            self.db,
            self.business_id,
            tables,
        )
        # Stable order: older docs first by date string then id
        docs_sorted = sorted(
            docs,
            key=lambda d: (str(d.get("date") or ""), int(d.get("id") or 0)),
        )
        # Import invoices and other docs first so invoice_codes map is ready for receipt/payment linking.
        non_receipt_payment = [
            d for d in docs_sorted
            if str(d.get("type") or "").strip() not in LEGACY_DOC_TYPE_TO_RECEIPT_PAYMENT
        ]
        receipt_payment_docs = [
            d for d in docs_sorted
            if str(d.get("type") or "").strip() in LEGACY_DOC_TYPE_TO_RECEIPT_PAYMENT
        ]
        self._rp_to_invoice_code = self._build_related_docs_link_map(docs_sorted)
        for doc in non_receipt_payment:
            self._import_document(doc, rows_by_doc, chart)
        for doc in receipt_payment_docs:
            self._import_document(doc, rows_by_doc, chart)

    def _build_related_docs_link_map(self, docs: List[Dict[str, Any]]) -> Dict[str, str]:
        """Fetch relatedDocs from legacy API for each invoice (receipt/payment code → invoice code)."""
        if not self._legacy_client:
            return {}
        link_map: Dict[str, str] = {}
        invoice_docs = [
            d for d in docs
            if str(d.get("type") or "").strip() in LEGACY_DOC_TYPE_TO_INVOICE
        ]
        for doc in invoice_docs:
            code = doc.get("code")
            if code is None:
                continue
            try:
                detail = self._legacy_client.get_document_by_code(str(code))
                related = detail.get("relatedDocs") or []
                apply_related_docs_to_link_map(link_map, code, related)
            except ApiError as exc:
                logger.warning(
                    "legacy_related_docs_fetch_failed code=%s: %s",
                    code,
                    exc.detail.get("error", {}).get("message") if isinstance(exc.detail, dict) else exc,
                )
            except Exception as exc:
                logger.warning("legacy_related_docs_fetch_failed code=%s: %s", code, exc)
        logger.info(
            "legacy_related_docs_link_map built: %s receipt/payment links from %s invoices",
            len(link_map),
            len(invoice_docs),
        )
        return link_map

    def _import_document(
        self,
        doc: Dict[str, Any],
        rows_by_doc: Dict[int, List[Dict[str, Any]]],
        chart: LegacyChartResolver,
    ) -> None:
        doc_type = str(doc.get("type") or "").strip()
        doc_id = doc.get("id")
        if doc_type == "open_balance":
            return
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

    def _register_invoice_code(self, doc: Dict[str, Any], new_doc_id: int) -> None:
        code = doc.get("code")
        if code is None:
            return
        self.id_map.invoice_codes[str(code).strip()] = int(new_doc_id)

    def _import_invoice(self, doc: Dict[str, Any], rows: List[Dict[str, Any]]) -> None:
        invoice_type = LEGACY_DOC_TYPE_TO_INVOICE[str(doc["type"])]
        person_id = self._resolve_person_for_doc(doc, rows)
        if not person_id:
            raise ApiError("LEGACY_DOC_NO_PERSON", "شخص سند یافت نشد", http_status=400)

        lines = self._build_invoice_lines(rows)
        if not lines:
            raise ApiError("LEGACY_DOC_NO_LINES", "اقلام فاکتور یافت نشد", http_status=400)

        document_date = parse_legacy_date(doc.get("date"))
        extra_info: Dict[str, Any] = {
            "person_id": int(person_id),
            "post_inventory": False,
            "auto_post_warehouse": False,
            "legacy_import": True,
            "legacy_doc_id": doc.get("id"),
            "legacy_doc_code": doc.get("code"),
        }
        header_discount = self._extract_invoice_header_discount(rows)
        if header_discount > 0:
            extra_info["global_discount"] = {
                "type": "amount",
                "value": float(header_discount),
                "amount": float(header_discount),
            }
        payload: Dict[str, Any] = {
            "invoice_type": invoice_type,
            "document_date": document_date.isoformat(),
            "currency_id": self.currency_id,
            "description": doc.get("des") or None,
            "lines": lines,
            "extra_info": extra_info,
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
            self._register_invoice_code(doc, int(new_doc_id))
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

        legacy_type = str(doc.get("type") or "").strip()
        linked_invoice_id: Optional[int] = None
        linked_legacy_code: Optional[str] = None
        if legacy_type in INVOICE_LINKED_RECEIPT_PAYMENT_TYPES:
            linked_legacy_code = resolve_linked_invoice_legacy_code(
                receipt_payment_code=doc.get("code"),
                related_docs_link_map=self._rp_to_invoice_code,
                doc=doc,
                rows=rows,
            )
            if linked_legacy_code:
                linked_invoice_id = self.id_map.invoice_codes.get(linked_legacy_code)
                if linked_invoice_id:
                    for pl in person_lines:
                        pl.setdefault("extra_info", {})
                        pl["extra_info"]["invoice_id"] = int(linked_invoice_id)
                        pl["extra_info"]["invoice_code"] = linked_legacy_code
                        pl["extra_info"]["link_to_invoice"] = True
                else:
                    self.stats.add_warning(
                        f"سند {legacy_type} #{doc.get('code')}: فاکتور با کد {linked_legacy_code} یافت نشد"
                    )

        payload = {
            "document_type": document_type,
            "document_date": parse_legacy_date(doc.get("date")).isoformat(),
            "currency_id": self.currency_id,
            "description": doc.get("des"),
            "person_lines": person_lines,
            "account_lines": account_lines,
            "extra_info": {
                "legacy_import": True,
                "legacy_doc_id": doc.get("id"),
                "legacy_doc_code": doc.get("code"),
                "legacy_doc_type": legacy_type,
            },
        }
        if linked_invoice_id:
            payload["extra_info"]["linked_invoice_id"] = int(linked_invoice_id)
            if linked_legacy_code:
                payload["extra_info"]["linked_invoice_code"] = linked_legacy_code

        result = create_receipt_payment(
            self.db,
            self.business_id,
            self.user_id,
            payload,
            commit=False,
        )
        new_doc_id = (result.get("data") or {}).get("id") or result.get("id")
        if doc.get("id") and new_doc_id:
            self.id_map.set("documents", int(doc["id"]), int(new_doc_id))
            if linked_invoice_id:
                append_receipt_payment_to_invoice(
                    self.db,
                    int(linked_invoice_id),
                    int(new_doc_id),
                )
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

    def _extract_invoice_header_discount(self, rows: List[Dict[str, Any]]) -> Decimal:
        """تخفیف سطح فاکتور از سطرهای بدون کالا (مثل «تخفیف فاکتور»)."""
        total = Decimal(0)
        for r in rows:
            if r.get("commodity_id"):
                continue
            des = str(r.get("des") or "")
            if "تخفیف" not in des:
                continue
            amt = row_amount(r)
            if amt > 0:
                total += amt
        return total

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
            line_gross = row_amount(r)
            if line_gross <= 0:
                continue
            unit_price = line_gross / qty if qty else line_gross
            line_discount = safe_decimal(r.get("discount") or 0)
            tax_amount = safe_decimal(r.get("tax") or 0)
            line_total = (qty * unit_price) - line_discount + tax_amount
            if line_total <= 0:
                line_total = line_gross - line_discount + tax_amount
            desc = str(r.get("des") or "").strip() or None
            lines.append(
                {
                    "product_id": product_id,
                    "quantity": float(qty),
                    **({"description": desc} if desc else {}),
                    "extra_info": {
                        "legacy_import": True,
                        "unit_price": float(unit_price),
                        "line_discount": float(line_discount),
                        "tax_amount": float(tax_amount),
                        "line_total": float(line_total),
                    },
                }
            )
        return lines
