#!/usr/bin/env python3
"""
Backfill default document monetization policies for businesses missing them.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from adapters.db.session import SessionLocal
from app.services.document_monetization_service import backfill_missing_default_document_policies


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Apply missing default document monetization policies to businesses.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=200,
        help="Log progress every N businesses (default: 200)",
    )
    parser.add_argument(
        "--business-id",
        type=int,
        action="append",
        dest="business_ids",
        help="Limit backfill to specific business id (repeatable)",
    )
    args = parser.parse_args()

    db = SessionLocal()
    try:
        result = backfill_missing_default_document_policies(
            db,
            batch_size=args.batch_size,
            business_ids=args.business_ids,
        )
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if not result.get("errors") else 1
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
