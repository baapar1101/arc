from __future__ import annotations

import re
from copy import deepcopy
from typing import Any

from jinja2 import BaseLoader, TemplateSyntaxError
from jinja2.sandbox import SandboxedEnvironment

from app.services.report_template_gallery import get_family, is_v2_design

_HEX_COLOR_RE = re.compile(r"^#[0-9a-fA-F]{3,8}$")
_ID_RE = re.compile(r"^[a-zA-Z0-9_-]{1,80}$")
_KEY_RE = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*$")


_BLOCKS: dict[str, dict[str, Any]] = {
	"brand_header": {
		"label_fa": "سربرگ و برند",
		"allowed_regions": ["header"],
		"max_instances": 1,
		"default_props": {},
	},
	"party_info": {
		"label_fa": "اطلاعات طرف حساب",
		"allowed_regions": ["body"],
		"max_instances": 2,
		"default_props": {"role": "buyer", "title": "خریدار"},
	},
	"invoice_lines": {
		"label_fa": "جدول اقلام",
		"allowed_regions": ["body"],
		"max_instances": 1,
		"required": True,
		"default_props": {},
	},
	"invoice_totals": {
		"label_fa": "جمع‌بندی مالی",
		"allowed_regions": ["body"],
		"max_instances": 1,
		"default_props": {},
	},
	"payments": {
		"label_fa": "پرداخت‌ها",
		"allowed_regions": ["body"],
		"max_instances": 1,
		"default_props": {},
	},
	"note": {
		"label_fa": "یادداشت فاکتور",
		"allowed_regions": ["body", "footer"],
		"max_instances": 1,
		"default_props": {},
	},
	"signatures": {
		"label_fa": "امضاها",
		"allowed_regions": ["body", "footer"],
		"max_instances": 1,
		"default_props": {"show_seller": True, "show_buyer": True},
	},
	"qr": {
		"label_fa": "کد QR",
		"allowed_regions": ["body", "footer"],
		"max_instances": 1,
		"default_props": {},
	},
	"footer_meta": {
		"label_fa": "اطلاعات چاپ",
		"allowed_regions": ["footer"],
		"max_instances": 1,
		"default_props": {"show_print_time": True, "show_preparer": True},
	},
	"custom_text": {
		"label_fa": "متن دلخواه",
		"allowed_regions": ["header", "body", "footer"],
		"default_props": {"text": "متن دلخواه"},
	},
	"divider": {
		"label_fa": "خط جداکننده",
		"allowed_regions": ["header", "body", "footer"],
		"default_props": {"style": "solid"},
	},
	"spacer": {
		"label_fa": "فاصله",
		"allowed_regions": ["header", "body", "footer"],
		"default_props": {"height": 12},
	},
}


def is_v3_design(design: dict[str, Any]) -> bool:
	try:
		return int(design.get("schema_version") or 0) == 3
	except Exception:
		return False


def studio_block_catalog(module_key: str, subtype: str | None) -> list[dict[str, Any]]:
	if module_key != "invoices" or (subtype or "") not in ("detail", "receipt"):
		return []
	return [
		{"type": block_type, **deepcopy(definition)}
		for block_type, definition in _BLOCKS.items()
	]


def _block(block_id: str, block_type: str, props: dict[str, Any] | None = None) -> dict[str, Any]:
	return {
		"id": block_id,
		"type": block_type,
		"visible": True,
		"props": deepcopy(props or {}),
		"style": {},
	}


def migrate_v2_design_to_v3(design: dict[str, Any]) -> dict[str, Any]:
	if is_v3_design(design):
		return deepcopy(design)
	if not is_v2_design(design):
		raise ValueError("Only template design v2 can be migrated to v3")

	family_id = str(design.get("family_id") or "")
	family = get_family(family_id)
	if not family:
		raise ValueError(f"Unknown template family: {family_id}")
	if family.layout not in ("invoice_detail", "invoice_receipt"):
		raise ValueError(f"Studio v3 does not support layout: {family.layout}")

	sections = design.get("sections") or {}
	header = [_block("brand-header", "brand_header")]
	body: list[dict[str, Any]] = []
	footer: list[dict[str, Any]] = []

	if sections.get("show_seller_info", family.layout == "invoice_detail"):
		body.append(_block("seller-info", "party_info", {"role": "seller", "title": "فروشنده"}))
	if sections.get("show_buyer_info", True):
		body.append(_block("buyer-info", "party_info", {"role": "buyer", "title": "خریدار"}))
	table_props = deepcopy(design.get("table") or {})
	table_props["show_unit_price"] = sections.get("show_unit_price", True)
	body.append(_block("invoice-lines", "invoice_lines", table_props))
	body.append(_block("invoice-totals", "invoice_totals", deepcopy(design.get("totals") or {})))
	if sections.get("show_payments", True):
		body.append(_block("payments", "payments"))
	if sections.get("show_footer_note", True):
		body.append(_block("invoice-note", "note"))
	if sections.get("show_signatures", family.layout == "invoice_detail"):
		body.append(
			_block(
				"signatures",
				"signatures",
				{
					"show_seller": sections.get("show_seller_signature", True),
					"show_buyer": sections.get("show_buyer_signature", True),
				},
			)
		)
	if sections.get("show_qr", False):
		body.append(_block("invoice-qr", "qr"))

	show_print_time = sections.get("show_print_time", True)
	show_preparer = sections.get("show_preparer", family.layout == "invoice_detail")
	if show_print_time or show_preparer:
		footer.append(
			_block(
				"footer-meta",
				"footer_meta",
				{"show_print_time": show_print_time, "show_preparer": show_preparer},
			)
		)

	theme = deepcopy(design.get("theme") or {})
	theme.setdefault("direction", "rtl")
	return {
		"schema_version": 3,
		"family_id": family_id,
		"layout": family.layout,
		"theme": theme,
		"branding": deepcopy(design.get("branding") or {}),
		"custom_css": str(design.get("custom_css") or ""),
		"regions": {"header": header, "body": body, "footer": footer},
	}


def validate_v3_design(
	module_key: str,
	subtype: str | None,
	design: dict[str, Any],
) -> dict[str, list[str]]:
	errors: list[str] = []
	warnings: list[str] = []
	if not isinstance(design, dict) or not is_v3_design(design):
		return {"errors": ["schema_version must be 3"], "warnings": []}

	family_id = str(design.get("family_id") or "").strip()
	family = get_family(family_id)
	if not family:
		return {"errors": [f"Unknown family_id: {family_id}"], "warnings": []}
	if family.module_key != module_key or (family.subtype or None) != (subtype or None):
		errors.append("family_id does not match template scope")
	if family.layout not in ("invoice_detail", "invoice_receipt"):
		errors.append("Studio v3 currently supports invoice detail and receipt layouts")

	theme = design.get("theme") or {}
	direction = str(theme.get("direction") or "rtl").strip().lower()
	if direction not in ("rtl", "ltr"):
		errors.append("Invalid theme.direction")
	for key in ("primary_color", "accent_color", "text_color"):
		value = str(theme.get(key) or "").strip()
		if value and not _HEX_COLOR_RE.fullmatch(value):
			errors.append(f"Invalid theme.{key}")

	regions = design.get("regions")
	if not isinstance(regions, dict):
		return {"errors": errors + ["regions must be an object"], "warnings": warnings}

	seen_ids: set[str] = set()
	counts: dict[str, int] = {}
	for region_name in ("header", "body", "footer"):
		blocks = regions.get(region_name) or []
		if not isinstance(blocks, list):
			errors.append(f"regions.{region_name} must be a list")
			continue
		for index, block in enumerate(blocks):
			if not isinstance(block, dict):
				errors.append(f"Invalid block in {region_name} at index {index}")
				continue
			block_id = str(block.get("id") or "").strip()
			block_type = str(block.get("type") or "").strip()
			definition = _BLOCKS.get(block_type)
			if not block_id or not _ID_RE.fullmatch(block_id):
				errors.append(f"Invalid block id in {region_name} at index {index}")
			elif block_id in seen_ids:
				errors.append(f"Duplicate block id: {block_id}")
			seen_ids.add(block_id)
			if not definition:
				errors.append(f"Unknown block type: {block_type}")
				continue
			if region_name not in definition["allowed_regions"]:
				errors.append(f"Block '{block_type}' is not allowed in region '{region_name}'")
			counts[block_type] = counts.get(block_type, 0) + 1

			props = block.get("props") or {}
			if not isinstance(props, dict):
				errors.append(f"Block '{block_id}' props must be an object")
				continue
			style = block.get("style") or {}
			if not isinstance(style, dict):
				errors.append(f"Block '{block_id}' style must be an object")
				continue
			text_align = str(style.get("text_align") or "").strip().lower()
			if text_align and text_align not in ("right", "center", "left"):
				errors.append(f"Invalid text alignment in block '{block_id}'")
			if block_type == "invoice_lines":
				items_var = str(props.get("items_var") or "lines")
				if not _KEY_RE.fullmatch(items_var):
					errors.append(f"Invalid invoice items variable: {items_var}")
				columns = props.get("columns") or []
				visible_columns = [c for c in columns if isinstance(c, dict) and c.get("visible", True) is not False]
				if not visible_columns:
					errors.append("Invoice lines must have at least one visible column")
				for column in visible_columns:
					key = str(column.get("key") or "")
					if not _KEY_RE.fullmatch(key):
						errors.append(f"Invalid invoice column key: {key}")
			if block_type == "party_info" and str(props.get("role") or "") not in ("seller", "buyer"):
				errors.append(f"Invalid party role in block '{block_id}'")
			if block_type == "invoice_totals":
				for row_index, row in enumerate(props.get("rows") or [], start=1):
					if not isinstance(row, dict) or row.get("visible", True) is False:
						continue
					expr = str(row.get("expr") or "").strip()
					if not expr:
						errors.append(f"Totals row {row_index} is missing expr")
						continue
					try:
						SandboxedEnvironment(loader=BaseLoader(), autoescape=True).from_string(f"{{{{ {expr} }}}}")
					except TemplateSyntaxError as ex:
						errors.append(f"Invalid totals expression in row {row_index}: {ex.message}")
			if block_type == "custom_text" and len(str(props.get("text") or "")) > 2000:
				errors.append(f"Custom text is too long in block '{block_id}'")

	for block_type, definition in _BLOCKS.items():
		count = counts.get(block_type, 0)
		max_instances = definition.get("max_instances")
		if max_instances is not None and count > int(max_instances):
			errors.append(f"Block '{block_type}' exceeds its maximum instances")
		if definition.get("required") and count == 0:
			errors.append(f"Required block is missing: {block_type}")

	try:
		from app.services.template_design_v3_compiler import compile_v3_design_to_jinja_html

		compile_v3_design_to_jinja_html(design)
	except Exception as ex:
		errors.append(f"Compile error: {ex}")
	return {"errors": errors, "warnings": warnings}
