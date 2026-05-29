from __future__ import annotations

from typing import Any, Dict, List

from app.services.legacy_import.archive import LegacyArchive
from app.services.legacy_import.constants import (
    LEGACY_DOC_TYPE_TO_EXPENSE_INCOME,
    LEGACY_DOC_TYPE_TO_INVOICE,
    LEGACY_DOC_TYPE_TO_RECEIPT_PAYMENT,
)
from app.services.legacy_import.document_rows import detect_account_transaction, row_amount


def compute_import_risks(archive: LegacyArchive) -> List[Dict[str, Any]]:
    """برآورد ریسک‌ها قبل از شروع انتقال (برای UI)."""
    risks: List[Dict[str, Any]] = []
    counts = archive.counts()
    banks = archive.data.get("bank_accounts.json") or []
    bank_count = len(banks)
    if bank_count <= 1:
        risks.append(
            {
                "code": "SINGLE_BANK",
                "severity": "high",
                "message": "فقط یک حساب بانکی در آرشیو وجود دارد؛ اسناد «انتقال» بین دو بانک احتمالاً منتقل نمی‌شوند.",
                "count": max(0, bank_count),
            }
        )

    rows_by_doc = archive.rows_by_doc_id()
    invoice_no_person = 0
    receipt_no_account = 0
    unsupported = 0
    transfers = 0

    for doc in archive.data.get("hesabdari_docs.json") or []:
        doc_type = str(doc.get("type") or "").strip()
        doc_id = doc.get("id")
        rows = rows_by_doc.get(int(doc_id), []) if doc_id is not None else []

        if doc_type in LEGACY_DOC_TYPE_TO_INVOICE:
            has_person = bool(doc.get("person_id") or doc.get("personId"))
            if not has_person:
                has_person = any(r.get("person_id") for r in rows)
            if not has_person:
                invoice_no_person += 1
        elif doc_type in LEGACY_DOC_TYPE_TO_RECEIPT_PAYMENT:
            has_account = False
            for r in rows:
                if row_amount(r) <= 0:
                    continue
                tx, _ = detect_account_transaction(r)
                if tx:
                    has_account = True
                    break
            if not has_account:
                receipt_no_account += 1
        elif doc_type == "transfer":
            transfers += 1
        elif doc_type not in LEGACY_DOC_TYPE_TO_EXPENSE_INCOME and doc_type != "transfer":
            if doc_type not in ("open_balance",):
                unsupported += 1

    if invoice_no_person > 0:
        risks.append(
            {
                "code": "INVOICE_NO_PERSON",
                "severity": "medium",
                "message": "برخی فاکتورها در آرشیو شخص ندارند؛ با «مشتری نقدی انتقال» یا اولین شخص نگاشت‌شده جایگزین می‌شوند.",
                "count": invoice_no_person,
            }
        )
    if receipt_no_account > 0:
        risks.append(
            {
                "code": "RECEIPT_NO_ACCOUNT",
                "severity": "medium",
                "message": "برخی دریافت/پرداخت‌ها بانک/صندوق مشخص ندارند؛ از بانک یا صندوق پیش‌فرض استفاده می‌شود.",
                "count": receipt_no_account,
            }
        )
    if transfers > 0 and bank_count < 2:
        risks.append(
            {
                "code": "TRANSFER_NEEDS_TWO_BANKS",
                "severity": "high",
                "message": f"{transfers} سند انتقال نیاز به حداقل دو حساب بانکی مجزا دارد.",
                "count": transfers,
            }
        )
    if unsupported > 0:
        risks.append(
            {
                "code": "UNSUPPORTED_DOC_TYPES",
                "severity": "low",
                "message": "برخی انواع سند (مثل مانده افتتاحیه) هنوز پشتیبانی نمی‌شوند.",
                "count": unsupported,
            }
        )

    doc_total = counts.get("documents") or counts.get("hesabdari_docs") or 0
    if doc_total:
        risks.append(
            {
                "code": "DOCUMENT_VOLUME",
                "severity": "info",
                "message": f"حدود {doc_total} سند حسابداری در آرشیو وجود دارد؛ انتقال ممکن است چند دقیقه طول بکشد.",
                "count": doc_total,
            }
        )

    return risks
