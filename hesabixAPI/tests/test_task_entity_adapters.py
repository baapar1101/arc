from adapters.db.models.document import Document
from adapters.db.models.person import Person
from app.services.task_management_service import (
    _TASK_ENTITY_TYPES,
    _DOCUMENT_ENTITY_TYPES,
    _PERSON_ENTITY_TYPES,
    _entity_model,
    _equivalent_entity_link_types,
)


def test_phase14_explicit_aliases_are_registered() -> None:
    assert {"customer", "contact"}.issubset(_PERSON_ENTITY_TYPES)
    assert {"quote", "invoice", "payment"}.issubset(_DOCUMENT_ENTITY_TYPES)

    for key in [
        "customer",
        "contact",
        "lead",
        "deal",
        "crm_activity",
        "quote",
        "invoice",
        "payment",
        "product",
    ]:
        assert key in _TASK_ENTITY_TYPES

    assert "contract" not in _TASK_ENTITY_TYPES
    assert "ticket" not in _TASK_ENTITY_TYPES


def test_person_aliases_use_native_person_model() -> None:
    assert _entity_model("person") is Person
    assert _entity_model("customer") is Person
    assert _entity_model("contact") is Person


def test_document_aliases_use_native_document_model() -> None:
    assert _entity_model("document") is Document
    assert _entity_model("quote") is Document
    assert _entity_model("invoice") is Document
    assert _entity_model("payment") is Document


def test_person_reverse_lookup_keeps_alias_compatibility() -> None:
    expected = {"person", "customer", "contact"}
    assert _equivalent_entity_link_types("person") == expected
    assert _equivalent_entity_link_types("customer") == expected
    assert _equivalent_entity_link_types("contact") == expected


def test_document_reverse_lookup_keeps_generic_history_visible() -> None:
    assert _equivalent_entity_link_types("quote") == {"document", "quote"}
    assert _equivalent_entity_link_types("invoice") == {"document", "invoice"}
    assert _equivalent_entity_link_types("payment") == {"document", "payment"}
    assert _equivalent_entity_link_types("document") == {
        "document",
        "quote",
        "invoice",
        "payment",
    }
