"""سخت‌سازی اجرای HScript: پاکسازی خطا و سقف‌های worker."""

from __future__ import annotations

from typing import Any

from app.services.hscript.limits import ResourceLimits


def worker_limits(*, preview: bool) -> ResourceLimits:
	"""سقف سخت‌تر برای اجرای worker (جدا از process API)."""
	if preview:
		return ResourceLimits.preview()
	# برای job کامل کمی سخاوتمندانه‌تر ولی همچنان capped
	return ResourceLimits(
		max_execution_ms=55_000,
		max_steps=400_000,
		max_loop_iterations=20_000,
		max_call_depth=32,
		max_list_size=5_000,
		max_dict_size=2_000,
		max_string_size=100_000,
		max_output_bytes=2_000_000,
		max_source_bytes=100_000,
		max_gateway_calls=80,
		max_gateway_rows_per_call=5_000,
		max_report_blocks=200,
		max_function_defs=50,
	)


def sanitize_public_error(error: Any) -> dict[str, Any] | None:
	"""حذف جزئیات داخلی از خطا قبل از بازگشت به کلاینت/Redis."""
	if error is None:
		return None
	if isinstance(error, dict):
		return {
			"code": str(error.get("code") or "E040_RUNTIME")[:64],
			"message": str(error.get("message") or "خطا")[:500],
			"line": error.get("line"),
			"column": error.get("column"),
			"hint": (str(error["hint"])[:300] if error.get("hint") else None),
			"doc_id": error.get("doc_id"),
		}
	return {"code": "E040_RUNTIME", "message": str(error)[:500]}
