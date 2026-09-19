from __future__ import annotations

from app.services.pdf.template_renderer import render_template
from app.services.report_template_scope_registry import is_known_scope


def test_receipt_scope_is_registered():
	assert is_known_scope("invoices", "receipt") is True


def test_receipt_html_renders_narrow_layout():
	html = render_template(
		"pdf/invoices/receipt.html",
		{
			"title_text": "فاکتور فروش",
			"business_name": "فروشگاه نمونه",
			"business_logo_data_uri": None,
			"invoice": {
				"code": "INV-80",
				"issue_date": "1405/01/01",
				"title": "فاکتور فروش",
				"is_proforma": False,
				"invoice_type_name": "فروش",
				"subtotal": 1000,
				"discount_total": 0,
				"tax_total": 0,
				"payable_total": 1000,
				"final_payable_total": 1000,
				"invoice_adjustments": [],
			},
			"lines": [
				{
					"product_name": "نان",
					"product_code": "B1",
					"quantity": 2,
					"quantity_display": "2",
					"unit_display": "عدد",
					"unit_price": 500,
					"line_total": 1000,
					"description": "",
				}
			],
			"buyer": {"name": "مشتری", "mobile": "09120000000"},
			"seller": {"name": "فروشنده"},
			"payments": [],
			"is_fa": True,
			"show_summary_discount": False,
			"show_summary_tax": False,
			"show_invoice_verify_qr": False,
			"invoice_verify_qr_data_uri": None,
			"business_stamp_data_uri": None,
			"invoice_footer_note": None,
			"show_footer_print_time": True,
			"show_footer_preparer": True,
			"generated_at": "1405/01/01 12:00",
			"issuer_name": "کاربر",
			"paper_size": "80mm",
			"orientation": "portrait",
			"page_size_css": "80mm 297mm",
			"hide_page_numbers": True,
			"fa_font_url_regular": "",
			"fa_font_url_bold": "",
			"footer_text": "",
		},
	)
	assert "INV-80" in html
	assert "نان" in html
	assert "80mm 297mm" in html
	assert "ادامه فاکتور" in html
	assert "قابل پرداخت" in html
	assert 'content: "صفحه ' not in html
