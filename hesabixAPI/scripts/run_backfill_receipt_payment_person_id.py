#!/usr/bin/env python3
"""
اجرای دستی مایگریشن backfill برای پر کردن extra_info.person_id در خطوط سند دریافت/پرداخت.
برای استفاده وقتی alembic upgrade head به‌دلیل مسیرهای مختلف versions در دسترس نیست.
"""
from __future__ import annotations

import sys
import os

# اضافه کردن مسیر پروژه برای import
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import text, create_engine
from app.core.settings import get_settings

REVISION = "20250226_000001_backfill_receipt_payment_person_id_extra_info"


def main() -> None:
    settings = get_settings()
    engine = create_engine(settings.postgresql_dsn)
    with engine.connect() as conn:
        if conn.dialect.name != "postgresql":
            print("این اسکریپت فقط برای PostgreSQL است.")
            sys.exit(1)
        # اجرای UPDATE
        result = conn.execute(
            text("""
            UPDATE document_lines dl
            SET extra_info = (
                COALESCE(dl.extra_info::jsonb, '{}'::jsonb)
                || jsonb_build_object('person_id', dl.person_id)
            )::json
            FROM documents d
            WHERE dl.document_id = d.id
              AND d.document_type IN ('receipt', 'payment')
              AND dl.person_id IS NOT NULL
              AND (dl.extra_info IS NULL
                   OR (dl.extra_info->>'person_id') IS NULL
                   OR (dl.extra_info->>'person_id') = '')
            """)
        )
        conn.commit()
        rowcount = result.rowcount if hasattr(result, "rowcount") else 0
        print(f"تعداد خطوط به‌روز شده: {rowcount}")
        # در صورت نیاز به ثبت در alembic_version ابتدا طول ستون را افزایش دهید:
        # ALTER TABLE alembic_version ALTER COLUMN version_num TYPE VARCHAR(255);
        # سپس: UPDATE alembic_version SET version_num = '20250226_000001_backfill_receipt_payment_person_id_extra_info';
    print("مایگریشن (backfill داده) با موفقیت اجرا شد.")


if __name__ == "__main__":
    main()
