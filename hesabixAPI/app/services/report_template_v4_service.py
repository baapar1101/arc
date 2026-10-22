from __future__ import annotations

from copy import deepcopy
from typing import Any, Iterable

from app.services.report_template_gallery import get_family
from app.services.report_template_v3_service import (
	_validate_media,
	is_v3_design,
	studio_block_catalog,
	validate_v3_design,
)

SCHEMA_VERSION = 4
COMPILER_NAME = "hesabix-template-html-css"
COMPILER_VERSION = 1
GRID_COLUMNS = 60

_SHEET_SIZES: dict[str, tuple[float, float]] = {
	"A3": (297, 420),
	"A4": (210, 297),
	"A5": (148, 210),
	"A6": (105, 148),
	"Letter": (215.9, 279.4),
	"Legal": (215.9, 355.6),
}
_ROLL_WIDTHS = (58, 60, 80, 100)
_REGIONS = ("header", "body", "footer")
_CONTAINER_LAYOUTS = {"flow", "grid", "freeform", "stack", "page_grid"}
_FREEFORM_COMPONENTS = {
	"brand_header",
	"party_info",
	"note",
	"signatures",
	"qr",
	"footer_meta",
	"custom_text",
	"divider",
	"spacer",
}


def is_v4_design(design: dict[str, Any]) -> bool:
	try:
		return int(design.get("schema_version") or 0) == SCHEMA_VERSION
	except Exception:
		return False


def _profile_key(media: dict[str, Any]) -> str:
	media_type = str(media.get("type") or "sheet").lower()
	if media_type == "roll":
		try:
			width = float(media.get("width_mm") or 80)
		except (TypeError, ValueError):
			return "custom_roll"
		for preset in _ROLL_WIDTHS:
			if abs(width - preset) < 0.01:
				return f"roll_{preset}"
		return "custom_roll"
	preset = str(media.get("preset") or "A4")
	orientation = "landscape" if media.get("orientation") == "landscape" else "portrait"
	if preset in _SHEET_SIZES:
		return f"{preset.lower()}_{orientation}"
	return f"custom_sheet_{orientation}"


def media_profile_catalog() -> list[dict[str, Any]]:
	items: list[dict[str, Any]] = []
	for preset, (width, height) in _SHEET_SIZES.items():
		for orientation in ("portrait", "landscape"):
			items.append(
				{
					"key": f"{preset.lower()}_{orientation}",
					"label": f"{preset} {'افقی' if orientation == 'landscape' else 'عمودی'}",
					"media": {
						"type": "sheet",
						"preset": preset,
						"width_mm": width,
						"height_mm": height,
						"orientation": orientation,
						"margins_mm": {"top": 10, "right": 10, "bottom": 10, "left": 10},
					},
				}
			)
	for width in _ROLL_WIDTHS:
		items.append(
			{
				"key": f"roll_{width}",
				"label": f"رول {width} میلی‌متر",
				"media": {
					"type": "roll",
					"preset": f"{width}mm",
					"width_mm": width,
					"height_mode": "auto",
					"orientation": "portrait",
					"margins_mm": {"top": 3, "right": 2, "bottom": 4, "left": 2},
				},
			}
		)
	items.extend(
		[
			{"key": "custom_sheet_portrait", "label": "صفحه سفارشی عمودی", "custom": True},
			{"key": "custom_sheet_landscape", "label": "صفحه سفارشی افقی", "custom": True},
			{"key": "custom_roll", "label": "رول سفارشی", "custom": True},
		]
	)
	return items


def component_catalog(module_key: str, subtype: str | None) -> list[dict[str, Any]]:
	items = []
	for item in studio_block_catalog(module_key, subtype):
		next_item = deepcopy(item)
		next_item["component"] = str(next_item.pop("type"))
		next_item["allowed_containers"] = ["page_grid"]
		items.append(next_item)
	return items


def binding_catalog(module_key: str, subtype: str | None) -> list[dict[str, Any]]:
	if module_key != "invoices" or (subtype or "") not in ("detail", "receipt"):
		return []
	return [
		{"key": "title_text", "type": "string", "label_fa": "عنوان فاکتور"},
		{"key": "business_name", "type": "string", "label_fa": "نام کسب‌وکار"},
		{"key": "invoice.code", "type": "string", "label_fa": "شماره فاکتور"},
		{"key": "invoice.issue_date", "type": "date", "label_fa": "تاریخ فاکتور"},
		{"key": "buyer.name", "type": "string", "label_fa": "نام خریدار"},
		{"key": "seller.name", "type": "string", "label_fa": "نام فروشنده"},
		{"key": "lines", "type": "collection", "label_fa": "اقلام فاکتور"},
		{"key": "payments", "type": "collection", "label_fa": "پرداخت‌ها"},
		{"key": "invoice_footer_note", "type": "string", "label_fa": "یادداشت فاکتور"},
		{"key": "invoice_verify_qr_data_uri", "type": "asset", "label_fa": "QR اعتبارسنجی"},
		{"key": "generated_at", "type": "datetime", "label_fa": "زمان تولید"},
		{"key": "issuer_name", "type": "string", "label_fa": "تنظیم‌کننده"},
	]


def studio_v4_contract(module_key: str, subtype: str | None) -> dict[str, Any]:
	return {
		"schema_version": SCHEMA_VERSION,
		"compiler": {"name": COMPILER_NAME, "version": COMPILER_VERSION, "output": "html_css"},
		"grid_columns": GRID_COLUMNS,
		"container_types": sorted(_CONTAINER_LAYOUTS),
		"freeform": {
			"legacy": True,
			"grid_sizes_mm": [1, 3, 5],
			"snap_targets": ["grid", "safe_margin", "sibling_edge", "sibling_center"],
			"position_unit": "mm",
			"dynamic_components_allowed": False,
		},
		"page_grid": {
			"grid_sizes_mm": [1, 3, 5],
			"snap_targets": ["grid", "safe_margin", "sibling_edge", "sibling_center"],
			"position_unit": "mm",
			"dynamic_components_allowed": True,
		},
		"components": component_catalog(module_key, subtype),
		"bindings": binding_catalog(module_key, subtype),
		"media_profiles": media_profile_catalog(),
		"json_schema": _json_schema(),
	}


def _json_schema() -> dict[str, Any]:
	return {
		"$schema": "https://json-schema.org/draft/2020-12/schema",
		"$id": "https://hesabix.ir/schemas/report-template-studio-v4.json",
		"title": "Hesabix report template design v4",
		"type": "object",
		"required": ["schema_version", "compiler_contract", "root", "variants", "media"],
		"properties": {
			"schema_version": {"const": SCHEMA_VERSION},
			"compiler_contract": {
				"type": "object",
				"required": ["name", "version", "output"],
				"properties": {
					"name": {"const": COMPILER_NAME},
					"version": {"const": COMPILER_VERSION},
					"output": {"const": "html_css"},
				},
			},
			"root": {"$ref": "#/$defs/node"},
			"variants": {"type": "object", "additionalProperties": {"$ref": "#/$defs/variant"}},
			"media": {"type": "object"},
		},
		"$defs": {
			"node": {
				"type": "object",
				"required": ["id", "kind"],
				"properties": {
					"id": {"type": "string", "pattern": "^[a-zA-Z0-9_-]{1,80}$"},
					"kind": {"enum": ["container", "component"]},
					"children": {"type": "array", "items": {"$ref": "#/$defs/node"}},
					"component": {"type": "string"},
					"layout": {"type": "object"},
					"placement": {"type": "object"},
				},
			},
			"variant": {
				"type": "object",
				"required": ["media", "node_overrides"],
				"properties": {"media": {"type": "object"}, "node_overrides": {"type": "object"}},
			},
		},
	}


def _iter_nodes(node: dict[str, Any]) -> Iterable[dict[str, Any]]:
	yield node
	for child in node.get("children") or []:
		if isinstance(child, dict):
			yield from _iter_nodes(child)


def _row_layout_from_v3(block: dict[str, Any]) -> dict[str, Any]:
	style = block.get("style") or {}
	height_mode = str(style.get("row_height_mode") or "auto")
	layout: dict[str, Any] = {"type": "grid", "columns": GRID_COLUMNS, "gap_mm": 0}
	if height_mode in ("minimum", "fixed"):
		layout["height_mode"] = height_mode
		layout["height_mm"] = float(style.get("row_height_mm") or 20)
	return layout


def _component_from_v3(block: dict[str, Any]) -> dict[str, Any]:
	style = deepcopy(block.get("style") or {})
	span = int(style.pop("grid_span", GRID_COLUMNS) or GRID_COLUMNS)
	style.pop("row_id", None)
	style.pop("row_height_mode", None)
	style.pop("row_height_mm", None)
	return {
		"id": str(block.get("id") or "component"),
		"kind": "component",
		"component": str(block.get("type") or ""),
		"visible": block.get("visible", True) is not False,
		"props": deepcopy(block.get("props") or {}),
		"style": style,
		"placement": {"column_span": max(1, min(GRID_COLUMNS, span))},
	}


def _printable_size(media: dict[str, Any]) -> tuple[float, float]:
	try:
		width = float(media.get("width_mm") or 210)
	except (TypeError, ValueError):
		width = 210
	try:
		height = float(media.get("height_mm") or (300 if media.get("type") == "roll" else 297))
	except (TypeError, ValueError):
		height = 300 if media.get("type") == "roll" else 297
	if media.get("type") != "roll" and media.get("orientation") == "landscape":
		width, height = height, width
	margins = media.get("margins_mm") or {}
	try:
		width -= float(margins.get("left") or 0) + float(margins.get("right") or 0)
		height -= float(margins.get("top") or 0) + float(margins.get("bottom") or 0)
	except (TypeError, ValueError):
		pass
	return max(10, width), max(20, height)


def _default_component_height(component: str) -> float:
	return {
		"brand_header": 30,
		"party_info": 24,
		"invoice_lines": 72,
		"invoice_totals": 38,
		"payments": 24,
		"note": 22,
		"signatures": 38,
		"qr": 34,
		"footer_meta": 14,
		"custom_text": 18,
		"divider": 4,
		"spacer": 10,
	}.get(component, 20)


def _base_root_from_v3(design: dict[str, Any]) -> dict[str, Any]:
	printable_width, printable_height = _printable_size(design.get("media") or {})
	region_nodes: list[dict[str, Any]] = []
	cursor_y = 0.0
	regions = design.get("regions") or {}
	for region_name in _REGIONS:
		rows: list[dict[str, Any]] = []
		for block in regions.get(region_name) or []:
			if not isinstance(block, dict):
				continue
			style = block.get("style") or {}
			row_id = str(style.get("row_id") or f"row-{block.get('id')}")
			if not rows or rows[-1]["id"] != row_id:
				rows.append(
					{
						"id": row_id,
						"kind": "container",
						"layout": _row_layout_from_v3(block),
						"children": [],
					}
				)
			component = _component_from_v3(block)
			rows[-1]["children"].append(component)
		for row in rows:
			children = row.get("children") or []
			row_height = max(
				[_default_component_height(str(child.get("component") or "")) for child in children] or [20]
			)
			layout = row.get("layout") or {}
			if layout.get("height_mode") in ("minimum", "fixed"):
				try:
					row_height = max(row_height, float(layout.get("height_mm") or row_height))
				except (TypeError, ValueError):
					pass
			cursor_x = 0.0
			for child in children:
				placement = child.get("placement") or {}
				span = max(1, min(GRID_COLUMNS, int(placement.get("column_span") or GRID_COLUMNS)))
				width = printable_width * span / GRID_COLUMNS
				child["placement"] = {
					**placement,
					"x_mm": round(cursor_x, 3),
					"y_mm": round(cursor_y, 3),
					"width_mm": round(width, 3),
					"height_mm": round(row_height, 3),
				}
				cursor_x += width
			cursor_y += row_height + 3
		region_nodes.append(
			{
				"id": f"region-{region_name}",
				"kind": "container",
				"region": region_name,
				"layout": {"type": "flow", "gap_mm": 2},
				"children": rows,
			}
		)
	if (design.get("media") or {}).get("type") != "roll" and cursor_y > printable_height:
		vertical_ratio = printable_height / cursor_y
		for region_node in region_nodes:
			for node in _iter_nodes(region_node):
				if node.get("kind") != "component":
					continue
				placement = node.get("placement") or {}
				placement["y_mm"] = round(float(placement.get("y_mm") or 0) * vertical_ratio, 3)
				placement["height_mm"] = round(max(4, float(placement.get("height_mm") or 20) * vertical_ratio), 3)
		cursor_y = printable_height
	return {
		"id": "invoice-root",
		"kind": "container",
		"layout": {
			"type": "page_grid",
			"grid_mm": 1,
			"snap": True,
			"width_mm": round(printable_width, 3),
			"height_mm": round(max(printable_height, cursor_y), 3),
		},
		"children": region_nodes,
	}


def _full_overrides(
	root: dict[str, Any],
	*,
	media: dict[str, Any],
	base_width: float,
	base_height: float,
	narrow: bool,
) -> dict[str, dict[str, Any]]:
	overrides: dict[str, dict[str, Any]] = {}
	printable_width, printable_height = _printable_size(media)
	stack_y = 0.0
	content_bottom = 0.0
	for node in _iter_nodes(root):
		node_id = str(node.get("id") or "")
		if not node_id:
			continue
		if node.get("kind") == "container":
			layout = deepcopy(node.get("layout") or {})
			if node_id == str(root.get("id") or ""):
				layout.update(
					{
						"type": "page_grid",
						"width_mm": round(printable_width, 3),
						"height_mm": round(max(printable_height, stack_y), 3),
					}
				)
			overrides[node_id] = {"layout": layout}
		else:
			placement = deepcopy(node.get("placement") or {})
			if narrow:
				placement["column_span"] = GRID_COLUMNS
				height = float(placement.get("height_mm") or _default_component_height(str(node.get("component") or "")))
				placement.update(
					{
						"x_mm": 0,
						"y_mm": round(stack_y, 3),
						"width_mm": round(printable_width, 3),
						"height_mm": round(height, 3),
					}
				)
				stack_y += height + 3
			else:
				ratio = printable_width / max(1, base_width)
				vertical_ratio = printable_height / max(1, base_height)
				placement.update(
					{
						"x_mm": round(float(placement.get("x_mm") or 0) * ratio, 3),
						"y_mm": round(float(placement.get("y_mm") or 0) * vertical_ratio, 3),
						"width_mm": round(float(placement.get("width_mm") or base_width) * ratio, 3),
						"height_mm": round(max(4, float(placement.get("height_mm") or 20) * vertical_ratio), 3),
					}
				)
				content_bottom = max(
					content_bottom,
					float(placement.get("y_mm") or 0) + float(placement.get("height_mm") or 0),
				)
			overrides[node_id] = {"placement": placement}
	root_id = str(root.get("id") or "")
	if root_id and root_id in overrides:
		overrides[root_id]["layout"]["height_mm"] = round(
			max(printable_height, stack_y if narrow else content_bottom),
			3,
		)
	return overrides


def migrate_v3_design_to_v4(design: dict[str, Any]) -> dict[str, Any]:
	if is_v4_design(design):
		return deepcopy(design)
	if not is_v3_design(design):
		raise ValueError("Only template design v3 can be migrated to v4")
	root = _base_root_from_v3(design)
	base_width = float((root.get("layout") or {}).get("width_mm") or 190)
	base_height = float((root.get("layout") or {}).get("height_mm") or 277)
	variants: dict[str, Any] = {}
	for profile in media_profile_catalog():
		key = str(profile["key"])
		media = deepcopy(profile.get("media") or design.get("media") or {})
		variants[key] = {
			"media": media,
			"node_overrides": _full_overrides(
				root,
				media=media,
				base_width=base_width,
				base_height=base_height,
				narrow=key.startswith("roll_") or key == "custom_roll",
			),
		}
	active = _profile_key(design.get("media") or {})
	if active in variants:
		variants[active]["media"] = deepcopy(design.get("media") or variants[active]["media"])
	return {
		"schema_version": SCHEMA_VERSION,
		"family_id": design.get("family_id"),
		"layout": design.get("layout"),
		"theme": deepcopy(design.get("theme") or {}),
		"branding": deepcopy(design.get("branding") or {}),
		"custom_css": str(design.get("custom_css") or ""),
		"media": deepcopy(design.get("media") or {}),
		"active_variant": active,
		"compiler_contract": {"name": COMPILER_NAME, "version": COMPILER_VERSION, "output": "html_css"},
		"root": root,
		"variants": variants,
		"migration": {"from_schema_version": 3, "mode": "copy_on_write"},
	}


def active_variant_key(design: dict[str, Any]) -> str:
	computed = _profile_key(design.get("media") or {})
	variants = design.get("variants") or {}
	if computed in variants:
		return computed
	configured = str(design.get("active_variant") or "")
	return configured if configured in variants else computed


def resolved_root(design: dict[str, Any]) -> dict[str, Any]:
	root = deepcopy(design.get("root") or {})
	variant = (design.get("variants") or {}).get(active_variant_key(design)) or {}
	overrides = variant.get("node_overrides") or {}
	for node in _iter_nodes(root):
		override = overrides.get(str(node.get("id") or "")) or {}
		for key in ("layout", "placement", "style"):
			if isinstance(override.get(key), dict):
				node[key] = {**(node.get(key) or {}), **deepcopy(override[key])}
	return root


def v4_to_v3_projection(design: dict[str, Any]) -> dict[str, Any]:
	root = resolved_root(design)
	regions: dict[str, list[dict[str, Any]]] = {key: [] for key in _REGIONS}
	for region_node in root.get("children") or []:
		if not isinstance(region_node, dict):
			continue
		region_name = str(region_node.get("region") or "")
		if region_name not in regions:
			continue
		for row in region_node.get("children") or []:
			if not isinstance(row, dict):
				continue
			layout = row.get("layout") or {}
			for component in row.get("children") or []:
				if not isinstance(component, dict) or component.get("kind") != "component":
					continue
				placement = component.get("placement") or {}
				style = deepcopy(component.get("style") or {})
				style.update(
					{
						# The v3 projection is used for component/property validation and
						# theme CSS only. A responsive v4 grid is allowed to wrap (for
						# example two 60-column cells on roll media), while v3 rows were
						# required to total at most 60 columns.
						"row_id": f"{row.get('id')}-{component.get('id')}",
						"layout_type": layout.get("type", "grid"),
						"grid_span": placement.get("column_span", GRID_COLUMNS),
					}
				)
				if layout.get("height_mode"):
					style["row_height_mode"] = layout.get("height_mode")
					style["row_height_mm"] = layout.get("height_mm")
				if layout.get("type") == "freeform":
					style.update(
						{
							"freeform_grid_mm": layout.get("grid_mm", 1),
							"freeform_snap": layout.get("snap", True),
							"freeform_height_mm": layout.get("height_mm", 40),
							"x_mm": placement.get("x_mm", 0),
							"y_mm": placement.get("y_mm", 0),
							"width_mm": placement.get("width_mm", 30),
							"height_mm": placement.get("height_mm", 15),
						}
					)
				regions[region_name].append(
					{
						"id": component.get("id"),
						"type": component.get("component"),
						"visible": component.get("visible", True),
						"props": deepcopy(component.get("props") or {}),
						"style": style,
					}
				)
	return {
		"schema_version": 3,
		"family_id": design.get("family_id"),
		"layout": design.get("layout"),
		"theme": deepcopy(design.get("theme") or {}),
		"branding": deepcopy(design.get("branding") or {}),
		"custom_css": str(design.get("custom_css") or ""),
		"media": deepcopy(design.get("media") or {}),
		"regions": regions,
	}


def validate_v4_design(module_key: str, subtype: str | None, design: dict[str, Any]) -> dict[str, list[str]]:
	errors: list[str] = []
	warnings: list[str] = []
	if not isinstance(design, dict) or not is_v4_design(design):
		return {"errors": ["schema_version must be 4"], "warnings": []}
	contract = design.get("compiler_contract") or {}
	if contract != {"name": COMPILER_NAME, "version": COMPILER_VERSION, "output": "html_css"}:
		errors.append("Unsupported compiler_contract")
	errors.extend(_validate_media(design.get("media")))
	root = design.get("root")
	if not isinstance(root, dict) or root.get("kind") != "container":
		return {"errors": errors + ["root must be a container"], "warnings": warnings}
	definitions = {item["component"]: item for item in component_catalog(module_key, subtype)}
	seen: set[str] = set()
	component_counts: dict[str, int] = {}
	for node in _iter_nodes(root):
		node_id = str(node.get("id") or "")
		if not node_id or len(node_id) > 80 or not all(ch.isalnum() or ch in "_-" for ch in node_id):
			errors.append(f"Invalid node id: {node_id}")
		elif node_id in seen:
			errors.append(f"Duplicate node id: {node_id}")
		seen.add(node_id)
		kind = node.get("kind")
		if kind == "container":
			if not isinstance(node.get("children"), list):
				errors.append(f"Container '{node_id}' children must be a list")
			layout = node.get("layout") or {}
			if not isinstance(layout, dict):
				errors.append(f"Container '{node_id}' layout must be an object")
				continue
			layout_type = str(layout.get("type") or "")
			if layout_type not in _CONTAINER_LAYOUTS:
				errors.append(f"Invalid layout type in '{node_id}'")
			if layout_type == "grid":
				try:
					columns = int(layout.get("columns") or GRID_COLUMNS)
				except (TypeError, ValueError):
					columns = 0
				if columns != GRID_COLUMNS:
					errors.append(f"Grid container '{node_id}' must have 60 columns")
			if layout_type == "freeform":
				try:
					height_mm = float(layout.get("height_mm") or 0)
				except (TypeError, ValueError):
					height_mm = 0
				try:
					grid_mm = int(layout.get("grid_mm") or 1)
				except (TypeError, ValueError):
					grid_mm = 0
				if height_mm < 4:
					errors.append(f"Freeform container '{node_id}' needs a fixed height")
				if grid_mm not in (1, 3, 5):
					errors.append(f"Invalid freeform grid in '{node_id}'")
				for child in node.get("children") or []:
					if isinstance(child, dict) and child.get("component") not in _FREEFORM_COMPONENTS:
						errors.append(f"{child.get('component')} cannot be placed in a freeform container")
			if layout_type == "page_grid":
				try:
					grid_mm = int(layout.get("grid_mm") or 1)
				except (TypeError, ValueError):
					grid_mm = 0
				if node is not root:
					errors.append("page_grid is only allowed on the document root")
				if grid_mm not in (1, 3, 5):
					errors.append("Page grid size must be 1, 3 or 5 millimeters")
		elif kind == "component":
			component = str(node.get("component") or "")
			for field in ("props", "style", "placement"):
				if node.get(field) is not None and not isinstance(node.get(field), dict):
					errors.append(f"Component '{node_id}' {field} must be an object")
			definition = definitions.get(component)
			if not definition:
				errors.append(f"Unknown component: {component}")
			else:
				component_counts[component] = component_counts.get(component, 0) + 1
		else:
			errors.append(f"Invalid node kind in '{node_id}'")
	variants = design.get("variants")
	if not isinstance(variants, dict):
		errors.append("variants must be an object")
	else:
		required_profiles = {str(item["key"]) for item in media_profile_catalog()}
		missing = required_profiles.difference(variants)
		if missing:
			errors.append("Missing responsive variants: " + ", ".join(sorted(missing)))
		for profile_key, variant in variants.items():
			if not isinstance(variant, dict):
				errors.append(f"Invalid variant: {profile_key}")
				continue
			overrides = variant.get("node_overrides") or {}
			if not isinstance(overrides, dict):
				errors.append(f"Variant '{profile_key}' node_overrides must be an object")
				continue
			unknown = set(overrides).difference(seen)
			if unknown:
				errors.append(f"Variant '{profile_key}' refers to unknown nodes")
			missing_overrides = seen.difference(overrides)
			if missing_overrides:
				errors.append(f"Variant '{profile_key}' is missing explicit node overrides")
			for node_id, override in overrides.items():
				if not isinstance(override, dict):
					errors.append(f"Invalid override for '{node_id}' in '{profile_key}'")
					continue
				placement = (override or {}).get("placement") or {}
				if "column_span" in placement:
					try:
						span = int(placement.get("column_span") or 0)
					except (TypeError, ValueError):
						span = 0
					if span < 1 or span > GRID_COLUMNS:
						errors.append(f"Invalid column span for '{node_id}' in '{profile_key}'")
				for key in ("x_mm", "y_mm", "width_mm", "height_mm"):
					if key in placement:
						try:
							value = float(placement[key])
						except (TypeError, ValueError):
							value = -1
						if value < 0:
							errors.append(f"Invalid {key} for '{node_id}' in '{profile_key}'")
			variant_media = (
				design.get("media") or {}
				if profile_key == active_variant_key(design)
				else variant.get("media") if isinstance(variant.get("media"), dict) else design.get("media") or {}
			)
			try:
				printable_width, printable_height = _printable_size(variant_media)
			except (TypeError, ValueError):
				printable_width = printable_height = 0
			root_layout = {
				**(root.get("layout") or {}),
				**((overrides.get(str(root.get("id") or "")) or {}).get("layout") or {}),
			}
			if root_layout.get("type") == "page_grid":
				try:
					canvas_width = float(root_layout.get("width_mm") or printable_width)
					canvas_height = float(root_layout.get("height_mm") or printable_height)
				except (TypeError, ValueError):
					canvas_width = canvas_height = 0
				if canvas_width <= 0 or canvas_height <= 0:
					errors.append(f"Invalid page grid dimensions in '{profile_key}'")
				for component_node in _iter_nodes(root):
					if component_node.get("kind") != "component":
						continue
					component_id = str(component_node.get("id") or "")
					placement = {
						**(component_node.get("placement") or {}),
						**((overrides.get(component_id) or {}).get("placement") or {}),
					}
					try:
						x = float(placement.get("x_mm"))
						y = float(placement.get("y_mm"))
						width = float(placement.get("width_mm"))
						height = float(placement.get("height_mm"))
					except (TypeError, ValueError):
						errors.append(f"Missing page grid geometry for '{component_id}' in '{profile_key}'")
						continue
					if x < 0 or y < 0 or width < 1 or height < 1:
						errors.append(f"Invalid page grid geometry for '{component_id}' in '{profile_key}'")
					elif x + width > canvas_width + 0.001 or y + height > canvas_height + 0.001:
						errors.append(f"Page grid item '{component_id}' exceeds its canvas in '{profile_key}'")
			for node in _iter_nodes(root):
				if node.get("kind") != "container":
					continue
				node_id = str(node.get("id") or "")
				layout = {**(node.get("layout") or {}), **((overrides.get(node_id) or {}).get("layout") or {})}
				if layout.get("type") != "freeform":
					continue
				try:
					height = float(layout.get("height_mm") or 0)
				except (TypeError, ValueError):
					height = 0
				for child in node.get("children") or []:
					if not isinstance(child, dict):
						continue
					child_id = str(child.get("id") or "")
					placement = {
						**(child.get("placement") or {}),
						**((overrides.get(child_id) or {}).get("placement") or {}),
					}
					try:
						x = float(placement.get("x_mm") or 0)
						y = float(placement.get("y_mm") or 0)
						width = float(placement.get("width_mm") or 0)
						child_height = float(placement.get("height_mm") or 0)
					except (TypeError, ValueError):
						errors.append(f"Invalid freeform geometry for '{child_id}' in '{profile_key}'")
						continue
					if width < 1 or child_height < 1:
						errors.append(f"Freeform item '{child_id}' has no usable size in '{profile_key}'")
					if x + width > printable_width + 0.001 or y + child_height > height + 0.001:
						errors.append(f"Freeform item '{child_id}' exceeds its container in '{profile_key}'")
	# Reuse the mature component/property validation through a lossless projection.
	try:
		projection_result = validate_v3_design(module_key, subtype, v4_to_v3_projection(design))
		errors.extend(projection_result["errors"])
		warnings.extend(projection_result["warnings"])
	except Exception as ex:
		errors.append(f"Invalid v4 structure: {ex}")
	return {"errors": list(dict.fromkeys(errors)), "warnings": list(dict.fromkeys(warnings))}
