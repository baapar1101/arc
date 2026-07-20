"""رندر امن Report Spec به HTML و PDF (بدون اجرای اسکریپت دوباره در قالب)."""

from __future__ import annotations

import html
import logging
from typing import Any, Optional

from app.services.hscript.errors import TypeErrorHS
from app.services.hscript.report_builder import ALLOWED_BLOCK_TYPES, ALLOWED_CHART_TYPES
from app.services.hscript.number_format import format_number


logger = logging.getLogger(__name__)


def _esc(value: Any) -> str:
	return html.escape("" if value is None else str(value), quote=True)


def _num_opts(spec: dict[str, Any]) -> dict[str, str]:
	meta = spec.get("meta") if isinstance(spec.get("meta"), dict) else {}
	nf = meta.get("number_format") if isinstance(meta.get("number_format"), dict) else {}
	return {
		"thousands_sep": str(nf.get("thousands_sep", ",") or ","),
		"decimal_sep": str(nf.get("decimal_sep", ".") or "."),
	}


def _format_value(value: Any, fmt: str | None = None, *, num_opts: dict[str, str] | None = None) -> str:
	if value is None:
		return "—"
	if fmt:
		try:
			opts = num_opts or {}
			return html.escape(
				format_number(
					value,
					fmt,
					thousands_sep=opts.get("thousands_sep", ","),
					decimal_sep=opts.get("decimal_sep", "."),
				),
				quote=True,
			)
		except Exception:
			return _esc(value)
	return _esc(value)


def spec_to_html(spec: dict[str, Any], *, business_name: str | None = None) -> str:
	"""تبدیل Spec ساختاریافته به HTML امن (escape کامل متن کاربر)."""
	if not isinstance(spec, dict):
		raise TypeErrorHS("spec باید dict باشد")
	blocks = spec.get("blocks") or []
	if not isinstance(blocks, list):
		raise TypeErrorHS("blocks نامعتبر است")

	title = spec.get("title") or "گزارش HScript"
	parts: list[str] = [
		"<!DOCTYPE html><html lang='fa' dir='rtl'><head><meta charset='utf-8'/>",
		"<style>",
		"@page { size: A4; margin: 16mm; }",
		"body { font-family: Vazirmatn, Tahoma, sans-serif; color: #1a1a1a; font-size: 12px; }",
		"h1 { font-size: 20px; margin: 0 0 12px; }",
		"h2 { font-size: 16px; margin: 18px 0 8px; }",
		".meta { color: #666; font-size: 11px; margin-bottom: 16px; }",
		".kpi-row { display: flex; flex-wrap: wrap; gap: 10px; margin: 12px 0; }",
		".kpi { border: 1px solid #ddd; border-radius: 8px; padding: 10px 14px; min-width: 140px; }",
		".kpi .label { color: #666; font-size: 11px; }",
		".kpi .value { font-size: 18px; font-weight: 700; margin-top: 4px; }",
		"table { width: 100%; border-collapse: collapse; margin: 10px 0 16px; }",
		"th, td { border: 1px solid #ddd; padding: 6px 8px; text-align: right; }",
		"th { background: #f5f5f5; }",
		".chart-box { border: 1px dashed #bbb; padding: 10px; margin: 10px 0; border-radius: 8px; }",
		".chart-bar { display: flex; align-items: center; gap: 8px; margin: 4px 0; }",
		".chart-bar .bar { height: 10px; background: #3b82f6; border-radius: 4px; }",
		".page-break { page-break-after: always; }",
		"p { margin: 6px 0 10px; line-height: 1.6; }",
		"</style></head><body>",
		f"<h1>{_esc(title)}</h1>",
	]
	if business_name:
		parts.append(f"<div class='meta'>{_esc(business_name)}</div>")

	num_opts = _num_opts(spec)
	for block in blocks:
		if not isinstance(block, dict):
			continue
		btype = str(block.get("type") or "")
		if btype not in ALLOWED_BLOCK_TYPES:
			continue
		parts.append(_render_block_html(block, num_opts=num_opts))

	parts.append("</body></html>")
	return "".join(parts)


def _render_block_html(block: dict[str, Any], *, num_opts: dict[str, str] | None = None) -> str:
	btype = str(block.get("type") or "")
	if btype == "title":
		# already rendered as doc title; skip duplicate or render as h1 if different
		return f"<h1>{_esc(block.get('text'))}</h1>"
	if btype == "heading":
		level = int(block.get("level") or 2)
		level = min(6, max(2, level))
		return f"<h{level}>{_esc(block.get('text'))}</h{level}>"
	if btype in ("paragraph", "text"):
		return f"<p>{_esc(block.get('text'))}</p>"
	if btype == "section":
		return f"<h2>{_esc(block.get('title'))}</h2>"
	if btype == "page_break":
		return "<div class='page-break'></div>"
	if btype == "row_break":
		return "<div style='clear:both;height:8px'></div>"
	if btype == "kpi":
		return (
			"<div class='kpi-row'><div class='kpi'>"
			f"<div class='label'>{_esc(block.get('label'))}</div>"
			f"<div class='value'>{_format_value(block.get('value'), block.get('format'), num_opts=num_opts)}</div>"
			"</div></div>"
		)
	if btype == "card":
		return (
			"<div class='kpi-row'><div class='kpi'>"
			f"<div class='label'>{_esc(block.get('title'))}</div>"
			f"<div class='value'>{_format_value(block.get('value'), num_opts=num_opts)}</div>"
			f"<div class='label'>{_esc(block.get('subtitle') or '')}</div>"
			"</div></div>"
		)
	if btype == "table":
		return _table_html(block, num_opts=num_opts)
	if btype == "chart":
		return _chart_html(block, num_opts=num_opts)
	if btype == "gauge":
		return (
			"<div class='chart-box'>"
			f"<strong>{_esc(block.get('label') or 'Gauge')}</strong>: "
			f"{_format_value(block.get('value'), 'number', num_opts=num_opts)} "
			f"(min {_format_value(block.get('min'), 'number', num_opts=num_opts)} / max {_format_value(block.get('max'), 'number', num_opts=num_opts)})"
			"</div>"
		)
	if btype in ("qr", "barcode"):
		return (
			f"<div class='chart-box'><strong>{_esc(btype.upper())}</strong>: "
			f"{_esc(block.get('data'))}"
			f"{(' — ' + _esc(block.get('label'))) if block.get('label') else ''}"
			"</div>"
		)
	if btype == "image":
		# عمداً URL خام رندر نمی‌کنیم (SSRF/XSS) — فقط برچسب
		return f"<div class='chart-box'>[تصویر: {_esc(block.get('alt') or block.get('label') or 'image')}]</div>"
	if btype == "timeline":
		return f"<div class='chart-box'>Timeline: {_esc(block.get('title') or '')}</div>"
	return ""


def _table_html(block: dict[str, Any], *, num_opts: dict[str, str] | None = None) -> str:
	cols = [str(c) for c in (block.get("columns") or [])][:50]
	rows = block.get("rows") or []
	if not isinstance(rows, list):
		rows = []
	formats = block.get("formats") if isinstance(block.get("formats"), dict) else {}
	title = block.get("title")
	out = []
	if title:
		out.append(f"<h2>{_esc(title)}</h2>")
	out.append("<table><thead><tr>")
	for c in cols:
		out.append(f"<th>{_esc(c)}</th>")
	out.append("</tr></thead><tbody>")
	for row in rows[:5000]:
		if not isinstance(row, dict):
			continue
		out.append("<tr>")
		for c in cols:
			fmt = formats.get(c) if formats else None
			out.append(f"<td>{_format_value(row.get(c), fmt, num_opts=num_opts)}</td>")
		out.append("</tr>")
	out.append("</tbody></table>")
	return "".join(out)


def _chart_html(block: dict[str, Any], *, num_opts: dict[str, str] | None = None) -> str:
	chart_type = str(block.get("chart_type") or "bar")
	if chart_type not in ALLOWED_CHART_TYPES:
		chart_type = "bar"
	title = block.get("title") or chart_type
	data = block.get("data") or []
	if not isinstance(data, list):
		data = []
	# برای PDF: نمایش میله‌ای ساده از مقادیر (بدون JS)
	nums: list[tuple[str, float]] = []
	for item in data[:100]:
		if not isinstance(item, dict):
			continue
		if "label" in item and "value" in item:
			label = str(item.get("label") or "")
			try:
				val = float(item.get("value") or 0)
			except Exception:
				val = 0.0
		else:
			label = str(item.get("x") or "")
			try:
				val = float(item.get("y") or 0)
			except Exception:
				val = 0.0
		nums.append((label, val))
	max_v = max((v for _, v in nums), default=1.0) or 1.0
	parts = [f"<div class='chart-box'><strong>{_esc(title)}</strong>"]
	for label, val in nums:
		width = max(2, int(180 * (val / max_v)))
		parts.append(
			"<div class='chart-bar'>"
			f"<span style='min-width:80px'>{_esc(label)}</span>"
			f"<span class='bar' style='width:{width}px'></span>"
			f"<span>{_format_value(val, 'number', num_opts=num_opts)}</span>"
			"</div>"
		)
	parts.append("</div>")
	return "".join(parts)


def render_spec_pdf(spec: dict[str, Any], *, business_name: str | None = None) -> bytes:
	"""HTML امن → PDF با WeasyPrint."""
	from weasyprint import HTML
	from weasyprint.text.fonts import FontConfiguration

	html_content = spec_to_html(spec, business_name=business_name)
	font_config = FontConfiguration()
	return HTML(string=html_content).write_pdf(font_config=font_config)
