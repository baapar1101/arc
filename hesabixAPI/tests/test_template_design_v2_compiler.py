from __future__ import annotations

from copy import deepcopy
import re
from types import SimpleNamespace
from unittest.mock import MagicMock

from jinja2 import BaseLoader, StrictUndefined
from jinja2.sandbox import SandboxedEnvironment
import pytest

from app.core.responses import ApiError
from app.services.report_template_gallery import default_design_for_family, list_gallery_items
from app.services.report_template_service import ReportTemplateService
from app.services.report_template_v2_service import migrate_builder_design_to_v2, validate_v2_design
from app.services.report_template_v3_service import (
	migrate_v2_design_to_v3,
	studio_block_catalog,
	validate_v3_design,
)
from app.services.report_template_v4_service import (
	active_variant_key,
	migrate_v3_design_to_v4,
	studio_v4_contract,
	validate_v4_design,
)
from app.services.template_design_v2_compiler import compile_v2_design_to_jinja_html
from app.services.template_design_v3_compiler import compile_v3_design_to_jinja_html
from app.services.template_design_v4_compiler import compile_v4_design_to_jinja_html


def _sample_invoice_context() -> dict:
	return {
		"title_text": "فاکتور فروش",
		"business_name": "تست",
		"invoice": {
			"code": "INV-1",
			"issue_date": "1403/01/01",
			"subtotal": 1000,
			"discount_total": 100,
			"tax_total": 90,
			"payable_total": 990,
		},
		"lines": [
			{"product_name": "A", "quantity": 1, "quantity_display": "1", "unit_price": 1000, "line_total": 1000},
		],
		"buyer": {"name": "خریدار"},
		"seller": {"name": "فروشنده"},
		"payments": [],
		"generated_at": "now",
		"issuer_name": "user",
		"is_fa": True,
		"show_line_discount_column": True,
		"show_line_tax_column": True,
		"show_line_amount_before_discount_column": True,
		"show_line_amount_before_tax_column": True,
		"show_summary_discount": True,
		"show_summary_tax": True,
		"show_summary_amount_without_tax": True,
	}


def test_gallery_lists_invoice_families():
	items = list_gallery_items(module_key="invoices", subtype="detail")
	ids = {i["id"] for i in items}
	assert "invoice_classic" in ids
	assert "invoice_modern" in ids


def test_gallery_lists_invoice_receipt_families():
	items = list_gallery_items(module_key="invoices", subtype="receipt")
	ids = {i["id"] for i in items}
	assert "invoice_receipt_simple" in ids
	assert "invoice_receipt_branded" in ids


def test_validate_v2_design_accepts_default_classic():
	design = default_design_for_family("invoice_classic")
	assert design is not None
	out = validate_v2_design("invoices", "detail", design)
	assert out["errors"] == []


def test_compile_and_render_invoice_classic():
	design = default_design_for_family("invoice_classic")
	assert design is not None
	html, css, header, footer = compile_v2_design_to_jinja_html(design)
	assert "<table" in html
	assert "lines" in html
	env = SandboxedEnvironment(loader=BaseLoader(), autoescape=True, undefined=StrictUndefined)
	env.filters["money"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	env.filters["date"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	full = f"<style>{css}</style>{header}{html}{footer}"
	rendered = env.from_string(full).render(**_sample_invoice_context())
	assert "INV-1" in rendered
	assert "A" in rendered


def test_compile_and_render_invoice_classic_without_optional_display_flags():
	design = default_design_for_family("invoice_classic")
	assert design is not None
	html, css, header, footer = compile_v2_design_to_jinja_html(design)
	context = _sample_invoice_context()
	for key in (
		"show_line_discount_column",
		"show_line_tax_column",
		"show_line_amount_before_discount_column",
		"show_line_amount_before_tax_column",
		"show_summary_discount",
		"show_summary_tax",
		"show_summary_amount_without_tax",
	):
		context.pop(key)
	env = SandboxedEnvironment(loader=BaseLoader(), autoescape=True, undefined=StrictUndefined)
	env.filters["money"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	env.filters["date"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	full = f"<style>{css}</style>{header}{html}{footer}"
	rendered = env.from_string(full).render(**context)
	assert "INV-1" in rendered
	assert "تخفیف" in rendered


def test_compile_and_render_invoice_receipt():
	design = default_design_for_family("invoice_receipt_simple")
	assert design is not None
	out = validate_v2_design("invoices", "receipt", design)
	assert out["errors"] == []
	html, css, header, footer = compile_v2_design_to_jinja_html(design)
	assert "rt-receipt-items" in html
	assert "lines" in html
	env = SandboxedEnvironment(loader=BaseLoader(), autoescape=True, undefined=StrictUndefined)
	env.filters["money"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	env.filters["date"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	full = f"<style>{css}</style>{header}{html}{footer}"
	rendered = env.from_string(full).render(**_sample_invoice_context())
	assert "INV-1" in rendered
	assert "A" in rendered


def test_migrate_builder_table_columns():
	builder = {
		"css": ".x{color:red}",
		"header": [],
		"blocks": [
			{
				"type": "table",
				"props": {
					"items": "lines",
					"columns": [
						{"key": "name", "title": "نام", "format": ""},
					],
				},
			}
		],
		"footer": [],
	}
	design = migrate_builder_design_to_v2("invoices", "detail", builder)
	assert design["table"]["items_var"] == "lines"
	assert design["table"]["columns"][0]["key"] == "name"
	assert ".x" in design.get("custom_css", "")


def test_gallery_covers_all_scopes():
	items = list_gallery_items()
	assert len(items) >= 14
	modules = {(i["module_key"], i.get("subtype")) for i in items}
	assert ("receipts_payments", "detail") in modules
	assert ("warehouse_documents", "postal_label") in modules
	assert ("invoices", "receipt") in modules


def test_compile_postal_label():
	design = default_design_for_family("postal_label_classic")
	assert design is not None
	html, css, header, footer = compile_v2_design_to_jinja_html(design)
	assert "sender" in html
	assert "receiver" in html


def test_migrate_invoice_design_to_v3_and_render_strict():
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design = migrate_v2_design_to_v3(design_v2)
	assert design["schema_version"] == 3
	assert design["theme"]["direction"] == "rtl"
	assert design["media"]["preset"] == "A4"
	assert design["media"]["width_mm"] == 210
	assert [block["type"] for block in design["regions"]["body"]][:3] == [
		"party_info",
		"party_info",
		"invoice_lines",
	]
	validation = validate_v3_design("invoices", "detail", design)
	assert validation["errors"] == []
	html, css, header, footer = compile_v3_design_to_jinja_html(design)
	env = SandboxedEnvironment(loader=BaseLoader(), autoescape=True, undefined=StrictUndefined)
	env.filters["money"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	env.filters["date"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	rendered = env.from_string(f"<style>{css}</style>{header}{html}{footer}").render(**_sample_invoice_context())
	assert "INV-1" in rendered
	assert "A" in rendered


def test_v3_compiler_preserves_dragged_block_order():
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design = migrate_v2_design_to_v3(design_v2)
	body = design["regions"]["body"]
	body.insert(0, {"id": "custom-first", "type": "custom_text", "visible": True, "props": {"text": "ابتدای بدنه"}, "style": {}})
	html, _, _, _ = compile_v3_design_to_jinja_html(design)
	assert html.index("ابتدای بدنه") < html.index("rt-party")


def test_v3_compiler_applies_ltr_direction_and_block_text_alignment():
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design = migrate_v2_design_to_v3(design_v2)
	design["theme"]["direction"] = "ltr"
	design["regions"]["body"].insert(
		0,
		{
			"id": "centered-text",
			"type": "custom_text",
			"visible": True,
			"props": {"text": "Centered"},
			"style": {"text_align": "center"},
		},
	)
	design["regions"]["body"][0]["style"]["width_mode"] = "percentage"
	design["regions"]["body"][0]["style"]["width_value"] = 60
	validation = validate_v3_design("invoices", "detail", design)
	assert validation["errors"] == []
	html, css, _, _ = compile_v3_design_to_jinja_html(design)
	assert '<html dir="ltr">' in html
	assert "direction: ltr;" in css
	assert 'class="rt-block rt-block-align-center"' in html
	assert 'style="width:60%;"' in html


def test_v3_compiler_groups_blocks_in_a_sixty_column_resizable_row():
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design = migrate_v2_design_to_v3(design_v2)
	first, second = design["regions"]["body"][:2]
	for block in (first, second):
		block["style"].update(
			{
				"row_id": "party-row",
				"grid_span": 30,
				"row_height_mode": "minimum",
				"row_height_mm": 24,
			}
		)
	validation = validate_v3_design("invoices", "detail", design)
	assert validation["errors"] == []
	html, css, _, _ = compile_v3_design_to_jinja_html(design)
	assert "grid-template-columns:repeat(60" in css
	assert html.count('grid-column:span 30;') == 2
	assert html.count('class="rt-grid-row" style="min-height:24mm;"') == 1

	second["style"]["grid_span"] = 31
	validation = validate_v3_design("invoices", "detail", design)
	assert any("exceeds 60 columns" in error for error in validation["errors"])


def test_v3_render_uses_hesabix_persian_font_in_css():
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design = migrate_v2_design_to_v3(design_v2)
	template = type(
		"Template",
		(),
		{
			"engine": "template_v2",
			"assets": {"template_design": design},
			"content_html": "",
			"content_css": "",
			"header_html": "",
			"footer_html": "",
			"paper_size": "A4",
			"orientation": "portrait",
			"margins": None,
		},
	)()
	context = _sample_invoice_context()
	context["fa_font_url_regular"] = "data:font/ttf;base64,UkVHVUxBUg=="
	context["fa_font_url_bold"] = "data:font/ttf;base64,Qk9MRA=="
	rendered = ReportTemplateService.render_with_template(template, context)
	assert "font-family: 'YekanBakhFaNum'" in rendered
	assert "data:font/ttf;base64,UkVHVUxBUg==" in rendered
	assert "data:font/ttf;base64,Qk9MRA==" in rendered
	assert "{{ fa_font_url" not in rendered


def test_v3_validation_rejects_invalid_direction_and_alignment():
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design = migrate_v2_design_to_v3(design_v2)
	design["theme"]["direction"] = "diagonal"
	design["regions"]["body"][0]["style"] = {"text_align": "wide"}
	validation = validate_v3_design("invoices", "detail", design)
	assert "Invalid theme.direction" in validation["errors"]
	assert any("Invalid text alignment" in error for error in validation["errors"])


def test_v3_validation_accepts_custom_roll_and_rejects_impossible_margins():
	design_v2 = default_design_for_family("invoice_receipt_simple")
	assert design_v2 is not None
	design = migrate_v2_design_to_v3(design_v2)
	assert design["media"]["type"] == "roll"
	design["media"] = {
		"type": "roll",
		"preset": "custom",
		"width_mm": 72.5,
		"height_mode": "auto",
		"orientation": "portrait",
		"margins_mm": {"top": 3, "right": 2, "bottom": 4, "left": 2},
	}
	assert validate_v3_design("invoices", "receipt", design)["errors"] == []
	design["media"]["margins_mm"]["right"] = 40
	design["media"]["margins_mm"]["left"] = 40
	assert "Horizontal margins leave no printable width" in validate_v3_design(
		"invoices", "receipt", design
	)["errors"]


def test_v3_catalog_and_required_invoice_lines_validation():
	catalog = studio_block_catalog("invoices", "detail")
	assert any(item["type"] == "invoice_lines" and item.get("required") for item in catalog)
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design = migrate_v2_design_to_v3(design_v2)
	design["regions"]["body"] = [block for block in design["regions"]["body"] if block["type"] != "invoice_lines"]
	validation = validate_v3_design("invoices", "detail", design)
	assert any("invoice_lines" in error for error in validation["errors"])


def test_migrate_and_render_invoice_receipt_v3():
	design_v2 = default_design_for_family("invoice_receipt_simple")
	assert design_v2 is not None
	design = migrate_v2_design_to_v3(design_v2)
	validation = validate_v3_design("invoices", "receipt", design)
	assert validation["errors"] == []
	html, css, header, footer = compile_v3_design_to_jinja_html(design)
	env = SandboxedEnvironment(loader=BaseLoader(), autoescape=True, undefined=StrictUndefined)
	env.filters["money"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	env.filters["date"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	rendered = env.from_string(f"<style>{css}</style>{header}{html}{footer}").render(**_sample_invoice_context())
	assert "INV-1" in rendered
	assert "rt-receipt-items" in rendered


def test_v4_migration_is_copy_on_write_and_has_every_responsive_profile():
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design_v3 = migrate_v2_design_to_v3(design_v2)
	original = __import__("copy").deepcopy(design_v3)
	design = migrate_v3_design_to_v4(design_v3)
	assert design_v3 == original
	assert design["schema_version"] == 4
	assert design["migration"]["mode"] == "copy_on_write"
	contract = studio_v4_contract("invoices", "detail")
	profile_keys = {item["key"] for item in contract["media_profiles"]}
	assert profile_keys == set(design["variants"])
	assert {"a4_portrait", "a4_landscape", "roll_80", "custom_roll"}.issubset(profile_keys)
	assert contract["compiler"]["output"] == "html_css"
	assert contract["freeform"]["grid_sizes_mm"] == [1, 3, 5]
	assert contract["page_grid"]["grid_sizes_mm"] == [1, 3, 5]
	assert contract["page_grid"]["dynamic_components_allowed"] is True
	assert design["root"]["layout"]["type"] == "page_grid"
	landscape_layout = design["variants"]["a4_landscape"]["node_overrides"]["invoice-root"]["layout"]
	assert landscape_layout["width_mm"] == 277
	assert landscape_layout["height_mm"] == 190
	assert validate_v4_design("invoices", "detail", design)["errors"] == []


def test_v4_a4_compiles_to_traceable_html_css_and_existing_renderer():
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design = migrate_v3_design_to_v4(migrate_v2_design_to_v3(design_v2))
	assert active_variant_key(design) == "a4_portrait"
	html, css, header, footer = compile_v4_design_to_jinja_html(design)
	assert 'data-template-schema="4"' in html
	assert 'data-template-variant="a4_portrait"' in html
	assert "rt-page-grid" in html
	assert "grid-column:" in html
	assert ".rt-page-grid { display:grid" in css
	template = type(
		"Template",
		(),
		{
			"engine": "template_v2",
			"assets": {"template_design": design},
			"content_html": "",
			"content_css": "",
			"header_html": "",
			"footer_html": "",
			"paper_size": "A4",
			"orientation": "portrait",
			"margins": {"top": 10, "right": 10, "bottom": 10, "left": 10},
		},
	)()
	rendered = ReportTemplateService.render_with_template(template, _sample_invoice_context())
	assert "INV-1" in rendered
	assert "@page { size: A4 portrait;" in rendered
	assert 'data-template-node-id="invoice-lines"' in rendered


def test_v4_roll_80_uses_explicit_full_page_grid_variant():
	design_v2 = default_design_for_family("invoice_receipt_simple")
	assert design_v2 is not None
	design = migrate_v3_design_to_v4(migrate_v2_design_to_v3(design_v2))
	assert active_variant_key(design) == "roll_80"
	assert validate_v4_design("invoices", "receipt", design)["errors"] == []
	html, css, header, footer = compile_v4_design_to_jinja_html(design)
	assert 'data-template-variant="roll_80"' in html
	assert "rt-receipt-items" in html
	assert "rt-page-grid" in html
	assert 'data-template-region="body"' in html
	assert header == ""
	assert footer == ""
	env = SandboxedEnvironment(loader=BaseLoader(), autoescape=True, undefined=StrictUndefined)
	env.filters["money"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	env.filters["date"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	rendered = env.from_string(f"<style>{css}</style>{header}{html}{footer}").render(**_sample_invoice_context())
	assert "INV-1" in rendered


def test_v4_page_grid_compiles_geometry_and_allows_dynamic_table():
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design = migrate_v3_design_to_v4(migrate_v2_design_to_v3(design_v2))
	assert validate_v4_design("invoices", "detail", design)["errors"] == []
	html, _, _, _ = compile_v4_design_to_jinja_html(design)
	assert "rt-page-grid-item-dynamic" in html
	assert 'data-template-node-id="invoice-lines"' in html
	assert "min-height:" in html


def test_v4_a4_and_roll_80_render_with_the_existing_pdf_engine():
	from weasyprint import HTML

	for family_id, paper_size, orientation, expected_width_mm in (
		("invoice_classic", "A4", "portrait", 210),
		("invoice_receipt_simple", "80mm", "portrait", 80),
	):
		design_v2 = default_design_for_family(family_id)
		assert design_v2 is not None
		design = migrate_v3_design_to_v4(migrate_v2_design_to_v3(design_v2))
		template = type(
			"Template",
			(),
			{
				"engine": "template_v2",
				"assets": {"template_design": design},
				"content_html": "",
				"content_css": "",
				"header_html": "",
				"footer_html": "",
				"paper_size": paper_size,
				"orientation": orientation,
				"margins": None,
			},
		)()
		rendered = ReportTemplateService.render_with_template(template, _sample_invoice_context())
		document = HTML(string=rendered).render()
		assert document.pages
		page_width_mm = document.pages[0].width * 25.4 / 96
		assert abs(page_width_mm - expected_width_mm) < 0.2


def test_v4_full_page_grid_keeps_long_invoice_on_existing_pdf_pipeline():
	from weasyprint import HTML

	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design = migrate_v3_design_to_v4(migrate_v2_design_to_v3(design_v2))
	template = type(
		"Template",
		(),
		{
			"engine": "template_v2",
			"assets": {"template_design": design},
			"content_html": "",
			"content_css": "",
			"header_html": "",
			"footer_html": "",
			"paper_size": "A4",
			"orientation": "portrait",
			"margins": None,
		},
	)()
	context = _sample_invoice_context()
	base_line = context["lines"][0]
	context["lines"] = [{**base_line, "product_name": f"کالای شماره {index}"} for index in range(1, 81)]
	rendered = ReportTemplateService.render_with_template(template, context)
	document = HTML(string=rendered).render()
	assert len(document.pages) >= 2


def test_v4_dynamic_anchor_chain_keeps_followers_after_growing_invoice_lines():
	from weasyprint import HTML

	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design = migrate_v3_design_to_v4(migrate_v2_design_to_v3(design_v2))
	def walk(node):
		yield node
		for child in node.get("children") or []:
			yield from walk(child)
	nodes = {str(node.get("id") or ""): node for node in walk(design["root"])}
	def follow(source_id: str, target_id: str, gap_mm: float) -> None:
		nodes[source_id]["constraints"] = {
			"links": [
				{
					"id": "vertical-anchor",
					"axis": "vertical",
					"source_anchor": "top",
					"target": {"type": "node", "id": target_id, "anchor": "bottom"},
					"offset_mm": gap_mm,
					"variant_offsets": {"a4_portrait": gap_mm, "roll_80": 2},
				}
			],
			"keep_together": source_id != "invoice-lines",
		}
	follow("invoice-totals", "invoice-lines", 5)
	follow("payments", "invoice-totals", 3)
	assert validate_v4_design("invoices", "detail", design)["errors"] == []
	html, css, _, _ = compile_v4_design_to_jinja_html(design)
	assert 'data-template-anchor-chain="invoice-lines"' in html
	assert 'data-template-node-ref="invoice-totals"' in html
	assert "margin-top:5mm" in html
	assert "margin-top:3mm" in html
	assert ".rt-anchor-keep-together" in css

	template = type(
		"Template",
		(),
		{
			"engine": "template_v2",
			"assets": {"template_design": design},
			"content_html": "",
			"content_css": "",
			"header_html": "",
			"footer_html": "",
			"paper_size": "A4",
			"orientation": "portrait",
			"margins": None,
		},
	)()
	context = _sample_invoice_context()
	base_line = context["lines"][0]
	context["lines"] = [{**base_line, "product_name": f"کالای شماره {index}"} for index in range(1, 41)]
	context["payments"] = [{"method_name": "نقدی", "amount": 100}]
	document = HTML(string=ReportTemplateService.render_with_template(template, context)).render()
	assert len(document.pages) >= 2
	last_page_classes: list[tuple[str, float, float]] = []
	def collect(box) -> None:
		element = getattr(box, "element", None)
		if element is not None:
			classes = element.get("class", "")
			if any(name in classes for name in ("rt-component-invoice-lines", "rt-component-invoice-totals", "rt-component-payments")):
				last_page_classes.append((classes, box.position_y, box.height))
		for child in getattr(box, "children", []):
			collect(child)
	collect(document.pages[-1]._page_box)
	line_box = next(item for item in last_page_classes if "rt-component-invoice-lines" in item[0])
	total_box = next(item for item in last_page_classes if "rt-component-invoice-totals" in item[0])
	payment_box = next(item for item in last_page_classes if "rt-component-payments" in item[0])
	assert total_box[1] >= line_box[1] + line_box[2]
	assert payment_box[1] >= total_box[1] + total_box[2]

	design["media"] = __import__("copy").deepcopy(design["variants"]["roll_80"]["media"])
	roll_html, _, _, _ = compile_v4_design_to_jinja_html(design)
	assert 'data-template-variant="roll_80"' in roll_html
	assert "margin-top:2mm" in roll_html


def test_v4_anchor_validation_rejects_cycles_and_bad_points():
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design = migrate_v3_design_to_v4(migrate_v2_design_to_v3(design_v2))
	def walk(node):
		yield node
		for child in node.get("children") or []:
			yield from walk(child)
	nodes = {str(node.get("id") or ""): node for node in walk(design["root"])}
	nodes["invoice-lines"]["constraints"] = {
		"links": [{"axis": "vertical", "source_anchor": "top", "target": {"type": "node", "id": "payments", "anchor": "bottom"}}]
	}
	nodes["payments"]["constraints"] = {
		"links": [{"axis": "vertical", "source_anchor": "left", "target": {"type": "node", "id": "invoice-lines", "anchor": "bottom"}}]
	}
	errors = validate_v4_design("invoices", "detail", design)["errors"]
	assert "Anchor constraints contain a cycle" in errors
	assert any("horizontal point" in error.lower() for error in errors)


def _service_v4_design() -> dict:
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	return migrate_v3_design_to_v4(migrate_v2_design_to_v3(design_v2))


def _service_v4_nodes(design: dict) -> dict[str, dict]:
	def walk(node):
		yield node
		for child in node.get("children") or []:
			yield from walk(child)

	return {str(node.get("id") or ""): node for node in walk(design["root"])}


def _anchor_link(target_id: str, *, axis: str = "vertical", source: str = "top", target: str = "bottom") -> dict:
	return {
		"id": f"{axis}-anchor",
		"axis": axis,
		"source_anchor": source,
		"target": {"type": "node", "id": target_id, "anchor": target},
		"offset_mm": 5,
	}


def _invalid_service_v4_design(case: str) -> dict:
	design = _service_v4_design()
	nodes = _service_v4_nodes(design)
	if case == "cycle":
		nodes["invoice-lines"]["constraints"] = {"links": [_anchor_link("payments")]}
		nodes["payments"]["constraints"] = {"links": [_anchor_link("invoice-lines")]}
	elif case == "missing_target":
		nodes["payments"]["constraints"] = {"links": [_anchor_link("deleted-node")]}
	elif case == "duplicate_axis":
		nodes["payments"]["constraints"] = {
			"links": [_anchor_link("invoice-lines"), _anchor_link("invoice-totals")],
		}
	elif case == "multiple_followers":
		nodes["invoice-totals"]["constraints"] = {"links": [_anchor_link("invoice-lines")]}
		nodes["payments"]["constraints"] = {"links": [_anchor_link("invoice-lines")]}
	elif case == "invalid_axis":
		nodes["payments"]["constraints"] = {"links": [_anchor_link("invoice-lines", axis="diagonal")]}
	elif case == "invalid_point":
		nodes["payments"]["constraints"] = {
			"links": [_anchor_link("invoice-lines", source="left")],
		}
	else:
		raise AssertionError(case)
	return design


def _valid_service_anchor_chain() -> dict:
	design = _service_v4_design()
	nodes = _service_v4_nodes(design)
	for source_id, target_id, gap in (
		("invoice-totals", "invoice-lines", 5),
		("payments", "invoice-totals", 3),
		("signatures", "payments", 5),
	):
		link = _anchor_link(target_id)
		link["offset_mm"] = gap
		link["variant_offsets"] = {"a4_portrait": gap, "roll_80": 2}
		nodes[source_id]["constraints"] = {"links": [link], "keep_together": True}
	return design


def _node_by_component(design: dict, component: str) -> dict:
	return next(
		node
		for node in _service_v4_nodes(design).values()
		if node.get("component") == component
	)


def _template_for_v4_design(design: dict, *, paper_size: str = "A4") -> SimpleNamespace:
	return SimpleNamespace(
		engine="template_v2",
		assets={"template_design": design},
		content_html="",
		content_css="",
		header_html="",
		footer_html="",
		paper_size=paper_size,
		orientation="portrait",
		margins=None,
	)


def _context_with_line_count(count: int) -> dict:
	context = _sample_invoice_context()
	base_line = context["lines"][0]
	context["lines"] = [
		{**base_line, "product_name": f"کالای شماره {index}"}
		for index in range(1, count + 1)
	]
	context["payments"] = [{"method_name": "نقدی", "amount": 100}]
	return context


def _render_v4_pdf(design: dict, line_count: int):
	from weasyprint import HTML

	rendered = ReportTemplateService.render_with_template(
		_template_for_v4_design(design),
		_context_with_line_count(line_count),
	)
	return HTML(string=rendered).render()


def _boxes_with_attribute(document, attribute: str, value: str):
	result = []
	for page_index, page in enumerate(document.pages):
		def collect(box) -> None:
			element = getattr(box, "element", None)
			if element is not None and element.get(attribute) == value:
				result.append((page_index, box))
			for child in getattr(box, "children", []):
				collect(child)
		collect(page._page_box)
	return result


def _page_text(page) -> str:
	parts: list[str] = []
	def collect(box) -> None:
		text = getattr(box, "text", None)
		if text:
			parts.append(str(text))
		for child in getattr(box, "children", []):
			collect(child)
	collect(page._page_box)
	return " ".join(parts)


def _service_template_payload(design: dict) -> dict:
	return {
		"business_id": 1,
		"module_key": "invoices",
		"subtype": "detail",
		"name": "قالب تست",
		"engine": "template_v2",
		"content_html": "generated by template design",
		"assets": {"template_design": design},
	}


@pytest.mark.parametrize(
	"case",
	("cycle", "missing_target", "duplicate_axis", "multiple_followers", "invalid_axis", "invalid_point"),
)
@pytest.mark.parametrize("operation", ("create", "update"))
def test_v4_invalid_assets_are_rejected_before_create_or_update(case, operation, monkeypatch):
	db = MagicMock()
	invalid_assets = {"template_design": _invalid_service_v4_design(case)}
	if operation == "create":
		payload = _service_template_payload(invalid_assets["template_design"])
		with pytest.raises(ApiError) as exc:
			ReportTemplateService.create_template(db, payload, user_id=1)
	else:
		original_assets = {"template_design": _service_v4_design()}
		entity = SimpleNamespace(
			module_key="invoices",
			subtype="detail",
			assets=deepcopy(original_assets),
			version=7,
		)
		monkeypatch.setattr(
			ReportTemplateService,
			"get_template",
			staticmethod(lambda _db, _template_id, _business_id: entity),
		)
		with pytest.raises(ApiError) as exc:
			ReportTemplateService.update_template(
				db,
				template_id=10,
				data={"assets": invalid_assets},
				business_id=1,
			)
		assert entity.assets == original_assets
		assert entity.version == 7
	assert exc.value.code == "VALIDATION_ERROR"
	db.add.assert_not_called()
	db.commit.assert_not_called()


def test_v4_after_content_bottom_mode_is_rejected_before_write():
	design = _service_v4_design()
	nodes = _service_v4_nodes(design)
	nodes["payments"]["constraints"] = {
		"pins": {"bottom": True},
		"bottom_mode": "after_content",
	}
	assert any(
		"Invalid bottom pin mode" in error
		for error in validate_v4_design("invoices", "detail", design)["errors"]
	)
	db = MagicMock()
	with pytest.raises(ApiError) as exc:
		ReportTemplateService.create_template(db, _service_template_payload(design), user_id=1)
	assert exc.value.code == "VALIDATION_ERROR"
	db.add.assert_not_called()
	db.commit.assert_not_called()


def test_v4_explicit_anchor_chain_is_accepted_and_stored():
	design = _valid_service_anchor_chain()
	assert validate_v4_design("invoices", "detail", design)["errors"] == []
	db = MagicMock()
	entity = ReportTemplateService.create_template(
		db,
		_service_template_payload(design),
		user_id=1,
	)
	assert entity.assets == {"template_design": design}
	db.add.assert_called_once_with(entity)
	db.commit.assert_called_once()
	html, _, _, _ = compile_v4_design_to_jinja_html(entity.assets["template_design"])
	assert 'data-template-anchor-chain="invoice-lines"' in html
	assert 'data-template-node-ref="signatures"' in html


@pytest.mark.parametrize("schema_version", (3, 4))
def test_service_still_accepts_constraintless_v3_and_v4_designs(schema_version):
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design_v3 = migrate_v2_design_to_v3(design_v2)
	design = design_v3 if schema_version == 3 else migrate_v3_design_to_v4(design_v3)
	assert all("constraints" not in node for node in _service_v4_nodes(design)) if schema_version == 4 else True
	db = MagicMock()
	entity = ReportTemplateService.create_template(
		db,
		_service_template_payload(design),
		user_id=1,
	)
	rendered = ReportTemplateService.render_with_template(entity, _sample_invoice_context())
	assert "INV-1" in rendered
	db.commit.assert_called_once()


def test_service_v3_to_v4_copy_on_write_remains_intact_during_update(monkeypatch):
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design_v3 = migrate_v2_design_to_v3(design_v2)
	original_v3 = deepcopy(design_v3)
	design_v4 = migrate_v3_design_to_v4(design_v3)
	assert design_v3 == original_v3
	entity = SimpleNamespace(
		module_key="invoices",
		subtype="detail",
		assets={"template_design": design_v3},
		version=3,
	)
	monkeypatch.setattr(
		ReportTemplateService,
		"get_template",
		staticmethod(lambda _db, _template_id, _business_id: entity),
	)
	db = MagicMock()
	ReportTemplateService.update_template(
		db,
		template_id=11,
		data={"assets": {"template_design": design_v4}},
		business_id=1,
	)
	assert design_v3 == original_v3
	assert entity.assets["template_design"]["schema_version"] == 4
	assert entity.assets["template_design"] is design_v4
	db.commit.assert_called_once()


def test_v4_compiler_contract_is_exact():
	design = _service_v4_design()
	assert design["schema_version"] == 4
	assert design["compiler_contract"] == {
		"name": "hesabix-template-html-css",
		"version": 1,
		"output": "html_css",
	}
	contract = studio_v4_contract("invoices", "detail")
	assert contract["schema_version"] == 4
	assert contract["compiler"] == design["compiler_contract"]


@pytest.mark.parametrize("line_count", (1, 5, 40))
def test_v4_complete_dynamic_chain_follows_real_table_height(line_count):
	design = _valid_service_anchor_chain()
	document = _render_v4_pdf(design, line_count)
	chain = (
		("invoice-lines", None),
		("invoice-totals", 5),
		("payments", 3),
		("signatures", 5),
	)
	previous_last = None
	for node_id, gap_mm in chain:
		boxes = _boxes_with_attribute(document, "data-template-node-ref", node_id)
		assert boxes, f"{node_id} was not rendered"
		first = min(boxes, key=lambda item: (item[0], item[1].position_y))
		last = max(boxes, key=lambda item: (item[0], item[1].position_y))
		if gap_mm is not None:
			assert first[1].margin_top * 25.4 / 96 == pytest.approx(gap_mm, abs=0.15)
			assert previous_last is not None
			assert first[0] > previous_last[0] or (
				first[0] == previous_last[0]
				and first[1].position_y >= previous_last[1].position_y + previous_last[1].height
			)
		previous_last = last


def test_v4_dynamic_table_grows_beyond_its_designed_minimum_height():
	design = _valid_service_anchor_chain()
	line_node = _node_by_component(design, "invoice_lines")
	minimum_mm = float(line_node["placement"]["height_mm"])
	one_line = _render_v4_pdf(design, 1)
	forty_lines = _render_v4_pdf(design, 40)
	one_boxes = _boxes_with_attribute(one_line, "data-template-node-ref", "invoice-lines")
	forty_boxes = _boxes_with_attribute(forty_lines, "data-template-node-ref", "invoice-lines")
	assert sum(box.height for _, box in one_boxes) * 25.4 / 96 >= minimum_mm - 0.2
	assert sum(box.height for _, box in forty_boxes) > sum(box.height for _, box in one_boxes)


def test_v4_roll_80_uses_two_millimeter_offsets_for_the_same_chain():
	design = _valid_service_anchor_chain()
	design["media"] = deepcopy(design["variants"]["roll_80"]["media"])
	html, _, _, _ = compile_v4_design_to_jinja_html(design)
	assert 'data-template-variant="roll_80"' in html
	assert html.count("margin-top:2mm") == 3
	assert "margin-top:5mm" not in html
	assert "margin-top:3mm" not in html


def test_v4_horizontal_anchor_stays_geometric_when_invoice_lines_grow():
	design = _service_v4_design()
	payments = _node_by_component(design, "payments")
	payments["constraints"] = {
		"links": [{
			"id": "horizontal-anchor",
			"axis": "horizontal",
			"source_anchor": "left",
			"target": {"type": "node", "id": "invoice-lines", "anchor": "right"},
			"offset_mm": 2,
		}],
	}
	assert validate_v4_design("invoices", "detail", design)["errors"] == []
	one_line = _render_v4_pdf(design, 1)
	forty_lines = _render_v4_pdf(design, 40)
	positions = []
	for document in (one_line, forty_lines):
		boxes = _boxes_with_attribute(document, "data-template-node-id", "payments")
		assert boxes
		positions.append((boxes[0][0], boxes[0][1].position_x, boxes[0][1].position_y))
	assert positions[1] == pytest.approx(positions[0], abs=0.2)


def test_v4_left_and_right_pins_stretch_width_per_variant():
	design = _service_v4_design()
	totals = _node_by_component(design, "invoice_totals")
	totals["constraints"] = {
		"pins": {"left": True, "right": True},
		"pin_offsets_mm": {"left": 5, "right": 5},
		"variant_pin_offsets": {
			"a4_portrait": {"left": 5, "right": 5},
			"roll_80": {"left": 2, "right": 2},
		},
	}
	a4_html, _, _, _ = compile_v4_design_to_jinja_html(design)
	assert "grid-column:6/span 180" in a4_html
	design["media"] = deepcopy(design["variants"]["roll_80"]["media"])
	roll_html, _, _, _ = compile_v4_design_to_jinja_html(design)
	assert "grid-column:3/span 72" in roll_html


@pytest.mark.parametrize(
	("bottom_mode", "expected_pages"),
	(("last_page", "last"), ("every_page", "all")),
)
def test_v4_bottom_pin_modes_place_footer_on_expected_pages(bottom_mode, expected_pages):
	design = _service_v4_design()
	footer = _node_by_component(design, "footer_meta")
	footer["placement"] = {
		**footer["placement"],
		"x_mm": 10,
		"y_mm": 260,
		"width_mm": 100,
		"height_mm": 12,
	}
	footer["constraints"] = {
		"pins": {"bottom": True},
		"pin_offsets_mm": {"bottom": 5},
		"bottom_mode": bottom_mode,
		"keep_together": True,
	}
	document = _render_v4_pdf(design, 80)
	assert len(document.pages) >= 2
	boxes = _boxes_with_attribute(document, "data-template-node-id", footer["id"])
	pages = sorted({page for page, _ in boxes})
	assert pages == ([len(document.pages) - 1] if expected_pages == "last" else list(range(len(document.pages))))


def test_v4_keep_together_css_covers_totals_payments_and_signatures():
	design = _service_v4_design()
	html, css, _, _ = compile_v4_design_to_jinja_html(design)
	assert ".rt-anchor-keep-together { break-inside:avoid; page-break-inside:avoid; }" in css
	for node_id in ("invoice-totals", "payments", "signatures"):
		pattern = rf'class="[^"]*rt-anchor-keep-together[^"]*"[^>]*>.*?data-template-node-id="{node_id}"'
		assert re.search(pattern, html, re.DOTALL), node_id


def test_v4_table_header_repeats_and_designed_height_is_a_minimum():
	design = _valid_service_anchor_chain()
	header = str(_node_by_component(design, "invoice_lines")["props"]["columns"][0]["title"])
	document = _render_v4_pdf(design, 80)
	assert len(document.pages) >= 2
	line_pages = []
	for page_index, page in enumerate(document.pages):
		if _boxes_with_attribute(type("D", (), {"pages": [page]})(), "data-template-node-id", "invoice-lines"):
			line_pages.append(page_index)
			assert header in _page_text(page)
	assert len(line_pages) >= 2


def test_v4_editor_zoom_metadata_does_not_change_html_or_css():
	design = _service_v4_design()
	baseline = compile_v4_design_to_jinja_html(design)
	zoomed = deepcopy(design)
	zoomed["editor_state"] = {"zoom": 2.0}
	assert compile_v4_design_to_jinja_html(zoomed) == baseline


def test_v4_direction_does_not_mirror_physical_grid_geometry():
	rtl = _service_v4_design()
	ltr = deepcopy(rtl)
	ltr["theme"] = {**ltr.get("theme", {}), "direction": "ltr"}
	rtl_html, _, _, _ = compile_v4_design_to_jinja_html(rtl)
	ltr_html, _, _, _ = compile_v4_design_to_jinja_html(ltr)
	assert '<html dir="rtl"' in rtl_html
	assert '<html dir="ltr"' in ltr_html
	geometry = re.compile(r"style=\"grid-column:[^\"]+;grid-row:[^\"]+;min-height:[^\"]+\"")
	assert geometry.findall(ltr_html) == geometry.findall(rtl_html)
