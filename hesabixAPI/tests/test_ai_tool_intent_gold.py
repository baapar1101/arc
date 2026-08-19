"""مجموعه طلایی recall انتخاب ابزار (TOOL-01)."""
from __future__ import annotations

from app.services.ai.ai_constants import MAX_TOOLS_PER_REQUEST
from app.services.ai.ai_tool_intent import (
    _CATEGORY_TOOLS,
    _CORE_TOOL_NAMES,
    _WRITE_TOOLS,
    detect_categories,
    merge_tool_allowlists,
    select_tool_names,
)
from app.services.ai.ai_tool_rank import rank_and_cap_tool_names, score_tool_for_query

GOLD_CASES: list[tuple[str, tuple[str, ...]]] = [
    ("گزارش فاکتور فروش ماه گذشته", ("search_invoices", "get_sales_report")),
    ("موجودی انبار و کاردکس کالا", ("get_inventory_status", "get_product_kardex")),
    ("سرنخ‌های این هفته را لیست کن", ("search_leads",)),
    ("امتیاز باشگاه مشتریان چقدر است", ("get_customer_club_settings",)),
    ("وضعیت سینک باسلام چطور است", ("get_basalam_overview",)),
    ("سفارش‌های ووکامرس را نشان بده", ("list_woocommerce_orders",)),
    ("گزارش بدهکاران", ("get_debtors_report",)),
    ("یک مشتری جدید به نام علی اضافه کن", ("create_person",)),
    ("یه شخص با نام علی اضافه کن و براش شماره کارت بانک مهر را بگذار", ("create_person",)),
    ("لیست گردش‌کارهای اتوماسیون", ("list_workflows",)),
    ("قالب چاپ فاکتور", ("list_report_templates",)),
    ("آیا افزونه باشگاه مشتریان فعال است", ("list_business_plugins",)),
    ("تنظیمات مالیات مودیان", ("get_tax_settings",)),
    ("لیست محصولات و کالاها", ("search_products",)),
    ("یک کالای جدید با بارکد و انبار پیش‌فرض اضافه کن", ("create_product",)),
    ("قیمت کالای پیچ را ویرایش کن", ("update_product",)),
    ("موجودی کیف پول کسب‌وکار", ("get_wallet_overview",)),
    ("سرفصل حساب‌های کل", ("list_accounts",)),
    ("یه فاکتور برای علی بزن", ("create_invoice", "list_currencies")),
    ("حواله ورود انبار بزن", ("create_warehouse_document", "list_warehouses")),
    ("یک چک دریافتی ثبت کن", ("create_check",)),
    ("اتوماسیون جدید بساز", ("create_workflow", "get_workflow_design_rules")),
]


def _catalog_names() -> set[str]:
    names = set(_CORE_TOOL_NAMES) | set(_WRITE_TOOLS)
    for group in _CATEGORY_TOOLS.values():
        names |= set(group)
    names |= {f"zzz_filler_{i:03d}" for i in range(30)}
    return names


def test_gold_set_recall_at_least_95_percent():
    catalog = _catalog_names()
    hits = 0
    total = 0
    missed: list[str] = []
    for query, required in GOLD_CASES:
        selected = select_tool_names(catalog, query)
        assert len(selected) <= MAX_TOOLS_PER_REQUEST
        for tool in required:
            total += 1
            if tool in selected:
                hits += 1
            else:
                missed.append(f"{query!r} → {tool}")
    recall = hits / total if total else 0.0
    assert recall >= 0.95, f"recall={recall:.2%} missed={missed}"


def test_rank_keeps_basalam_when_capped():
    names = {f"aaa_filler_{i:03d}" for i in range(60)}
    names |= {
        "query_business_data",
        "get_basalam_overview",
        "list_basalam_dead_letter",
        "search_invoices",
    }
    capped = rank_and_cap_tool_names(
        names,
        "وضعیت باسلام و صف خطا",
        max_tools=12,
        core_names=_CORE_TOOL_NAMES,
    )
    assert "get_basalam_overview" in capped
    assert "list_basalam_dead_letter" in capped
    assert len(capped) <= 12


def test_basalam_score_beats_unrelated_filler():
    q = "خلاصه باسلام"
    assert score_tool_for_query("get_basalam_overview", q) > score_tool_for_query(
        "aaa_filler_001", q
    )


def test_history_followup_keeps_integration_tools():
    catalog = _catalog_names()
    history = [{"role": "user", "content": "وضعیت سینک باسلام را بررسی کن"}]
    selected = select_tool_names(catalog, "صف خطا چطور شد", history_messages=history)
    assert "list_basalam_dead_letter" in selected
    assert "get_basalam_overview" in selected


def test_skill_union_does_not_drop_intent_tools():
    merged = merge_tool_allowlists(
        {"search_invoices", "get_sales_report"},
        skill_names={"hscript_search_docs"},
        forced_names={"create_invoice"},
    )
    assert "search_invoices" in merged
    assert "hscript_search_docs" in merged
    assert "create_invoice" in merged


def test_prefer_names_survive_cap():
    catalog = _catalog_names()
    # سوال چنددامنه‌ای که سقف ۴۸ را پر می‌کند
    query = (
        "گزارش فاکتور فروش انبار موجودی سرنخ باشگاه مالیات "
        "پروژه ووکامرس اتوماسیون مشتری کالا قالب افزونه"
    )
    selected = select_tool_names(
        catalog,
        query,
        prefer_names={"hscript_language_guide"},
    )
    assert len(selected) <= MAX_TOOLS_PER_REQUEST
    assert "hscript_language_guide" in selected


def test_invoice_write_keeps_currency_companion_when_capped():
    catalog = _catalog_names()
    selected = select_tool_names(catalog, "یه فاکتور فروش برای رضا بزن")
    assert "create_invoice" in selected
    assert "list_currencies" in selected
    assert "search_persons" in selected
    assert "search_products" in selected
    assert len(selected) <= MAX_TOOLS_PER_REQUEST


def test_warehouse_and_workflow_write_keep_companions():
    catalog = _catalog_names()
    wh = select_tool_names(catalog, "حواله ورود انبار بزن")
    assert "create_warehouse_document" in wh
    assert "list_warehouses" in wh
    wf = select_tool_names(catalog, "اتوماسیون جدید بساز")
    assert "create_workflow" in wf
    assert "get_workflow_design_rules" in wf
    rec = select_tool_names(catalog, "یک دریافت از علی ثبت کن")
    assert "create_receipt_payment" in rec
    assert "list_bank_accounts" in rec


def test_wallet_and_accounts_categories_detected():
    assert "financial" in detect_categories("موجودی کیف پول")
    assert "financial" in detect_categories("سرفصل حساب کل")
    assert "hscript" in detect_categories("راهنمای hscript")
    assert "products_write" in detect_categories("لیست کالاها")
    assert "marketplace" in detect_categories("افزونه باشگاه فعال است؟")
