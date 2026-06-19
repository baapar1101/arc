from __future__ import annotations

import re
from copy import deepcopy
from typing import Any, Dict, List, Optional

from jinja2 import BaseLoader, TemplateSyntaxError
from jinja2.sandbox import SandboxedEnvironment

from app.services.report_template_gallery import (
	default_design_for_family,
	default_family_for_scope,
	get_family,
	is_v2_design,
)


_HEX_COLOR_RE = re.compile(r"^#[0-9a-fA-F]{3,8}$")


def validate_v2_design(
	module_key: str,
	subtype: Optional[str],
	design: Dict[str, Any],
) -> Dict[str, List[str]]:
	errors: List[str] = []
	warnings: List[str] = []
	if not isinstance(design, dict):
		errors.append("design must be an object")
		return {"errors": errors, "warnings": warnings}
	if not is_v2_design(design):
		errors.append("schema_version must be 2")
		return {"errors": errors, "warnings": warnings}

	family_id = str(design.get("family_id") or "").strip()
	family = get_family(family_id)
	if not family:
		errors.append(f"Unknown family_id: {family_id}")
		return {"errors": errors, "warnings": warnings}
	layout = str(design.get("layout") or family.layout or "")
	if family.module_key != module_key:
		errors.append("family_id does not match module_key")
	if (family.subtype or None) != (subtype or None):
		errors.append("family_id does not match subtype")

	theme = design.get("theme") or {}
	for key in ("primary_color", "accent_color", "text_color"):
		val = str(theme.get(key) or "").strip()
		if val and not _HEX_COLOR_RE.fullmatch(val):
			errors.append(f"Invalid theme.{key}")

	try:
		base_font = int(theme.get("font_size_base") or 11)
		if base_font < 8 or base_font > 16:
			warnings.append("font_size_base is outside recommended range (8-16)")
	except Exception:
		errors.append("theme.font_size_base must be a number")

	table = design.get("table") or {}
	columns = table.get("columns") or []
	visible_cols = [c for c in columns if isinstance(c, dict) and c.get("visible", True) is not False]
	if layout != "postal_label":
		if not visible_cols:
			errors.append("At least one visible table column is required")

	items_var = str(table.get("items_var") or "").strip()
	if layout != "postal_label":
		if not items_var:
			errors.append("table.items_var is required")
		elif not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", items_var):
			errors.append("table.items_var must be a valid identifier")

	for idx, col in enumerate(visible_cols, start=1):
		key = str(col.get("key") or "").strip()
		if not key:
			errors.append(f"Column {idx} is missing key")

	if module_key == "invoices" and (subtype or "") == "detail":
		totals = (design.get("totals") or {}).get("rows") or []
		visible_totals = [r for r in totals if isinstance(r, dict) and r.get("visible", True) is not False]
		if not visible_totals:
			warnings.append("Invoice detail templates usually need at least one totals row")
		for idx, row in enumerate(visible_totals, start=1):
			expr = str(row.get("expr") or "").strip()
			if not expr:
				errors.append(f"Totals row {idx} is missing expr")
				continue
			try:
				SandboxedEnvironment(loader=BaseLoader(), autoescape=True).from_string(f"{{{{ {expr} }}}}")
			except TemplateSyntaxError as ex:
				errors.append(f"Invalid totals expression in row {idx}: {ex.message}")
	elif layout in ("document_detail", "receipt_detail", "transfer_detail"):
		totals = (design.get("totals") or {}).get("rows") or []
		for idx, row in enumerate(totals, start=1):
			if not isinstance(row, dict) or row.get("visible", True) is False:
				continue
			expr = str(row.get("expr") or "").strip()
			if not expr:
				continue
			try:
				SandboxedEnvironment(loader=BaseLoader(), autoescape=True).from_string(f"{{{{ {expr} }}}}")
			except TemplateSyntaxError as ex:
				errors.append(f"Invalid totals expression in row {idx}: {ex.message}")

	try:
		from app.services.template_design_v2_compiler import compile_v2_design_to_jinja_html

		compile_v2_design_to_jinja_html(design)
	except Exception as ex:
		errors.append(f"Compile error: {ex}")

	return {"errors": errors, "warnings": warnings}


def migrate_builder_design_to_v2(
	module_key: str,
	subtype: Optional[str],
	builder_design: Dict[str, Any],
) -> Dict[str, Any]:
	"""Best-effort migration from legacy block builder to v2 wizard design."""
	family_id = default_family_for_scope(module_key, subtype) or "invoice_classic"
	base = default_design_for_family(family_id)
	if not base:
		raise ValueError("No default design for migration target")

	design = deepcopy(base)
	all_blocks: List[Dict[str, Any]] = []
	for section in ("header", "blocks", "footer"):
		for block in builder_design.get(section) or []:
			if isinstance(block, dict):
				all_blocks.append(block)

	for block in all_blocks:
		bt = str(block.get("type") or "").lower()
		props = block.get("props") or {}
		if bt == "table" and isinstance(props.get("columns"), list):
			cols = []
			for col in props["columns"]:
				if not isinstance(col, dict):
					continue
				cols.append(
					{
						"key": col.get("key") or "",
						"title": col.get("title") or col.get("key") or "",
						"visible": True,
						"format": col.get("format") or "",
						"width": "auto",
					}
				)
			if cols:
				design["table"]["columns"] = cols
			if props.get("items"):
				design["table"]["items_var"] = str(props["items"])
		elif bt == "totals" and isinstance(props.get("items"), list):
			rows = []
			for item in props["items"]:
				if not isinstance(item, dict):
					continue
				rows.append(
					{
						"key": str(item.get("title") or "row"),
						"title": item.get("title") or "",
						"expr": item.get("expr") or "",
						"visible": True,
						"format": item.get("format") or "money",
						"emphasis": False,
					}
				)
			if rows:
				design["totals"]["rows"] = rows
		elif bt == "qr":
			design["sections"]["show_qr"] = True

	custom_css = str(builder_design.get("css") or "").strip()
	if custom_css:
		design["custom_css"] = custom_css

	return design
