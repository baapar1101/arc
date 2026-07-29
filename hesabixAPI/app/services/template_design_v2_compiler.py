from __future__ import annotations

import html
import re
from typing import Any, Dict, List, Tuple

from app.services.report_template_gallery import get_family, is_v2_design


def _esc(s: Any) -> str:
	return html.escape("" if s is None else str(s))


def _color(value: Any, fallback: str) -> str:
	s = str(value or "").strip()
	if re.fullmatch(r"#[0-9a-fA-F]{3,8}", s):
		return s
	return fallback


def _visible_columns(columns: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
	out: List[Dict[str, Any]] = []
	for col in columns or []:
		if not isinstance(col, dict):
			continue
		if col.get("visible", True) is False:
			continue
		out.append(col)
	return out


def _cell_expr(col: Dict[str, Any]) -> str:
	key = _esc(col.get("key") or "")
	fmt = str(col.get("format") or "").lower()
	if fmt == "money":
		return f"{{{{ row.{key}|money }}}}"
	if fmt == "date":
		return f"{{{{ row.{key}|date }}}}"
	return f"{{{{ row.{key} }}}}"


def _total_expr(row: Dict[str, Any]) -> str:
	expr = str(row.get("expr") or "").strip()
	fmt = str(row.get("format") or "").lower()
	if not expr:
		return '""'
	if fmt == "money":
		return f"{{{{ {expr}|money }}}}"
	if fmt == "date":
		return f"{{{{ {expr}|date }}}}"
	return f"{{{{ {expr} }}}}"


def _theme_css(design: Dict[str, Any], family_id: str) -> str:
	theme = design.get("theme") or {}
	primary = _color(theme.get("primary_color"), "#1e3a5f")
	accent = _color(theme.get("accent_color"), "#366092")
	text = _color(theme.get("text_color"), "#212529")
	base_font = int(theme.get("font_size_base") or 11)
	compact = family_id == "invoice_compact"
	table_font = max(8, base_font - (2 if compact else 1))
	custom = str(design.get("custom_css") or "")
	return f"""
:root {{
  --rt-primary: {primary};
  --rt-accent: {accent};
  --rt-text: {text};
  --rt-base: {base_font}px;
  --rt-table: {table_font}px;
}}
.rt-layout {{
  font-size: var(--rt-base);
  color: var(--rt-text);
  line-height: 1.5;
}}
.rt-card {{
  border: 1px solid #d1d5db;
  border-radius: 8px;
  padding: 10px 12px;
  margin-bottom: 10px;
  background: #fff;
  page-break-inside: avoid;
}}
.rt-card.table-card {{
  page-break-inside: auto;
}}
.rt-header-band {{
  background: linear-gradient(135deg, var(--rt-primary), var(--rt-accent));
  color: #fff;
  border-radius: 10px;
  padding: 14px 16px;
  margin-bottom: 12px;
}}
.rt-header-band .rt-title {{
  font-size: calc(var(--rt-base) + 6px);
  font-weight: 700;
  margin: 0;
}}
.rt-header-band .rt-subtitle {{
  opacity: 0.92;
  margin-top: 4px;
  font-size: calc(var(--rt-base) - 1px);
}}
.rt-classic-header {{
  border-bottom: 2px solid var(--rt-primary);
  padding-bottom: 10px;
  margin-bottom: 12px;
}}
.rt-classic-header .rt-title {{
  color: var(--rt-primary);
  font-size: calc(var(--rt-base) + 5px);
  font-weight: 700;
  margin: 0;
}}
.rt-meta-row {{
  display: flex;
  flex-wrap: wrap;
  gap: 12px 24px;
  margin-top: 8px;
  font-size: calc(var(--rt-base) - 1px);
}}
.rt-meta-item strong {{
  color: var(--rt-primary);
  margin-inline-end: 4px;
}}
.rt-parties {{
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
}}
.rt-party {{
  flex: 1;
  min-width: 42%;
}}
.rt-party h4 {{
  margin: 0 0 6px 0;
  font-size: calc(var(--rt-base) + 1px);
  color: var(--rt-primary);
}}
.rt-table {{
  width: 100%;
  border-collapse: collapse;
  font-size: var(--rt-table);
}}
.rt-table th, .rt-table td {{
  border: 1px solid #cbd5e1;
  padding: 5px 6px;
  vertical-align: top;
}}
.rt-table thead th {{
  background: var(--rt-primary);
  color: #fff;
  font-weight: 600;
}}
.rt-table.striped tbody tr:nth-child(even) {{
  background: #f8fafc;
}}
.rt-table .num {{
  text-align: left;
  direction: ltr;
  unicode-bidi: plaintext;
  font-variant-numeric: tabular-nums;
}}
.rt-totals {{
  width: 100%;
  max-width: 320px;
  margin-inline-start: auto;
  border-collapse: collapse;
  font-size: var(--rt-base);
}}
.rt-totals td {{
  padding: 5px 8px;
  border-bottom: 1px solid #e2e8f0;
}}
.rt-totals td:last-child {{
  text-align: left;
  direction: ltr;
}}
.rt-totals tr.emphasis td {{
  font-weight: 700;
  color: var(--rt-primary);
  border-top: 2px solid var(--rt-primary);
}}
.rt-signatures {{
  display: flex;
  gap: 16px;
  margin-top: 16px;
}}
.rt-sig-box {{
  flex: 1;
  border: 1px dashed #94a3b8;
  border-radius: 8px;
  min-height: 72px;
}}
.rt-sig-label {{
  text-align: center;
  font-size: calc(var(--rt-base) - 2px);
  margin-top: 6px;
  color: #64748b;
}}
.rt-footer-note {{
  margin-top: 12px;
  padding: 10px;
  background: #fffbeb;
  border-inline-start: 4px solid #f59e0b;
  border-radius: 4px;
  font-size: calc(var(--rt-base) - 1px);
}}
.rt-qr-wrap {{
  text-align: center;
  margin-top: 10px;
}}
.rt-logo {{
  max-height: 56px;
  max-width: 160px;
  object-fit: contain;
}}
{custom}
""".strip()


def _logo_src(design: Dict[str, Any]) -> str:
	branding = design.get("branding") or {}
	if not branding.get("show_logo", True):
		return ""
	source = str(branding.get("logo_source") or "business").lower()
	if source == "none":
		return ""
	if source == "custom":
		return str(branding.get("custom_logo_data_uri") or "")
	return "{{ business_logo_data_uri }}"


def _business_name_expr(design: Dict[str, Any]) -> str:
	branding = design.get("branding") or {}
	if not branding.get("show_business_name", True):
		return ""
	override = str(branding.get("business_name_override") or "").strip()
	if override:
		return _esc(override)
	return "{{ business_name }}"


def _compile_invoice_detail(design: Dict[str, Any]) -> Tuple[str, str, str, str]:
	family_id = str(design.get("family_id") or "invoice_classic")
	sections = design.get("sections") or {}
	table_cfg = design.get("table") or {}
	totals_cfg = design.get("totals") or {}
	items_var = str(table_cfg.get("items_var") or "lines")
	columns = _visible_columns(list(table_cfg.get("columns") or []))
	striped = "striped" if table_cfg.get("striped", True) else ""
	css = _theme_css(design, family_id)
	logo_src = _logo_src(design)
	business_name = _business_name_expr(design)

	header_parts: List[str] = []
	if family_id == "invoice_modern":
		header_parts.append(
			f"""
<div class="rt-header-band">
  <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:12px;">
    <div>
      <h1 class="rt-title">{{{{ title_text | default('فاکتور') }}}}</h1>
      <div class="rt-subtitle">{{{{ invoice.code | default('-') }}}} — {{{{ invoice.issue_date | default('-') }}}}</div>
    </div>
    {"<img class='rt-logo' src='" + logo_src + "' alt='' />" if logo_src else ""}
  </div>
</div>
""".strip()
		)
	else:
		logo_html = f"<img class='rt-logo' src='{logo_src}' alt='' />" if logo_src else ""
		name_html = f"<div style='font-weight:700;font-size:14px;'>{business_name}</div>" if business_name else ""
		header_parts.append(
			f"""
<div class="rt-classic-header">
  <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:12px;">
    <div>
      <h1 class="rt-title">{{{{ title_text | default('فاکتور') }}}}</h1>
      {name_html}
    </div>
    {logo_html}
  </div>
  <div class="rt-meta-row">
    <div class="rt-meta-item"><strong>کد:</strong> {{{{ invoice.code | default('-') }}}}</div>
    <div class="rt-meta-item"><strong>تاریخ:</strong> {{{{ invoice.issue_date | default(invoice_date_jalali | default('-')) }}}}</div>
  </div>
</div>
""".strip()
		)

	body_parts: List[str] = []
	if sections.get("show_seller_info", True) or sections.get("show_buyer_info", True):
		party_cols: List[str] = []
		if sections.get("show_seller_info", True):
			party_cols.append(
				"""
<div class="rt-party">
  <h4>فروشنده</h4>
  <div>{{ seller.name | default(business_name | default('-')) }}</div>
</div>
""".strip()
			)
		if sections.get("show_buyer_info", True):
			party_cols.append(
				"""
<div class="rt-party">
  <h4>خریدار</h4>
  <div>{{ buyer.name | default('-') }}</div>
</div>
""".strip()
			)
		body_parts.append(f'<div class="rt-card"><div class="rt-parties">{"".join(party_cols)}</div></div>')

	if columns:
		headers = "".join(
			f"<th style='width:{_esc(col.get('width') or 'auto')};'>{_esc(col.get('title') or col.get('key') or '')}</th>"
			for col in columns
		)
		cells = "".join(f"<td class='num'>{_cell_expr(col)}</td>" for col in columns)
		body_parts.append(
			f"""
<div class="rt-card table-card">
  <table class="rt-table {striped}">
    <thead><tr>{headers}</tr></thead>
    <tbody>
      {{% for row in {items_var} %}}
      <tr>{cells}</tr>
      {{% endfor %}}
    </tbody>
  </table>
</div>
""".strip()
		)

	total_rows = [
		row
		for row in (totals_cfg.get("rows") or [])
		if isinstance(row, dict) and row.get("visible", True) is not False
	]
	if total_rows:
		rows_html = []
		for row in total_rows:
			emphasis = " class='emphasis'" if row.get("emphasis") else ""
			title = _esc(row.get("title") or "")
			val = _total_expr(row)
			rows_html.append(f"<tr{emphasis}><td>{title}</td><td>{val}</td></tr>")
		body_parts.append(
			f"""
<div class="rt-card">
  <table class="rt-totals"><tbody>{"".join(rows_html)}</tbody></table>
</div>
""".strip()
		)

	if sections.get("show_payments", True):
		body_parts.append(
			"""
{% if payments %}
<div class="rt-card">
  <h4 style="margin:0 0 6px 0;color:var(--rt-primary);">پرداخت‌ها</h4>
  <ul style="margin:0;padding-inline-start:18px;">
  {% for p in payments %}
    <li>{{ p.method_name | default('-') }} — {{ p.amount | money }}</li>
  {% endfor %}
  </ul>
</div>
{% endif %}
""".strip()
		)

	if sections.get("show_footer_note", True):
		body_parts.append(
			"""
{% if invoice_footer_note %}
<div class="rt-footer-note">{{ invoice_footer_note }}</div>
{% endif %}
""".strip()
		)

	if sections.get("show_signatures", True):
		sig_cols: List[str] = []
		if sections.get("show_seller_signature", True):
			sig_cols.append('<div style="flex:1;"><div class="rt-sig-box"></div><div class="rt-sig-label">امضای فروشنده</div></div>')
		if sections.get("show_buyer_signature", True):
			sig_cols.append('<div style="flex:1;"><div class="rt-sig-box"></div><div class="rt-sig-label">امضای خریدار</div></div>')
		if sig_cols:
			body_parts.append(f'<div class="rt-signatures">{"".join(sig_cols)}</div>')

	if sections.get("show_qr", False):
		body_parts.append(
			"""
{% if show_invoice_verify_qr and invoice_verify_qr_data_uri %}
<div class="rt-qr-wrap">
  <img src="{{ invoice_verify_qr_data_uri }}" width="120" height="120" alt="QR" />
</div>
{% endif %}
""".strip()
		)

	footer_parts: List[str] = []
	if sections.get("show_print_time", True) or sections.get("show_preparer", True):
		footer_bits: List[str] = []
		if sections.get("show_print_time", True):
			footer_bits.append("{{ generated_at }}")
		if sections.get("show_preparer", True):
			footer_bits.append("{{ issuer_name | default('') }}")
		footer_parts.append(
			f"""
<div style="font-size:10px;color:#64748b;text-align:center;margin-top:8px;">
  {" — ".join(footer_bits)}
</div>
""".strip()
		)

	body_html = f'<div class="rt-layout">{"".join(body_parts)}</div>'
	header_html = "".join(header_parts)
	footer_html = "".join(footer_parts)
	html_doc = f"<!doctype html><html><head></head><body>{body_html}</body></html>"
	return html_doc, css, header_html, footer_html


def _is_modern_header(design: Dict[str, Any]) -> bool:
	family_id = str(design.get("family_id") or "")
	if str(design.get("header_style") or "").lower() == "modern":
		return True
	return family_id.endswith("_modern") or family_id == "invoice_modern"


def _compile_list_header(design: Dict[str, Any], *, default_title: str = "گزارش") -> str:
	sections = design.get("sections") or {}
	logo_src = _logo_src(design)
	business_name = _business_name_expr(design)
	if _is_modern_header(design):
		return f"""
<div class="rt-header-band">
  <h1 class="rt-title">{{{{ title_text | default('{_esc(default_title)}') }}}}</h1>
  {"<div class='rt-subtitle'>" + business_name + "</div>" if business_name else ""}
</div>
""".strip()
	logo_html = f"<img class='rt-logo' src='{logo_src}' alt='' />" if logo_src else ""
	name_html = f"<div>{business_name}</div>" if business_name else ""
	return f"""
<div class="rt-classic-header">
  <div style="display:flex;justify-content:space-between;align-items:center;">
    <h1 class="rt-title">{{{{ title_text | default('{_esc(default_title)}') }}}}</h1>
    {logo_html}
  </div>
  {name_html}
  {"<div class='rt-meta-item'><strong>تاریخ:</strong> {{ date_now }}</div>" if sections.get("show_date", True) else ""}
</div>
""".strip()


def _compile_table_block(table_cfg: Dict[str, Any]) -> str:
	items_var = str(table_cfg.get("items_var") or "items")
	columns = _visible_columns(list(table_cfg.get("columns") or []))
	striped = "striped" if table_cfg.get("striped", True) else ""
	if not columns:
		return ""
	headers = "".join(
		f"<th style='width:{_esc(col.get('width') or 'auto')};'>{_esc(col.get('title') or col.get('key') or '')}</th>"
		for col in columns
	)
	cells = "".join(f"<td class='num'>{_cell_expr(col)}</td>" for col in columns)
	return f"""
<div class="rt-card table-card">
  <table class="rt-table {striped}">
    <thead><tr>{headers}</tr></thead>
    <tbody>
      {{% for row in {items_var} %}}
      <tr>{cells}</tr>
      {{% endfor %}}
    </tbody>
  </table>
</div>
""".strip()


def _compile_totals_block(totals_cfg: Dict[str, Any]) -> str:
	total_rows = [
		row
		for row in (totals_cfg.get("rows") or [])
		if isinstance(row, dict) and row.get("visible", True) is not False
	]
	if not total_rows:
		return ""
	rows_html = []
	for row in total_rows:
		emphasis = " class='emphasis'" if row.get("emphasis") else ""
		title = _esc(row.get("title") or "")
		val = _total_expr(row)
		rows_html.append(f"<tr{emphasis}><td>{title}</td><td>{val}</td></tr>")
	return f"""
<div class="rt-card">
  <table class="rt-totals"><tbody>{"".join(rows_html)}</tbody></table>
</div>
""".strip()


def _compile_footer_bits(sections: Dict[str, Any]) -> str:
	footer_bits: List[str] = []
	if sections.get("show_print_time", True):
		footer_bits.append("{{ generated_at }}")
	if sections.get("show_preparer", True):
		footer_bits.append("{{ issuer_name | default(created_by_name | default('')) }}")
	if not footer_bits:
		return ""
	return f"""
<div style="font-size:10px;color:#64748b;text-align:center;margin-top:8px;">
  {" — ".join(footer_bits)}
</div>
""".strip()


def _compile_generic_list(design: Dict[str, Any]) -> Tuple[str, str, str, str]:
	family_id = str(design.get("family_id") or "list_standard")
	table_cfg = design.get("table") or {}
	css = _theme_css(design, family_id)
	header_html = _compile_list_header(design)
	body_html = f'<div class="rt-layout">{_compile_table_block(table_cfg)}</div>'
	html_doc = f"<!doctype html><html><head></head><body>{body_html}</body></html>"
	return html_doc, css, header_html, ""


def _compile_document_detail(design: Dict[str, Any]) -> Tuple[str, str, str, str]:
	family_id = str(design.get("family_id") or "doc_detail_classic")
	sections = design.get("sections") or {}
	table_cfg = design.get("table") or {}
	totals_cfg = design.get("totals") or {}
	css = _theme_css(design, family_id)
	logo_src = _logo_src(design)
	business_name = _business_name_expr(design)
	logo_html = f"<img class='rt-logo' src='{logo_src}' alt='' />" if logo_src else ""
	name_html = f"<div style='font-weight:700;'>{business_name}</div>" if business_name else ""
	header_html = f"""
<div class="rt-classic-header">
  <div style="display:flex;justify-content:space-between;align-items:flex-start;">
    <div>
      <h1 class="rt-title">{{{{ title_text | default('سند حسابداری') }}}}</h1>
      {name_html}
    </div>
    {logo_html}
  </div>
  <div class="rt-meta-row">
    <div class="rt-meta-item"><strong>کد:</strong> {{{{ code | default(document.code | default('-')) }}}}</div>
    <div class="rt-meta-item"><strong>تاریخ:</strong> {{{{ document_date_display | default(document_date_jalali | default(document_date | default('-'))) }}}}</div>
    <div class="rt-meta-item"><strong>نوع:</strong> {{{{ document.document_type_name | default(document.document_type | default('-')) }}}}</div>
  </div>
</div>
""".strip()
	body_parts: List[str] = []
	if sections.get("show_description", True):
		body_parts.append("{% if description %}<div class='rt-card'>{{ description }}</div>{% endif %}")
	body_parts.append(_compile_table_block(table_cfg))
	if sections.get("show_totals_row", True):
		body_parts.append(_compile_totals_block(totals_cfg))
	body_html = f'<div class="rt-layout">{"".join(body_parts)}</div>'
	footer_html = _compile_footer_bits(sections)
	html_doc = f"<!doctype html><html><head></head><body>{body_html}</body></html>"
	return html_doc, css, header_html, footer_html


def _compile_receipt_detail(design: Dict[str, Any]) -> Tuple[str, str, str, str]:
	family_id = str(design.get("family_id") or "rp_detail_classic")
	sections = design.get("sections") or {}
	table_cfg = design.get("table") or {}
	totals_cfg = design.get("totals") or {}
	css = _theme_css(design, family_id)
	header_html = """
<div class="rt-classic-header">
  <h1 class="rt-title">{{ title_text | default('رسید دریافت/پرداخت') }}</h1>
  <div class="rt-meta-row">
    <div class="rt-meta-item"><strong>کد:</strong> {{ code | default('-') }}</div>
    <div class="rt-meta-item"><strong>تاریخ:</strong> {{ document_date | default('-') }}</div>
  </div>
</div>
""".strip()
	body_parts: List[str] = []
	if sections.get("show_description", True):
		body_parts.append("{% if description %}<div class='rt-card'>{{ description }}</div>{% endif %}")
	if sections.get("show_person_lines", True):
		body_parts.append("""
{% if person_lines %}
<div class="rt-card">
  <h4 style="margin:0 0 6px 0;color:var(--rt-primary);">اشخاص</h4>
  <ul style="margin:0;padding-inline-start:18px;">
  {% for p in person_lines %}
    <li>{{ p.person_name | default(p.name | default('-')) }} — {{ p.amount | money }}</li>
  {% endfor %}
  </ul>
</div>
{% endif %}
""".strip())
	if sections.get("show_account_lines", True):
		body_parts.append(_compile_table_block(table_cfg))
	if sections.get("show_total", True):
		body_parts.append(_compile_totals_block(totals_cfg))
	body_html = f'<div class="rt-layout">{"".join(body_parts)}</div>'
	footer_html = _compile_footer_bits(sections)
	html_doc = f"<!doctype html><html><head></head><body>{body_html}</body></html>"
	return html_doc, css, header_html, footer_html


def _compile_transfer_detail(design: Dict[str, Any]) -> Tuple[str, str, str, str]:
	family_id = str(design.get("family_id") or "transfer_detail_classic")
	sections = design.get("sections") or {}
	table_cfg = design.get("table") or {}
	totals_cfg = design.get("totals") or {}
	css = _theme_css(design, family_id)
	header_html = """
<div class="rt-classic-header">
  <h1 class="rt-title">{{ title_text | default('سند انتقال') }}</h1>
  <div class="rt-meta-row">
    <div class="rt-meta-item"><strong>کد:</strong> {{ code | default('-') }}</div>
    <div class="rt-meta-item"><strong>تاریخ:</strong> {{ document_date | default('-') }}</div>
  </div>
</div>
""".strip()
	body_parts: List[str] = []
	if sections.get("show_source_dest", True):
		body_parts.append("""
<div class="rt-card">
  <div class="rt-parties">
    <div class="rt-party">
      <h4>مبدأ</h4>
      <div>{{ source_type_name | default('-') }} — {{ source_name | default('-') }}</div>
    </div>
    <div class="rt-party">
      <h4>مقصد</h4>
      <div>{{ destination_type_name | default('-') }} — {{ destination_name | default('-') }}</div>
    </div>
  </div>
</div>
""".strip())
	if sections.get("show_description", True):
		body_parts.append("{% if description %}<div class='rt-card'>{{ description }}</div>{% endif %}")
	if sections.get("show_account_lines", True):
		body_parts.append(_compile_table_block(table_cfg))
	if sections.get("show_total", True) or sections.get("show_commission", True):
		body_parts.append(_compile_totals_block(totals_cfg))
	body_html = f'<div class="rt-layout">{"".join(body_parts)}</div>'
	footer_html = _compile_footer_bits(sections)
	html_doc = f"<!doctype html><html><head></head><body>{body_html}</body></html>"
	return html_doc, css, header_html, footer_html


def _compile_postal_label(design: Dict[str, Any]) -> Tuple[str, str, str, str]:
	family_id = str(design.get("family_id") or "postal_label_classic")
	sections = design.get("sections") or {}
	meta = design.get("meta") or {}
	compact = bool(meta.get("compact"))
	css = _theme_css(design, family_id)
	if compact:
		css += "\n.rt-layout { font-size: 9px; }\n.rt-card { padding: 6px 8px; margin-bottom: 6px; }"
	logo_src = _logo_src(design)
	logo_html = f"<img class='rt-logo' src='{logo_src}' alt='' style='max-height:40px;' />" if logo_src else ""
	header_html = f"""
<div class="rt-classic-header">
  <div style="display:flex;justify-content:space-between;align-items:center;">
    <h1 class="rt-title">{{{{ label_title | default('برچسب پستی') }}}}</h1>
    {logo_html}
  </div>
  <div class="rt-meta-item"><strong>کد حواله:</strong> {{{{ document.code | default('-') }}}} — {{{{ direction_label | default('') }}}}</div>
</div>
""".strip()
	body_parts: List[str] = []
	if sections.get("show_sender", True):
		body_parts.append("""
<div class="rt-card">
  <h4>{{ sender_caption | default('فرستنده') }}</h4>
  <div>{{ sender.name | default('-') }}</div>
  <div>{{ sender.phone | default('') }}</div>
  <div>{{ sender.address | default('') }}</div>
</div>
""".strip())
	if sections.get("show_receiver", True):
		body_parts.append("""
<div class="rt-card">
  <h4>{{ receiver_caption | default('گیرنده') }}</h4>
  <div>{{ receiver.name | default('-') }}</div>
  <div>{{ receiver.phone | default('') }}</div>
  <div>{{ receiver.address | default('') }}</div>
  {% if show_warehouse and receiver.warehouse_name %}<div>انبار: {{ receiver.warehouse_name }}</div>{% endif %}
</div>
""".strip())
	if sections.get("show_delivery", True):
		body_parts.append("<div class='rt-card'>روش ارسال: {{ document.delivery_method_display | default('-') }}</div>")
	if sections.get("show_tracking", True):
		body_parts.append("{% if document.tracking_number %}<div class='rt-card'>پیگیری: {{ document.tracking_number }}</div>{% endif %}")
	if sections.get("show_lines", True):
		body_parts.append("{% if lines_summary %}<div class='rt-card'>{{ lines_summary }}</div>{% endif %}")
	body_html = f'<div class="rt-layout">{"".join(body_parts)}</div>'
	html_doc = f"<!doctype html><html><head></head><body>{body_html}</body></html>"
	return html_doc, css, header_html, ""


def _compile_invoice_list(design: Dict[str, Any]) -> Tuple[str, str, str, str]:
	return _compile_generic_list(design)


def compile_v2_design_to_jinja_html(design: Dict[str, Any]) -> Tuple[str, str, str, str]:
	if not is_v2_design(design):
		raise ValueError("Not a v2 design schema")
	family_id = str(design.get("family_id") or "")
	family = get_family(family_id)
	if not family:
		raise ValueError(f"Unknown template family: {family_id}")
	layout = str(design.get("layout") or family.layout or "").strip()
	compilers = {
		"invoice_detail": _compile_invoice_detail,
		"generic_list": _compile_generic_list,
		"document_detail": _compile_document_detail,
		"receipt_detail": _compile_receipt_detail,
		"transfer_detail": _compile_transfer_detail,
		"postal_label": _compile_postal_label,
	}
	fn = compilers.get(layout)
	if not fn:
		raise ValueError(f"Layout not supported by compiler: {layout}")
	return fn(design)
