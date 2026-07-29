from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from typing import Any, Dict, List, Optional


@dataclass(frozen=True)
class TemplateFamily:
	id: str
	module_key: str
	subtype: Optional[str]
	label_fa: str
	label_en: str
	description_fa: str
	preview_accent: str
	tags: tuple[str, ...]
	layout: str


def _theme(primary: str, accent: str, *, base: int = 11) -> Dict[str, Any]:
	return {
		"primary_color": primary,
		"accent_color": accent,
		"text_color": "#212529",
		"font_size_base": base,
	}


def _branding() -> Dict[str, Any]:
	return {
		"show_logo": True,
		"logo_source": "business",
		"custom_logo_data_uri": None,
		"show_business_name": True,
		"business_name_override": "",
	}


def _cols(items: List[tuple[str, str, str, str]]) -> List[Dict[str, Any]]:
	return [
		{"key": k, "title": t, "visible": True, "format": fmt, "width": w}
		for k, t, fmt, w in items
	]


def _invoice_detail_columns() -> List[Dict[str, Any]]:
	return _cols([
		("product_name", "شرح", "", "32%"),
		("quantity", "تعداد", "", "10%"),
		("unit_price", "فی", "money", "14%"),
		("line_total", "مبلغ", "money", "14%"),
	])


def _invoice_detail_totals() -> List[Dict[str, Any]]:
	return [
		{"key": "subtotal", "title": "جمع اقلام", "expr": "invoice.subtotal", "visible": True, "format": "money"},
		{"key": "discount", "title": "تخفیف", "expr": "invoice.discount_total", "visible": True, "format": "money"},
		{"key": "tax", "title": "مالیات", "expr": "invoice.tax_total", "visible": True, "format": "money"},
		{"key": "payable", "title": "قابل پرداخت", "expr": "invoice.payable_total", "visible": True, "format": "money", "emphasis": True},
	]


def _design_base(family_id: str, layout: str, theme: Dict[str, Any], **extra: Any) -> Dict[str, Any]:
	return {
		"schema_version": 2,
		"family_id": family_id,
		"layout": layout,
		"theme": theme,
		"branding": _branding(),
		"custom_css": "",
		**extra,
	}


def _invoice_detail_design(family_id: str, theme: Dict[str, Any], sections: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
	base_sections = {
		"show_seller_info": True,
		"show_buyer_info": True,
		"show_payments": True,
		"show_footer_note": True,
		"show_qr": False,
		"show_signatures": True,
		"show_seller_signature": True,
		"show_buyer_signature": True,
		"show_print_time": True,
		"show_preparer": True,
	}
	if sections:
		base_sections.update(sections)
	return _design_base(
		family_id,
		"invoice_detail",
		theme,
		sections=base_sections,
		table={"items_var": "lines", "striped": True, "bordered": True, "columns": _invoice_detail_columns()},
		totals={"rows": _invoice_detail_totals()},
	)


def _generic_list_design(
	family_id: str,
	theme: Dict[str, Any],
	columns: List[Dict[str, Any]],
	*,
	modern_header: bool = False,
) -> Dict[str, Any]:
	return _design_base(
		family_id,
		"generic_list",
		theme,
		header_style="modern" if modern_header else "classic",
		sections={"show_title": True, "show_date": True, "show_footer_note": False},
		table={"items_var": "items", "striped": True, "bordered": True, "columns": columns},
	)


def _document_detail_design(family_id: str, theme: Dict[str, Any]) -> Dict[str, Any]:
	return _design_base(
		family_id,
		"document_detail",
		theme,
		sections={
			"show_meta": True,
			"show_description": True,
			"show_totals_row": True,
			"show_signatures": False,
			"show_print_time": True,
		},
		table={
			"items_var": "lines",
			"striped": True,
			"bordered": True,
			"columns": _cols([
				("description", "شرح", "", "46%"),
				("debit", "بدهکار", "money", "27%"),
				("credit", "بستانکار", "money", "27%"),
			]),
		},
		totals={
			"rows": [
				{"key": "debit", "title": "جمع بدهکار", "expr": "total_debit", "visible": True, "format": "money", "emphasis": True},
				{"key": "credit", "title": "جمع بستانکار", "expr": "total_credit", "visible": True, "format": "money", "emphasis": True},
			],
		},
	)


def _receipt_detail_design(family_id: str, theme: Dict[str, Any]) -> Dict[str, Any]:
	return _design_base(
		family_id,
		"receipt_detail",
		theme,
		sections={
			"show_meta": True,
			"show_description": True,
			"show_person_lines": True,
			"show_account_lines": True,
			"show_total": True,
			"show_print_time": True,
		},
		table={
			"items_var": "account_lines",
			"striped": True,
			"bordered": True,
			"columns": _cols([
				("account_name", "حساب", "", "40%"),
				("side", "نوع", "", "20%"),
				("amount", "مبلغ", "money", "24%"),
			]),
		},
		totals={
			"rows": [
				{"key": "total", "title": "جمع کل", "expr": "total_amount", "visible": True, "format": "money", "emphasis": True},
			],
		},
	)


def _transfer_detail_design(family_id: str, theme: Dict[str, Any]) -> Dict[str, Any]:
	return _design_base(
		family_id,
		"transfer_detail",
		theme,
		sections={
			"show_meta": True,
			"show_source_dest": True,
			"show_description": True,
			"show_account_lines": True,
			"show_commission": True,
			"show_total": True,
			"show_print_time": True,
		},
		table={
			"items_var": "account_lines",
			"striped": True,
			"bordered": True,
			"columns": _cols([
				("account_name", "حساب", "", "34%"),
				("account_code", "کد", "", "16%"),
				("side", "سمت", "", "18%"),
				("amount", "مبلغ", "money", "22%"),
			]),
		},
		totals={
			"rows": [
				{"key": "total", "title": "مبلغ انتقال", "expr": "total_amount", "visible": True, "format": "money", "emphasis": True},
				{"key": "commission", "title": "کارمزد", "expr": "commission", "visible": True, "format": "money"},
			],
		},
	)


def _postal_label_design(family_id: str, theme: Dict[str, Any], *, compact: bool = False) -> Dict[str, Any]:
	return _design_base(
		family_id,
		"postal_label",
		theme,
		sections={
			"show_sender": True,
			"show_receiver": True,
			"show_warehouse": True,
			"show_lines": True,
			"show_delivery": True,
			"show_tracking": True,
			"show_source": True,
			"show_qr": False,
		},
		meta={"compact": compact},
	)


_LIST_COLS_INVOICE = _cols([
	("code", "کد", "", "14%"),
	("title", "عنوان", "", "28%"),
	("issue_date", "تاریخ", "date", "14%"),
	("payable_total", "مبلغ", "money", "16%"),
])

_LIST_COLS_RP = _cols([
	("code", "کد", "", "14%"),
	("document_date", "تاریخ", "date", "14%"),
	("total_amount", "مبلغ", "money", "16%"),
	("description", "توضیحات", "", "28%"),
])

_LIST_COLS_DOC = _cols([
	("code", "کد", "", "14%"),
	("document_date", "تاریخ", "date", "14%"),
	("document_type_name", "نوع", "", "18%"),
	("total_debit", "بدهکار", "money", "14%"),
])

_LIST_COLS_TRANSFER = _cols([
	("code", "کد", "", "14%"),
	("document_date", "تاریخ", "date", "14%"),
	("total_amount", "مبلغ", "money", "16%"),
	("description", "توضیحات", "", "28%"),
])

_LIST_COLS_EI = _cols([
	("code", "کد", "", "14%"),
	("document_date", "تاریخ", "date", "14%"),
	("amount", "مبلغ", "money", "16%"),
	("description", "شرح", "", "28%"),
])


_FAMILIES: List[TemplateFamily] = [
	# invoices
	TemplateFamily("invoice_classic", "invoices", "detail", "فاکتور کلاسیک", "Classic Invoice", "چیدمان سنتی با حاشیه و جدول مشخص", "#1e3a5f", ("فاکتور", "رسمی"), "invoice_detail"),
	TemplateFamily("invoice_modern", "invoices", "detail", "فاکتور مدرن", "Modern Invoice", "سربرگ رنگی و فضای سفید بیشتر", "#2563eb", ("فاکتور", "مدرن"), "invoice_detail"),
	TemplateFamily("invoice_compact", "invoices", "detail", "فاکتور فشرده", "Compact Invoice", "فونت کوچک‌تر برای اقلام زیاد", "#0f766e", ("فاکتور", "فشرده"), "invoice_detail"),
	TemplateFamily("list_standard", "invoices", "list", "لیست استاندارد", "Standard List", "جدول خوانا برای لیست فاکتورها", "#475569", ("لیست",), "generic_list"),
	TemplateFamily("list_modern", "invoices", "list", "لیست مدرن", "Modern List", "لیست با سربرگ رنگی", "#7c3aed", ("لیست", "مدرن"), "generic_list"),
	# receipts_payments
	TemplateFamily("rp_list_standard", "receipts_payments", "list", "لیست دریافت/پرداخت", "RP List", "گزارش لیستی رسیدها", "#0369a1", ("دریافت", "لیست"), "generic_list"),
	TemplateFamily("rp_detail_classic", "receipts_payments", "detail", "رسید کلاسیک", "RP Detail", "جزئیات دریافت/پرداخت با جدول حساب‌ها", "#0c4a6e", ("رسید",), "receipt_detail"),
	# documents
	TemplateFamily("doc_list_standard", "documents", "list", "لیست اسناد", "Documents List", "گزارش لیستی اسناد حسابداری", "#4b5563", ("سند", "لیست"), "generic_list"),
	TemplateFamily("doc_detail_classic", "documents", "detail", "سند حسابداری", "Document Detail", "سند با جدول بدهکار/بستانکار", "#374151", ("سند",), "document_detail"),
	# transfers
	TemplateFamily("transfer_list_standard", "transfers", "list", "لیست انتقالات", "Transfers List", "گزارش لیستی انتقالات", "#155e75", ("انتقال", "لیست"), "generic_list"),
	TemplateFamily("transfer_detail_classic", "transfers", "detail", "انتقال کلاسیک", "Transfer Detail", "جزئیات سند انتقال", "#164e63", ("انتقال",), "transfer_detail"),
	# expense_income
	TemplateFamily("ei_list_standard", "expense_income", "list", "لیست هزینه/درآمد", "Expense/Income List", "گزارش لیستی هزینه و درآمد", "#b45309", ("هزینه", "لیست"), "generic_list"),
	# warehouse postal
	TemplateFamily("postal_label_classic", "warehouse_documents", "postal_label", "برچسب پستی کلاسیک", "Postal Label", "برچسب پستی با بلوک فرستنده/گیرنده", "#be123c", ("انبار", "پستی"), "postal_label"),
	TemplateFamily("postal_label_compact", "warehouse_documents", "postal_label", "برچسب پستی فشرده", "Postal Compact", "برچسب کوچک برای چاپ سریع", "#9f1239", ("انبار", "فشرده"), "postal_label"),
]

_FAMILY_MAP: Dict[str, TemplateFamily] = {f.id: f for f in _FAMILIES}

_DEFAULT_DESIGNS: Dict[str, Dict[str, Any]] = {
	"invoice_classic": _invoice_detail_design("invoice_classic", _theme("#1e3a5f", "#366092")),
	"invoice_modern": _invoice_detail_design("invoice_modern", _theme("#2563eb", "#3b82f6")),
	"invoice_compact": _invoice_detail_design(
		"invoice_compact",
		_theme("#0f766e", "#14b8a6", base=9),
		{"show_payments": False},
	),
	"list_standard": _generic_list_design("list_standard", _theme("#475569", "#64748b"), _LIST_COLS_INVOICE),
	"list_modern": _generic_list_design("list_modern", _theme("#7c3aed", "#8b5cf6"), _LIST_COLS_INVOICE, modern_header=True),
	"rp_list_standard": _generic_list_design("rp_list_standard", _theme("#0369a1", "#0284c7"), _LIST_COLS_RP),
	"rp_detail_classic": _receipt_detail_design("rp_detail_classic", _theme("#0c4a6e", "#0369a1")),
	"doc_list_standard": _generic_list_design("doc_list_standard", _theme("#4b5563", "#6b7280"), _LIST_COLS_DOC),
	"doc_detail_classic": _document_detail_design("doc_detail_classic", _theme("#374151", "#4b5563")),
	"transfer_list_standard": _generic_list_design("transfer_list_standard", _theme("#155e75", "#0891b2"), _LIST_COLS_TRANSFER),
	"transfer_detail_classic": _transfer_detail_design("transfer_detail_classic", _theme("#164e63", "#0e7490")),
	"ei_list_standard": _generic_list_design("ei_list_standard", _theme("#b45309", "#d97706"), _LIST_COLS_EI),
	"postal_label_classic": _postal_label_design("postal_label_classic", _theme("#be123c", "#e11d48")),
	"postal_label_compact": _postal_label_design("postal_label_compact", _theme("#9f1239", "#be123c"), compact=True),
}


def default_family_for_scope(module_key: str, subtype: Optional[str]) -> Optional[str]:
	mapping = {
		("invoices", "detail"): "invoice_classic",
		("invoices", "list"): "list_standard",
		("receipts_payments", "detail"): "rp_detail_classic",
		("receipts_payments", "list"): "rp_list_standard",
		("documents", "detail"): "doc_detail_classic",
		("documents", "list"): "doc_list_standard",
		("transfers", "detail"): "transfer_detail_classic",
		("transfers", "list"): "transfer_list_standard",
		("expense_income", "list"): "ei_list_standard",
		("warehouse_documents", "postal_label"): "postal_label_classic",
	}
	return mapping.get((module_key, subtype or "")) or mapping.get((module_key, subtype))


def list_gallery_items(
	module_key: Optional[str] = None,
	subtype: Optional[str] = None,
) -> List[Dict[str, Any]]:
	items: List[Dict[str, Any]] = []
	for fam in _FAMILIES:
		if module_key and fam.module_key != module_key:
			continue
		if subtype is not None and fam.subtype != subtype:
			continue
		items.append(
			{
				"id": fam.id,
				"module_key": fam.module_key,
				"subtype": fam.subtype,
				"layout": fam.layout,
				"label_fa": fam.label_fa,
				"label_en": fam.label_en,
				"description_fa": fam.description_fa,
				"preview_accent": fam.preview_accent,
				"tags": list(fam.tags),
				"default_design": deepcopy(_DEFAULT_DESIGNS[fam.id]),
			}
		)
	return items


def get_family(family_id: str) -> Optional[TemplateFamily]:
	return _FAMILY_MAP.get(family_id)


def default_design_for_family(family_id: str) -> Optional[Dict[str, Any]]:
	design = _DEFAULT_DESIGNS.get(family_id)
	return deepcopy(design) if design else None


def is_v2_design(design: Dict[str, Any]) -> bool:
	try:
		return int(design.get("schema_version") or 0) == 2
	except Exception:
		return False
