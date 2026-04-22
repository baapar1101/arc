#!/usr/bin/env python3
"""
کامپایل messages.po به messages.mo برای gettext (Babel).
پس از ویرایش فایل‌های .po، این اسکریپت را اجرا کنید و سپس API را دوباره راه‌اندازی کنید
(till i18n_catalog.get_gettext_translation از حافظهٔ کش استفاده می‌کند).
"""
from __future__ import annotations

import os
import sys

# hesabixAPI/scripts/ → ریشهٔ پروژه API
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from babel.messages.mofile import write_mo
from babel.messages.pofile import read_po


def main() -> None:
    locales_dir = os.path.join(_ROOT, "locales")
    for rel in ("fa/LC_MESSAGES/messages.po", "en/LC_MESSAGES/messages.po"):
        po_path = os.path.join(locales_dir, rel)
        mo_path = po_path.replace(".po", ".mo")
        with open(po_path, "rb") as f:
            catalog = read_po(f)
        with open(mo_path, "wb") as f:
            write_mo(f, catalog)
        print("wrote", mo_path, f"({os.path.getsize(mo_path)} bytes)")


if __name__ == "__main__":
    main()
