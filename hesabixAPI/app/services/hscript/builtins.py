"""توابع built-in امن HScript."""

from __future__ import annotations

from typing import Any, Callable

from app.services.hscript.errors import ResourceLimitErrorHS, TypeErrorHS
from app.services.hscript.limits import ResourceLimits
from app.services.hscript.values import HTable


def build_builtins(limits: ResourceLimits) -> dict[str, Callable[..., Any]]:
	def _len(x: Any) -> int:
		return len(x)

	def _str(x: Any) -> str:
		s = str(x)
		if len(s) > limits.max_string_size:
			raise ResourceLimitErrorHS("رشته خیلی طولانی")
		return s

	def _int(x: Any) -> int:
		return int(x)

	def _float(x: Any) -> float:
		return float(x)

	def _bool(x: Any) -> bool:
		return bool(x)

	def _abs(x: Any) -> Any:
		return abs(x)

	def _min(*args: Any) -> Any:
		if len(args) == 1 and isinstance(args[0], (list, tuple)):
			return min(args[0])
		return min(args)

	def _max(*args: Any) -> Any:
		if len(args) == 1 and isinstance(args[0], (list, tuple)):
			return max(args[0])
		return max(args)

	def _round(x: Any, ndigits: int = 0) -> Any:
		return round(float(x), int(ndigits))

	def _sum(x: Any) -> float:
		if isinstance(x, HTable):
			raise TypeErrorHS("برای Table از .sum(field) استفاده کنید")
		return float(sum(x))

	def _range(n: Any) -> list[int]:
		n_i = int(n)
		if n_i < 0 or n_i > limits.max_loop_iterations:
			raise ResourceLimitErrorHS("range خارج از محدوده مجاز")
		return list(range(n_i))

	def _table(rows: Any = None) -> HTable:
		if rows is None:
			return HTable(rows=[], _max_rows=limits.max_list_size)
		return HTable.from_rows(rows, max_rows=limits.max_list_size)

	return {
		"len": _len,
		"str": _str,
		"int": _int,
		"float": _float,
		"bool": _bool,
		"abs": _abs,
		"min": _min,
		"max": _max,
		"round": _round,
		"sum": _sum,
		"range": _range,
		"table": _table,
	}
