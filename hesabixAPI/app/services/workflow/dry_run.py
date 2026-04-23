"""
اجرای آزمایشی (dry run): بدون اثر جانبی — برای تست امن توسط کاربر عادی.
"""

from __future__ import annotations

from typing import Any, Dict, Optional

DRY_RUN_TRIGGER_KEY = "__workflow_dry_run__"


def dry_run_skip(context: Dict[str, Any], action_name_fa: str) -> Optional[Dict[str, Any]]:
    """اگر اجرا آزمایشی است، نتیجهٔ جایگزین برگردان؛ وگرنه None."""
    if not context.get("dry_run"):
        return None
    return {
        "success": True,
        "dry_run": True,
        "message": f"«{action_name_fa}» در حالت آزمایشی اجرا نشد؛ فقط مسیر گردش بررسی شد.",
    }
