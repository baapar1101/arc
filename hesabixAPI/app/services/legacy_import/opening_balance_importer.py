from __future__ import annotations

import logging
from typing import Any, Dict, List, TYPE_CHECKING

from app.core.responses import ApiError
from app.services.expense_income_service import _get_fixed_account_by_code
from app.services.legacy_import.legacy_chart_resolver import LegacyChartResolver
from app.services.legacy_import.mappers import parse_legacy_date, safe_decimal
from app.services.opening_balance_service import upsert_opening_balance

if TYPE_CHECKING:
    from app.services.legacy_import.archive import LegacyArchive
    from app.services.legacy_import.id_map import LegacyIdMap, LegacyImportStats

logger = logging.getLogger(__name__)


class LegacyApiOpeningBalanceImporter:
    """انتقال open_balance از آرشیو API به سند تراز افتتاحیه."""

    def __init__(
        self,
        db,
        business_id: int,
        user_id: int,
        currency_id: int,
        id_map: "LegacyIdMap",
        stats: "LegacyImportStats",
        *,
        chart: LegacyChartResolver,
    ) -> None:
        self.db = db
        self.business_id = business_id
        self.user_id = user_id
        self.currency_id = currency_id
        self.id_map = id_map
        self.stats = stats
        self.chart = chart

    def import_all(self, archive: "LegacyArchive") -> None:
        rows_by_doc = archive.rows_by_doc_id()
        for doc in archive.data.get("hesabdari_docs.json") or []:
            if str(doc.get("type") or "").strip() != "open_balance":
                continue
            doc_id = doc.get("id")
            rows = rows_by_doc.get(int(doc_id), []) if doc_id is not None else []
            try:
                self._import_one(doc, rows)
            except ApiError as exc:
                self.stats.documents_skipped += 1
                msg = exc.detail.get("error", {}).get("message") if isinstance(exc.detail, dict) else str(exc)
                self.stats.add_warning(f"سند open_balance #{doc.get('code')}: {msg}")
            except Exception as exc:
                self.stats.documents_skipped += 1
                logger.exception("legacy_open_balance_failed doc_id=%s", doc_id)
                self.stats.add_warning(f"سند open_balance #{doc.get('code')}: {exc}")

    def _import_one(self, doc: Dict[str, Any], rows: List[Dict[str, Any]]) -> None:
        old_year_id = doc.get("year_id")
        fiscal_year_id = self.id_map.get("fiscal_years", old_year_id)
        if not fiscal_year_id:
            raise ApiError("LEGACY_NO_FISCAL_YEAR", "سال مالی برای تراز افتتاحیه یافت نشد", http_status=400)

        equity_account = _get_fixed_account_by_code(self.db, "30101")
        account_lines: List[Dict[str, Any]] = []

        for row in rows:
            # در دیتابیس قدیم: bs→debit و bd→credit (همان قرارداد SQL importer)
            debit = safe_decimal(row.get("bs"))
            credit = safe_decimal(row.get("bd"))
            if debit <= 0 and credit <= 0:
                continue

            ref_data = str(row.get("refData") or row.get("ref_data") or "").lower()
            if ref_data == "shareholder" or "shareholder" in ref_data:
                account_lines.append(
                    {
                        "account_id": int(equity_account.id),
                        "debit": float(debit),
                        "credit": float(credit),
                        "description": row.get("des"),
                    }
                )
                continue

            if row.get("bank_id") is not None:
                new_bank = self.id_map.get("bank_accounts", row.get("bank_id"))
                if new_bank:
                    account_lines.append(
                        {
                            "bank_account_id": int(new_bank),
                            "debit": float(debit),
                            "credit": float(credit),
                            "description": row.get("des"),
                        }
                    )
                    continue

            if row.get("cashdesk_id") is not None:
                new_cr = self.id_map.get("cash_registers", row.get("cashdesk_id"))
                if new_cr:
                    account_lines.append(
                        {
                            "cash_register_id": int(new_cr),
                            "debit": float(debit),
                            "credit": float(credit),
                            "description": row.get("des"),
                        }
                    )
                    continue

            if row.get("salary_id") is not None:
                new_pc = self.id_map.get("petty_cash", row.get("salary_id"))
                if new_pc:
                    account_lines.append(
                        {
                            "petty_cash_id": int(new_pc),
                            "debit": float(debit),
                            "credit": float(credit),
                            "description": row.get("des"),
                        }
                    )
                    continue

            if row.get("person_id") is not None:
                new_person = self.id_map.get("persons", row.get("person_id"))
                if new_person:
                    account_lines.append(
                        {
                            "person_id": int(new_person),
                            "debit": float(debit),
                            "credit": float(credit),
                            "description": row.get("des"),
                        }
                    )
                    continue

            ref_id = row.get("ref_id")
            account_id = self.chart.resolve_account_id(
                int(ref_id) if ref_id is not None else None,
                is_income=False,
            )
            if account_id:
                account_lines.append(
                    {
                        "account_id": int(account_id),
                        "debit": float(debit),
                        "credit": float(credit),
                        "description": row.get("des"),
                    }
                )

        if not account_lines:
            raise ApiError("LEGACY_OB_NO_LINES", "سطر تراز افتتاحیه یافت نشد", http_status=400)

        payload = {
            "fiscal_year_id": int(fiscal_year_id),
            "document_date": parse_legacy_date(doc.get("date")).isoformat(),
            "currency_id": self.currency_id,
            "account_lines": account_lines,
            "inventory_lines": [],
            "auto_balance_to_equity": False,
            "description": doc.get("des") or "تراز افتتاحیه",
            "extra_info": {
                "source": "legacy_api",
                "legacy_import": True,
                "legacy_doc_id": doc.get("id"),
                "legacy_doc_code": doc.get("code"),
            },
        }
        result = upsert_opening_balance(self.db, self.business_id, self.user_id, payload)
        new_doc_id = (result or {}).get("id")
        if doc.get("id") is not None and new_doc_id:
            self.id_map.set("documents", int(doc["id"]), int(new_doc_id))
        self.stats.documents_imported += 1
