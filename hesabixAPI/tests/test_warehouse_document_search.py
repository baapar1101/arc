from app.services.warehouse_service import _warehouse_doc_search_fields_set


def test_warehouse_doc_search_fields_default() -> None:
    assert _warehouse_doc_search_fields_set(None) == {"code", "counterparty"}


def test_warehouse_doc_search_fields_custom() -> None:
    assert _warehouse_doc_search_fields_set(["code"]) == {"code"}


def test_warehouse_doc_search_fields_party_alias() -> None:
    sf = _warehouse_doc_search_fields_set(["source_invoice_party_name"])
    assert "counterparty" in sf
    assert "source_invoice_party_name" in sf
