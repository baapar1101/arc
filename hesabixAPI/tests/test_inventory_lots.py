"""Unit tests for commercial lot / expiry tracking (opt-in, default off)."""

from datetime import date
from decimal import Decimal
from types import SimpleNamespace
from app.services.inventory_lot_allocation_service import (
    parse_payload_lot_allocations,
    pick_return_lots,
    _effective_allow_unsellable,
)
from app.services.inventory_lot_service import (
    STATUS_BLOCKED,
    STATUS_EXPIRED,
    STATUS_NEAR_EXPIRY,
    STATUS_SELLABLE,
    business_as_of,
    compute_lot_dates,
    dual_unit_qty,
    instance_expiry_view,
    is_expiry_tracked_product,
    is_instance_sellable,
    is_lot_sellable,
    lot_identity_key,
    lot_status,
)
from app.services.invoice_unit_conversion_service import quantity_line_to_main


def _product(**kwargs):
    data = dict(
        track_inventory=True,
        track_expiry=True,
        lot_policy="optional",
        shelf_life_days=30,
        best_before_offset_days=5,
        removal_offset_days=3,
        alert_offset_days=7,
        min_remaining_shelf_life_days=0,
        expired_sale_policy="block",
        main_unit="کارتن",
        secondary_unit="عدد",
        unit_conversion_factor=Decimal("10"),
        inventory_mode="bulk",
    )
    data.update(kwargs)
    return SimpleNamespace(**data)


def test_business_as_of_keeps_explicit_date() -> None:
    assert business_as_of(None, date(2026, 11, 2)) == date(2026, 11, 2)


def test_scale_allocations_to_remaining_warehouse_qty() -> None:
    from app.services.inventory_lot_allocation_service import scale_allocations_to_qty

    rows = [(1, Decimal("7")), (2, Decimal("3"))]
    assert scale_allocations_to_qty(rows, Decimal("6")) == [(1, Decimal("6"))]
    assert scale_allocations_to_qty(rows, Decimal("8")) == [
        (1, Decimal("7")),
        (2, Decimal("1")),
    ]
    assert scale_allocations_to_qty(rows, Decimal("10")) == rows
    assert scale_allocations_to_qty(rows, Decimal("0")) == []


def test_list_lot_balances_empty_for_unique_products() -> None:
    from app.services.inventory_lot_service import list_lot_balances

    p = _product(inventory_mode="unique")

    class _Q:
        def filter(self, *args, **kwargs):
            return self

        def first(self):
            return p

    class _DB:
        def query(self, *args, **kwargs):
            return _Q()

    assert list_lot_balances(_DB(), 1, 9, 1, date(2026, 11, 2)) == []


def test_non_expiry_product_is_untouched() -> None:
    p = _product(track_expiry=False)
    assert is_expiry_tracked_product(p) is False
    p2 = _product(track_inventory=False, track_expiry=True)
    assert is_expiry_tracked_product(p2) is False


def test_manufacturing_plus_shelf_life_computes_expiry_and_offsets() -> None:
    p = _product()
    mfg = date(2026, 11, 1)
    dates = compute_lot_dates(p, manufacturing_date=mfg, expiry_date=None)
    assert dates["expiry_date"] == date(2026, 12, 1)
    assert dates["alert_date"] == date(2026, 11, 24)
    assert dates["removal_date"] == date(2026, 11, 28)
    assert dates["best_before_date"] == date(2026, 11, 26)
    assert dates["manufacturing_date"] == mfg


def test_printed_expiry_wins_and_production_is_kept() -> None:
    p = _product()
    mfg = date(2026, 1, 1)
    exp = date(2026, 2, 15)
    dates = compute_lot_dates(p, manufacturing_date=mfg, expiry_date=exp)
    assert dates["manufacturing_date"] == mfg
    assert dates["expiry_date"] == exp


def test_carton_to_piece_inherits_same_lot_identity() -> None:
    p = _product()
    qty_main = quantity_line_to_main(Decimal("10"), p, "عدد")
    assert qty_main == Decimal("1")
    dual = dual_unit_qty(p, qty_main)
    assert dual["quantity_main"] == 1.0
    assert dual["quantity_secondary"] == 10.0
    key = lot_identity_key(9, None, "L-1", date(2026, 11, 1), date(2026, 12, 1))
    assert "9|0|L-1|2026-11-01|2026-12-01" in key


def test_lot_status_expired_and_near() -> None:
    lot = SimpleNamespace(
        is_undated=False,
        expiry_date=date(2026, 11, 10),
        removal_date=date(2026, 11, 7),
        alert_date=date(2026, 11, 3),
    )
    assert lot_status(lot, date(2026, 11, 10)) == STATUS_EXPIRED
    assert lot_status(lot, date(2026, 11, 8)) == "blocked"
    assert lot_status(lot, date(2026, 11, 4)) == STATUS_NEAR_EXPIRY
    assert lot_status(lot, date(2026, 11, 1)) == STATUS_SELLABLE


def test_parse_lot_allocations_and_single_lot_fallback() -> None:
    items = parse_payload_lot_allocations(
        {
            "extra_info": {
                "lot_allocations": [
                    {
                        "lot_code": "A",
                        "manufacturing_date": "2026-11-01",
                        "expiry_date": "2026-12-01",
                        "quantity": 1,
                    }
                ]
            }
        }
    )
    assert items[0]["lot_code"] == "A"
    fallback = parse_payload_lot_allocations(
        {
            "quantity": 2,
            "lot_code": "B",
            "manufacturing_date": "2026-11-01",
            "expiry_date": "2026-12-01",
        }
    )
    assert fallback[0]["lot_code"] == "B"
    assert fallback[0]["quantity"] == 2


def test_parse_empty_when_product_has_no_lot_fields() -> None:
    assert parse_payload_lot_allocations({"quantity": 5, "extra_info": {"unit": "عدد"}}) == []


def test_undated_status_and_identity_differs_from_dated() -> None:
    lot = SimpleNamespace(is_undated=True, expiry_date=None, removal_date=None, alert_date=None)
    assert lot_status(lot, date(2026, 11, 1)) == "undated"
    dated = lot_identity_key(1, None, "-", date(2026, 11, 1), date(2026, 12, 1), is_undated=False)
    undated = lot_identity_key(1, None, "-", None, None, is_undated=True)
    assert dated != undated


def test_parse_lot_from_dates_without_quantity() -> None:
    items = parse_payload_lot_allocations(
        {
            "extra_info": {
                "lot_code": "L1",
                "manufacturing_date": "2026-11-01",
                "expiry_date": "2026-12-01",
            }
        }
    )
    assert items[0]["lot_code"] == "L1"
    assert items[0]["quantity"] is None


def test_min_remaining_shelf_life_blocks_sellable() -> None:
    p = _product(min_remaining_shelf_life_days=10)
    lot = SimpleNamespace(
        is_undated=False,
        expiry_date=date(2026, 11, 10),
        removal_date=None,
        alert_date=None,
    )
    assert is_lot_sellable(lot, p, date(2026, 11, 5)) is False
    assert is_lot_sellable(lot, p, date(2026, 10, 30)) is True


def test_return_picks_last_sold_lots_first() -> None:
    sold = [
        (2, Decimal("3")),
        (1, Decimal("5")),
    ]
    picked = pick_return_lots(sold, {}, Decimal("4"))
    assert picked == [(2, Decimal("3")), (1, Decimal("1"))]


def test_return_excludes_already_returned_qty() -> None:
    sold = [(1, Decimal("10"))]
    picked = pick_return_lots(sold, {1: Decimal("6")}, Decimal("4"))
    assert picked == [(1, Decimal("4"))]
    empty = pick_return_lots(sold, {1: Decimal("10")}, Decimal("1"))
    assert empty == []


def test_waste_allows_expired_even_when_policy_blocks() -> None:
    p = _product(expired_sale_policy="block")
    assert _effective_allow_unsellable(p, allow_expired_confirm=True, allow_unsellable=True) is True
    assert _effective_allow_unsellable(p, allow_expired_confirm=True, allow_unsellable=None) is False
    p2 = _product(expired_sale_policy="manager_confirm")
    assert _effective_allow_unsellable(p2, allow_expired_confirm=True, allow_unsellable=None) is True


def test_eleven_pieces_from_dated_carton() -> None:
    p = _product()
    qty_main = quantity_line_to_main(Decimal("11"), p, "عدد")
    assert qty_main == Decimal("1.1")
    dual = dual_unit_qty(p, qty_main)
    assert dual["quantity_secondary"] == 11.0


def test_lot_identity_differs_by_variant() -> None:
    a = lot_identity_key(9, 1, "L-1", date(2026, 11, 1), date(2026, 12, 1))
    b = lot_identity_key(9, 2, "L-1", date(2026, 11, 1), date(2026, 12, 1))
    assert a != b


def test_unique_instance_dates_required_when_expiry_tracked() -> None:
    from adapters.api.v1.product_instances import _require_instance_dates
    from app.core.responses import ApiError

    p = _product(inventory_mode="unique")
    try:
        _require_instance_dates(p, None, None)
        raise AssertionError("expected INSTANCE_DATES_REQUIRED")
    except ApiError as exc:
        assert exc.code == "INSTANCE_DATES_REQUIRED"


def test_unique_instance_dates_kept_from_existing_on_update() -> None:
    from app.services.warehouse_service import _unique_instance_dates_from_payload

    p = _product(inventory_mode="unique")
    existing = SimpleNamespace(
        manufacturing_date=date(2026, 2, 1),
        expiry_date=date(2026, 4, 1),
    )
    mfg, exp = _unique_instance_dates_from_payload(p, {}, existing=existing)
    assert mfg == date(2026, 2, 1)
    assert exp == date(2026, 4, 1)
    m2, e2 = _unique_instance_dates_from_payload(
        p, {"manufacturing_date": "2026-01-10", "expiry_date": "2026-03-10"}
    )
    assert m2 == date(2026, 1, 10)
    assert e2 == date(2026, 3, 10)


def test_unique_instance_uses_same_expiry_status_as_lots() -> None:
    p = _product(inventory_mode="unique", min_remaining_shelf_life_days=0)
    inst = SimpleNamespace(manufacturing_date=date(2026, 1, 1), expiry_date=date(2026, 11, 1))
    view = instance_expiry_view(inst, p, date(2026, 11, 1))
    assert view["status"] == STATUS_EXPIRED
    assert is_instance_sellable(inst, p, date(2026, 11, 1)) is False
    assert is_instance_sellable(inst, p, date(2026, 10, 20)) is True


def test_variant_quantity_slices_keep_each_variant() -> None:
    from app.services.inventory_lot_allocation_service import _variant_quantity_slices

    extra = {
        "allocations": [
            {"variant_id": 1, "quantity": 2},
            {"variant_id": 2, "quantity": 3},
        ]
    }
    slices = _variant_quantity_slices({}, extra, Decimal("5"))
    assert slices == [(1, Decimal("2")), (2, Decimal("3"))]


def test_van_expired_lot_is_skipped_from_sale_plan() -> None:
    from app.services.distribution_field_ops_service import _van_lot_is_expired, NO_EXPIRY

    assert _van_lot_is_expired(date(2026, 10, 1), date(2026, 11, 1)) is True
    assert _van_lot_is_expired(date(2026, 12, 1), date(2026, 11, 1)) is False
    assert _van_lot_is_expired(NO_EXPIRY, date(2026, 11, 1)) is False
    assert _van_lot_is_expired(None, date(2026, 11, 1)) is False


def test_expired_confirm_flag_stripped_without_permission() -> None:
    from app.services.invoice_service import _apply_expired_sale_confirm_permission

    lines = [
        {"extra_info": {"allow_expired_lot_sale": True, "manager_confirm_expired": True}},
        {"extra_info": {"lot_code": "A"}},
    ]
    _apply_expired_sale_confirm_permission(
        "invoice_sales", lines, user_can_confirm_expired_sale=False
    )
    assert "allow_expired_lot_sale" not in lines[0]["extra_info"]
    assert "manager_confirm_expired" not in lines[0]["extra_info"]
    _apply_expired_sale_confirm_permission(
        "invoice_sales", lines, user_can_confirm_expired_sale=True
    )
    waste = [{"extra_info": {"allow_expired_lot_sale": True}}]
    _apply_expired_sale_confirm_permission(
        "invoice_waste", waste, user_can_confirm_expired_sale=False
    )
    assert waste[0]["extra_info"]["allow_expired_lot_sale"] is True


def test_instance_blocked_by_removal_offset() -> None:
    p = _product(inventory_mode="unique", removal_offset_days=3, min_remaining_shelf_life_days=0)
    inst = SimpleNamespace(manufacturing_date=date(2026, 1, 1), expiry_date=date(2026, 11, 5))
    view = instance_expiry_view(inst, p, date(2026, 11, 3))
    assert view["status"] == STATUS_BLOCKED
    assert is_instance_sellable(inst, p, date(2026, 11, 3)) is False
    assert is_instance_sellable(inst, p, date(2026, 10, 1)) is True


def _lot_sqlite_session():
    from sqlalchemy import Column, Integer, MetaData, Table, create_engine
    from sqlalchemy.orm import sessionmaker

    from adapters.db.models.inventory_lot import InventoryLot, InvoiceItemLineLotAllocation
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from adapters.db.models.product_instance import ProductInstance

    engine = create_engine("sqlite:///:memory:")
    meta = MetaData()
    for src in (
        InventoryLot.__table__,
        InvoiceItemLine.__table__,
        InvoiceItemLineLotAllocation.__table__,
        ProductInstance.__table__,
    ):
        cols = []
        for c in src.columns:
            cols.append(
                Column(
                    c.name,
                    Integer() if c.primary_key else c.type,
                    primary_key=c.primary_key,
                    nullable=c.nullable,
                    autoincrement=True if c.primary_key else False,
                )
            )
        Table(src.name, meta, *cols)
    meta.create_all(engine)
    return sessionmaker(bind=engine)()


def test_sqlite_find_or_create_lot_computes_offsets() -> None:
    from app.services.inventory_lot_service import find_or_create_lot

    db = _lot_sqlite_session()
    p = _product()
    p.id = 7
    p.name = "شیر"
    lot = find_or_create_lot(
        db,
        1,
        p,
        lot_code="L-1",
        manufacturing_date=date(2026, 1, 1),
        expiry_date=date(2026, 1, 31),
    )
    db.commit()
    same = find_or_create_lot(
        db,
        1,
        p,
        lot_code="L-1",
        manufacturing_date=date(2026, 1, 1),
        expiry_date=date(2026, 1, 31),
    )
    assert same.id == lot.id
    assert lot.best_before_date == date(2026, 1, 26)
    assert lot.removal_date == date(2026, 1, 28)
    assert lot.alert_date == date(2026, 1, 24)
    db.close()


def test_sqlite_persist_rejects_lots_when_expiry_off() -> None:
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from app.core.responses import ApiError
    from app.services.inventory_lot_allocation_service import persist_invoice_lot_allocations

    db = _lot_sqlite_session()
    line = InvoiceItemLine(document_id=1, product_id=3, quantity=Decimal("2"), extra_info={})
    db.add(line)
    db.flush()
    p = _product(track_expiry=False)
    p.id = 3
    p.name = "پیچ"
    try:
        persist_invoice_lot_allocations(
            db,
            1,
            line,
            p,
            {
                "lot_allocations": [
                    {"lot_code": "X", "expiry_date": "2026-12-01", "quantity": 2}
                ]
            },
            movement="in",
            warehouse_id=1,
            document_date=date(2026, 11, 1),
        )
        raise AssertionError("expected EXPIRY_NOT_ENABLED")
    except ApiError as exc:
        assert exc.code == "EXPIRY_NOT_ENABLED"
    empty = persist_invoice_lot_allocations(
        db,
        1,
        line,
        p,
        {},
        movement="out",
        warehouse_id=1,
        document_date=date(2026, 11, 1),
    )
    assert empty == []
    db.close()


def test_sqlite_inbound_persist_creates_lot_and_allocation() -> None:
    from adapters.db.models.inventory_lot import InventoryLot, InvoiceItemLineLotAllocation
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from app.services.inventory_lot_allocation_service import persist_invoice_lot_allocations

    db = _lot_sqlite_session()
    line = InvoiceItemLine(document_id=9, product_id=4, quantity=Decimal("2"), extra_info={})
    db.add(line)
    db.flush()
    p = _product()
    p.id = 4
    p.name = "ماست"
    rows = persist_invoice_lot_allocations(
        db,
        1,
        line,
        p,
        {
            "lot_allocations": [
                {
                    "lot_code": "YOG-1",
                    "manufacturing_date": "2026-01-01",
                    "expiry_date": "2026-12-01",
                    "quantity": 2,
                }
            ]
        },
        movement="in",
        warehouse_id=1,
        document_date=date(2026, 11, 1),
    )
    db.commit()
    assert len(rows) == 1
    lot = db.query(InventoryLot).one()
    assert lot.lot_code == "YOG-1"
    assert lot.expiry_date == date(2026, 12, 1)
    alloc = db.query(InvoiceItemLineLotAllocation).one()
    assert alloc.lot_id == lot.id
    assert alloc.quantity == Decimal("2")
    stamped = line.extra_info["lot_allocations"]
    assert stamped[0]["lot_code"] == "YOG-1"
    db.close()


def test_sqlite_fefo_skips_expired_and_picks_earliest_sellable(monkeypatch) -> None:
    from decimal import Decimal as D

    from app.services.inventory_lot_service import find_or_create_lot, suggest_fefo

    db = _lot_sqlite_session()
    p = _product()
    p.id = 8
    p.name = "شیر"
    expired = find_or_create_lot(
        db, 1, p, lot_code="OLD", manufacturing_date=date(2026, 1, 1), expiry_date=date(2026, 10, 1)
    )
    soon = find_or_create_lot(
        db, 1, p, lot_code="SOON", manufacturing_date=date(2026, 2, 1), expiry_date=date(2026, 11, 20)
    )
    later = find_or_create_lot(
        db, 1, p, lot_code="LATER", manufacturing_date=date(2026, 3, 1), expiry_date=date(2026, 12, 20)
    )
    db.commit()

    def _avail(_db, _bid, _pid, _wh, lot_id, _as_of, **_kw):
        return D("10")

    monkeypatch.setattr(
        "app.services.inventory_lot_service.compute_available_lot_stock", _avail
    )
    monkeypatch.setattr(
        "app.services.inventory_lot_service.ensure_undated_lot", lambda *a, **k: soon
    )
    picked = suggest_fefo(db, 1, p, 1, D("4"), date(2026, 11, 2), allow_unsellable=False)
    assert [lot.lot_code for lot, _qty in picked] == ["SOON"]
    assert picked[0][1] == D("4")
    waste = suggest_fefo(db, 1, p, 1, D("4"), date(2026, 11, 2), allow_unsellable=True)
    assert waste[0][0].id == expired.id
    assert later.id not in {lot.id for lot, _ in waste}
    db.close()


def test_sqlite_outbound_auto_fefo_stamps_line_extra(monkeypatch) -> None:
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from app.services.inventory_lot_allocation_service import persist_invoice_lot_allocations
    from app.services.inventory_lot_service import find_or_create_lot

    db = _lot_sqlite_session()
    p = _product()
    p.id = 11
    p.name = "کره"
    lot = find_or_create_lot(
        db, 1, p, lot_code="BUTTER", manufacturing_date=date(2026, 1, 1), expiry_date=date(2026, 12, 1)
    )
    db.commit()
    line = InvoiceItemLine(document_id=2, product_id=11, quantity=Decimal("1"), extra_info={})
    db.add(line)
    db.flush()

    def _avail(_db, _bid, _pid, _wh, lot_id, _as_of, **_kw):
        return Decimal("5") if int(lot_id) == int(lot.id) else Decimal("0")

    monkeypatch.setattr(
        "app.services.inventory_lot_service.compute_available_lot_stock", _avail
    )
    monkeypatch.setattr(
        "app.services.inventory_lot_service.ensure_undated_lot", lambda *a, **k: lot
    )
    rows = persist_invoice_lot_allocations(
        db,
        1,
        line,
        p,
        {},
        movement="out",
        warehouse_id=1,
        document_date=date(2026, 11, 1),
    )
    assert len(rows) == 1
    assert rows[0].lot_id == lot.id
    assert line.extra_info["lot_allocations"][0]["lot_code"] == "BUTTER"
    db.close()


def test_sqlite_outbound_fefo_secondary_unit_consumes_one_main_lot(monkeypatch) -> None:
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from app.services.inventory_lot_allocation_service import persist_invoice_lot_allocations
    from app.services.inventory_lot_service import find_or_create_lot

    db = _lot_sqlite_session()
    p = _product()
    p.id = 12
    p.name = "شیر کارتن"
    lot = find_or_create_lot(
        db, 1, p, lot_code="CTN-1", manufacturing_date=date(2026, 1, 1), expiry_date=date(2026, 12, 1)
    )
    db.commit()
    line = InvoiceItemLine(
        document_id=3,
        product_id=12,
        quantity=Decimal("10"),
        extra_info={"unit": "عدد"},
    )
    db.add(line)
    db.flush()

    def _avail(_db, _bid, _pid, _wh, lot_id, _as_of, **_kw):
        return Decimal("5") if int(lot_id) == int(lot.id) else Decimal("0")

    monkeypatch.setattr(
        "app.services.inventory_lot_service.compute_available_lot_stock", _avail
    )
    monkeypatch.setattr(
        "app.services.inventory_lot_service.ensure_undated_lot", lambda *a, **k: lot
    )
    rows = persist_invoice_lot_allocations(
        db,
        1,
        line,
        p,
        {"extra_info": {"unit": "عدد"}},
        movement="out",
        warehouse_id=1,
        document_date=date(2026, 11, 1),
    )
    assert len(rows) == 1
    assert rows[0].quantity == Decimal("10")
    assert rows[0].lot_id == lot.id
    db.close()


def test_operational_and_issuable_stock_use_sellable_for_expiry(monkeypatch) -> None:
    from app.services.production_order_service import _issuable_stock
    from app.services.warehouse_reports_service import _operational_stock

    p = _product()
    p.id = 21
    p.name = "شیر"
    monkeypatch.setattr(
        "app.services.inventory_lot_service.sellable_quantity",
        lambda *a, **k: Decimal("3"),
    )
    monkeypatch.setattr(
        "app.services.warehouse_reports_service._compute_available_stock",
        lambda *a, **k: Decimal("9"),
    )
    monkeypatch.setattr(
        "app.services.invoice_service._compute_available_stock",
        lambda *a, **k: Decimal("9"),
    )
    as_of = date(2026, 11, 2)
    assert _operational_stock(None, 1, p, 4, as_of) == Decimal("3")
    assert _issuable_stock(None, 1, p, 4, as_of) == Decimal("3")
    plain = _product(track_expiry=False)
    plain.id = 22
    plain.name = "پیچ"
    assert _operational_stock(None, 1, plain, 4, as_of) == Decimal("9")
    assert _issuable_stock(None, 1, plain, 4, as_of) == Decimal("9")


def test_sqlite_expired_sale_blocked_waste_writes_off(monkeypatch) -> None:
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from app.core.responses import ApiError
    from app.services.inventory_lot_allocation_service import persist_invoice_lot_allocations
    from app.services.inventory_lot_service import find_or_create_lot

    db = _lot_sqlite_session()
    p = _product(expired_sale_policy="block")
    p.id = 31
    p.name = "ماست"
    lot = find_or_create_lot(
        db, 1, p, lot_code="EXP", manufacturing_date=date(2026, 1, 1), expiry_date=date(2026, 10, 1)
    )
    db.commit()
    sale = InvoiceItemLine(document_id=10, product_id=31, quantity=Decimal("2"), extra_info={})
    db.add(sale)
    db.flush()
    payload = {"lot_allocations": [{"lot_id": int(lot.id), "quantity": 2}]}
    try:
        persist_invoice_lot_allocations(
            db, 1, sale, p, payload, movement="out", warehouse_id=1, document_date=date(2026, 11, 2)
        )
        raise AssertionError("expected EXPIRED_LOT_BLOCKED")
    except ApiError as exc:
        assert exc.code == "EXPIRED_LOT_BLOCKED"
    waste = InvoiceItemLine(document_id=11, product_id=31, quantity=Decimal("2"), extra_info={})
    db.add(waste)
    db.flush()
    rows = persist_invoice_lot_allocations(
        db,
        1,
        waste,
        p,
        payload,
        movement="out",
        warehouse_id=1,
        document_date=date(2026, 11, 2),
        allow_unsellable=True,
    )
    assert len(rows) == 1
    assert rows[0].lot_id == lot.id
    db.close()


def test_sqlite_sales_return_restores_same_sale_lot(monkeypatch) -> None:
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from app.services.inventory_lot_allocation_service import persist_invoice_lot_allocations
    from app.services.inventory_lot_service import find_or_create_lot

    db = _lot_sqlite_session()
    p = _product()
    p.id = 41
    p.name = "شیر"
    lot = find_or_create_lot(
        db, 1, p, lot_code="SALE-1", manufacturing_date=date(2026, 1, 1), expiry_date=date(2026, 12, 1)
    )
    db.commit()
    sale = InvoiceItemLine(document_id=20, product_id=41, quantity=Decimal("4"), extra_info={})
    db.add(sale)
    db.flush()

    def _avail(_db, _bid, _pid, _wh, lot_id, _as_of, **_kw):
        return Decimal("10") if int(lot_id) == int(lot.id) else Decimal("0")

    monkeypatch.setattr(
        "app.services.inventory_lot_service.compute_available_lot_stock", _avail
    )
    monkeypatch.setattr(
        "app.services.inventory_lot_service.ensure_undated_lot", lambda *a, **k: lot
    )
    sold = persist_invoice_lot_allocations(
        db, 1, sale, p, {}, movement="out", warehouse_id=1, document_date=date(2026, 11, 1)
    )
    assert sold[0].lot_id == lot.id
    ret = InvoiceItemLine(document_id=21, product_id=41, quantity=Decimal("4"), extra_info={})
    db.add(ret)
    db.flush()
    restored = persist_invoice_lot_allocations(
        db,
        1,
        ret,
        p,
        {"extra_info": {"returned_from_invoice_item_line_id": int(sale.id)}},
        movement="in",
        warehouse_id=1,
        document_date=date(2026, 11, 2),
        restore_from_sales=True,
    )
    assert len(restored) == 1
    assert restored[0].lot_id == lot.id
    assert restored[0].quantity == Decimal("4")
    db.close()


def test_sqlite_unique_sellable_skips_expired_instances() -> None:
    from adapters.db.models.product_instance import ProductInstance
    from app.services.inventory_lot_service import unique_sellable_quantity

    db = _lot_sqlite_session()
    p = _product(inventory_mode="unique")
    p.id = 51
    p.name = "دارو"
    db.add(
        ProductInstance(
            business_id=1,
            product_id=51,
            serial_number="SN-OK",
            status="available",
            warehouse_id=1,
            entry_date=date(2026, 1, 1),
            manufacturing_date=date(2026, 1, 1),
            expiry_date=date(2026, 12, 1),
        )
    )
    db.add(
        ProductInstance(
            business_id=1,
            product_id=51,
            serial_number="SN-EXP",
            status="available",
            warehouse_id=1,
            entry_date=date(2026, 1, 1),
            manufacturing_date=date(2026, 1, 1),
            expiry_date=date(2026, 10, 1),
        )
    )
    db.add(
        ProductInstance(
            business_id=1,
            product_id=51,
            serial_number="SN-SOLD",
            status="sold",
            warehouse_id=1,
            entry_date=date(2026, 1, 1),
            manufacturing_date=date(2026, 1, 1),
            expiry_date=date(2026, 12, 1),
        )
    )
    db.commit()
    qty = unique_sellable_quantity(db, 1, p, 1, date(2026, 11, 2))
    assert qty == Decimal("1")
    db.close()


def test_sqlite_same_lot_code_differs_by_variant() -> None:
    from app.services.inventory_lot_service import find_or_create_lot

    db = _lot_sqlite_session()
    p = _product()
    p.id = 61
    p.name = "شیر طعم‌دار"
    a = find_or_create_lot(
        db,
        1,
        p,
        lot_code="L-1",
        variant_id=11,
        manufacturing_date=date(2026, 1, 1),
        expiry_date=date(2026, 12, 1),
    )
    b = find_or_create_lot(
        db,
        1,
        p,
        lot_code="L-1",
        variant_id=12,
        manufacturing_date=date(2026, 1, 1),
        expiry_date=date(2026, 12, 1),
    )
    db.commit()
    assert a.id != b.id
    assert a.variant_id == 11
    assert b.variant_id == 12
    db.close()


def test_sqlite_outbound_fefo_splits_variant_slices(monkeypatch) -> None:
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from app.services.inventory_lot_allocation_service import persist_invoice_lot_allocations
    from app.services.inventory_lot_service import find_or_create_lot

    db = _lot_sqlite_session()
    p = _product()
    p.id = 62
    p.name = "ماست"
    v1 = find_or_create_lot(
        db, 1, p, lot_code="V1", variant_id=21, manufacturing_date=date(2026, 1, 1), expiry_date=date(2026, 11, 10)
    )
    v2 = find_or_create_lot(
        db, 1, p, lot_code="V2", variant_id=22, manufacturing_date=date(2026, 1, 1), expiry_date=date(2026, 12, 10)
    )
    db.commit()
    line = InvoiceItemLine(document_id=30, product_id=62, quantity=Decimal("5"), extra_info={})
    db.add(line)
    db.flush()

    def _avail(_db, _bid, _pid, _wh, lot_id, _as_of, **_kw):
        return Decimal("10")

    monkeypatch.setattr(
        "app.services.inventory_lot_service.compute_available_lot_stock", _avail
    )
    monkeypatch.setattr(
        "app.services.inventory_lot_service.ensure_undated_lot",
        lambda *_a, **k: v1 if k.get("variant_id") == 21 else v2,
    )
    rows = persist_invoice_lot_allocations(
        db,
        1,
        line,
        p,
        {
            "extra_info": {
                "allocations": [
                    {"variant_id": 21, "quantity": 2},
                    {"variant_id": 22, "quantity": 3},
                ]
            }
        },
        movement="out",
        warehouse_id=1,
        document_date=date(2026, 11, 1),
    )
    by_lot = {int(r.lot_id): r.quantity for r in rows}
    assert by_lot[int(v1.id)] == Decimal("2")
    assert by_lot[int(v2.id)] == Decimal("3")
    db.close()


def test_sqlite_opening_balance_uses_undated_lot() -> None:
    from adapters.db.models.inventory_lot import InventoryLot
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from app.services.inventory_lot_allocation_service import persist_invoice_lot_allocations

    db = _lot_sqlite_session()
    p = _product()
    p.id = 63
    p.name = "کره"
    line = InvoiceItemLine(document_id=40, product_id=63, quantity=Decimal("8"), extra_info={})
    db.add(line)
    db.flush()
    rows = persist_invoice_lot_allocations(
        db,
        1,
        line,
        p,
        {"extra_info": {"allow_undated_opening": True}},
        movement="in",
        warehouse_id=1,
        document_date=date(2026, 11, 1),
    )
    db.commit()
    assert len(rows) == 1
    lot = db.query(InventoryLot).one()
    assert bool(lot.is_undated) is True
    assert lot.lot_code == "-"
    assert rows[0].quantity == Decimal("8")
    db.close()


def test_sqlite_unique_product_rejects_bulk_lot_allocations() -> None:
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from app.core.responses import ApiError
    from app.services.inventory_lot_allocation_service import persist_invoice_lot_allocations

    db = _lot_sqlite_session()
    p = _product(inventory_mode="unique")
    p.id = 71
    p.name = "دارو یونیک"
    line = InvoiceItemLine(document_id=50, product_id=71, quantity=Decimal("1"), extra_info={})
    db.add(line)
    db.flush()
    try:
        persist_invoice_lot_allocations(
            db,
            1,
            line,
            p,
            {
                "lot_allocations": [
                    {"lot_code": "X", "expiry_date": "2026-12-01", "quantity": 1}
                ]
            },
            movement="out",
            warehouse_id=1,
            document_date=date(2026, 11, 1),
        )
        raise AssertionError("expected LOT_UNIQUE_NOT_SUPPORTED")
    except ApiError as exc:
        assert exc.code == "LOT_UNIQUE_NOT_SUPPORTED"
    db.close()


def test_mcp_lot_tools_map_to_inventory_stock() -> None:
    from app.services.ai.ai_tool_capability import resolve_tool_capability
    from app.services.ai.ai_tool_keys import TOOL_L10N_KEYS, TOOL_LABELS_FA
    from app.services.ai.ai_tool_manifest import TOOL_MANIFEST
    from app.services.ai.ai_tool_search_meta import TOOL_SEARCH_META

    assert resolve_tool_capability("list_inventory_lots") == "inventory.stock"
    assert resolve_tool_capability("get_expiry_stock_report") == "inventory.stock"
    for name in ("list_inventory_lots", "get_expiry_stock_report"):
        assert name in TOOL_MANIFEST
        assert name in TOOL_SEARCH_META
        assert name in TOOL_LABELS_FA
        assert name in TOOL_L10N_KEYS


def test_unit_dates_from_lot_balances_fefo_then_undated() -> None:
    from app.services.inventory_lot_service import unit_dates_from_lot_balances

    rows = [
        {"quantity_main": 2, "manufacturing_date": "2026-01-01", "expiry_date": "2026-02-01"},
        {"quantity_main": 1, "manufacturing_date": None, "expiry_date": None},
    ]
    dates = unit_dates_from_lot_balances(rows, 4)
    assert dates == [
        ("2026-01-01", "2026-02-01"),
        ("2026-01-01", "2026-02-01"),
        (None, None),
        (None, None),
    ]


def test_slice_lots_across_quantities_keeps_dates() -> None:
    from app.services.inventory_lot_allocation_service import slice_lots_across_quantities

    early = SimpleNamespace(
        lot_code="A",
        manufacturing_date=date(2026, 1, 1),
        expiry_date=date(2026, 2, 1),
        is_undated=False,
    )
    later = SimpleNamespace(
        lot_code="B",
        manufacturing_date=date(2026, 3, 1),
        expiry_date=date(2026, 6, 1),
        is_undated=False,
    )
    sliced = slice_lots_across_quantities(
        [(early, Decimal("3")), (later, Decimal("2"))],
        [(11, Decimal("2")), (12, Decimal("3"))],
    )
    assert sliced[0][0] == 11
    assert sliced[0][1] == [
        {
            "lot_code": "A",
            "manufacturing_date": "2026-01-01",
            "expiry_date": "2026-02-01",
            "quantity": "2",
            "is_undated": False,
        }
    ]
    assert sliced[1][0] == 12
    assert [row["lot_code"] for row in sliced[1][1]] == ["A", "B"]
    assert sliced[1][1][0]["quantity"] == "1"
    assert sliced[1][1][1]["quantity"] == "2"


def test_sqlite_sale_return_then_waste_same_lots(monkeypatch) -> None:
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from app.services.inventory_lot_allocation_service import persist_invoice_lot_allocations
    from app.services.inventory_lot_service import find_or_create_lot

    db = _lot_sqlite_session()
    p = _product(expired_sale_policy="block")
    p.id = 81
    p.name = "ماست"
    fresh = find_or_create_lot(
        db, 1, p, lot_code="FRESH", manufacturing_date=date(2026, 10, 1), expiry_date=date(2026, 12, 1)
    )
    expired = find_or_create_lot(
        db, 1, p, lot_code="OLD", manufacturing_date=date(2026, 1, 1), expiry_date=date(2026, 10, 1)
    )
    db.commit()
    avail = {int(fresh.id): Decimal("10"), int(expired.id): Decimal("5")}

    def _avail(_db, _bid, _pid, _wh, lot_id, _as_of, **_kw):
        return avail.get(int(lot_id), Decimal("0"))

    monkeypatch.setattr("app.services.inventory_lot_service.compute_available_lot_stock", _avail)
    monkeypatch.setattr("app.services.inventory_lot_service.ensure_undated_lot", lambda *a, **k: fresh)
    sale = InvoiceItemLine(document_id=90, product_id=81, quantity=Decimal("3"), extra_info={})
    db.add(sale)
    db.flush()
    sold = persist_invoice_lot_allocations(
        db, 1, sale, p, {}, movement="out", warehouse_id=1, document_date=date(2026, 11, 2)
    )
    assert sold[0].lot_id == fresh.id
    avail[int(fresh.id)] -= Decimal("3")
    ret = InvoiceItemLine(document_id=91, product_id=81, quantity=Decimal("3"), extra_info={})
    db.add(ret)
    db.flush()
    restored = persist_invoice_lot_allocations(
        db,
        1,
        ret,
        p,
        {"extra_info": {"returned_from_invoice_item_line_id": int(sale.id)}},
        movement="in",
        warehouse_id=1,
        document_date=date(2026, 11, 2),
        restore_from_sales=True,
    )
    assert restored[0].lot_id == fresh.id
    avail[int(fresh.id)] += Decimal("3")
    waste = InvoiceItemLine(document_id=92, product_id=81, quantity=Decimal("5"), extra_info={})
    db.add(waste)
    db.flush()
    written_off = persist_invoice_lot_allocations(
        db,
        1,
        waste,
        p,
        {},
        movement="out",
        warehouse_id=1,
        document_date=date(2026, 11, 2),
        allow_unsellable=True,
    )
    assert written_off[0].lot_id == expired.id
    assert written_off[0].quantity == Decimal("5")
    db.close()


def test_quick_sale_mcp_schema_accepts_lot_allocations() -> None:
    from app.services.ai.ai_function_extensions_mcp_quick_sales import _LINE

    assert "lot_allocations" in _LINE["properties"]
    assert "allow_expired_lot_sale" in _LINE["properties"]


def test_gei_mcp_schema_accepts_unique_instance_ids() -> None:
    from app.services.ai.ai_function_extensions_mcp_gei import _LINE

    assert "lot_allocations" in _LINE["properties"]
    assert "selected_instance_ids" in _LINE["properties"]
    assert "instance_ids" in _LINE["properties"]


def test_product_search_payload_includes_expiry_flags() -> None:
    import inspect
    from adapters.db.repositories.product_repository import ProductRepository

    src = inspect.getsource(ProductRepository.search)
    assert '"track_expiry"' in src
    assert '"lot_policy"' in src
    assert '"expired_sale_policy"' in src
    assert '"inventory_stock_sellable"' in src
    assert "sellable_quantity" in src
    assert "business_as_of" in src


def test_pick_unique_instances_fefo_skips_expired() -> None:
    from app.services.inventory_lot_service import pick_unique_instances_fefo

    p = _product(inventory_mode="unique", id=9)
    insts = [
        SimpleNamespace(id=1, manufacturing_date=None, expiry_date=date(2026, 12, 1), status="available", warehouse_id=1),
        SimpleNamespace(id=2, manufacturing_date=None, expiry_date=date(2026, 11, 10), status="available", warehouse_id=1),
        SimpleNamespace(id=3, manufacturing_date=None, expiry_date=date(2026, 10, 1), status="available", warehouse_id=1),
    ]

    class _Q:
        def filter(self, *args, **kwargs):
            return self

        def all(self):
            return insts

    class _DB:
        def query(self, *args, **kwargs):
            return _Q()

    ids = pick_unique_instances_fefo(_DB(), 1, p, 1, 1, date(2026, 11, 2))
    assert ids == [2]


def test_stock_count_unique_and_gei_keep_lot_identity() -> None:
    import inspect
    from app.services.warehouse_service import _stock_count_lot_rows, calculate_stock_count_differences
    from app.services.goods_expense_income_service import create_from_stock_count

    rows_src = inspect.getsource(_stock_count_lot_rows)
    assert "instance_id" in rows_src
    assert "instance_expiry_view" in rows_src
    diff_src = inspect.getsource(calculate_stock_count_differences)
    assert "instance_id" in diff_src
    gei_src = inspect.getsource(create_from_stock_count)
    assert "lot_allocations" in gei_src
    assert "selected_instance_ids" in gei_src


def test_normalize_unique_instance_ids_from_singular() -> None:
    from app.services.invoice_service import _normalize_unique_instance_ids
    from app.services.warehouse_service import _unique_instance_ids_from_line

    extra = _normalize_unique_instance_ids({"instance_id": 9})
    assert extra["selected_instance_ids"] == [9]
    assert extra["instance_ids"] == [9]
    assert extra["instance_id"] == 9
    merged = _normalize_unique_instance_ids(
        {"instance_id": 2, "selected_instance_ids": [2, 3]}
    )
    assert merged["selected_instance_ids"] == [2, 3]
    assert _unique_instance_ids_from_line({}, {"instance_id": 11}) == [11]
    assert _unique_instance_ids_from_line(
        {}, {"selected_instance_ids": [4, 5]}
    ) == [4, 5]


def test_van_available_qty_uses_sellable_for_expiry_products(monkeypatch) -> None:
    from app.services.distribution_phase3_service import _van_available_qty

    p = _product()

    class _DB:
        def get(self, model, pid):
            return p

    monkeypatch.setattr(
        "app.services.inventory_lot_service.sellable_quantity",
        lambda *args, **kwargs: 4,
    )
    monkeypatch.setattr(
        "app.services.distribution_phase3_service.get_physical_stock",
        lambda *args, **kwargs: 9,
    )
    as_of = date(2026, 11, 2)
    assert _van_available_qty(_DB(), 1, 1, 1, as_of, sellable=True) == 4.0
    assert _van_available_qty(_DB(), 1, 1, 1, as_of, sellable=False) == 9.0


def test_suggest_fefo_skips_unique_leftover_lots() -> None:
    from app.services.inventory_lot_service import suggest_fefo

    p = _product(inventory_mode="unique")

    class _DB:
        def query(self, *args, **kwargs):
            raise AssertionError("unique products must not query leftover bulk lots")

    assert suggest_fefo(_DB(), 1, p, 1, Decimal("2"), date(2026, 11, 2)) == []


def test_production_lots_persist_unique_instance_ids() -> None:
    import inspect
    from adapters.api.v1.schema_models.production_order import ProductionOrderLotLine
    from app.services.invoice_service import _attach_production_order_lots_to_invoice_lines
    from app.services.production_order_service import _order_dict, update_production_order_lots

    assert "selected_instance_ids" in ProductionOrderLotLine.model_fields
    src = inspect.getsource(update_production_order_lots)
    assert "material_instance_ids" in src
    assert "selected_instance_ids" in inspect.getsource(_order_dict)
    attach = inspect.getsource(_attach_production_order_lots_to_invoice_lines)
    assert "material_instance_ids" in attach


def test_gei_unique_income_mints_instances() -> None:
    import inspect
    from app.services.goods_expense_income_service import _create_warehouse_and_post

    src = inspect.getsource(_create_warehouse_and_post)
    assert "ProductInstance" in src
    assert "manufacturing_date" in src
    assert "_unique_instance_dates_from_payload" in src


def test_basalam_stock_uses_sellable_for_expiry() -> None:
    from pathlib import Path

    src = Path("app/services/basalam_integration_service.py").read_text(encoding="utf-8")
    assert "def _basalam_local_stock" in src
    assert "is_expiry_tracked_product" in src
    assert "sellable_quantity" in src
    assert "_basalam_local_stock(db, int(business_id), p, payload, settings)" in src


def test_repair_parts_stamp_instance_and_lot_identity() -> None:
    import inspect
    from app.services.repair_shop_operations import add_parts_to_repair_order

    src = inspect.getsource(add_parts_to_repair_order)
    assert "selected_instance_ids" in src
    assert "lot_allocations" in src
    assert "sellable_quantity" in src


def test_workflow_inventory_and_invoice_stamp_lot_identity() -> None:
    from pathlib import Path

    src = Path("app/services/workflow/actions/document_actions.py").read_text(encoding="utf-8")
    assert "lot_allocations" in src
    assert "selected_instance_ids" in src
    assert "manufacturing_date" in src
    payload = Path("app/services/ai/ai_tool_payloads.py").read_text(encoding="utf-8")
    assert '"selected_instance_ids"' in payload
    assert "line[\"instance_ids\"]" in payload or "line['instance_ids']" in payload
