"""System presets for barcode label designs (label_design_v1)."""

from __future__ import annotations

from copy import deepcopy
from typing import Any, Dict, List


def _sheet_a4_grid(columns: int, rows: int) -> Dict[str, Any]:
	return {
		"paper": "A4",
		"orientation": "portrait",
		"custom_paper_mm": None,
		"margin_mm": {"top": 8, "right": 8, "bottom": 8, "left": 8},
		"columns": columns,
		"rows": rows,
		"gap_mm": {"x": 2, "y": 2},
		"label_from_canvas": True,
	}


def _design_shelf(width: float, height: float, *, with_price: bool = False) -> Dict[str, Any]:
	elements: List[Dict[str, Any]] = [
		{
			"id": "el_name",
			"type": "text",
			"name": "product_name",
			"x_mm": 2,
			"y_mm": 1.5,
			"w_mm": width - 4,
			"h_mm": 6,
			"rotation_deg": 0,
			"z_index": 1,
			"locked": False,
			"visible": True,
			"props": {
				"content_mode": "binding",
				"text": "",
				"binding": "product.name",
				"font_family": "YekanBakhFaNum",
				"font_size_pt": 8 if width < 45 else 9,
				"font_weight": "bold",
				"align": "center",
				"valign": "middle",
				"color": "#000000",
				"rtl": True,
				"wrap": True,
			},
		},
		{
			"id": "el_barcode",
			"type": "barcode",
			"name": "main_barcode",
			"x_mm": 3,
			"y_mm": 8,
			"w_mm": width - 6,
			"h_mm": height - (18 if with_price else 14),
			"rotation_deg": 0,
			"z_index": 2,
			"locked": False,
			"visible": True,
			"props": {
				"symbology": "code128",
				"content_mode": "binding",
				"value": "",
				"binding": "product.general_barcode",
				"show_text": True,
				"text_size_pt": 7,
				"quiet_zone_mm": 1,
			},
		},
	]
	if with_price:
		elements.append(
			{
				"id": "el_price",
				"type": "text",
				"name": "sale_price",
				"x_mm": 2,
				"y_mm": height - 7,
				"w_mm": width - 4,
				"h_mm": 5.5,
				"rotation_deg": 0,
				"z_index": 3,
				"locked": False,
				"visible": True,
				"props": {
					"content_mode": "binding",
					"text": "",
					"binding": "product.sale_price",
					"font_family": "YekanBakhFaNum",
					"font_size_pt": 10,
					"font_weight": "bold",
					"align": "center",
					"valign": "middle",
					"color": "#111111",
					"rtl": True,
					"wrap": False,
				},
			}
		)
	return {
		"schema_version": 1,
		"canvas": {
			"width_mm": width,
			"height_mm": height,
			"grid_mm": 1,
			"snap_to_grid": True,
			"guides_mm": {"vertical": [], "horizontal": []},
			"dpi": 300,
		},
		"elements": elements,
	}


_PRESETS: List[Dict[str, Any]] = [
	{
		"code": "shelf_50x30",
		"name": "قفسه ۵۰×۳۰",
		"name_en": "Shelf 50×30",
		"description": "برچسب قفسه استاندارد با نام کالا و Code128",
		"width_mm": 50,
		"height_mm": 30,
		"design_json": _design_shelf(50, 30),
		"sheet_json": _sheet_a4_grid(3, 8),
	},
	{
		"code": "shelf_40x30",
		"name": "قفسه ۴۰×۳۰",
		"name_en": "Shelf 40×30",
		"description": "برچسب فشرده قفسه",
		"width_mm": 40,
		"height_mm": 30,
		"design_json": _design_shelf(40, 30),
		"sheet_json": _sheet_a4_grid(4, 8),
	},
	{
		"code": "price_70x40",
		"name": "قیمت ۷۰×۴۰",
		"name_en": "Price 70×40",
		"description": "برچسب قیمت با نام، بارکد و قیمت فروش",
		"width_mm": 70,
		"height_mm": 40,
		"design_json": _design_shelf(70, 40, with_price=True),
		"sheet_json": _sheet_a4_grid(2, 6),
	},
	{
		"code": "qr_50x50",
		"name": "QR ۵۰×۵۰",
		"name_en": "QR 50×50",
		"description": "برچسب مربعی با QR و نام کالا",
		"width_mm": 50,
		"height_mm": 50,
		"design_json": {
			"schema_version": 1,
			"canvas": {
				"width_mm": 50,
				"height_mm": 50,
				"grid_mm": 1,
				"snap_to_grid": True,
				"guides_mm": {"vertical": [], "horizontal": []},
				"dpi": 300,
			},
			"elements": [
				{
					"id": "el_name",
					"type": "text",
					"name": "product_name",
					"x_mm": 2,
					"y_mm": 1.5,
					"w_mm": 46,
					"h_mm": 7,
					"rotation_deg": 0,
					"z_index": 1,
					"locked": False,
					"visible": True,
					"props": {
						"content_mode": "binding",
						"text": "",
						"binding": "product.name",
						"font_family": "YekanBakhFaNum",
						"font_size_pt": 9,
						"font_weight": "bold",
						"align": "center",
						"valign": "middle",
						"color": "#000000",
						"rtl": True,
						"wrap": True,
					},
				},
				{
					"id": "el_qr",
					"type": "qr",
					"name": "main_qr",
					"x_mm": 10,
					"y_mm": 10,
					"w_mm": 30,
					"h_mm": 30,
					"rotation_deg": 0,
					"z_index": 2,
					"locked": False,
					"visible": True,
					"props": {
						"content_mode": "binding",
						"value": "",
						"binding": "product.general_barcode",
						"ecc": "M",
						"quiet_zone_mm": 1,
					},
				},
				{
					"id": "el_code",
					"type": "text",
					"name": "product_code",
					"x_mm": 2,
					"y_mm": 42,
					"w_mm": 46,
					"h_mm": 5,
					"rotation_deg": 0,
					"z_index": 3,
					"locked": False,
					"visible": True,
					"props": {
						"content_mode": "binding",
						"text": "",
						"binding": "product.code",
						"font_family": "YekanBakhFaNum",
						"font_size_pt": 7,
						"font_weight": "normal",
						"align": "center",
						"valign": "middle",
						"color": "#333333",
						"rtl": False,
						"wrap": False,
					},
				},
			],
		},
		"sheet_json": _sheet_a4_grid(3, 5),
	},
]


def list_presets() -> List[Dict[str, Any]]:
	items: List[Dict[str, Any]] = []
	for p in _PRESETS:
		items.append(
			{
				"code": p["code"],
				"name": p["name"],
				"name_en": p["name_en"],
				"description": p["description"],
				"width_mm": p["width_mm"],
				"height_mm": p["height_mm"],
				"thumbnail_url": None,
			}
		)
	return items


def get_preset(code: str) -> Dict[str, Any] | None:
	for p in _PRESETS:
		if p["code"] == code:
			return deepcopy(p)
	return None


def empty_design(width_mm: float = 50, height_mm: float = 30) -> Dict[str, Any]:
	return {
		"schema_version": 1,
		"canvas": {
			"width_mm": width_mm,
			"height_mm": height_mm,
			"grid_mm": 1,
			"snap_to_grid": True,
			"guides_mm": {"vertical": [], "horizontal": []},
			"dpi": 300,
		},
		"elements": [],
	}


def default_sheet() -> Dict[str, Any]:
	return _sheet_a4_grid(3, 8)
