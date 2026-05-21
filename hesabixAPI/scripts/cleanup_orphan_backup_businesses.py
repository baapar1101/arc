#!/usr/bin/env python3
"""
پاک‌سازی کسب‌وکارهای نیمه‌مانده از import بکاپ ناموفق (CLI).

مثال:
  cd hesabixAPI && .venv/bin/python scripts/cleanup_orphan_backup_businesses.py --dry-run
  cd hesabixAPI && .venv/bin/python scripts/cleanup_orphan_backup_businesses.py --execute --min-age-hours 24
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from adapters.db.session import get_db_session
from app.services.business_backup_orphan_cleanup_service import run_orphan_backup_business_cleanup


def main() -> int:
    parser = argparse.ArgumentParser(description="پاک‌سازی کسب‌وکارهای یتیم import بکاپ")
    parser.add_argument("--dry-run", action="store_true", help="فقط گزارش کاندیدها")
    parser.add_argument("--execute", action="store_true", help="حذف واقعی (بدون این پرچم = dry-run)")
    parser.add_argument("--business-id", type=int, default=None)
    parser.add_argument("--owner-id", type=int, default=None)
    parser.add_argument("--min-age-hours", type=int, default=1)
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()

    dry_run = not args.execute
    if args.dry_run:
        dry_run = True

    params = {
        "business_id": args.business_id,
        "owner_id": args.owner_id,
        "min_age_hours": args.min_age_hours,
        "limit": args.limit,
    }

    with get_db_session() as db:
        stats = run_orphan_backup_business_cleanup(db, params, dry_run=dry_run)

    print(json.dumps(stats, ensure_ascii=False, indent=2))
    return 0 if stats.get("errors", 0) == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
