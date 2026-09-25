"""محدودیت‌های منابع اجرای HScript."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ResourceLimits:
	"""سقف‌های امن اجرای یک اسکریپت."""

	max_execution_ms: int = 10_000
	max_steps: int = 200_000
	max_loop_iterations: int = 10_000
	max_call_depth: int = 32
	max_list_size: int = 5_000
	max_dict_size: int = 2_000
	max_string_size: int = 100_000
	max_output_bytes: int = 2_000_000
	max_source_bytes: int = 100_000
	max_gateway_calls: int = 50
	max_gateway_rows_per_call: int = 5_000
	max_report_blocks: int = 200
	max_function_defs: int = 50

	@classmethod
	def default(cls) -> "ResourceLimits":
		return cls()

	@classmethod
	def preview(cls) -> "ResourceLimits":
		"""سقف سخت‌تر برای پیش‌نمایش Studio."""
		return cls(
			max_execution_ms=5_000,
			max_steps=80_000,
			max_loop_iterations=2_000,
			max_gateway_calls=20,
			max_gateway_rows_per_call=500,
			max_output_bytes=500_000,
		)
