#!/usr/bin/env python3
"""فراخوانی واقعی document_to_dict برای سند RC-20260226-0001."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import SessionLocal
from adapters.db.models.document import Document
from app.services.receipt_payment_service import document_to_dict

def main():
    db = SessionLocal()
    try:
        doc = db.query(Document).filter(Document.code == "RC-20260226-0001").first()
        if not doc:
            print("سند یافت نشد")
            return
        result = document_to_dict(db, doc)
        print("person_names:", repr(result.get("person_names")))
        print("person_lines_count:", result.get("person_lines_count"))
        print("person_lines:", len(result.get("person_lines", [])))
        for pl in result.get("person_lines", []):
            print("  ", pl.get("person_name"), pl.get("person_id"))
    finally:
        db.close()

if __name__ == "__main__":
    main()
