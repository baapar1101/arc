"""قواعد خالص نمای ذخیره‌شده و جست‌وجوی CRM."""
import pytest

from app.core.responses import ApiError
from app.services.crm_workspace_service import clean_saved_filters, like_pattern, normalize_search_query


def test_search_query_requires_two_characters_and_collapses_space():
    assert normalize_search_query("  a   b  ") == "a b"
    assert normalize_search_query(" ن ") is None
    assert normalize_search_query(None) is None
    assert len(normalize_search_query("x" * 90) or "") == 80


def test_like_pattern_escapes_wildcards():
    assert like_pattern("100%") == "%100\\%%"
    assert like_pattern("a_b") == "%a\\_b%"


def test_saved_filters_keep_only_known_keys():
    cleaned = clean_saved_filters(
        "lead",
        {"process_definition_id": 4, "search": "  علی  ", "kanban": True, "drop_me": 1},
    )
    assert cleaned == {"process_definition_id": 4, "search": "علی", "kanban": True}


def test_saved_filters_reject_wrong_types():
    with pytest.raises(ApiError) as caught:
        clean_saved_filters("deal", {"open_only": "yes"})
    assert caught.value.code == "CRM_SAVED_VIEW_FILTERS_INVALID"
