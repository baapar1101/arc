"""Validate label_design_v1 and sheet_json documents."""

from __future__ import annotations

import re
from typing import Any, Dict, List

from app.core.responses import ApiError

_ALLOWED_TYPES = frozenset({"text", "barcode", "qr", "datamatrix", "image", "shape", "line"})
_LINEAR = frozenset({"code128", "code39", "code93", "ean8", "ean13", "codabar"})
_COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
_MAX_ELEMENTS = 50


def _err(code: str, message: str, details: dict | None = None) -> None:
	raise ApiError(code, message, http_status=422, details=details)


def validate_sheet_json(sheet: Any) -> Dict[str, Any]:
	if sheet is None:
		from app.services.barcode_label_presets import default_sheet

		return default_sheet()
	if not isinstance(sheet, dict):
		_err("INVALID_SHEET", "sheet_json must be an object")
	paper = sheet.get("paper") or "A4"
	if paper not in ("A4", "A5", "Letter", "custom"):
		_err("INVALID_SHEET_PAPER", f"Unsupported paper: {paper}")
	orientation = sheet.get("orientation") or "portrait"
	if orientation not in ("portrait", "landscape"):
		_err("INVALID_SHEET_ORIENTATION", "orientation must be portrait or landscape")
	columns = int(sheet.get("columns") or 1)
	rows = int(sheet.get("rows") or 1)
	if columns < 1 or columns > 20 or rows < 1 or rows > 40:
		_err("INVALID_SHEET_GRID", "columns/rows out of allowed range")
	margin = sheet.get("margin_mm") or {"top": 5, "right": 5, "bottom": 5, "left": 5}
	gap = sheet.get("gap_mm") or {"x": 2, "y": 2}
	return {
		"print_mode": sheet.get("print_mode") or "sheet",
		"paper": paper,
		"orientation": orientation,
		"custom_paper_mm": sheet.get("custom_paper_mm"),
		"margin_mm": margin,
		"columns": columns,
		"rows": rows,
		"gap_mm": gap,
		"label_from_canvas": bool(sheet.get("label_from_canvas", True)),
	}


def validate_design_json(design: Any, *, strict_publish: bool = False) -> Dict[str, Any]:
	if not isinstance(design, dict):
		_err("INVALID_DESIGN", "design_json must be an object")
	if int(design.get("schema_version") or 0) != 1:
		_err("UNSUPPORTED_SCHEMA", "Only label_design_v1 (schema_version=1) is supported")
	canvas = design.get("canvas")
	if not isinstance(canvas, dict):
		_err("INVALID_CANVAS", "canvas is required")
	try:
		width = float(canvas.get("width_mm"))
		height = float(canvas.get("height_mm"))
	except (TypeError, ValueError):
		_err("INVALID_CANVAS_SIZE", "canvas width_mm/height_mm must be numbers")
	if width <= 0 or height <= 0 or width > 500 or height > 500:
		_err("INVALID_CANVAS_SIZE", "canvas size out of range (0..500 mm]")

	elements = design.get("elements")
	if not isinstance(elements, list):
		_err("INVALID_ELEMENTS", "elements must be an array")
	if len(elements) > _MAX_ELEMENTS:
		_err("TOO_MANY_ELEMENTS", f"Maximum {_MAX_ELEMENTS} elements allowed")

	ids: set[str] = set()
	normalized: List[Dict[str, Any]] = []
	for idx, raw in enumerate(elements):
		if not isinstance(raw, dict):
			_err("INVALID_ELEMENT", f"element[{idx}] must be an object")
		el_id = str(raw.get("id") or "").strip()
		if not el_id:
			_err("INVALID_ELEMENT_ID", f"element[{idx}] missing id")
		if el_id in ids:
			_err("DUPLICATE_ELEMENT_ID", f"Duplicate element id: {el_id}")
		ids.add(el_id)
		el_type = str(raw.get("type") or "")
		if el_type not in _ALLOWED_TYPES:
			_err("INVALID_ELEMENT_TYPE", f"Unsupported type: {el_type}")
		try:
			x = float(raw.get("x_mm", 0))
			y = float(raw.get("y_mm", 0))
			w = float(raw.get("w_mm", 0))
			h = float(raw.get("h_mm", 0))
		except (TypeError, ValueError):
			_err("INVALID_ELEMENT_GEOMETRY", f"element {el_id} has invalid geometry")
		if w <= 0 or h <= 0:
			_err("INVALID_ELEMENT_GEOMETRY", f"element {el_id} width/height must be > 0")
		if strict_publish:
			if x < -0.5 or y < -0.5 or x + w > width + 0.5 or y + h > height + 0.5:
				_err(
					"ELEMENT_OUT_OF_CANVAS",
					f"element {el_id} is outside the canvas",
					details={"element_id": el_id},
				)
		props = raw.get("props") if isinstance(raw.get("props"), dict) else {}
		_validate_props(el_type, props, el_id, strict_publish=strict_publish)
		normalized.append(
			{
				"id": el_id,
				"type": el_type,
				"name": (raw.get("name") or el_id)[:120],
				"x_mm": x,
				"y_mm": y,
				"w_mm": w,
				"h_mm": h,
				"rotation_deg": float(raw.get("rotation_deg") or 0),
				"z_index": int(raw.get("z_index") or 0),
				"locked": bool(raw.get("locked", False)),
				"visible": bool(raw.get("visible", True)),
				"props": props,
			}
		)

	grid_mm = float(canvas.get("grid_mm") or 1)
	dpi = int(canvas.get("dpi") or 300)
	if dpi not in (203, 300, 600):
		dpi = 300
	guides = canvas.get("guides_mm") if isinstance(canvas.get("guides_mm"), dict) else {}
	return {
		"schema_version": 1,
		"canvas": {
			"width_mm": width,
			"height_mm": height,
			"grid_mm": grid_mm if grid_mm > 0 else 1,
			"snap_to_grid": bool(canvas.get("snap_to_grid", True)),
			"guides_mm": {
				"vertical": list(guides.get("vertical") or []),
				"horizontal": list(guides.get("horizontal") or []),
			},
			"dpi": dpi,
		},
		"elements": normalized,
	}


def _validate_props(el_type: str, props: Dict[str, Any], el_id: str, *, strict_publish: bool) -> None:
	if el_type == "text":
		mode = props.get("content_mode") or "fixed"
		if mode not in ("fixed", "binding"):
			_err("INVALID_TEXT_MODE", f"{el_id}: invalid content_mode")
		if mode == "binding" and strict_publish and not str(props.get("binding") or "").strip():
			_err("MISSING_BINDING", f"{el_id}: binding required", details={"element_id": el_id})
		color = props.get("color") or "#000000"
		if not _COLOR_RE.match(str(color)):
			_err("INVALID_COLOR", f"{el_id}: invalid color")
	elif el_type == "barcode":
		sym = str(props.get("symbology") or "")
		if sym not in _LINEAR:
			_err("INVALID_SYMBOLOGY", f"{el_id}: unsupported symbology {sym}")
		mode = props.get("content_mode") or "fixed"
		if mode not in ("fixed", "binding"):
			_err("INVALID_BARCODE_MODE", f"{el_id}: invalid content_mode")
		if mode == "fixed":
			value = str(props.get("value") or "")
			if strict_publish:
				_validate_linear_value(sym, value, el_id)
		elif strict_publish and not str(props.get("binding") or "").strip():
			_err("MISSING_BINDING", f"{el_id}: binding required", details={"element_id": el_id})
	elif el_type in ("qr", "datamatrix"):
		mode = props.get("content_mode") or "fixed"
		if mode not in ("fixed", "binding"):
			_err("INVALID_QR_MODE", f"{el_id}: invalid content_mode")
		if mode == "fixed" and strict_publish and not str(props.get("value") or "").strip():
			_err("EMPTY_BARCODE_VALUE", f"{el_id}: value required")
		if mode == "binding" and strict_publish and not str(props.get("binding") or "").strip():
			_err("MISSING_BINDING", f"{el_id}: binding required", details={"element_id": el_id})
	elif el_type == "image":
		source = props.get("source") or "upload"
		if source not in ("upload", "product.image", "business.logo"):
			_err("INVALID_IMAGE_SOURCE", f"{el_id}: invalid image source")
		if source == "upload" and strict_publish:
			if not props.get("file_id") and not props.get("data_uri"):
				_err("MISSING_IMAGE", f"{el_id}: upload image requires file_id or data_uri")
	elif el_type == "shape":
		shape = props.get("shape") or "rect"
		if shape not in ("rect", "ellipse"):
			_err("INVALID_SHAPE", f"{el_id}: shape must be rect or ellipse")


def _validate_linear_value(symbology: str, value: str, el_id: str) -> None:
	v = value.strip()
	if not v:
		_err("EMPTY_BARCODE_VALUE", f"{el_id}: barcode value is empty")
	if symbology == "ean13":
		digits = re.sub(r"\D", "", v)
		if len(digits) not in (12, 13):
			_err("INVALID_EAN13", f"{el_id}: EAN-13 requires 12 or 13 digits")
	elif symbology == "ean8":
		digits = re.sub(r"\D", "", v)
		if len(digits) not in (7, 8):
			_err("INVALID_EAN8", f"{el_id}: EAN-8 requires 7 or 8 digits")


def design_warnings(design: Dict[str, Any]) -> List[Dict[str, str]]:
	"""Non-blocking warnings for studio UI."""
	warnings: List[Dict[str, str]] = []
	canvas = design.get("canvas") or {}
	width = float(canvas.get("width_mm") or 0)
	height = float(canvas.get("height_mm") or 0)
	for el in design.get("elements") or []:
		el_id = str(el.get("id"))
		x, y, w, h = float(el["x_mm"]), float(el["y_mm"]), float(el["w_mm"]), float(el["h_mm"])
		if x < 0 or y < 0 or x + w > width or y + h > height:
			warnings.append({"element_id": el_id, "code": "OUT_OF_BOUNDS", "message": "Element overlaps canvas edge"})
		if el.get("type") == "barcode" and h < 8:
			warnings.append({"element_id": el_id, "code": "BARCODE_SHORT", "message": "Barcode height may be hard to scan"})
		props = el.get("props") or {}
		if el.get("type") == "text" and float(props.get("font_size_pt") or 9) < 5:
			warnings.append({"element_id": el_id, "code": "FONT_TOO_SMALL", "message": "Font size is very small"})
		qz = props.get("quiet_zone_mm")
		if qz is not None and float(qz) < 0.5 and el.get("type") in ("barcode", "qr", "datamatrix"):
			warnings.append({"element_id": el_id, "code": "QUIET_ZONE", "message": "Quiet zone is below 0.5mm"})
	return warnings


def sample_print_context() -> Dict[str, Any]:
	return {
		"product": {
			"name": "کالای نمونه",
			"code": "P-1001",
			"price": 250000,
			"sale_price": 225000,
			"general_barcode": "6260000000017",
		},
		"instance": {"serial": "SN-0001", "barcode": "INST-0001"},
		"warehouse": {"name": "انبار مرکزی"},
		"business": {"name": "فروشگاه نمونه"},
		"print": {"counter": 1, "copy_index": 1},
	}


def resolve_binding(binding: str, context: Dict[str, Any]) -> str:
	key = (binding or "").strip()
	if not key:
		return ""
	# product.general_barcode[n]
	m = re.match(r"^product\.general_barcode\[(\d+)\]$", key)
	if m:
		raw = str((context.get("product") or {}).get("general_barcode") or "")
		parts = [p.strip() for p in re.split(r"[,،\n]+", raw) if p.strip()]
		idx = int(m.group(1))
		return parts[idx] if 0 <= idx < len(parts) else ""
	parts = key.split(".")
	cur: Any = context
	for p in parts:
		if not isinstance(cur, dict):
			return ""
		cur = cur.get(p)
	if cur is None:
		return ""
	if isinstance(cur, (int, float)):
		# format price-ish without forcing locale here
		if float(cur).is_integer():
			return str(int(cur))
		return str(cur)
	return str(cur)
