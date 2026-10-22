from __future__ import annotations

from jinja2 import BaseLoader, StrictUndefined
from jinja2.sandbox import SandboxedEnvironment

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
