"""پیش‌نمایش پیامک و سقف روزانه توالی، بدون پایگاه داده."""
from app.services.crm_sequence_runtime import (
    discount_approval_workflow_data,
    render_sequence_sms,
    sms_send_allowed,
)


def test_sms_preview_replaces_known_tokens_and_drops_unknown():
    text = render_sequence_sms("سلام {{ name }} از {{company}}، کد {{missing}}", {"name": "علی", "company": "حسابیکس"})
    assert text == "سلام علی از حسابیکس، کد"


def test_daily_cap_blocks_only_after_the_limit():
    assert sms_send_allowed(0, None) is True
    assert sms_send_allowed(3, 0) is True
    assert sms_send_allowed(4, 5) is True
    assert sms_send_allowed(5, 5) is False


def test_discount_template_is_a_draft_graph_on_the_invoice_trigger():
    data = discount_approval_workflow_data(9, threshold=1000)
    assert [node["type"] for node in data["nodes"]] == ["trigger", "condition", "action"]
    assert data["nodes"][0]["config"]["trigger_type"] == "invoice.sales.created"
    assert data["connections"][1]["sourceHandle"] == "true"
    assert "/business/9/invoice/" in data["nodes"][2]["config"]["deep_link"]
