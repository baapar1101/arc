"""جایگزینی $node.field و {{ trigger_data.field }} در متن اکشن‌های ورک‌فلو."""

from app.services.workflow.workflow_engine import WorkflowEngine
from app.services.workflow.workflow_trigger_enrichment import crm_chat_visitor_name


def test_brace_tokens_in_message_use_trigger_data():
    template = (
        "فرستنده: {{ trigger_data.visitor_name }}\n"
        "پیام: {{ trigger_data.message }}\n"
        "شناسه گفتگو: {{ trigger_data.conversation_id }}"
    )
    context = {
        "trigger_data": {
            "visitor_name": "وحید عرب سعیدی",
            "message": "سلام",
            "conversation_id": 1288,
        }
    }
    resolved = WorkflowEngine._resolve_value_static(template, context, {})
    assert resolved == "فرستنده: وحید عرب سعیدی\nپیام: سلام\nشناسه گفتگو: 1288"


def test_unresolved_brace_token_stays_literal():
    resolved = WorkflowEngine._resolve_value_static(
        "پیام: {{ trigger_data.missing }}",
        {"trigger_data": {"body": "سلام"}},
        {},
    )
    assert resolved == "پیام: {{ trigger_data.missing }}"


def test_dollar_trigger_data_and_node_field_still_resolve():
    context = {"trigger_data": {"body": "متن چت"}}
    node_results = {"crm_chat_in": {"body": "از نود", "conversation_id": 7}}
    assert WorkflowEngine._resolve_value_static("$trigger_data.body", context, node_results) == "متن چت"
    assert (
        WorkflowEngine._resolve_value_static("پیام $crm_chat_in.body", context, node_results)
        == "پیام از نود"
    )


def test_single_brace_token_keeps_original_type():
    resolved = WorkflowEngine._resolve_value_static(
        "{{ trigger_data.conversation_id }}",
        {"trigger_data": {"conversation_id": 1288}},
        {},
    )
    assert resolved == 1288


def test_crm_chat_visitor_name_joins_parts():
    assert crm_chat_visitor_name("وحید", "عرب سعیدی") == "وحید عرب سعیدی"
    assert crm_chat_visitor_name("  وحید ", "") == "وحید"
    assert crm_chat_visitor_name(None, None) == ""
