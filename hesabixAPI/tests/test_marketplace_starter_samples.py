"""نمونه‌های مخزن ورک‌فلو: ساختار، فیلتر تریگر و جایگزینی متن."""

from app.services.workflow.marketplace_starter_samples import starter_workflow_samples
from app.services.workflow.trigger_registry import TriggerRegistry
from app.services.workflow.workflow_engine import WorkflowEngine
from app.services.workflow.workflow_marketplace_service import sanitize_workflow_for_marketplace
from adapters.api.v1.workflows import validate_workflow_data
from app.services.workflow.workflow_trigger_enrichment import person_display_name


def _by_title(title: str) -> dict:
    for sample in starter_workflow_samples():
        if sample["title"] == title:
            return sample
    raise AssertionError(title)


def _trigger_node(sample: dict) -> dict:
    return next(n for n in sample["workflow_data"]["nodes"] if n["type"] == "trigger")


def _run_trigger(sample: dict, payload: dict) -> dict:
    node = _trigger_node(sample)
    handler = TriggerRegistry().get_handler(node["config"]["trigger_type"])
    assert handler is not None
    return handler.execute({"trigger_data": payload, "db": None, "business_id": None}, node["config"])


def _message_of(sample: dict, node_id: str) -> str:
    node = next(n for n in sample["workflow_data"]["nodes"] if n["id"] == node_id)
    return node["config"]["message"]


def test_every_sample_is_valid_and_keeps_template_refs_after_sanitize():
    titles = []
    for sample in starter_workflow_samples():
        titles.append(sample["title"])
        errors = validate_workflow_data(sample["workflow_data"])
        assert errors == [], sample["title"]
        cleaned, _settings = sanitize_workflow_for_marketplace(sample["workflow_data"], None)
        assert validate_workflow_data(cleaned) == []
        raw = str(sample["workflow_data"])
        if "$tr." in raw or "$backup." in raw:
            assert "$tr." in str(cleaned) or "$backup." in str(cleaned)
        for node in cleaned["nodes"]:
            cfg = node.get("config") or {}
            assert "user_id" not in cfg
    assert len(titles) == len(set(titles)) == 29


def test_receipt_and_payment_filters_do_not_cross():
    receipt = _run_trigger(_by_title("دریافت وجه"), {"type": "receipt", "amount": 10})
    assert receipt.get("type") == "receipt"
    assert _run_trigger(_by_title("دریافت وجه"), {"type": "payment", "amount": 10}) == {}
    payment = _run_trigger(_by_title("پرداخت ثبت شد"), {"type": "payment", "amount": 5})
    assert payment.get("type") == "payment"
    assert _run_trigger(_by_title("پرداخت ثبت شد"), {"type": "receipt", "amount": 5}) == {}


def test_check_type_and_days_before():
    received = _by_title("سررسید چک دریافتی")
    assert _run_trigger(received, {"check_type": "paid", "days_until_due": 1}) == {}
    assert _run_trigger(received, {"check_type": "received", "days_until_due": 9, "check_number": "1"}) == {}
    kept = _run_trigger(received, {"check_type": "received", "days_until_due": 1, "check_number": "88"})
    assert kept.get("check_number") == "88"
    paid = _by_title("سررسید چک پرداختی")
    assert _run_trigger(paid, {"check_type": "received", "days_until_due": 0}) == {}
    assert _run_trigger(paid, {"check_type": "paid", "days_until_due": 0, "amount": 20}).get("amount") == 20


def test_deal_won_and_customer_filters():
    deal = _by_title("معامله برنده شد")
    assert _run_trigger(deal, {"is_win": False, "title": "بازنده"}) == {}
    assert _run_trigger(deal, {"is_win": True, "title": "برنده"}).get("title") == "برنده"
    person = _by_title("مشتری جدید")
    assert _run_trigger(person, {"person_types": ["supplier"], "name": "تأمین"}) == {}
    assert _run_trigger(person, {"person_types": ["customer"], "name": "مشتری"}).get("name") == "مشتری"


def test_templates_fill_real_trigger_fields():
    context = {"trigger_data": {}}
    sales = _by_title("فاکتور فروش جدید به مدیر")
    text = WorkflowEngine._resolve_value_static(
        _message_of(sales, "bale"),
        context,
        {"tr": {"invoice_number": "S-14", "customer_name": "آزمایش", "total_amount": 2500}},
    )
    assert "S-14" in text and "آزمایش" in text and "2500" in text
    assert "$tr." not in text

    chat = _by_title("پیام جدید بازدیدکننده در چت وب")
    chat_text = WorkflowEngine._resolve_value_static(
        _message_of(chat, "bale"),
        context,
        {"tr": {"visitor_name": "وحید", "message": "سلام", "conversation_id": 9, "visitor_phone": "0912", "page_url": "https://example.test"}},
    )
    assert "وحید" in chat_text and "سلام" in chat_text and "9" in chat_text
    assert "{{" not in chat_text and "$tr." not in chat_text

    stock = _by_title("موجودی به حد هشدار رسید")
    stock_text = WorkflowEngine._resolve_value_static(
        _message_of(stock, "bale"),
        context,
        {"tr": {"product_name": "کاغذ", "current_quantity": 2, "min_quantity": 5}},
    )
    assert "کاغذ" in stock_text and "2" in stock_text and "5" in stock_text


def test_amount_and_document_gates():
    engine = WorkflowEngine(db=None, business_id=1)
    high = _by_title("فاکتور فروش بالاتر از سقف")
    gate = next(n for n in high["workflow_data"]["nodes"] if n["id"] == "gate")
    assert engine._execute_simple_condition(gate["config"], {}, {"tr": {"total_amount": 100000000}}) is True
    assert engine._execute_simple_condition(gate["config"], {}, {"tr": {"total_amount": 100}}) is False

    doc = _by_title("سند هزینه یا درآمد")
    doc_gate = next(n for n in doc["workflow_data"]["nodes"] if n["id"] == "gate")
    assert engine._execute_simple_condition(doc_gate["config"], {}, {"tr": {"document_type": "expense"}}) is True
    assert engine._execute_simple_condition(doc_gate["config"], {}, {"tr": {"document_type": "income"}}) is True
    assert engine._execute_simple_condition(doc_gate["config"], {}, {"tr": {"document_type": "receipt"}}) is False


def test_backup_schedule_is_daily_morning_and_attaches_file():
    sample = _by_title("پشتیبان روزانه و ارسال فایل به بله")
    trigger = _trigger_node(sample)
    assert trigger["config"]["schedule_mode"] == "simple"
    assert trigger["config"]["simple_time"] == "08:00"
    bale = next(n for n in sample["workflow_data"]["nodes"] if n["id"] == "bale")
    assert bale["config"]["send_file_attachment"] is True
    assert bale["config"]["attachment_file_id"] == "$backup.file_id"
    resolved = WorkflowEngine._resolve_value_static(
        bale["config"]["attachment_file_id"], {}, {"backup": {"file_id": "abc-file"}}
    )
    assert resolved == "abc-file"


def test_second_wave_filters_match_real_payloads():
    sales_return = _by_title("برگشت از فروش")
    assert _run_trigger(sales_return, {"invoice_type": "invoice_sales", "invoice_number": "S"}) == {}
    kept = _run_trigger(sales_return, {"invoice_type": "invoice_sales_return", "invoice_number": "R-3"})
    assert kept.get("invoice_number") == "R-3"

    edited = _by_title("ویرایش دریافت یا پرداخت")
    assert _run_trigger(edited, {"type": "receipt", "amount": 12}).get("amount") == 12
    assert _run_trigger(edited, {"type": "payment", "amount": 7}).get("amount") == 7

    transfer = _by_title("انتقال بین صندوق و بانک")
    assert _run_trigger(transfer, {"document_type": "expense", "total_amount": 1}) == {}
    assert _run_trigger(transfer, {"document_type": "transfer", "total_amount": 40}).get("total_amount") == 40

    lost = _by_title("معامله باخت")
    assert _run_trigger(lost, {"is_win": True, "is_lost": False, "title": "برد"}) == {}
    assert _run_trigger(lost, {"is_win": False, "is_lost": True, "title": "باخت"}).get("title") == "باخت"

    supplier = _by_title("تأمین‌کننده جدید")
    assert _run_trigger(supplier, {"person_types": ["customer"], "name": "مشتری"}) == {}
    assert _run_trigger(supplier, {"person_types": ["supplier"], "name": "تأمین"}).get("name") == "تأمین"

    stage = _by_title("تغییر مرحله سرنخ")
    text = WorkflowEngine._resolve_value_static(
        _message_of(stage, "bale"),
        {},
        {"tr": {"name": "شرکت الف", "old_stage_name": "جدید", "new_stage_name": "مذاکره"}},
    )
    assert "شرکت الف" in text and "جدید" in text and "مذاکره" in text and "$tr." not in text


def test_person_display_name_prefers_alias():
    assert person_display_name("شرکت نمونه", "علی", "رضایی") == "شرکت نمونه"
    assert person_display_name("  ", "علی", "رضایی") == "علی رضایی"
    assert person_display_name(None, None, None) == ""
