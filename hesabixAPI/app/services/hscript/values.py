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

	@staticmethod
	def _safe_cmp(op: str, a: Any, b: Any) -> bool:
		try:
			if op == "eq":
				return a == b
			if op == "ne":
				return a != b
			if a is None or b is None:
				return False
			if op == "gt":
				return a > b
			if op == "gte":
				return a >= b
			if op == "lt":
				return a < b
			if op == "lte":
				return a <= b
		except TypeError:
			return False
		return False

	_WHERE_OPS = {
		"eq": lambda a, b: HTable._safe_cmp("eq", a, b),
		"ne": lambda a, b: HTable._safe_cmp("ne", a, b),
		"gt": lambda a, b: HTable._safe_cmp("gt", a, b),
		"gte": lambda a, b: HTable._safe_cmp("gte", a, b),
		"lt": lambda a, b: HTable._safe_cmp("lt", a, b),
		"lte": lambda a, b: HTable._safe_cmp("lte", a, b),
		"contains": lambda a, b: b is not None and str(b).lower() in str(a or "").lower(),
		"startswith": lambda a, b: b is not None and str(a or "").lower().startswith(str(b).lower()),
		"in": lambda a, b: a in (b if isinstance(b, (list, tuple, set)) else [b]),
		"isnull": lambda a, b: (a is None) if bool(b) else (a is not None),
	}

	def filter(self, **kwargs: Any) -> "HTable":
		"""فیلتر تساوی ساده یا با پسوند اپراتور (field__gt=…)."""
		if not kwargs:
			return HTable(rows=list(self.rows), _max_rows=self._max_rows)

		def match(row: dict[str, Any]) -> bool:
			for k, v in kwargs.items():
				field, op = self._split_where_key(str(k))
				fn = self._WHERE_OPS.get(op)
				if fn is None:
					raise TypeErrorHS(f"عملگر فیلتر نامعتبر: {op}")
				if not fn(row.get(field), v):
					return False
			return True

		return HTable(rows=[r for r in self.rows if match(r)], _max_rows=self._max_rows)

	def where(self, field: Any = None, op: Any = "eq", value: Any = None, **kwargs: Any) -> "HTable":
		"""
		فیلتر امن:
		  rows.where("amount", "gt", 1000)
		  rows.where(amount__gt=1000, status="paid")
		"""
		merged: dict[str, Any] = dict(kwargs)
		if field is not None:
			op_s = str(op or "eq").lower().strip()
			aliases = {"=": "eq", "==": "eq", "!=": "ne", ">": "gt", ">=": "gte", "<": "lt", "<=": "lte"}
			op_s = aliases.get(op_s, op_s)
			if op_s not in self._WHERE_OPS:
				raise TypeErrorHS(f"عملگر where نامعتبر: {op}")
			key = f"{field}__{op_s}" if op_s != "eq" else str(field)
			merged[key] = value
		return self.filter(**merged)

	@classmethod
	def _split_where_key(cls, key: str) -> tuple[str, str]:
		if "__" in key:
			field, op = key.rsplit("__", 1)
			op = op.lower()
			if op in cls._WHERE_OPS:
				return field, op
		return key, "eq"

	def select(self, *columns: str) -> "HTable":
		cols = [str(c) for c in columns]
		return HTable(
			rows=[{c: r.get(c) for c in cols} for r in self.rows],
			_max_rows=self._max_rows,
		)

	def rename(self, **mapping: Any) -> "HTable":
		mp = {str(k): str(v) for k, v in mapping.items()}
		out = []
		for row in self.rows:
			nr = {}
			for k, v in row.items():
				nr[mp.get(str(k), str(k))] = v
			out.append(nr)
		return HTable(rows=out, _max_rows=self._max_rows)

	def distinct(self, *columns: str) -> "HTable":
		cols = [str(c) for c in columns] if columns else None
		seen: set[Any] = set()
		out: list[dict[str, Any]] = []
		for row in self.rows:
			if cols:
				key = tuple(row.get(c) for c in cols)
				payload = {c: row.get(c) for c in cols}
			else:
				key = tuple(sorted((str(k), sanitize_jsonish(v)) for k, v in row.items()))
				payload = dict(row)
			if key in seen:
				continue
			seen.add(key)
			out.append(payload)
			if len(out) >= self._max_rows:
				raise ResourceLimitErrorHS(f"تعداد ردیف جدول از سقف {self._max_rows} بیشتر شد")
		return HTable(rows=out, _max_rows=self._max_rows)

	def join(
		self,
		other: Any,
		*,
		left_on: str,
		right_on: Optional[str] = None,
		how: str = "inner",
		prefix: Optional[str] = None,
	) -> "HTable":
		if not isinstance(other, HTable):
			raise TypeErrorHS("join فقط با HTable مجاز است")
		how_s = str(how or "inner").lower()
		if how_s not in {"inner", "left"}:
			raise TypeErrorHS("how باید inner یا left باشد")
		lkey = str(left_on)
		rkey = str(right_on or left_on)
		pfx = str(prefix) if prefix else ""
		index: dict[Any, list[dict[str, Any]]] = {}
		for r in other.rows:
			index.setdefault(r.get(rkey), []).append(r)
		out: list[dict[str, Any]] = []
		for left in self.rows:
			matches = index.get(left.get(lkey), [])
			if not matches:
				if how_s == "left":
					merged = dict(left)
					out.append(merged)
					if len(out) >= self._max_rows:
						raise ResourceLimitErrorHS(f"تعداد ردیف جدول از سقف {self._max_rows} بیشتر شد")
				continue
			for right in matches:
				merged = dict(left)
				for rk, rv in right.items():
					mk = f"{pfx}{rk}" if pfx else str(rk)
					if mk in merged and mk != rkey:
						mk = f"right_{rk}"
					merged[mk] = rv
				out.append(merged)
				if len(out) >= self._max_rows:
					raise ResourceLimitErrorHS(f"تعداد ردیف جدول از سقف {self._max_rows} بیشتر شد")
		return HTable(rows=out, _max_rows=self._max_rows)

	def pivot(
		self,
		*,
		index: str,
		columns: str,
		values: str,
		agg: str = "sum",
	) -> "HTable":
		agg_s = str(agg or "sum").lower()
		if agg_s not in {"sum", "count", "avg"}:
			raise TypeErrorHS("agg باید sum یا count یا avg باشد")
		idx_f = str(index)
		col_f = str(columns)
		val_f = str(values)
		# {(index_val, col_val): [nums]}
		buckets: dict[tuple[Any, Any], list[float]] = {}
		col_values: set[Any] = set()
		for row in self.rows:
			iv = row.get(idx_f)
			cv = row.get(col_f)
			col_values.add(cv)
			raw = row.get(val_f)
			num = float(raw) if raw is not None and agg_s != "count" else (1.0 if agg_s == "count" else 0.0)
			if agg_s == "count":
				num = 1.0
			buckets.setdefault((iv, cv), []).append(num)
		sorted_cols = sorted(col_values, key=lambda x: (x is None, str(x)))
		out: list[dict[str, Any]] = []
		index_vals = []
		seen_idx: set[Any] = set()
		for (iv, _), _ in buckets.items():
			if iv in seen_idx:
				continue
			seen_idx.add(iv)
			index_vals.append(iv)
		for iv in index_vals:
			row: dict[str, Any] = {idx_f: iv}
			for cv in sorted_cols:
				nums = buckets.get((iv, cv), [])
				col_name = "null" if cv is None else str(cv)
				if not nums:
					row[col_name] = 0 if agg_s == "count" else 0.0
				elif agg_s == "sum" or agg_s == "count":
					row[col_name] = float(sum(nums)) if agg_s == "sum" else float(len(nums))
				else:
					row[col_name] = float(sum(nums) / len(nums))
			out.append(row)
			if len(out) >= self._max_rows:
				raise ResourceLimitErrorHS(f"تعداد ردیف جدول از سقف {self._max_rows} بیشتر شد")
		return HTable(rows=out, _max_rows=self._max_rows)

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
