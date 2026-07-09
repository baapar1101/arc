#!/usr/bin/env python3
"""
اصلاح لینک‌های دوطرفه فاکتور ↔ سند دریافت/پرداخت.

موارد پوشش‌داده‌شده:
- extra_info.invoice_id روی سند دریافت/پرداخت (منبع فاکتور)
- extra_info.invoice_id روی خط شخص (لینک از UI سند دریافت)
"""

from __future__ import annotations

import argparse
import os
import sys
from collections import defaultdict
from typing import Dict, List, Set

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import cast, create_engine, Integer
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Session, sessionmaker

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from app.core.settings import get_settings
from app.services.legacy_import.invoice_settlement import append_receipt_payment_to_invoice


def _collect_invoice_receipt_pairs(db: Session) -> Dict[int, Set[int]]:
    """invoice_id -> set(receipt_payment_document_id)"""
    pairs: Dict[int, Set[int]] = defaultdict(set)

    rp_docs = (
        db.query(Document.id, Document.extra_info)
        .filter(Document.document_type.in_(["receipt", "payment"]))
        .all()
    )
    for doc_id, extra in rp_docs:
        if not isinstance(extra, dict):
            continue
        inv_id = extra.get("invoice_id")
        if inv_id is not None:
            try:
                pairs[int(inv_id)].add(int(doc_id))
            except (TypeError, ValueError):
                pass

    line_invoice_id_expr = cast(
        cast(DocumentLine.extra_info, JSONB)["invoice_id"].astext,
        Integer,
    )
    person_rows = (
        db.query(DocumentLine.document_id, line_invoice_id_expr)
        .join(Document, DocumentLine.document_id == Document.id)
        .filter(
            Document.document_type.in_(["receipt", "payment"]),
            DocumentLine.person_id.isnot(None),
            line_invoice_id_expr.isnot(None),
        )
        .all()
    )
    for doc_id, inv_id in person_rows:
        if inv_id is None:
            continue
        try:
            pairs[int(inv_id)].add(int(doc_id))
        except (TypeError, ValueError):
            continue

    return pairs


def find_invoices_with_missing_links(db: Session) -> List[Dict[str, object]]:
    pairs = _collect_invoice_receipt_pairs(db)
    to_fix: List[Dict[str, object]] = []

    for invoice_id, rp_ids in sorted(pairs.items()):
        invoice = (
            db.query(Document)
            .filter(
                Document.id == int(invoice_id),
                Document.document_type.like("invoice_%"),
            )
            .first()
        )
        if not invoice:
            continue

        extra = invoice.extra_info if isinstance(invoice.extra_info, dict) else {}
        links = extra.get("links") or {}
        existing_raw = links.get("receipt_payment_document_ids") or []
        existing: Set[int] = set()
        for raw in existing_raw:
            try:
                existing.add(int(raw))
            except (TypeError, ValueError):
                continue

        missing = sorted(rp_ids - existing)
        if missing:
            to_fix.append(
                {
                    "invoice_id": int(invoice_id),
                    "invoice_code": invoice.code,
                    "existing_rp_ids": sorted(existing),
                    "missing_rp_ids": missing,
                    "all_rp_ids": sorted(rp_ids),
                }
            )

    return to_fix


def fix_invoice_links(db: Session, invoice_id: int, rp_ids: List[int], *, dry_run: bool) -> bool:
    if dry_run:
        return True
    for rp_id in rp_ids:
        append_receipt_payment_to_invoice(db, int(invoice_id), int(rp_id))
    db.commit()
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description="اصلاح لینک‌های receipt/payment روی فاکتورها")
    parser.add_argument("--auto", action="store_true", help="بدون تأیید تعاملی اجرا شود")
    parser.add_argument("--dry-run", action="store_true", help="فقط گزارش؛ بدون تغییر دیتابیس")
    args = parser.parse_args()

    settings = get_settings()
    engine = create_engine(settings.postgresql_dsn)
    SessionLocal = sessionmaker(bind=engine)
    db = SessionLocal()

    print("🔧 اصلاح لینک‌های تراکنش‌های پرداخت در فاکتورها")
    print("=" * 80)

    try:
        invoices_to_fix = find_invoices_with_missing_links(db)
        if not invoices_to_fix:
            print("✅ همه فاکتورها لینک‌های صحیح دارند!")
            return

        print(f"📋 {len(invoices_to_fix)} فاکتور نیازمند اصلاح یافت شد:\n")
        for inv in invoices_to_fix:
            print(f"  فاکتور ID: {inv['invoice_id']!s:>6} | کد: {inv['invoice_code']}")
            print(f"    لینک‌های موجود: {inv['existing_rp_ids']}")
            print(f"    لینک‌های مفقود: {inv['missing_rp_ids']}")
            print(f"    لینک‌های کامل: {inv['all_rp_ids']}\n")

        if args.dry_run:
            print("حالت dry-run: تغییری اعمال نشد.")
            return

        if not args.auto:
            response = input("آیا می‌خواهید این فاکتورها را اصلاح کنید؟ (y/n): ")
            if response.lower() != "y":
                print("❌ عملیات لغو شد.")
                return

        fixed_count = 0
        for inv in invoices_to_fix:
            ok = fix_invoice_links(
                db,
                int(inv["invoice_id"]),
                list(inv["missing_rp_ids"]),
                dry_run=False,
            )
            if ok:
                print(f"  ✅ فاکتور {inv['invoice_id']} ({inv['invoice_code']}) اصلاح شد")
                fixed_count += 1
            else:
                print(f"  ❌ فاکتور {inv['invoice_id']} ({inv['invoice_code']}) اصلاح نشد")

        print(f"\n✅ {fixed_count} از {len(invoices_to_fix)} فاکتور اصلاح شدند.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
