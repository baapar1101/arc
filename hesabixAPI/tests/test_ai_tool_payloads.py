"""نگاشت payload فاکتور AI و قرارداد فیلتر/اسکیما."""
from __future__ import annotations

from datetime import date

from app.services.ai.ai_query_filter_catalog import resolve_filter_property
from app.services.ai.ai_query_filter_service import normalize_filter_items
from app.services.ai.ai_tool_payloads import (
    CREATE_INVOICE_PARAMETERS_SCHEMA,
    build_create_check_payload,
    build_create_invoice_payload,
    build_create_receipt_payment_payload,
    build_create_transfer_payload,
    build_create_warehouse_document_payload,
    build_create_workflow_payload,
    build_update_invoice_payload,
    normalize_ai_invoice_line,
    normalize_workflow_graph,
)
from app.services.ai.ai_tool_query_params import ai_list_parameters_schema


def test_normalize_line_moves_unit_price_to_extra_info():
    line = normalize_ai_invoice_line(
        {"product_id": "12", "quantity": 2, "unit_price": 150000}
    )
    assert line["product_id"] == 12
    assert line["quantity"] == 2.0
    assert line["extra_info"]["unit_price"] == 150000


def test_build_create_invoice_payload_session_896_shape():
    payload = build_create_invoice_payload(
        {
            "invoice_type": "invoice_sales",
            "document_date": "2026-08-18",
            "currency_id": 1,
            "person_id": 176105,
            "lines": [
                {
                    "product_id": 44,
                    "quantity": 1,
                    "unit_price": 25000000,
                }
            ],
        }
    )
    assert payload["person_id"] == 176105
    assert payload["extra_info"]["person_id"] == 176105
    assert payload["lines"][0]["extra_info"]["unit_price"] == 25000000
    assert payload["invoice_type"] == "invoice_sales"
    assert payload["currency_id"] == 1


def test_build_create_invoice_aliases_and_defaults():
    payload = build_create_invoice_payload(
        {
            "invoice_type": "فروش",
            "customer_id": 9,
            "lines": [{"product_id": 1, "quantity": 1, "unit_price": 10}],
        }
    )
    assert payload["invoice_type"] == "invoice_sales"
    assert payload["person_id"] == 9
    assert payload["document_date"] == date.today().isoformat()


def test_create_invoice_schema_requires_person_and_describes_unit_price():
    schema = CREATE_INVOICE_PARAMETERS_SCHEMA
    assert "invoice_type" in schema["required"]
    assert "lines" in schema["required"]
    assert "person_id" in schema["properties"]
    line_props = schema["properties"]["lines"]["items"]["properties"]
    assert "unit_price" in line_props
    assert "description" in line_props["unit_price"]
    assert len(schema["properties"]["person_id"]["description"]) > 20
    for key in (
        "due_date",
        "global_discount",
        "invoice_adjustments",
        "seller_id",
        "commission",
        "payments",
        "installment_plan",
        "project_id",
        "tag_ids",
        "fx_rate_id",
    ):
        assert key in schema["properties"]
    assert "discount_percent" in line_props
    assert "discount_type" in line_props


def test_filter_aliases_sale_date_and_person_type():
    assert resolve_filter_property("invoice", "sale_date") == "document_date"
    assert resolve_filter_property("person", "name") == "alias_name"
    items = normalize_filter_items(
        [{"property": "sale_date", "operator": ">,", "value": "2026-01-01"}],
        entity="invoice",
    )
    assert items[0]["property"] == "document_date"
    assert items[0]["operator"] == ">"


def test_filter_id_on_person_is_rejected_with_search_hint():
    try:
        resolve_filter_property("person", "id")
        assert False, "expected ValueError"
    except ValueError as exc:
        assert "search" in str(exc)


def test_search_schema_lists_allowed_filter_properties():
    schema = ai_list_parameters_schema(entity="invoice")
    desc = schema["properties"]["filters"]["description"]
    assert "document_date" in desc
    assert schema["properties"]["take"]["maximum"] == 100


def test_receipt_payment_maps_bank_id_not_chart_account():
    payload = build_create_receipt_payment_payload(
        {
            "type": "دریافت",
            "person_id": 10,
            "amount": 5000,
            "account_type": "بانک",
            "account_id": 3,
            "currency_id": 1,
        }
    )
    assert payload["document_type"] == "receipt"
    assert payload["person_lines"][0]["person_id"] == 10
    line = payload["account_lines"][0]
    assert line["transaction_type"] == "bank"
    assert line["bank_id"] == 3
    assert "account_id" not in line


def test_create_check_aliases_and_requires_person_for_received():
    payload = build_create_check_payload(
        {
            "type": "دریافتی",
            "check_number": "123",
            "amount": 100,
            "issue_date": "2026-08-01",
            "due_date": "2026-09-01",
            "person_id": 7,
            "currency_id": 1,
        }
    )
    assert payload["type"] == "received"
    assert payload["currency_id"] == 1
    try:
        build_create_check_payload(
            {
                "type": "received",
                "check_number": "1",
                "amount": 1,
                "issue_date": "2026-08-01",
                "due_date": "2026-09-01",
                "currency_id": 1,
            }
        )
        assert False, "expected ValueError"
    except ValueError as exc:
        assert "person_id" in str(exc)


def test_create_transfer_and_warehouse_and_workflow_payloads():
    tr = build_create_transfer_payload(
        {
            "from_account_type": "صندوق",
            "from_account_id": 2,
            "to_account_type": "bank",
            "to_account_id": 4,
            "amount": 80,
            "currency_id": 1,
        }
    )
    assert tr["source"] == {"type": "cash_register", "id": 2}
    assert tr["destination"]["type"] == "bank"
    assert tr["document_date"] == date.today().isoformat()

    wh = build_create_warehouse_document_payload(
        {
            "doc_type": "ورود",
            "warehouse_id": 9,
            "lines": [{"product_id": 1, "quantity": 2}],
        }
    )
    assert wh["doc_type"] == "receipt"
    assert wh["warehouse_id_to"] == 9
    assert wh["lines"][0]["product_id"] == 1

    wf = build_create_workflow_payload(
        {
            "name": "تست",
            "status": "draft",
            "workflow_data": {"nodes": [{"id": "a", "type": "trigger"}]},
        }
    )
    assert wf["status"] == "پیش‌نویس"
    assert wf["workflow_data"]["connections"] == []
    graph = normalize_workflow_graph({"nodes": []})
    assert graph["connections"] == []


def test_update_invoice_normalizes_lines_when_sent():
    payload = build_update_invoice_payload(
        {
            "invoice_id": 5,
            "person_id": 8,
            "lines": [{"product_id": 1, "quantity": 1, "unit_price": 20}],
        }
    )
    assert payload["person_id"] == 8
    assert payload["extra_info"]["person_id"] == 8
    assert payload["lines"][0]["extra_info"]["unit_price"] == 20


def test_build_create_invoice_covers_form_header_and_line_fields():
    payload = build_create_invoice_payload(
        {
            "invoice_type": "فروش",
            "person_id": 3,
            "due_date": "2026-09-01",
            "warehouse_id": 2,
            "seller_id": 11,
            "commission": {"type": "percent", "value": 5},
            "global_discount": {"type": "amount", "value": 1000},
            "invoice_adjustments": [
                {"kind": "addition", "account_id": 20, "amount": 500, "tax_rate": 9}
            ],
            "payments": [{"type": "bank", "account_id": 8, "amount": 50000}],
            "project_id": 4,
            "tag_ids": [1, 2],
            "lines": [
                {
                    "product_id": 9,
                    "quantity": 2,
                    "unit_price": 10000,
                    "discount_percent": 10,
                    "tax_rate": 9,
                    "unit": "عدد",
                }
            ],
        }
    )
    extra = payload["extra_info"]
    assert extra["due_date"] == "2026-09-01"
    assert extra["warehouse_id"] == 2
    assert extra["seller_id"] == 11
    assert extra["commission"] == {"type": "percentage", "value": 5}
    assert extra["global_discount"] == {"type": "amount", "value": 1000}
    assert extra["invoice_adjustments"][0]["account_id"] == 20
    assert payload["due_date"] == "2026-09-01"
    assert payload["project_id"] == 4
    assert payload["tag_ids"] == [1, 2]
    assert payload["payments"][0]["bank_id"] == 8
    line_extra = payload["lines"][0]["extra_info"]
    assert line_extra["discount_percent"] == 10
    assert line_extra["tax_percent"] == 9
    assert line_extra["unit"] == "عدد"


def test_build_create_invoice_requires_person_only_for_sales_family():
    import pytest

    with pytest.raises(ValueError, match="person_id"):
        build_create_invoice_payload(
            {
                "invoice_type": "invoice_sales",
                "lines": [{"product_id": 1, "quantity": 1, "unit_price": 1}],
            }
        )
    waste = build_create_invoice_payload(
        {
            "invoice_type": "ضایعات",
            "lines": [{"product_id": 1, "quantity": 1, "unit_price": 0}],
        }
    )
    assert waste["invoice_type"] == "invoice_waste"
    assert waste["person_id"] is None


def test_build_create_person_payload_includes_bank_accounts_and_all_types():
    from adapters.api.v1.schema_models.person import PersonCreateRequest
    from app.services.ai.ai_tool_payloads import (
        CREATE_PERSON_PARAMETERS_SCHEMA,
        build_create_person_payload,
    )

    payload = build_create_person_payload(
        {
            "name": "علی علی زاده",
            "person_type": "customer",
            "mobile": "09120000000",
            "national_id": "0012345678",
            "bank_accounts": [
                {
                    "bank": "مهر ایران",
                    "card": "6063731003703163",
                }
            ],
            "social_contacts": [
                {"platform_key": "telegram", "value": "@ali"},
            ],
        }
    )
    assert payload["alias_name"] == "علی علی زاده"
    assert payload["person_types"] == ["مشتری"]
    assert payload["mobile"] == "09120000000"
    assert payload["national_id"] == "0012345678"
    assert payload["bank_accounts"] == [
        {
            "bank_name": "مهر ایران",
            "account_number": None,
            "card_number": "6063731003703163",
            "sheba_number": None,
        }
    ]
    req = PersonCreateRequest(**payload)
    assert req.alias_name == "علی علی زاده"
    assert req.bank_accounts and req.bank_accounts[0].card_number == "6063731003703163"
    assert "bank_accounts" in CREATE_PERSON_PARAMETERS_SCHEMA["properties"]
    assert "shareholder" in CREATE_PERSON_PARAMETERS_SCHEMA["properties"]["person_type"]["enum"]


def test_build_create_person_payload_maps_tax_id_and_multiple_types():
    from app.services.ai.ai_tool_payloads import build_create_person_payload

    payload = build_create_person_payload(
        {
            "name": "شرکت نمونه",
            "person_types": ["supplier", "partner"],
            "person_type": "customer",
            "tax_id": "12345678901",
            "legal_entity_type": "legal",
        }
    )
    assert payload["person_types"] == ["تامین‌کننده", "همکار", "مشتری"]
    assert payload["national_id"] == "12345678901"
    assert payload["legal_entity_type"] == "legal"


def test_build_update_person_payload_replaces_bank_accounts():
    from adapters.api.v1.schema_models.person import PersonUpdateRequest
    from app.services.ai.ai_tool_payloads import (
        UPDATE_PERSON_PARAMETERS_SCHEMA,
        build_update_person_payload,
    )

    payload = build_update_person_payload(
        {
            "person_id": 10,
            "bank_accounts": [
                {"bank_name": "ملی", "sheba": "IR123"},
            ],
        }
    )
    assert "alias_name" not in payload
    assert payload["bank_accounts"][0]["sheba_number"] == "IR123"
    req = PersonUpdateRequest(**payload)
    assert req.bank_accounts is not None
    assert req.bank_accounts[0].bank_name == "ملی"
    assert "bank_accounts" in UPDATE_PERSON_PARAMETERS_SCHEMA["properties"]


def test_build_create_product_payload_covers_form_fields():
    from adapters.api.v1.schema_models.product import ProductCreateRequest
    from app.services.ai.ai_tool_payloads import (
        CREATE_PRODUCT_PARAMETERS_SCHEMA,
        build_create_product_payload,
    )

    payload = build_create_product_payload(
        {
            "name": "پیچ ۸",
            "type": "product",
            "price": 15000,
            "purchase_price": 10000,
            "unit": "عدد",
            "warehouse_id": 3,
            "track_inventory": True,
            "barcodes": ["1234567890123", "987"],
            "is_sales_taxable": True,
            "sales_tax_rate": 9,
            "attribute_ids": [1, 2],
            "suppliers": [{"person_id": 44, "name": "پخش نمونه"}],
            "opening_balance": {"qty": 10, "cost": 8000, "warehouse_id": 3},
            "catalog_brand": "برند الف",
            "catalog_specifications": [{"label": "قطر", "value": "۸ میلی‌متر"}],
        }
    )
    assert payload["item_type"] == "کالا"
    assert payload["base_sales_price"] == 15000
    assert payload["base_purchase_price"] == 10000
    assert payload["main_unit"] == "عدد"
    assert payload["default_warehouse_id"] == 3
    assert payload["general_barcodes"] == "1234567890123,987"
    assert payload["opening_balance"]["quantity"] == 10
    assert payload["opening_balance"]["cost_price"] == 8000
    req = ProductCreateRequest(**payload)
    assert req.name == "پیچ ۸"
    assert req.track_inventory is True
    assert req.suppliers and req.suppliers[0].person_id == 44
    assert req.catalog_specifications[0].label == "قطر"
    props = CREATE_PRODUCT_PARAMETERS_SCHEMA["properties"]
    for key in (
        "main_unit",
        "default_warehouse_id",
        "general_barcodes",
        "tax_code",
        "attribute_ids",
        "suppliers",
        "opening_balance",
        "catalog_brand",
        "inventory_mode",
        "is_public_catalog",
    ):
        assert key in props


def test_build_update_product_payload_partial_and_service_alias():
    from adapters.api.v1.schema_models.product import ProductUpdateRequest
    from app.services.ai.ai_tool_payloads import (
        UPDATE_PRODUCT_PARAMETERS_SCHEMA,
        build_update_product_payload,
    )

    payload = build_update_product_payload(
        {
            "product_id": 9,
            "item_type": "service",
            "track_inventory": False,
            "base_sales_price": 200000,
        }
    )
    assert "name" not in payload
    assert payload["item_type"] == "خدمت"
    assert payload["base_sales_price"] == 200000
    req = ProductUpdateRequest(**payload)
    assert req.item_type == "خدمت"
    assert "suppliers" in UPDATE_PRODUCT_PARAMETERS_SCHEMA["properties"]
    assert "product_id" in UPDATE_PRODUCT_PARAMETERS_SCHEMA["required"]


def test_product_ai_schema_covers_all_api_form_fields():
    from adapters.api.v1.schema_models.product import ProductCreateRequest, ProductUpdateRequest
    from app.services.ai.ai_tool_payloads import (
        CREATE_PRODUCT_PARAMETERS_SCHEMA,
        UPDATE_PRODUCT_PARAMETERS_SCHEMA,
        build_create_product_payload,
        build_update_product_payload,
    )

    create_props = set(CREATE_PRODUCT_PARAMETERS_SCHEMA["properties"])
    for field in ProductCreateRequest.model_fields:
        assert field in create_props, f"create_product schema missing {field}"

    update_props = set(UPDATE_PRODUCT_PARAMETERS_SCHEMA["properties"])
    for field in ProductUpdateRequest.model_fields:
        assert field in update_props, f"update_product schema missing {field}"
    assert "product_id" in update_props

    by_sku = build_create_product_payload({"name": "نمونه", "sku": "P-9", "sale_price": 500})
    assert by_sku["code"] == "P-9"
    assert by_sku["base_sales_price"] == 500

    named_category = build_create_product_payload({"name": "نمونه", "category": "ابزار"})
    assert "category_id" not in named_category

    numeric_category = build_create_product_payload({"name": "نمونه", "category": "7"})
    assert numeric_category["category_id"] == 7

    updated = build_update_product_payload(
        {
            "product_id": 1,
            "attribute_ids": [3],
            "suppliers": [],
            "inventory_mode": "فله‌ای",
        }
    )
    assert updated["attribute_ids"] == [3]
    assert updated["suppliers"] == []
    assert updated["inventory_mode"] == "bulk"


def test_product_price_list_items_extracted_and_fx_fields_on_payload():
    from adapters.api.v1.schema_models.product import ProductCreateRequest
    from app.services.ai.ai_tool_payloads import (
        CREATE_PRODUCT_PARAMETERS_SCHEMA,
        build_create_product_payload,
        extract_product_price_list_items,
    )

    args = {
        "name": "پیچ ۸",
        "base_sales_price": 15000,
        "base_purchase_price": 10000,
        "fx_sales_price": 2.5,
        "fx_purchase_price": 1.8,
        "fx_currency_id": 7,
        "price_list_items": [
            {
                "price_list_name": "عمده",
                "currency_code": "USD",
                "price": 12.5,
                "tier_name": "عمده",
            },
            {"price_list_id": 4, "currency_id": 1, "price": 9000},
        ],
    }
    payload = build_create_product_payload(args)
    assert "price_list_items" not in payload
    assert payload["sales_price_fx"] == 2.5
    assert payload["purchase_price_fx"] == 1.8
    assert payload["price_fx_currency_id"] == 7
    req = ProductCreateRequest(**payload)
    assert float(req.sales_price_fx) == 2.5
    items = extract_product_price_list_items(args)
    assert items[0]["price_list_name"] == "عمده"
    assert items[0]["currency_code"] == "USD"
    assert items[0]["price"] == 12.5
    assert items[1]["price_list_id"] == 4
    assert items[1]["currency_id"] == 1
    props = CREATE_PRODUCT_PARAMETERS_SCHEMA["properties"]
    assert "price_list_items" in props
    assert "sales_price_fx" in props
    assert "purchase_price_fx" in props
    assert "price_fx_currency_id" in props


def test_extract_product_price_list_items_requires_list_identity():
    import pytest
    from app.services.ai.ai_tool_payloads import extract_product_price_list_items

    with pytest.raises(ValueError, match="price_list_id"):
        extract_product_price_list_items(
            {"price_list_items": [{"price": 10}]}
        )
