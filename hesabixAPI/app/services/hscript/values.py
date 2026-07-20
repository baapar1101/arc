"""انواع مقدار و اشیای امن داخل HScript (بدون نشت object میزبان)."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, time
from decimal import Decimal
from typing import Any, Callable, Iterable, Iterator, Optional
from uuid import UUID

from app.services.hscript.errors import SecurityErrorHS, TypeErrorHS, ResourceLimitErrorHS


Primitive = None | bool | int | float | str


def is_primitive(value: Any) -> bool:
	return value is None or isinstance(value, (bool, int, float, str))


def sanitize_jsonish(value: Any, *, max_depth: int = 12, _depth: int = 0) -> Any:
	"""تبدیل خروجی به JSON-safe بدون objectهای میزبان."""
	if _depth > max_depth:
		raise ResourceLimitErrorHS("عمق داده بیش از حد مجاز است")
	if is_primitive(value):
		return value
	if isinstance(value, datetime):
		return value.isoformat()
	if isinstance(value, date):
		return value.isoformat()
	if isinstance(value, time):
		return value.isoformat()
	if isinstance(value, Decimal):
		# حفظ دقت معقول برای مبالغ
		as_int = value.to_integral_value()
		if as_int == value:
			return int(as_int)
		return float(value)
	if isinstance(value, UUID):
		return str(value)
	if isinstance(value, bytes):
		return value.decode("utf-8", errors="replace")[:5000]
	if isinstance(value, HTable):
		return value.to_plain()
	if isinstance(value, HModule):
		raise SecurityErrorHS("ماژول‌ها قابل سریالایز نیستند")
	if isinstance(value, HFunction):
		raise SecurityErrorHS("توابع قابل سریالایز نیستند")
	if isinstance(value, dict):
		return {str(k): sanitize_jsonish(v, max_depth=max_depth, _depth=_depth + 1) for k, v in value.items()}
	if isinstance(value, (list, tuple)):
		return [sanitize_jsonish(v, max_depth=max_depth, _depth=_depth + 1) for v in value]
	# هر چیز دیگر (ORM، exception، …) مسدود
	raise SecurityErrorHS(f"نوع غیرمجاز در خروجی: {type(value).__name__}")


@dataclass
class HFunction:
	name: str
	params: list[str]
	body: Any  # list[Stmt]
	closure: dict[str, Any]
	line: int = 1


@dataclass
class HModule:
	"""Proxy امن به API میزبان؛ فقط متدهای allowlisted."""

	name: str
	methods: dict[str, Callable[..., Any]] = field(default_factory=dict)

	def get_attr(self, attr: str, *, line: int | None = None) -> Any:
		if attr.startswith("_"):
			raise SecurityErrorHS(f"دسترسی به '{attr}' مجاز نیست", line=line)
		if attr not in self.methods:
			raise SecurityErrorHS(f"متد '{self.name}.{attr}' وجود ندارد یا مجاز نیست", line=line)
		return self.methods[attr]


@dataclass
class HTable:
	"""جدول داده‌ای درون‌حافظه‌ای برای فیلتر/تجمیع امن."""

	rows: list[dict[str, Any]] = field(default_factory=list)
	_max_rows: int = 5000

	def __len__(self) -> int:
		return len(self.rows)

	def __iter__(self) -> Iterator[dict[str, Any]]:
		return iter(self.rows)

	def to_plain(self) -> list[dict[str, Any]]:
		return [dict(r) for r in self.rows]

	@classmethod
	def from_rows(cls, rows: Iterable[Any], *, max_rows: int = 5000) -> "HTable":
		out: list[dict[str, Any]] = []
		for item in rows:
			if len(out) >= max_rows:
				raise ResourceLimitErrorHS(f"تعداد ردیف جدول از سقف {max_rows} بیشتر شد")
			if isinstance(item, dict):
				out.append({str(k): sanitize_jsonish(v) for k, v in item.items()})
			else:
				raise TypeErrorHS("ردیف جدول باید dict باشد")
		return cls(rows=out, _max_rows=max_rows)

	def filter(self, **kwargs: Any) -> "HTable":
		def match(row: dict[str, Any]) -> bool:
			for k, v in kwargs.items():
				if row.get(k) != v:
					return False
			return True

		return HTable(rows=[r for r in self.rows if match(r)], _max_rows=self._max_rows)

	def select(self, *columns: str) -> "HTable":
		cols = [str(c) for c in columns]
		return HTable(
			rows=[{c: r.get(c) for c in cols} for r in self.rows],
			_max_rows=self._max_rows,
		)

	def sort(self, by: str, *, desc: bool = False) -> "HTable":
		key = str(by)

		def sort_key(row: dict[str, Any]) -> Any:
			val = row.get(key)
			return (val is None, val)

		return HTable(
			rows=sorted(self.rows, key=sort_key, reverse=bool(desc)),
			_max_rows=self._max_rows,
		)

	def limit(self, n: int) -> "HTable":
		n_i = int(n)
		if n_i < 0:
			raise TypeErrorHS("limit باید غیرمنفی باشد")
		return HTable(rows=self.rows[:n_i], _max_rows=self._max_rows)

	def top(self, n: int, *, by: Optional[str] = None, desc: bool = True) -> "HTable":
		t = self
		if by is not None:
			t = t.sort(by, desc=desc)
		return t.limit(n)

	def sum(self, field: str) -> float:
		total = 0.0
		for row in self.rows:
			v = row.get(field)
			if v is None:
				continue
			total += float(v)
		return total

	def count(self) -> int:
		return len(self.rows)

	def avg(self, field: str) -> float:
		c = self.count()
		if c == 0:
			return 0.0
		return self.sum(field) / c

	def group_by(self, key: str) -> "HTable":
		"""گروه‌بندی ساده: برمی‌گرداند [{key, count, rows_sample}] — برای sum از group_sum استفاده کنید."""
		buckets: dict[Any, list[dict[str, Any]]] = {}
		for row in self.rows:
			k = row.get(key)
			buckets.setdefault(k, []).append(row)
		out = []
		for k, items in buckets.items():
			out.append({key: k, "count": len(items)})
		return HTable(rows=out, _max_rows=self._max_rows)

	def group_sum(self, key: str, field: str) -> "HTable":
		buckets: dict[Any, float] = {}
		counts: dict[Any, int] = {}
		for row in self.rows:
			k = row.get(key)
			v = row.get(field)
			buckets[k] = buckets.get(k, 0.0) + (float(v) if v is not None else 0.0)
			counts[k] = counts.get(k, 0) + 1
		out = [{key: k, field: total, "count": counts[k]} for k, total in buckets.items()]
		return HTable(rows=out, _max_rows=self._max_rows)
