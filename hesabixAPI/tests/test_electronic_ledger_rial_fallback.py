"""Regression: electronic legal books resolve Rial independently of UI filters.

Exercises the actual Currency catalogue on SQLite and verifies that both
journal and general-ledger services forward the resolved currency ID.
"""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest
import sqlalchemy as sa
from sqlalchemy.orm import Session

from adapters.db.models.currency import Currency
from app.core.responses import ApiError
from app.services import general_ledger_electronic_export_service as general
from app.services import journal_ledger_electronic_export_service as journal


@pytest.fixture()
def currencies():
    engine = sa.create_engine("sqlite://")
    with engine.begin() as connection:
        connection.execute(sa.schema.CreateTable(Currency.__table__, include_foreign_key_constraints=[]))
    with Session(engine) as db:
        db.add_all([
            Currency(id=3, name="Rial", title="Iranian Rial", symbol="IRR", code="irr"),
            Currency(id=8, name="Dollar", title="US Dollar", symbol="USD", code="USD"),
        ])
        db.commit()
        yield db
    engine.dispose()


def test_missing_filter_resolves_real_currency_catalogue(currencies):
    assert journal._ensure_rial_currency(currencies, None) == 3
    assert journal._ensure_rial_currency(currencies, 3) == 3


def test_explicit_non_rial_is_not_silently_converted(currencies):
    with pytest.raises(ApiError) as exc:
        journal._ensure_rial_currency(currencies, 8)
    assert (exc.value.code, exc.value.status_code) == ("NON_RIAL_CURRENCY", 400)


def test_unknown_selected_currency_fails_closed(currencies):
    with pytest.raises(ApiError) as exc:
        journal._ensure_rial_currency(currencies, 999)
    assert (exc.value.code, exc.value.status_code) == ("CURRENCY_NOT_FOUND", 404)


def test_catalogue_without_rial_is_rejected(currencies):
    currencies.query(Currency).filter(Currency.id == 3).delete()
    currencies.commit()
    with pytest.raises(ApiError) as exc:
        journal._ensure_rial_currency(currencies, None)
    assert (exc.value.code, exc.value.status_code) == ("CURRENCY_REQUIRED", 400)


@pytest.mark.parametrize("service", [journal, general], ids=["journal", "general-ledger"])
def test_electronic_export_forwards_resolved_currency_id(monkeypatch, service):
    seen = []

    def fake_report(**params):
        seen.append(params)
        return {"summary": {"balance_valid": True}, "items": [{}]}

    monkeypatch.setattr(service, "get_journal_ledger_report", fake_report)
    monkeypatch.setattr(service, "_ensure_rial_currency", lambda db, selected: 3)
    monkeypatch.setattr(service, "export_filename_timestamp", lambda business_id: "test")
    row_builder_name = (
        "build_electronic_journal_rows" if service is journal
        else "build_electronic_general_ledger_rows"
    )
    monkeypatch.setattr(service, row_builder_name, lambda items: [[1, "data"]])
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = None

    exporter = (
        journal.export_electronic_journal_books if service is journal
        else general.export_electronic_general_ledger_books
    )
    result = exporter(
        db,
        business_id=10,
        fiscal_year_id=2,
        currency_id=None,
        date_from="2026-01-01",
        date_to="2026-11-23",
        document_type=None,
        include_proforma=False,
        export_format="csv",
    )
    assert result.status_code == 200
    assert result.headers["X-Export-Format"] == "csv"
    assert len(seen) == 1
    assert seen[0]["currency_id"] == 3
    assert seen[0]["business_id"] == 10
    assert seen[0]["disable_pagination"] is True
