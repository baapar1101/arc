from __future__ import annotations

import pytest

from app.services.report_template_v2_service import migrate_builder_design_to_v2, validate_v2_design
from app.services.report_template_gallery import default_design_for_family, list_gallery_items
from app.services.template_design_v2_compiler import compile_v2_design_to_jinja_html
from jinja2.sandbox import SandboxedEnvironment
from jinja2 import BaseLoader


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
	env = SandboxedEnvironment(loader=BaseLoader(), autoescape=True)
	env.filters["money"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	env.filters["date"] = lambda value, *args, **kwargs: str(value if value is not None else "")
	full = f"<style>{css}</style>{header}{html}{footer}"
	rendered = env.from_string(full).render(**_sample_invoice_context())
	assert "INV-1" in rendered
	assert "A" in rendered


def test_compile_and_render_invoice_receipt():
	design = default_design_for_family("invoice_receipt_simple")
	assert design is not None
	out = validate_v2_design("invoices", "receipt", design)
	assert out["errors"] == []
	html, css, header, footer = compile_v2_design_to_jinja_html(design)
	assert "rt-receipt-items" in html
	assert "lines" in html
	env = SandboxedEnvironment(loader=BaseLoader(), autoescape=True)
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
