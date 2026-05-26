"""
کلیدهای i18n برای نام ابزارهای AI (هماهنگ با app_*.arb در Flutter).
"""
from __future__ import annotations

from typing import Dict, Optional

# function_name -> l10n key (بدون پیشوند؛ در UI با aiTool* map می‌شود)
TOOL_L10N_KEYS: Dict[str, str] = {
    "get_business_info": "aiToolGetBusinessInfo",
    "search_invoices": "aiToolSearchInvoices",
    "get_invoice_details": "aiToolGetInvoiceDetails",
    "get_invoices_count": "aiToolGetInvoicesCount",
    "create_invoice": "aiToolCreateInvoice",
    "search_products": "aiToolSearchProducts",
    "get_product_info": "aiToolGetProductInfo",
    "get_inventory_status": "aiToolGetInventoryStatus",
    "get_product_kardex": "aiToolGetProductKardex",
    "get_customer_info": "aiToolGetCustomerInfo",
    "search_persons": "aiToolSearchPersons",
    "get_person_balance": "aiToolGetPersonBalance",
    "create_person": "aiToolCreatePerson",
    "update_person": "aiToolUpdatePerson",
    "get_financial_summary": "aiToolGetFinancialSummary",
    "get_debtors_report": "aiToolGetDebtorsReport",
    "get_creditors_report": "aiToolGetCreditorsReport",
    "search_receipts_payments": "aiToolSearchReceiptsPayments",
    "create_receipt_payment": "aiToolCreateReceiptPayment",
    "get_sales_report": "aiToolGetSalesReport",
    "get_purchase_report": "aiToolGetPurchaseReport",
    "get_inventory_valuation": "aiToolGetInventoryValuation",
    "get_cash_flow": "aiToolGetCashFlow",
    "search_leads": "aiToolSearchLeads",
    "get_lead_details": "aiToolGetLeadDetails",
    "search_deals": "aiToolSearchDeals",
    "get_deal_details": "aiToolGetDealDetails",
    "search_activities": "aiToolSearchActivities",
    "get_crm_summary": "aiToolGetCrmSummary",
    "get_pipeline_report": "aiToolGetPipelineReport",
    "get_lead_funnel_report": "aiToolGetLeadFunnelReport",
    "invoke_business_connector": "aiToolInvokeConnector",
}

# برچسب فارسی fallback برای پیام‌های سیستمی (تأیید نوشتن و غیره)
TOOL_LABELS_FA: Dict[str, str] = {
    "get_business_info": "اطلاعات کسب‌وکار",
    "search_invoices": "جستجوی فاکتور",
    "get_invoice_details": "جزئیات فاکتور",
    "get_invoices_count": "شمارش فاکتورها",
    "create_invoice": "ثبت فاکتور",
    "search_products": "جستجوی کالا",
    "get_product_info": "اطلاعات کالا",
    "get_inventory_status": "وضعیت موجودی",
    "get_product_kardex": "کاردکس کالا",
    "get_customer_info": "اطلاعات مشتری",
    "search_persons": "جستجوی اشخاص",
    "get_person_balance": "مانده شخص",
    "create_person": "ایجاد شخص",
    "update_person": "ویرایش شخص",
    "get_financial_summary": "خلاصه مالی",
    "get_debtors_report": "گزارش بدهکاران",
    "get_creditors_report": "گزارش بستانکاران",
    "search_receipts_payments": "جستجوی دریافت/پرداخت",
    "create_receipt_payment": "ثبت دریافت/پرداخت",
    "get_sales_report": "گزارش فروش",
    "get_purchase_report": "گزارش خرید",
    "get_inventory_valuation": "ارزش موجودی",
    "get_cash_flow": "جریان نقدی",
    "search_leads": "جستجوی سرنخ",
    "get_lead_details": "جزئیات سرنخ",
    "search_deals": "جستجوی فرصت",
    "get_deal_details": "جزئیات فرصت",
    "search_activities": "جستجوی فعالیت",
    "get_crm_summary": "خلاصه CRM",
    "get_pipeline_report": "گزارش قیف فروش",
    "get_lead_funnel_report": "گزارش قیف سرنخ",
    "invoke_business_connector": "فراخوانی کانکتور",
}


def tool_l10n_key(function_name: str) -> str:
    return TOOL_L10N_KEYS.get(function_name, "aiToolGeneric")


def tool_label_fa(function_name: str) -> str:
    return TOOL_LABELS_FA.get(function_name, function_name)


def status_event(phase: str, step: Optional[str] = None, tool_key: Optional[str] = None) -> Dict:
    payload: Dict = {"event": "status", "phase": phase, "done": False}
    if step:
        payload["step"] = step
    if tool_key:
        payload["tool_key"] = tool_key
    return payload
