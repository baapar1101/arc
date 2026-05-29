from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from app.services.legacy_import.legacy_chart_resolver import LegacyChartResolver
from app.services.legacy_import.mappers import safe_decimal


def normalize_api_document_rows(api_rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """تبدیل سطرهای hesabdari/direct/doc/get به فرمت مشابه hesabdari_rows."""
    out: List[Dict[str, Any]] = []
    for r in api_rows or []:
        ref = r.get("ref") if isinstance(r.get("ref"), dict) else {}
        person = r.get("person")
        person_id = person.get("id") if isinstance(person, dict) else None
        out.append(
            {
                "ref_id": ref.get("id"),
                "bank_id": r.get("bankAccount") or r.get("bank_id"),
                "person_id": person_id,
                "commodity_id": (r.get("commodity") or {}).get("id")
                if isinstance(r.get("commodity"), dict)
                else r.get("commodity_id"),
                "bs": r.get("bs"),
                "bd": r.get("bd"),
                "des": r.get("des"),
                "_table_type": ref.get("tableType"),
            }
        )
    return out


def build_expense_income_payload(
    doc_type: str,
    rows: List[Dict[str, Any]],
    *,
    chart: LegacyChartResolver,
    id_map,
    doc_amount: Any = None,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """
    استخراج item_lines و counterparty_lines از سطرهای سند cost/income.

    cost: بدهکار حساب هزینه (bd)، بستانکار بانک/شخص (bs)
    income: بستانکار حساب درآمد (bs)، بدهکار بانک/شخص (bd)
    """
    is_income = doc_type == "income"
    item_lines: List[Dict[str, Any]] = []
    counterparty_lines: List[Dict[str, Any]] = []

    for row in rows:
        if row.get("commodity_id"):
            continue

        bs = safe_decimal(row.get("bs"))
        bd = safe_decimal(row.get("bd"))
        desc = row.get("des")

        bank_id = row.get("bank_id")
        if bank_id is not None:
            amt = bs if bs > 0 else bd
            if amt <= 0:
                continue
            new_bank = id_map.get("bank_accounts", bank_id)
            if new_bank:
                counterparty_lines.append(
                    {
                        "transaction_type": "bank",
                        "bank_id": int(new_bank),
                        "amount": float(amt),
                        "description": desc,
                    }
                )
            continue

        person_id = row.get("person_id")
        if person_id is not None:
            if is_income:
                amt = bd if bd > 0 else bs
            else:
                amt = bd if bd > 0 else bs
            if amt <= 0:
                continue
            new_person = id_map.get("persons", person_id)
            if new_person:
                counterparty_lines.append(
                    {
                        "transaction_type": "person",
                        "person_id": int(new_person),
                        "amount": float(amt),
                        "description": desc,
                    }
                )
            continue

        if is_income:
            item_amt = bs if bs > 0 else Decimal(0)
        else:
            item_amt = bd if bd > 0 else Decimal(0)
        if item_amt <= 0:
            continue

        ref_id = row.get("ref_id")
        account_id = chart.resolve_account_id(
            int(ref_id) if ref_id is not None else None,
            is_income=is_income,
        )
        if not account_id:
            continue
        item_lines.append(
            {
                "account_id": int(account_id),
                "amount": float(item_amt),
                "description": desc,
            }
        )

    sum_items = sum(Decimal(str(l["amount"])) for l in item_lines)
    sum_cp = sum(Decimal(str(c["amount"])) for c in counterparty_lines)
    doc_total = safe_decimal(doc_amount)

    if item_lines and not counterparty_lines and id_map.bank_accounts:
        amt = sum_items if sum_items > 0 else doc_total
        if amt > 0:
            first_bank = next(iter(id_map.bank_accounts.values()))
            counterparty_lines.append(
                {
                    "transaction_type": "bank",
                    "bank_id": int(first_bank),
                    "amount": float(amt),
                    "description": None,
                }
            )
    elif counterparty_lines and not item_lines:
        fb = chart.resolve_account_id(None, is_income=is_income)
        if fb:
            cp_total = sum_cp if sum_cp > 0 else doc_total
            if cp_total > 0:
                item_lines.append(
                    {
                        "account_id": int(fb),
                        "amount": float(cp_total),
                        "description": None,
                    }
                )
    elif not item_lines and not counterparty_lines and doc_total > 0:
        fb = chart.resolve_account_id(None, is_income=is_income)
        if fb:
            item_lines.append(
                {
                    "account_id": int(fb),
                    "amount": float(doc_total),
                    "description": None,
                }
            )

    return item_lines, counterparty_lines
