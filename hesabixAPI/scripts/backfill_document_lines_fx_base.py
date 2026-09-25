#!/usr/bin/env python3
"""Backfill نرم P2.5: پر کردن debit_base/credit_base/exchange_rate برای اسناد دارای fx یا ارز پایه.

استفاده:
  cd hesabixAPI && .venv/bin/python scripts/backfill_document_lines_fx_base.py
  .venv/bin/python scripts/backfill_document_lines_fx_base.py --business-id 1
  .venv/bin/python scripts/backfill_document_lines_fx_base.py --infer-missing
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
	sys.path.insert(0, str(ROOT))

from adapters.db.session import SessionLocal
from app.services.document_line_fx_service import backfill_document_lines_fx_base


def main() -> int:
	parser = argparse.ArgumentParser(description="Backfill document_lines FX base amounts")
	parser.add_argument("--business-id", type=int, default=None)
	parser.add_argument("--batch-size", type=int, default=200)
	parser.add_argument("--max-documents", type=int, default=None)
	parser.add_argument(
		"--infer-missing",
		action="store_true",
		help="برای اسناد ارزی بدون snapshot نیز از rate book استنباط کن (لایه ۳)",
	)
	parser.add_argument("--commit", action="store_true", default=True)
	parser.add_argument("--dry-run", action="store_true", help="بدون commit")
	args = parser.parse_args()

	db = SessionLocal()
	try:
		stats = backfill_document_lines_fx_base(
			db,
			business_id=args.business_id,
			batch_size=args.batch_size,
			only_with_fx_snapshot=not args.infer_missing,
			max_documents=args.max_documents,
		)
		print(stats)
		if args.dry_run:
			db.rollback()
			print("DRY-RUN: rolled back")
		else:
			db.commit()
			print("COMMITTED")
		return 0
	except Exception as e:
		db.rollback()
		print(f"ERROR: {e}", file=sys.stderr)
		raise
	finally:
		db.close()


if __name__ == "__main__":
	raise SystemExit(main())
