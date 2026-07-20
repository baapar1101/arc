"""Schema میانی Report Spec — خروجی ساختاریافته اسکریپت."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any, Optional

from app.services.hscript.errors import ResourceLimitErrorHS, TypeErrorHS
from app.services.hscript.values import HTable, sanitize_jsonish
from app.services.hscript.dates import format_date_value, normalize_calendar
from app.services.hscript.number_format import normalize_number_format_options, parse_format_spec

ALLOWED_BLOCK_TYPES = frozenset({
	"title",
	"heading",
	"paragraph",
	"text",
	"kpi",
	"card",
	"table",
	"chart",
	"section",
	"page_break",
	"row_break",
	"image",
	"qr",
	"barcode",
	"timeline",
	"gauge",
})

ALLOWED_CHART_TYPES = frozenset({
	"bar",
	"line",
	"pie",
	"area",
	"scatter",
	"gauge",
})


@dataclass
class ReportBuilder:
	"""API میزبان report.* برای ساخت Spec."""

	max_blocks: int = 200
	max_output_bytes: int = 2_000_000
	title_text: Optional[str] = None
	layout: str = "document"
	blocks: list[dict[str, Any]] = field(default_factory=list)
	meta: dict[str, Any] = field(default_factory=dict)

	def title(self, text: str) -> None:
		self.title_text = str(text)[:500]
		self.blocks.append({"type": "title", "text": self.title_text})

	def heading(self, text: str, *, level: int = 2) -> None:
		lvl = int(level)
		if lvl < 1 or lvl > 6:
			raise TypeErrorHS("level باید بین ۱ تا ۶ باشد")
		self._add({"type": "heading", "text": str(text)[:500], "level": lvl})

	def paragraph(self, text: str) -> None:
		self._add({"type": "text", "text": str(text)[:5000]})

	def text(self, content: str) -> None:
		self.paragraph(content)

	def kpi(self, label: str, value: Any, *, format: str = "number", hint: str | None = None, span: int | None = None) -> None:
		fmt = str(format)[:32]
		# اعتبارسنجی زودهنگام
		parse_format_spec(fmt)
		block = {
			"type": "kpi",
			"label": str(label)[:200],
			"value": sanitize_jsonish(value),
			"format": fmt,
			"hint": (str(hint)[:200] if hint is not None else None),
		}
		self._apply_span(block, span)
		self._add(block)

	def card(self, title: str, value: Any, *, subtitle: str | None = None, span: int | None = None) -> None:
		block = {
			"type": "card",
			"title": str(title)[:200],
			"value": sanitize_jsonish(value),
			"subtitle": (str(subtitle)[:200] if subtitle is not None else None),
		}
		self._apply_span(block, span)
		self._add(block)

	def table(
		self,
		data: Any,
		*,
		columns: list[str] | None = None,
		title: str | None = None,
		span: int | None = None,
		formats: dict[str, Any] | None = None,
	) -> None:
		rows = self._normalize_rows(data)
		cols = columns
		if cols is None and rows:
			cols = list(rows[0].keys())
		cols = [str(c) for c in (cols or [])][:50]
		trimmed = [{c: r.get(c) for c in cols} for r in rows]
		cal = self.meta.get("calendar_type")
		if cal in ("jalali", "gregorian"):
			trimmed = [
				{c: format_date_value(r.get(c), cal) for c in cols}
				for r in trimmed
			]
		block: dict[str, Any] = {"type": "table", "columns": cols, "rows": trimmed}
		if title:
			block["title"] = str(title)[:200]
		if formats:
			if not isinstance(formats, dict):
				raise TypeErrorHS("formats جدول باید dict باشد")
			clean_fmt: dict[str, str] = {}
			for k, v in list(formats.items())[:50]:
				key = str(k)[:64]
				spec = str(v)[:32]
				parse_format_spec(spec)
				clean_fmt[key] = spec
			if clean_fmt:
				block["formats"] = clean_fmt
		self._apply_span(block, span)
		self._add(block)

	def bar_chart(self, data: Any, *, x: str, y: str, title: str | None = None, span: int | None = None) -> None:
		self._chart("bar", data, x=x, y=y, title=title, span=span)

	def line_chart(self, data: Any, *, x: str, y: str, title: str | None = None, span: int | None = None) -> None:
		self._chart("line", data, x=x, y=y, title=title, span=span)

	def pie_chart(
		self,
		data: Any,
		*,
		label: str,
		value: str,
		title: str | None = None,
		span: int | None = None,
	) -> None:
		rows = self._normalize_rows(data)
		points = [{"label": r.get(label), "value": r.get(value)} for r in rows]
		block: dict[str, Any] = {"type": "chart", "chart_type": "pie", "data": points}
		if title:
			block["title"] = str(title)[:200]
		self._apply_span(block, span)
		self._add(block)

	def area_chart(self, data: Any, *, x: str, y: str, title: str | None = None, span: int | None = None) -> None:
		self._chart("area", data, x=x, y=y, title=title, span=span)

	def scatter_chart(self, data: Any, *, x: str, y: str, title: str | None = None, span: int | None = None) -> None:
		self._chart("scatter", data, x=x, y=y, title=title, span=span)

	def gauge(
		self,
		value: Any,
		*,
		min: float = 0,
		max: float = 100,
		label: str | None = None,
		span: int | None = None,
	) -> None:
		block = {
			"type": "gauge",
			"value": sanitize_jsonish(value),
			"min": float(min),
			"max": float(max),
			"label": (str(label)[:200] if label else None),
		}
		self._apply_span(block, span)
		self._add(block)

	def section(self, title: str) -> None:
		self._add({"type": "section", "title": str(title)[:200]})

	def page_break(self) -> None:
		self._add({"type": "page_break"})

	def row_break(self) -> None:
		"""پایان ردیف در layout داشبورد (grid 12 ستونه)."""
		self._add({"type": "row_break"})

	def qr(self, data: str, *, label: str | None = None) -> None:
		payload = str(data)[:2000]
		self._add({"type": "qr", "data": payload, "label": (str(label)[:200] if label else None)})

	def barcode(self, data: str, *, format: str = "code128", label: str | None = None) -> None:
		self._add({
			"type": "barcode",
			"data": str(data)[:500],
			"format": str(format)[:32],
			"label": (str(label)[:200] if label else None),
		})

	def dashboard(self, *, columns: int = 12) -> None:
		self.layout = "dashboard"
		cols = int(columns)
		if cols not in (6, 12, 24):
			raise TypeErrorHS("columns داشبورد باید 6، 12 یا 24 باشد")
		self.meta["dashboard_columns"] = cols

	def calendar(self, calendar_type: str = "jalali") -> None:
		"""تنظیم تقویم نمایش تاریخ‌ها در Spec: jalali یا gregorian."""
		cal = normalize_calendar(calendar_type, default="jalali")
		self.meta["calendar_type"] = cal

	def number_format(
		self,
		*,
		style: str = "western",
		thousands_sep: str | None = None,
		decimal_sep: str | None = None,
	) -> None:
		"""
		تنظیم پیش‌فرض جداکننده هزارگان/اعشار برای کل گزارش.
		style: western (1,234.56) یا fa (۱٬۲۳۴٫۵۶ با ارقام لاتین و جداکننده فارسی)
		"""
		opts: dict[str, Any] = {"style": style}
		if thousands_sep is not None:
			opts["thousands_sep"] = thousands_sep
		if decimal_sep is not None:
			opts["decimal_sep"] = decimal_sep
		self.meta["number_format"] = normalize_number_format_options(opts)

	def set_meta(self, **kwargs: Any) -> None:
		for k, v in kwargs.items():
			if str(k).startswith("_"):
				continue
			key = str(k)[:64]
			if key == "calendar_type":
				self.meta[key] = normalize_calendar(v, default="jalali")
			else:
				self.meta[key] = sanitize_jsonish(v)

	def to_spec(self) -> dict[str, Any]:
		spec = {
			"version": 1,
			"layout": self.layout,
			"title": self.title_text,
			"meta": sanitize_jsonish(self.meta),
			"blocks": self.blocks,
		}
		raw = json.dumps(spec, ensure_ascii=False, default=str)
		if len(raw.encode("utf-8")) > self.max_output_bytes:
			raise ResourceLimitErrorHS("حجم خروجی گزارش بیش از حد مجاز است")
		return spec

	# --- internals ---

	def _apply_span(self, block: dict[str, Any], span: int | None) -> None:
		if span is None:
			return
		s = int(span)
		if s < 1 or s > 24:
			raise TypeErrorHS("span باید بین ۱ تا ۲۴ باشد")
		block["span"] = s

	def _add(self, block: dict[str, Any]) -> None:
		if block.get("type") not in ALLOWED_BLOCK_TYPES:
			raise TypeErrorHS(f"نوع بلوک غیرمجاز: {block.get('type')}")
		if len(self.blocks) >= self.max_blocks:
			raise ResourceLimitErrorHS("تعداد بلوک‌های گزارش بیش از حد است")
		self.blocks.append(block)

	def _chart(
		self,
		chart_type: str,
		data: Any,
		*,
		x: str,
		y: str,
		title: str | None,
		span: int | None = None,
	) -> None:
		if chart_type not in ALLOWED_CHART_TYPES:
			raise TypeErrorHS(f"نوع نمودار غیرمجاز: {chart_type}")
		rows = self._normalize_rows(data)
		points = [{"x": r.get(x), "y": r.get(y)} for r in rows]
		block: dict[str, Any] = {"type": "chart", "chart_type": chart_type, "data": points}
		if title:
			block["title"] = str(title)[:200]
		self._apply_span(block, span)
		self._add(block)

	def _normalize_rows(self, data: Any) -> list[dict[str, Any]]:
		if isinstance(data, HTable):
			return data.to_plain()
		if isinstance(data, list):
			out: list[dict[str, Any]] = []
			for item in data:
				if not isinstance(item, dict):
					raise TypeErrorHS("ردیف جدول/نمودار باید dict باشد")
				out.append({str(k): sanitize_jsonish(v) for k, v in item.items()})
			return out
		raise TypeErrorHS("داده جدول/نمودار باید Table یا list[dict] باشد")
