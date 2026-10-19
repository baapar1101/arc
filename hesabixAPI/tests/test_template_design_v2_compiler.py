from __future__ import annotations

from jinja2 import BaseLoader, StrictUndefined
from jinja2.sandbox import SandboxedEnvironment

from app.services.report_template_gallery import default_design_for_family, list_gallery_items
from app.services.report_template_v2_service import migrate_builder_design_to_v2, validate_v2_design
from app.services.report_template_v3_service import (
	migrate_v2_design_to_v3,
	studio_block_catalog,
	validate_v3_design,
)
from app.services.template_design_v2_compiler import compile_v2_design_to_jinja_html
from app.services.template_design_v3_compiler import compile_v3_design_to_jinja_html


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
	validation = validate_v3_design("invoices", "detail", design)
	assert validation["errors"] == []
	html, css, _, _ = compile_v3_design_to_jinja_html(design)
	assert '<html dir="ltr">' in html
	assert "direction: ltr;" in css
	assert 'class="rt-block rt-block-align-center"' in html


def test_v3_validation_rejects_invalid_direction_and_alignment():
	design_v2 = default_design_for_family("invoice_classic")
	assert design_v2 is not None
	design = migrate_v2_design_to_v3(design_v2)
	design["theme"]["direction"] = "diagonal"
	design["regions"]["body"][0]["style"] = {"text_align": "wide"}
	validation = validate_v3_design("invoices", "detail", design)
	assert "Invalid theme.direction" in validation["errors"]
	assert any("Invalid text alignment" in error for error in validation["errors"])


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
