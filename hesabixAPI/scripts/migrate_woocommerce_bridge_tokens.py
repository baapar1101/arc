#!/usr/bin/env python3
"""یک‌بار رمزنگاری توکن‌های plaintext پل ووکامرس در BusinessPlugin.extra_info.

اجرای دستی پس از ارتقای API (مستقل از WOOCOMMERCE_DEV_MODE).

  cd hesabixAPI && python3 scripts/migrate_woocommerce_bridge_tokens.py
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import SessionLocal
from app.services.woocommerce_integration_service import migrate_plaintext_woocommerce_bridge_tokens


def main() -> int:
	db = SessionLocal()
	try:
		out = migrate_plaintext_woocommerce_bridge_tokens(db)
		print(out)
		return 0 if out.get("ok") else 1
	except Exception as exc:
		db.rollback()
		print(f"✗ Failed: {exc}")
		return 1
	finally:
		db.close()


if __name__ == "__main__":
	raise SystemExit(main())
