#!/usr/bin/env python3
"""ثبت/همگام‌سازی افزونه بسته حسابداری پیشرفته در بازار افزونه‌ها."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import SessionLocal
from adapters.db.seed_data.marketplace_plugins_seed import (
	ADVANCED_ACCOUNTING_PLUGIN_CODE,
	ensure_default_marketplace_plugins,
)


def main() -> int:
	db = SessionLocal()
	try:
		result = ensure_default_marketplace_plugins(db)
		if not result.get("ok"):
			print(f"✗ خطا: {result.get('message') or result.get('error') or 'seed failed'}")
			db.rollback()
			return 1
		db.commit()
		codes = result.get("plugin_codes") or []
		if ADVANCED_ACCOUNTING_PLUGIN_CODE not in codes:
			print("✗ افزونه advanced_accounting در seed پیش‌فرض نیست")
			return 1
		print(
			"✓ بسته حسابداری پیشرفته همگام شد "
			f"(created={result.get('plugins_created')}, updated={result.get('plugins_updated')})."
		)
		return 0
	except Exception as e:
		db.rollback()
		print(f"✗ خطا: {e}")
		import traceback

		traceback.print_exc()
		return 1
	finally:
		db.close()


if __name__ == "__main__":
	sys.exit(main())
