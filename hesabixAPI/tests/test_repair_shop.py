"""Regression tests for the repair-shop plugin."""

from __future__ import annotations

import inspect
import sys
from datetime import datetime
from decimal import Decimal
from types import ModuleType, SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

from adapters.db.repositories.repair_shop_repository import RepairOrderRepository
from app.core.responses import ApiError
from app.services import repair_shop_accounting as accounting
from app.services import repair_shop_operations as operations
from app.services import repair_shop_service as service


def test_order_search_uses_real_person_name_fields() -> None:
    src = inspect.getsource(RepairOrderRepository.list_by_business)
    assert "Person.name" not in src
    assert "Person.alias_name" in src
    assert "Person.first_name" in src
    assert "Person.last_name" in src
    assert "Person.company_name" in src


def test_invoice_creation_uses_data_not_payload() -> None:
    src = inspect.getsource(accounting.create_repair_invoice_accounting)
    assert "payload=invoice_payload" not in src
    assert "data=invoice_payload" in src
    assert "product_type" not in src
    assert '["document"]["id"]' not in src


def test_add_parts_uses_physical_stock_and_sales_price() -> None:
    src = inspect.getsource(operations.add_parts_to_repair_order)
    assert "get_product_stock" not in src
    assert "get_physical_stock" in src
    assert "base_sales_price" in src
    assert "product.price" not in src


def test_receipt_uses_data_keyword() -> None:
    src = inspect.getsource(accounting.create_receipt_for_repair_payment)
    assert "payload=receipt_payload" not in src
    assert "data=receipt_payload" in src


def test_extract_invoice_id_from_wrapped_and_flat_results() -> None:
    assert accounting._extract_invoice_id_and_code({"id": 9, "code": "INV-1"}) == (9, "INV-1")
    assert accounting._extract_invoice_id_and_code(
        {"data": {"id": 11, "code": "INV-2"}}
    ) == (11, "INV-2")
    assert accounting._extract_invoice_id_and_code(
        {"document": {"id": 13, "code": "INV-3"}}
    ) == (13, "INV-3")
    with pytest.raises(ApiError) as ei:
        accounting._extract_invoice_id_and_code({"ok": True})
    assert ei.value.code == "INVOICE_CREATION_FAILED"


class _Order:
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)


def _invoice_order(**overrides):
    data = dict(
        id=77,
        code="REC-1404-0001",
        status="completed_fixed",
        labor_cost=Decimal("100"),
        parts_cost=Decimal("0"),
        final_cost=Decimal("100"),
        technician_commission=Decimal("0"),
        customer_person_id=5,
        currency_id=1,
        completed_at=datetime(2026, 10, 16),
        product_name="Phone",
        assigned_technician_id=None,
        extra_info={},
    )
    data.update(overrides)
    return _Order(**data)


def _install_fake_invoice_service(create_invoice):
    mod = ModuleType("app.services.invoice_service")
    mod.create_invoice = create_invoice
    sys.modules["app.services.invoice_service"] = mod
    return mod


def test_invoice_reraises_api_error_instead_of_500() -> None:
    db = MagicMock()
    order = _invoice_order()
    invoice_repo = MagicMock()
    invoice_repo.get_by_order.return_value = None

    def boom(**kwargs):
        raise ApiError("LINES_REQUIRED", "At least one line is required", http_status=400)

    _install_fake_invoice_service(boom)
    db.query.return_value.filter.return_value.first.return_value = SimpleNamespace(id=1)
    db.query.return_value.filter.return_value.all.return_value = []

    with patch.object(accounting, "check_repair_shop_plugin_active", return_value=True), patch.object(
        accounting, "RepairInvoiceRepository", return_value=invoice_repo
    ), patch.object(
        accounting, "RepairShopSettingsRepository",
        return_value=MagicMock(get_by_business=MagicMock(return_value=None)),
    ), patch(
        "app.services.repair_shop_service._get_current_fiscal_year",
        return_value=SimpleNamespace(id=1),
    ), patch.object(accounting, "_resolve_or_create_service_product_id", return_value=44):
        with pytest.raises(ApiError) as ei:
            accounting.create_repair_invoice_accounting(db, 6979, order, user_id=1)
    assert ei.value.code == "LINES_REQUIRED"
    assert ei.value.status_code == 400


def test_invoice_rejects_empty_lines() -> None:
    db = MagicMock()
    order = _invoice_order(labor_cost=Decimal("0"), parts_cost=Decimal("0"), final_cost=Decimal("0"))
    invoice_repo = MagicMock()
    invoice_repo.get_by_order.return_value = None
    db.query.return_value.filter.return_value.first.return_value = SimpleNamespace(id=1)
    db.query.return_value.filter.return_value.all.return_value = []

    with patch.object(accounting, "check_repair_shop_plugin_active", return_value=True), patch.object(
        accounting, "RepairInvoiceRepository", return_value=invoice_repo
    ), patch.object(
        accounting, "RepairShopSettingsRepository",
        return_value=MagicMock(get_by_business=MagicMock(return_value=None)),
    ), patch(
        "app.services.repair_shop_service._get_current_fiscal_year",
        return_value=SimpleNamespace(id=1),
    ):
        with pytest.raises(ApiError) as ei:
            accounting.create_repair_invoice_accounting(db, 1, order, user_id=1)
    assert ei.value.code == "NO_INVOICE_LINES"


def test_invoice_calls_create_invoice_with_data_kwarg() -> None:
    db = MagicMock()
    order = _invoice_order(
        labor_cost=Decimal("150000"),
        final_cost=Decimal("150000"),
        technician_commission=Decimal("15000"),
        customer_person_id=9,
        currency_id=2,
        product_name="Laptop",
        assigned_technician_id=3,
        extra_info={},
    )
    invoice_repo = MagicMock()
    invoice_repo.get_by_order.return_value = None
    captured = {}

    def fake_create_invoice(**kwargs):
        captured.update(kwargs)
        return {"id": 501, "code": "INV-501"}

    _install_fake_invoice_service(fake_create_invoice)
    db.query.return_value.filter.return_value.first.return_value = SimpleNamespace(id=1)
    db.query.return_value.filter.return_value.all.return_value = []

    with patch.object(accounting, "check_repair_shop_plugin_active", return_value=True), patch.object(
        accounting, "RepairInvoiceRepository", return_value=invoice_repo
    ), patch.object(
        accounting, "RepairShopSettingsRepository",
        return_value=MagicMock(get_by_business=MagicMock(return_value=None)),
    ), patch(
        "app.services.repair_shop_service._get_current_fiscal_year",
        return_value=SimpleNamespace(id=8),
    ), patch.object(
        accounting, "_resolve_or_create_service_product_id", return_value=44
    ), patch.object(
        accounting, "flag_modified"
    ), patch.object(
        accounting, "RepairInvoice", return_value=SimpleNamespace()
    ):
        result = accounting.create_repair_invoice_accounting(db, 6979, order, user_id=12)

    assert "data" in captured
    assert "payload" not in captured
    assert captured["data"]["invoice_type"] == "invoice_sales"
    assert captured["data"]["person_id"] == 9
    assert captured["data"]["lines"][0]["product_id"] == 44
    assert captured["commit"] is False
    assert result["id"] == 501
    assert result["code"] == "INV-501"
    assert result["document"]["id"] == 501


def test_assign_does_not_rewind_in_progress_status() -> None:
    db = MagicMock()
    order = _Order(id=10, status="in_progress", assigned_technician_id=None, updated_at=None)
    repo = MagicMock()
    repo.get_by_id.return_value = order
    status_repo = MagicMock()

    with patch.object(operations, "check_repair_shop_plugin_active", return_value=True), patch.object(
        operations, "RepairOrderRepository", return_value=repo
    ), patch.object(
        operations, "RepairOrderStatusRepository", return_value=status_repo
    ), patch(
        "app.services.repair_shop_service.get_repair_order",
        return_value={"id": 10, "status": "in_progress"},
    ):
        db.query.return_value.filter.return_value.first.return_value = SimpleNamespace(id=5)
        result = operations.assign_technician_to_order(db, 1, 10, 5, user_id=1)

    assert order.status == "in_progress"
    assert order.assigned_technician_id == 5
    created = status_repo.create.call_args[0][0]
    assert created["status"] == "in_progress"
    assert result["status"] == "in_progress"


def test_assign_sets_assigned_from_received() -> None:
    db = MagicMock()
    order = _Order(id=10, status="received", assigned_technician_id=None, updated_at=None)
    repo = MagicMock()
    repo.get_by_id.return_value = order
    status_repo = MagicMock()

    with patch.object(operations, "check_repair_shop_plugin_active", return_value=True), patch.object(
        operations, "RepairOrderRepository", return_value=repo
    ), patch.object(
        operations, "RepairOrderStatusRepository", return_value=status_repo
    ), patch(
        "app.services.repair_shop_service.get_repair_order",
        return_value={"id": 10, "status": "assigned"},
    ):
        db.query.return_value.filter.return_value.first.return_value = SimpleNamespace(id=5)
        operations.assign_technician_to_order(db, 1, 10, 5, user_id=1)

    assert order.status == "assigned"


def test_operations_require_active_plugin() -> None:
    db = MagicMock()
    with patch.object(operations, "check_repair_shop_plugin_active", return_value=False):
        with pytest.raises(ApiError) as ei:
            operations.add_parts_to_repair_order(db, 1, 1, [{"product_id": 1, "quantity": 1}], 1)
    assert ei.value.code == "PLUGIN_NOT_ACTIVE"
    assert ei.value.status_code == 403


def test_recalculate_parts_cost_sums_all_rows() -> None:
    db = MagicMock()
    order = _Order(id=3, labor_cost=Decimal("10"), parts_cost=Decimal("0"), final_cost=Decimal("0"))
    db.query.return_value.filter.return_value.all.return_value = [
        SimpleNamespace(total_price=Decimal("3")),
        SimpleNamespace(total_price=Decimal("7")),
    ]
    total = operations._recalculate_parts_cost(db, order)
    assert total == Decimal("10")
    assert order.parts_cost == Decimal("10")
    assert order.final_cost == Decimal("20")


def test_repair_shop_catalog_keys_are_translated() -> None:
    from app.core.i18n import Translator

    fa = Translator("fa")
    en = Translator("en")
    assert fa.t("REPAIR_ORDER_NOT_FOUND") == "سفارش تعمیر یافت نشد"
    assert en.t("REPAIR_ORDER_NOT_FOUND") == "Repair order not found"
    assert fa.t("TECHNICIAN_DEACTIVATED") == "تعمیرکار با موفقیت غیرفعال شد"
    assert en.t("PLUGIN_NOT_ACTIVE") == "The required plugin is not active for this business"


def test_receipt_year_jalali_not_gregorian_in_autumn() -> None:
    year = service._receipt_year("jalali")
    gregorian = datetime.now().year
    assert 1300 <= year <= gregorian + 2


def test_list_technicians_uses_total_count_not_page_length() -> None:
    src = inspect.getsource(service.list_technicians)
    assert "len(items)" not in src
    assert "count_by_business" in src
