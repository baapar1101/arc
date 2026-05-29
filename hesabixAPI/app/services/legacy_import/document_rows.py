from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from app.services.legacy_import.mappers import safe_decimal


def row_amount(row: Dict[str, Any]) -> Decimal:
    bs = safe_decimal(row.get("bs"))
    bd = safe_decimal(row.get("bd"))
    return bs if bs > 0 else bd


def detect_account_transaction(
    row: Dict[str, Any],
) -> Tuple[Optional[str], Dict[str, Any]]:
    """تشخیص نوع طرف حساب سند (مشابه legacy_sql/receipt_payment_importer)."""
    cheque_id = row.get("cheque_id") or row.get("check_id")
    if cheque_id is not None:
        return "check", {"check_id": int(cheque_id)}
    bank_id = row.get("bank_id")
    if bank_id is not None:
        return "bank", {"bank_id": int(bank_id)}
    cashdesk_id = row.get("cashdesk_id")
    if cashdesk_id is not None:
        return "cash_register", {"cash_register_id": int(cashdesk_id)}
    salary_id = row.get("salary_id")
    if salary_id is not None:
        return "petty_cash", {"petty_cash_id": int(salary_id)}
    return None, {}


def build_receipt_payment_lines(
    rows: List[Dict[str, Any]],
    *,
    id_map,
    doc_amount: Any = None,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """استخراج person_lines و account_lines با transaction_type صحیح."""
    person_lines: List[Dict[str, Any]] = []
    account_lines: List[Dict[str, Any]] = []
    doc_total = safe_decimal(doc_amount)

    for row in rows:
        amt = row_amount(row)
        if amt <= 0:
            continue

        person_id = row.get("person_id")
        if person_id is not None:
            new_pid = id_map.get("persons", person_id)
            if new_pid:
                person_lines.append(
                    {
                        "person_id": int(new_pid),
                        "amount": float(amt),
                        "description": row.get("des"),
                    }
                )

        tx_type, tx_extra = detect_account_transaction(row)
        if not tx_type:
            continue

        acc_line: Dict[str, Any] = {
            "amount": float(amt),
            "transaction_type": tx_type,
            "description": row.get("des"),
        }

        if tx_type == "bank":
            new_bank = id_map.get("bank_accounts", tx_extra["bank_id"])
            if not new_bank:
                continue
            acc_line["bank_id"] = int(new_bank)
        elif tx_type == "cash_register":
            new_cr = id_map.get("cash_registers", tx_extra["cash_register_id"])
            if not new_cr:
                continue
            acc_line["cash_register_id"] = int(new_cr)
        elif tx_type == "petty_cash":
            new_pc = id_map.get("petty_cash", tx_extra["petty_cash_id"])
            if not new_pc:
                continue
            acc_line["petty_cash_id"] = int(new_pc)
        elif tx_type == "check":
            acc_line["check_id"] = tx_extra.get("check_id")

        account_lines.append(acc_line)

    if person_lines and not account_lines:
        default_bank = id_map.get_default_bank_id()
        if default_bank:
            total = sum(p["amount"] for p in person_lines)
            account_lines.append(
                {
                    "transaction_type": "bank",
                    "bank_id": int(default_bank),
                    "amount": float(total),
                    "description": None,
                }
            )
        default_cash = id_map.get_default_cash_register_id()
        if default_cash and not account_lines:
            total = sum(p["amount"] for p in person_lines)
            account_lines.append(
                {
                    "transaction_type": "cash_register",
                    "cash_register_id": int(default_cash),
                    "amount": float(total),
                    "description": None,
                }
            )

    if person_lines and account_lines:
        person_total = sum(Decimal(str(p["amount"])) for p in person_lines)
        account_total = sum(Decimal(str(a["amount"])) for a in account_lines)
        if person_total > 0 and account_total > 0 and person_total != account_total:
            if len(account_lines) == 1:
                account_lines[0]["amount"] = float(person_total)
            elif len(person_lines) == 1:
                person_lines[0]["amount"] = float(account_total)

    return person_lines, account_lines
