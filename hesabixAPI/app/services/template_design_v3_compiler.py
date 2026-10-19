from __future__ import annotations

from copy import deepcopy
from typing import Any

from app.services import template_design_v2_compiler as v2
from app.services.report_template_gallery import get_family
from app.services.report_template_v3_service import is_v3_design


def _blocks(design: dict[str, Any], region: str) -> list[dict[str, Any]]:
	regions = design.get("regions") or {}
	return [
		block
		for block in (regions.get(region) or [])
		if isinstance(block, dict) and block.get("visible", True) is not False
	]


def _block_by_type(design: dict[str, Any], block_type: str) -> dict[str, Any] | None:
	for region in ("header", "body", "footer"):
		for block in _blocks(design, region):
			if str(block.get("type") or "") == block_type:
				return block
	return None


def _v2_projection(design: dict[str, Any]) -> dict[str, Any]:
	lines = _block_by_type(design, "invoice_lines") or {}
	totals = _block_by_type(design, "invoice_totals") or {}
	return {
		"schema_version": 2,
		"family_id": design.get("family_id"),
		"layout": design.get("layout"),
		"theme": deepcopy(design.get("theme") or {}),
		"branding": deepcopy(design.get("branding") or {}),
		"custom_css": str(design.get("custom_css") or ""),
		"sections": {},
		"table": deepcopy(lines.get("props") or {}),
		"totals": deepcopy(totals.get("props") or {}),
	}


def _header_block(design: dict[str, Any], *, receipt: bool) -> str:
	family_id = str(design.get("family_id") or "")
	logo_html = v2._logo_html(design, style="max-height:28px;max-width:72px;" if receipt else "")
	business_name = v2._business_name_expr(design)
	if receipt:
		return f"""
<div class="rt-receipt">
  {logo_html}
  {f'<div class="rt-receipt-biz">{business_name}</div>' if business_name else ''}
  <div class="rt-receipt-title">{{{{ title_text | default('فاکتور') }}}}</div>
  <div class="rt-receipt-meta"><strong>{{{{ invoice.code | default('-') }}}}</strong> — {v2._jinja_first_of("invoice.issue_date", "invoice_date_jalali")}</div>
</div>
<hr class="rt-rule" />
""".strip()
	if family_id == "invoice_modern":
		return f"""
<div class="rt-header-band">
  <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:12px;">
    <div>
      <h1 class="rt-title">{{{{ title_text | default('فاکتور') }}}}</h1>
      <div class="rt-subtitle">{{{{ invoice.code | default('-') }}}} — {v2._jinja_first_of("invoice.issue_date", "invoice_date_jalali")}</div>
    </div>
    {logo_html}
  </div>
</div>
""".strip()
	name_html = f"<div style='font-weight:700;font-size:14px;'>{business_name}</div>" if business_name else ""
	return f"""
<div class="rt-classic-header">
  <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:12px;">
    <div><h1 class="rt-title">{{{{ title_text | default('فاکتور') }}}}</h1>{name_html}</div>
    {logo_html}
  </div>
  <div class="rt-meta-row">
    <div class="rt-meta-item"><strong>کد:</strong> {{{{ invoice.code | default('-') }}}}</div>
    <div class="rt-meta-item"><strong>تاریخ:</strong> {v2._jinja_first_of("invoice.issue_date", "invoice_date_jalali")}</div>
  </div>
</div>
""".strip()


def _party_block(props: dict[str, Any], *, receipt: bool) -> str:
	role = str(props.get("role") or "buyer")
	title = v2._esc(props.get("title") or ("فروشنده" if role == "seller" else "خریدار"))
	expr = v2._jinja_first_of("seller.name", "business_name") if role == "seller" else "{{ buyer.name | default('-') }}"
	if receipt:
		return f'<div class="rt-buyer"><strong>{title}:</strong> {expr}</div>'
	return f'<div class="rt-card"><div class="rt-party"><h4>{title}</h4><div>{expr}</div></div></div>'


def _detail_lines(props: dict[str, Any]) -> str:
	items_var = str(props.get("items_var") or "lines")
	columns = v2._visible_columns(list(props.get("columns") or []))
	if not columns:
		return ""
	striped = "striped" if props.get("striped", True) else ""
	headers = "".join(
		v2._wrap_if_flag(
			v2._column_display_flag(column),
			f"<th style='width:{v2._esc(column.get('width') or 'auto')};'>{v2._esc(column.get('title') or column.get('key') or '')}</th>",
		)
		for column in columns
	)
	cells = "".join(
		v2._wrap_if_flag(v2._column_display_flag(column), f"<td class='num'>{v2._cell_expr(column)}</td>")
		for column in columns
	)
	return f"""
<div class="rt-card table-card">
  <table class="rt-table {striped}">
    <thead><tr>{headers}</tr></thead>
    <tbody>{{% for row in {items_var} %}}<tr>{cells}</tr>{{% endfor %}}</tbody>
  </table>
</div>
""".strip()


def _receipt_cell(column: dict[str, Any], *, show_unit_price: bool) -> str:
	key = str(column.get("key") or "").strip()
	if key == "product_name":
		result = (
			"<div class='rt-item-name'>"
			"{% if row.product_code is defined and row.product_code %}{{ row.product_code }} — {% endif %}"
			"{{ row.product_name | default('-') }}</div>"
			"{% if row.description is defined and row.description %}<div class='rt-item-meta'>{{ row.description }}</div>{% endif %}"
		)
		if show_unit_price:
			result += (
				"{% if row.unit_price is defined and row.unit_price %}<div class='rt-item-meta'>{{ row.unit_price | money }}"
				"{% if row.unit_display is defined and row.unit_display %} / {{ row.unit_display }}{% endif %}</div>{% endif %}"
			)
		return result
	if key in ("quantity", "quantity_display"):
		return "{{ row.quantity_display | default(row.quantity, true) }}"
	return v2._cell_expr(column)


def _receipt_lines(props: dict[str, Any]) -> str:
	items_var = str(props.get("items_var") or "lines")
	columns = v2._visible_columns(list(props.get("columns") or []))
	if not columns:
		return ""
	headers = "".join(
		v2._wrap_if_flag(
			v2._column_display_flag(column),
			f"<th style='width:{v2._esc(column.get('width') or 'auto')};'>{v2._esc(column.get('title') or column.get('key') or '')}</th>",
		)
		for column in columns
	)
	cells = "".join(
		v2._wrap_if_flag(
			v2._column_display_flag(column),
			f"<td>{_receipt_cell(column, show_unit_price=props.get('show_unit_price', True) is not False)}</td>",
		)
		for column in columns
	)
	return f"""
<table class="rt-receipt-items">
  <thead><tr>{headers}</tr></thead>
  <tbody>{{% for row in {items_var} %}}<tr>{cells}</tr>{{% endfor %}}</tbody>
</table>
""".strip()


def _totals_block(props: dict[str, Any], *, receipt: bool) -> str:
	rows = [
		row
		for row in (props.get("rows") or [])
		if isinstance(row, dict) and row.get("visible", True) is not False
	]
	if not rows:
		return ""
	rows_html: list[str] = []
	for row in rows:
		emphasis = " class='emphasis'" if row.get("emphasis") else ""
		title = v2._esc(row.get("title") or "")
		value = v2._total_expr(row)
		value_style = " style='text-align:end;font-weight:700;'" if receipt else ""
		row_html = f"<tr{emphasis}><td>{title}</td><td{value_style}>{value}</td></tr>"
		rows_html.append(v2._wrap_if_flag(v2._total_display_flag(row), row_html))
	table = f"<table class='rt-totals'><tbody>{''.join(rows_html)}</tbody></table>"
	return f"<hr class='rt-rule-solid' />{table}" if receipt else f"<div class='rt-card'>{table}</div>"


def _payments_block(*, receipt: bool) -> str:
	if receipt:
		return """
{% if payments is defined and payments %}<hr class="rt-rule" />
{% for p in payments %}<div class="rt-receipt-meta">{{ p.method_name | default('-') }} — {{ p.amount | money }}</div>{% endfor %}{% endif %}
""".strip()
	return """
{% if payments is defined and payments %}<div class="rt-card"><h4 style="margin:0 0 6px 0;color:var(--rt-primary);">پرداخت‌ها</h4>
<ul style="margin:0;padding-inline-start:18px;">{% for p in payments %}<li>{{ p.method_name | default('-') }} — {{ p.amount | money }}</li>{% endfor %}</ul></div>{% endif %}
""".strip()


def _compile_block_content(design: dict[str, Any], block: dict[str, Any], *, receipt: bool) -> str:
	block_type = str(block.get("type") or "")
	props = block.get("props") or {}
	if block_type == "brand_header":
		return _header_block(design, receipt=receipt)
	if block_type == "party_info":
		return _party_block(props, receipt=receipt)
	if block_type == "invoice_lines":
		return _receipt_lines(props) if receipt else _detail_lines(props)
	if block_type == "invoice_totals":
		return _totals_block(props, receipt=receipt)
	if block_type == "payments":
		return _payments_block(receipt=receipt)
	if block_type == "note":
		css_class = "rt-receipt-meta" if receipt else "rt-footer-note"
		prefix = '<hr class="rt-rule" />' if receipt else ""
		return f"{{% if invoice_footer_note is defined and invoice_footer_note %}}{prefix}<div class='{css_class}'>{{{{ invoice_footer_note }}}}</div>{{% endif %}}"
	if block_type == "signatures":
		parts: list[str] = []
		if props.get("show_seller", True):
			parts.append('<div style="flex:1;"><div class="rt-sig-box"></div><div class="rt-sig-label">امضای فروشنده</div></div>')
		if props.get("show_buyer", True):
			parts.append('<div style="flex:1;"><div class="rt-sig-box"></div><div class="rt-sig-label">امضای خریدار</div></div>')
		return f'<div class="rt-signatures">{"".join(parts)}</div>' if parts else ""
	if block_type == "qr":
		size = 64 if receipt else 120
		return f"""
{{% if show_invoice_verify_qr is defined and show_invoice_verify_qr and invoice_verify_qr_data_uri is defined and invoice_verify_qr_data_uri %}}
<div class="rt-qr-wrap"><img src="{{{{ invoice_verify_qr_data_uri }}}}" width="{size}" height="{size}" alt="QR" /></div>{{% endif %}}
""".strip()
	if block_type == "footer_meta":
		bits: list[str] = []
		if props.get("show_print_time", True):
			bits.append("{{ generated_at | default('') }}")
		if props.get("show_preparer", True):
			bits.append("{{ issuer_name | default('') }}")
		return f'<div class="rt-studio-footer-meta">{" — ".join(bits)}</div>' if bits else ""
	if block_type == "custom_text":
		return f'<div class="rt-custom-text">{v2._esc(props.get("text") or "")}</div>'
	if block_type == "divider":
		style = "dashed" if str(props.get("style") or "") == "dashed" else "solid"
		return f'<hr style="border:0;border-top:1px {style} #94a3b8;margin:8px 0;" />'
	if block_type == "spacer":
		try:
			height = max(4, min(80, int(props.get("height") or 12)))
		except Exception:
			height = 12
		return f'<div style="height:{height}px;"></div>'
	return ""


def _compile_block(design: dict[str, Any], block: dict[str, Any], *, receipt: bool) -> str:
	content = _compile_block_content(design, block, receipt=receipt)
	if not content:
		return ""
	style = block.get("style") or {}
	align = str(style.get("text_align") or "").strip().lower()
	if not align and str(block.get("type") or "") == "custom_text":
		align = str((block.get("props") or {}).get("align") or "").strip().lower()
	if align in ("right", "center", "left"):
		return f'<div class="rt-block rt-block-align-{align}">{content}</div>'
	return content


def compile_v3_design_to_jinja_html(design: dict[str, Any]) -> tuple[str, str, str, str]:
	if not is_v3_design(design):
		raise ValueError("Not a v3 design schema")
	family_id = str(design.get("family_id") or "")
	family = get_family(family_id)
	if not family:
		raise ValueError(f"Unknown template family: {family_id}")
	if family.layout not in ("invoice_detail", "invoice_receipt"):
		raise ValueError(f"Studio v3 does not support layout: {family.layout}")
	receipt = family.layout == "invoice_receipt"
	theme = design.get("theme") or {}
	direction = str(theme.get("direction") or "rtl").strip().lower()
	if direction not in ("rtl", "ltr"):
		direction = "rtl"

	projection = _v2_projection(design)
	if receipt:
		_, css, _, _ = v2._compile_invoice_receipt(projection)
	else:
		css = v2._theme_css(design, family_id)
	css += """
.rt-studio-footer-meta { font-size: 10px; color: #64748b; text-align: center; margin-top: 8px; }
.rt-custom-text { white-space: pre-wrap; margin: 6px 0; }
.rt-block-align-right, .rt-block-align-right * { text-align: right !important; }
.rt-block-align-center, .rt-block-align-center * { text-align: center !important; }
.rt-block-align-left, .rt-block-align-left * { text-align: left !important; }
"""
	header_html = "".join(_compile_block(design, block, receipt=receipt) for block in _blocks(design, "header"))
	body = "".join(_compile_block(design, block, receipt=receipt) for block in _blocks(design, "body"))
	footer_html = "".join(_compile_block(design, block, receipt=receipt) for block in _blocks(design, "footer"))
	body_html = f'<div class="rt-layout">{body}</div>'
	html_doc = f'<!doctype html><html dir="{direction}"><head></head><body>{body_html}</body></html>'
	return html_doc, css.strip(), header_html, footer_html


def compile_template_design_to_jinja_html(design: dict[str, Any]) -> tuple[str, str, str, str]:
	if is_v3_design(design):
		return compile_v3_design_to_jinja_html(design)
	return v2.compile_v2_design_to_jinja_html(design)
