"""گردش طبقات اموال باید هویت استاندارد ۱۱ را حفظ کند."""
from datetime import date
from decimal import Decimal

import pytest

from app.core.responses import ApiError
from app.services.fixed_asset_reports import (
    REPORT_KINDS,
    _optional_date,
    _period,
    class_rollforward_amounts,
)


def test_class_rollforward_identity():
    rf = class_rollforward_amounts(
        closing_cost=Decimal("12000000.00"),
        closing_accum=Decimal("3000000.00"),
        additions=Decimal("4000000.00"),
        major_repairs=Decimal("500000.00"),
        depreciation=Decimal("800000.00"),
        disposals_cost=Decimal("2000000.00"),
        disposals_accum=Decimal("1500000.00"),
    )
    opening_nbv = rf["opening_nbv"]
    closing_nbv = rf["closing_nbv"]
    assert closing_nbv == Decimal("9000000.00")
    assert (
        opening_nbv
        + rf["additions"]
        + rf["major_repairs"]
        - rf["disposals_nbv"]
        - rf["depreciation"]
        == closing_nbv
    )
    assert rf["opening_cost"] == Decimal("9500000.00")
    assert rf["opening_accum"] == Decimal("3700000.00")


def test_report_kinds_cover_standard_fa_set():
    assert REPORT_KINDS == {
        "register",
        "class_summary",
        "depreciation",
        "acquisitions",
        "disposals",
        "idle",
        "locations",
        "expenditures",
    }


def test_period_rejects_inverted_range():
    with pytest.raises(ApiError) as exc:
        _period(date(2026, 12, 1), date(2026, 1, 1))
    assert exc.value.code == "INVALID_DATE_RANGE"


def test_optional_date_accepts_iso_and_datetime():
    assert _optional_date("2026-03-21", "from_date") == date(2026, 3, 21)
    assert _optional_date(None, "from_date") is None
