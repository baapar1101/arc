"""تست ثبت بهای تمام‌شده فروش در دفتر کل (invoice_cogs_gl_service)."""
from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from app.services.invoice_cogs_gl_service import (
    COGS_GL_SIDE,
    INVENTORY_COGS_GL_SIDE,
    _amounts_close,
    _evaluate_should_have_cogs_gl,
    _existing_cogs_gl_amount,
    _is_cogs_gl_line,
    _total_cost_from_profit_data,
    _recognized_ledger_cogs_total_from_document,
    resync_invoice_cogs_gl_lines,
)
from app.services.invoice_profit_ledger_service import (
    LEDGER_BASIS_SALES_INVOICE_DOCUMENT,
    LEDGER_BASIS_WAREHOUSE_DOCUMENT_POSTING,
)


def _line(side: str, debit: float = 0.0, credit: float = 0.0) -> SimpleNamespace:
    return SimpleNamespace(
        debit=debit,
        credit=credit,
        extra_info={"side": side, "source": "invoice_cogs_gl"},
    )


class TestCogsGlLineHelpers:
    def test_is_cogs_gl_line(self):
        assert _is_cogs_gl_line(_line(COGS_GL_SIDE, debit=100))
        assert _is_cogs_gl_line(_line(INVENTORY_COGS_GL_SIDE, credit=100))
        assert not _is_cogs_gl_line(SimpleNamespace(extra_info={"side": "person"}))

    def test_existing_cogs_gl_amount_from_debit(self):
        lines = [
            _line(COGS_GL_SIDE, debit=1500),
            _line(INVENTORY_COGS_GL_SIDE, credit=1500),
            SimpleNamespace(debit=100, credit=0, extra_info={"side": "revenue"}),
        ]
        assert _existing_cogs_gl_amount(lines) == Decimal("1500")

    def test_amounts_close_tolerance(self):
        assert _amounts_close(Decimal("100"), Decimal("100.005"))
        assert not _amounts_close(Decimal("100"), Decimal("100.02"))


class TestEvaluateShouldHaveCogsGl:
    def test_proforma_never(self):
        db = MagicMock()
        doc = SimpleNamespace(
            is_proforma=True,
            document_type="invoice_sales",
            business_id=1,
            id=10,
        )
        assert _evaluate_should_have_cogs_gl(db, doc) is False

    def test_sales_basis_non_proforma(self):
        db = MagicMock()
        biz = SimpleNamespace(invoice_profit_ledger_recognition_basis=LEDGER_BASIS_SALES_INVOICE_DOCUMENT)
        db.query.return_value.filter.return_value.first.return_value = biz
        doc = SimpleNamespace(
            is_proforma=False,
            document_type="invoice_sales",
            business_id=1,
            id=10,
        )
        assert _evaluate_should_have_cogs_gl(db, doc) is True

    @patch("app.services.invoice_cogs_gl_service.document_has_any_posted_warehouse")
    def test_warehouse_basis_requires_posted_warehouse(self, mock_wh):
        db = MagicMock()
        biz = SimpleNamespace(invoice_profit_ledger_recognition_basis=LEDGER_BASIS_WAREHOUSE_DOCUMENT_POSTING)
        db.query.return_value.filter.return_value.first.return_value = biz
        doc = SimpleNamespace(
            is_proforma=False,
            document_type="invoice_sales",
            business_id=1,
            id=10,
        )
        mock_wh.return_value = False
        assert _evaluate_should_have_cogs_gl(db, doc) is False
        mock_wh.return_value = True
        assert _evaluate_should_have_cogs_gl(db, doc) is True


    @patch("app.services.invoice_cogs_gl_service.document_has_any_posted_warehouse")
    def test_warehouse_basis_without_post_inventory_falls_back_to_invoice(self, mock_wh):
        db = MagicMock()
        biz = SimpleNamespace(invoice_profit_ledger_recognition_basis=LEDGER_BASIS_WAREHOUSE_DOCUMENT_POSTING)
        db.query.return_value.filter.return_value.first.return_value = biz
        doc = SimpleNamespace(
            is_proforma=False,
            document_type="invoice_sales",
            business_id=1,
            id=10,
            extra_info={"post_inventory": False},
        )
        mock_wh.return_value = False
        assert _evaluate_should_have_cogs_gl(db, doc) is True


class TestResyncInvoiceCogsGlLines:
    @patch("app.services.invoice_cogs_gl_service._post_cogs_gl_lines")
    @patch("app.services.invoice_cogs_gl_service._resolve_cogs_gl_accounts")
    @patch("app.services.invoice_cogs_gl_service._calculate_invoice_cogs_amount_for_gl")
    @patch("app.services.invoice_cogs_gl_service._evaluate_should_have_cogs_gl")
    @patch("app.services.invoice_cogs_gl_service.remove_invoice_cogs_gl_lines")
    def test_posts_cogs_when_amount_positive(
        self,
        mock_remove,
        mock_should,
        mock_calc,
        mock_resolve,
        mock_post,
    ):
        db = MagicMock()
        document = SimpleNamespace(
            id=42,
            business_id=1,
            document_type="invoice_sales",
            is_proforma=False,
            extra_info={},
        )
        cogs_line = _line(COGS_GL_SIDE, debit=0)
        db.query.return_value.filter.return_value.all.side_effect = [
            [cogs_line],
            [],
        ]
        db.query.return_value.filter.return_value.first.return_value = document

        mock_should.return_value = True
        mock_calc.return_value = Decimal("250000")
        mock_resolve.return_value = (
            SimpleNamespace(id=1, code="40001"),
            SimpleNamespace(id=2, code="10102"),
        )

        assert resync_invoice_cogs_gl_lines(db, 42) is True
        mock_remove.assert_called_once_with(db, 42)
        mock_post.assert_called_once()
        posted_amount = mock_post.call_args[0][2]
        assert posted_amount == Decimal("250000")

    @patch("app.services.invoice_cogs_gl_service._calculate_invoice_cogs_amount_for_gl")
    @patch("app.services.invoice_cogs_gl_service._evaluate_should_have_cogs_gl")
    @patch("app.services.invoice_cogs_gl_service.remove_invoice_cogs_gl_lines")
    def test_removes_cogs_when_should_not_have(
        self,
        mock_remove,
        mock_should,
        mock_calc,
    ):
        db = MagicMock()
        document = SimpleNamespace(
            id=7,
            business_id=1,
            document_type="invoice_sales",
            is_proforma=False,
            extra_info={},
        )
        existing = _line(COGS_GL_SIDE, debit=500)
        db.query.return_value.filter.return_value.all.return_value = [existing]
        db.query.return_value.filter.return_value.first.return_value = document

        mock_should.return_value = False

        assert resync_invoice_cogs_gl_lines(db, 7) is False
        mock_remove.assert_called_once_with(db, 7)
        mock_calc.assert_not_called()

    @patch("app.services.invoice_cogs_gl_service._post_cogs_gl_lines")
    @patch("app.services.invoice_cogs_gl_service._resolve_cogs_gl_accounts")
    @patch("app.services.invoice_cogs_gl_service._calculate_invoice_cogs_amount_for_gl")
    @patch("app.services.invoice_cogs_gl_service._evaluate_should_have_cogs_gl")
    @patch("app.services.invoice_cogs_gl_service.remove_invoice_cogs_gl_lines")
    def test_skips_repost_when_amount_unchanged(
        self,
        mock_remove,
        mock_should,
        mock_calc,
        mock_resolve,
        mock_post,
    ):
        db = MagicMock()
        document = SimpleNamespace(
            id=99,
            business_id=1,
            document_type="invoice_sales",
            is_proforma=False,
            extra_info={},
        )
        existing = _line(COGS_GL_SIDE, debit=1000)
        db.query.return_value.filter.return_value.all.return_value = [existing]
        db.query.return_value.filter.return_value.first.return_value = document

        mock_should.return_value = True
        mock_calc.return_value = Decimal("1000")

        assert resync_invoice_cogs_gl_lines(db, 99) is True
        mock_remove.assert_not_called()
        mock_post.assert_not_called()


class TestTotalCostFromProfitData:
    def test_reads_top_level_total_cost(self):
        data = {"total_cost": 1500000.0, "line_profits": [{"total_cost": 500000.0}]}
        assert _total_cost_from_profit_data(data) == Decimal("1500000")

    def test_falls_back_to_line_profits_sum(self):
        data = {
            "line_profits": [
                {"total_cost": 1000000.0},
                {"total_cost": 250000.5},
            ]
        }
        assert _total_cost_from_profit_data(data) == Decimal("1250000.5")

    def test_negative_total_cost_becomes_absolute(self):
        data = {"total_cost": -800000.0, "line_profits": []}
        assert _total_cost_from_profit_data(data) == Decimal("800000")

    def test_empty_profit_data_returns_zero(self):
        assert _total_cost_from_profit_data({}) == Decimal(0)


class TestRecognizedLedgerCogsTotal:
    def test_sums_recognized_lines_only(self):
        db = MagicMock()
        rows = [
            SimpleNamespace(
                ledger_recognized_at="2026-01-01",
                ledger_line_cogs=Decimal("1000"),
            ),
            SimpleNamespace(
                ledger_recognized_at=None,
                ledger_line_cogs=Decimal("500"),
            ),
            SimpleNamespace(
                ledger_recognized_at="2026-01-01",
                ledger_line_cogs=Decimal("-250"),
            ),
        ]
        db.query.return_value.filter.return_value.all.return_value = rows
        assert _recognized_ledger_cogs_total_from_document(db, 99) == Decimal("1250")
