#!/usr/bin/env python3
"""
Fix legacy expense/income document_lines references.

This script backfills missing foreign keys on `document_lines` for old
expense/income documents based on `extra_info` payload.

What it can backfill (when missing):
- bank_account_id      (transaction_type=bank, extra_info.bank_account_id/bank_id)
- cash_register_id     (transaction_type=cash_register, extra_info.cash_register_id)
- petty_cash_id        (transaction_type=petty_cash, extra_info.petty_cash_id)
- check_id             (transaction_type=check/check_expense, extra_info.check_id)
- person_id            (transaction_type=person, extra_info.person_id)
- account_id           (transaction_type=account, extra_info.account_id)

Default mode is dry-run. Use --apply to persist changes.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Dict, Optional

from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker


# add project root to PYTHONPATH when executed from scripts/
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _to_dict(value: Any) -> Dict[str, Any]:
    if value is None:
        return {}
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, dict) else {}
        except Exception:
            return {}
    return {}


def _to_int(value: Any) -> Optional[int]:
    if value is None:
        return None
    try:
        iv = int(str(value).strip())
        return iv if iv > 0 else None
    except Exception:
        return None


class Fixer:
    def __init__(self, db_url: str, business_id: Optional[int], limit: Optional[int], apply: bool):
        self.engine = create_engine(db_url, pool_pre_ping=True)
        self.session: Session = sessionmaker(bind=self.engine)()
        self.business_id = business_id
        self.limit = limit
        self.apply = apply
        self.stats = {
            "scanned": 0,
            "candidates": 0,
            "updated_lines": 0,
            "updated_fields": 0,
            "skipped_invalid_ref": 0,
            "errors": 0,
        }

    def close(self) -> None:
        self.session.close()

    def _exists_bank(self, bank_id: int, business_id: int) -> bool:
        q = text("SELECT 1 FROM bank_accounts WHERE id = :id AND business_id = :business_id LIMIT 1")
        return self.session.execute(q, {"id": bank_id, "business_id": business_id}).first() is not None

    def _exists_cash_register(self, item_id: int, business_id: int) -> bool:
        q = text("SELECT 1 FROM cash_registers WHERE id = :id AND business_id = :business_id LIMIT 1")
        return self.session.execute(q, {"id": item_id, "business_id": business_id}).first() is not None

    def _exists_petty_cash(self, item_id: int, business_id: int) -> bool:
        q = text("SELECT 1 FROM petty_cash WHERE id = :id AND business_id = :business_id LIMIT 1")
        return self.session.execute(q, {"id": item_id, "business_id": business_id}).first() is not None

    def _exists_check(self, check_id: int, business_id: int) -> bool:
        q = text("SELECT 1 FROM checks WHERE id = :id AND business_id = :business_id LIMIT 1")
        return self.session.execute(q, {"id": check_id, "business_id": business_id}).first() is not None

    def _exists_person(self, person_id: int, business_id: int) -> bool:
        q = text("SELECT 1 FROM persons WHERE id = :id AND business_id = :business_id LIMIT 1")
        return self.session.execute(q, {"id": person_id, "business_id": business_id}).first() is not None

    def _exists_account(self, account_id: int, business_id: int) -> bool:
        q = text(
            "SELECT 1 FROM accounts WHERE id = :id AND (business_id = :business_id OR business_id IS NULL) LIMIT 1"
        )
        return self.session.execute(q, {"id": account_id, "business_id": business_id}).first() is not None

    def _fetch_lines(self):
        base_sql = """
            SELECT
                dl.id,
                dl.document_id,
                dl.account_id,
                dl.person_id,
                dl.bank_account_id,
                dl.cash_register_id,
                dl.petty_cash_id,
                dl.check_id,
                dl.extra_info,
                d.business_id,
                d.document_type
            FROM document_lines dl
            JOIN documents d ON d.id = dl.document_id
            WHERE d.document_type IN ('expense', 'income')
              AND dl.extra_info IS NOT NULL
        """
        params: Dict[str, Any] = {}
        if self.business_id is not None:
            base_sql += " AND d.business_id = :business_id"
            params["business_id"] = self.business_id
        base_sql += " ORDER BY dl.id ASC"
        if self.limit is not None:
            base_sql += " LIMIT :limit"
            params["limit"] = self.limit
        return self.session.execute(text(base_sql), params).fetchall()

    def _build_updates(self, row) -> Dict[str, int]:
        extra = _to_dict(row.extra_info)
        tx_type = str(extra.get("transaction_type") or "").strip().lower()
        if not tx_type:
            return {}

        updates: Dict[str, int] = {}
        business_id = int(row.business_id)

        if tx_type == "bank" and row.bank_account_id is None:
            bank_id = _to_int(extra.get("bank_account_id")) or _to_int(extra.get("bank_id"))
            if bank_id is not None:
                if self._exists_bank(bank_id, business_id):
                    updates["bank_account_id"] = bank_id
                else:
                    self.stats["skipped_invalid_ref"] += 1

        elif tx_type == "cash_register" and row.cash_register_id is None:
            item_id = _to_int(extra.get("cash_register_id"))
            if item_id is not None:
                if self._exists_cash_register(item_id, business_id):
                    updates["cash_register_id"] = item_id
                else:
                    self.stats["skipped_invalid_ref"] += 1

        elif tx_type == "petty_cash" and row.petty_cash_id is None:
            item_id = _to_int(extra.get("petty_cash_id"))
            if item_id is not None:
                if self._exists_petty_cash(item_id, business_id):
                    updates["petty_cash_id"] = item_id
                else:
                    self.stats["skipped_invalid_ref"] += 1

        elif tx_type in ("check", "check_expense") and row.check_id is None:
            check_id = _to_int(extra.get("check_id"))
            if check_id is not None:
                if self._exists_check(check_id, business_id):
                    updates["check_id"] = check_id
                else:
                    self.stats["skipped_invalid_ref"] += 1

        elif tx_type == "person" and row.person_id is None:
            person_id = _to_int(extra.get("person_id"))
            if person_id is not None:
                if self._exists_person(person_id, business_id):
                    updates["person_id"] = person_id
                else:
                    self.stats["skipped_invalid_ref"] += 1

        elif tx_type == "account" and row.account_id is None:
            account_id = _to_int(extra.get("account_id"))
            if account_id is not None:
                if self._exists_account(account_id, business_id):
                    updates["account_id"] = account_id
                else:
                    self.stats["skipped_invalid_ref"] += 1

        return updates

    def run(self) -> int:
        rows = self._fetch_lines()
        self.stats["scanned"] = len(rows)

        print("=" * 80)
        print("Fix expense/income document_lines refs")
        print("=" * 80)
        print(f"mode: {'APPLY' if self.apply else 'DRY-RUN'}")
        print(f"business_id: {self.business_id if self.business_id is not None else 'ALL'}")
        print(f"scanned rows: {self.stats['scanned']}")

        for row in rows:
            try:
                updates = self._build_updates(row)
                if not updates:
                    continue

                self.stats["candidates"] += 1
                self.stats["updated_fields"] += len(updates)

                if self.apply:
                    set_parts = [f"{col} = :{col}" for col in updates.keys()]
                    sql = text(f"UPDATE document_lines SET {', '.join(set_parts)} WHERE id = :line_id")
                    params = dict(updates)
                    params["line_id"] = int(row.id)
                    self.session.execute(sql, params)
                    self.stats["updated_lines"] += 1
            except Exception as exc:
                self.stats["errors"] += 1
                print(f"[error] line_id={row.id}: {exc}")

        if self.apply:
            try:
                self.session.commit()
            except Exception as exc:
                self.session.rollback()
                print(f"[fatal] commit failed: {exc}")
                return 2

        print("-" * 80)
        print(f"candidates: {self.stats['candidates']}")
        print(f"updated_fields: {self.stats['updated_fields']}")
        print(f"updated_lines: {self.stats['updated_lines']}")
        print(f"skipped_invalid_ref: {self.stats['skipped_invalid_ref']}")
        print(f"errors: {self.stats['errors']}")
        print("=" * 80)
        return 0 if self.stats["errors"] == 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Backfill missing foreign keys in expense/income document_lines from extra_info"
    )
    parser.add_argument(
        "--db-url",
        default=os.getenv("DATABASE_URL", ""),
        help="SQLAlchemy DB URL. Defaults to DATABASE_URL env",
    )
    parser.add_argument("--business-id", type=int, help="Fix only one business")
    parser.add_argument("--limit", type=int, help="Max rows to scan")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply changes (default is dry-run)",
    )
    args = parser.parse_args()

    if not args.db_url:
        print("DATABASE_URL is required (or pass --db-url).")
        return 2

    fixer = Fixer(
        db_url=args.db_url,
        business_id=args.business_id,
        limit=args.limit,
        apply=args.apply,
    )
    try:
        return fixer.run()
    finally:
        fixer.close()


if __name__ == "__main__":
    raise SystemExit(main())

