#!/usr/bin/env python3
"""بررسی سند دریافت RC-20260226-0001 و خطوط آن در دیتابیس."""
import sys
import os
import json
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import text, create_engine
from app.core.settings import get_settings

def main():
    settings = get_settings()
    engine = create_engine(settings.postgresql_dsn)
    with engine.connect() as conn:
        # سند
        doc = conn.execute(
            text("SELECT id, code, document_type, business_id FROM documents WHERE code = :c"),
            {"c": "RC-20260226-0001"}
        ).fetchone()
        if not doc:
            print("سند یافت نشد.")
            return
        doc_id = doc[0]
        print(f"سند: id={doc_id}, code={doc[1]}, type={doc[2]}, business_id={doc[3]}")
        # خطوط
        rows = conn.execute(
            text("""
            SELECT dl.id, dl.account_id, dl.person_id, dl.extra_info,
                   a.code AS account_code, a.name AS account_name, a.account_type
            FROM document_lines dl
            JOIN accounts a ON a.id = dl.account_id
            WHERE dl.document_id = :doc_id
            ORDER BY dl.id
            """),
            {"doc_id": doc_id}
        ).fetchall()
        print(f"تعداد خطوط: {len(rows)}")
        for r in rows:
            line_id, acc_id, person_id, extra_info, acc_code, acc_name, acc_type = r
            ei = extra_info if isinstance(extra_info, dict) else (json.loads(extra_info) if extra_info else None)
            ei_pid = (ei or {}).get("person_id") if ei else None
            is_person_line = (ei and ei.get("person_id")) or (person_id and acc_type == "person")
            print(f"  line_id={line_id} account_id={acc_id} account_type={acc_type!r} person_id={person_id} extra_info.person_id={ei_pid} -> is_person_line={is_person_line} account={acc_code} {acc_name}")
            if ei:
                print(f"      extra_info keys: {list(ei.keys())} installment={ei.get('installment')} reclassification={ei.get('reclassification')}")
        # بررسی شخص 223 و حساب 13
        if rows:
            for r in rows:
                if r[2]:  # person_id
                    p = conn.execute(text("SELECT id, business_id, alias_name, first_name, last_name FROM persons WHERE id = :id"), {"id": r[2]}).fetchone()
                    print(f"  Person id={r[2]}: {p}")
            acc13 = conn.execute(text("SELECT id, code, name, account_type FROM accounts WHERE id = 13")).fetchone()
            print(f"  Account id=13: {acc13}")

if __name__ == "__main__":
    main()
