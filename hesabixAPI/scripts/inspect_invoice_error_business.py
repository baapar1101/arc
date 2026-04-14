#!/usr/bin/env python3
"""
بررسی خطاهای دیتابیس مربوط به ویرایش فاکتور:
- کسب‌وکار مربوطه (business_id=92)
- سند/فاکتور (document_id=30289)
- شخص مرتبط (person_id) و وجود در جدول persons
از لاگ: PUT /api/v1/invoices/business/92/30289 → ForeignKeyViolation document_lines_person_id_fkey
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import SessionLocal
from adapters.db.models.document import Document
from adapters.db.models.business import Business
from adapters.db.models.person import Person


def main():
    business_id = 92
    document_id = 30289

    db = SessionLocal()
    try:
        # نام کسب‌وکار
        business = db.query(Business).filter(Business.id == business_id).first()
        if business:
            name = getattr(business, "name", None) or getattr(business, "title", None) or "—"
            print(f"کسب‌وکار مرتبط با خطا:")
            print(f"  business_id = {business_id}")
            print(f"  نام = {name}")
        else:
            print(f"کسب‌وکار با id={business_id} یافت نشد.")

        # سند (فاکتور)
        doc = db.query(Document).filter(Document.id == document_id, Document.business_id == business_id).first()
        if doc:
            print(f"\nسند (فاکتور):")
            print(f"  document_id = {document_id}")
            print(f"  code = {getattr(doc, 'code', '—')}")
            print(f"  document_type = {getattr(doc, 'document_type', '—')}")
            extra = getattr(doc, "extra_info", None) or {}
            person_id_extra = extra.get("person_id") if isinstance(extra, dict) else None
            print(f"  extra_info.person_id = {person_id_extra}")
            if person_id_extra is not None:
                try:
                    pid = int(person_id_extra)
                except (TypeError, ValueError):
                    pid = None
                if pid is not None:
                    person = db.query(Person).filter(Person.id == pid, Person.business_id == business_id).first()
                    if person:
                        print(f"\nشخص (persons):")
                        print(f"  person_id = {person.id}")
                        print(f"  business_id = {person.business_id}")
                        print(f"  alias_name = {getattr(person, 'alias_name', '—')}")
                    else:
                        exists_other = db.query(Person).filter(Person.id == pid).first()
                        print(f"\n⚠️ شخص با person_id={pid}:")
                        if exists_other:
                            print(f"  در جدول persons وجود دارد ولی business_id={exists_other.business_id} (متفاوت از کسب‌وکار فاکتور {business_id})")
                        else:
                            print(f"  در جدول persons یافت نشد (حذف شده یا شناسه اشتباه).")
        else:
            print(f"\nسند با id={document_id} و business_id={business_id} یافت نشد.")

        print("\nخلاصه:")
        print("  خطای ForeignKeyViolation یعنی مقدار person_id در extra_info فاکتور به رکوردی در جدول persons اشاره می‌کند که وجود ندارد یا متعلق به کسب‌وکار دیگری است.")
        print("  خطای CannotCoerce (json to integer) معمولاً وقتی است که مقدار person_id از سمت کلاینت یا از extra_info به صورت نوع اشتباه (مثلاً شیء JSON) ارسال شده باشد.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
