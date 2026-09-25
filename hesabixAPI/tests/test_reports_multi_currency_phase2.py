"""تست‌های قرارداد چندارزی گزارشات (بدون نیاز به DB واقعی)."""
from datetime import date
from decimal import Decimal

from app.services.ar_ap_aging_service import (
    _age_open_items,
    _bucket_key,
    _fifo_open_credits,
    _fifo_open_debits,
)
from app.services.cash_flow_classification import classify_cfs_section


def test_aging_bucket_boundaries():
    assert _bucket_key(0) == "0_30"
    assert _bucket_key(30) == "0_30"
    assert _bucket_key(31) == "31_60"
    assert _bucket_key(90) == "61_90"
    assert _bucket_key(91) == "91_120"
    assert _bucket_key(200) == "120_plus"


def test_fifo_open_debits_ages_oldest_first():
    # دو فاکتور بدهکار + یک دریافت که اولی را تسویه می‌کند
    events = [
        (date(2024, 1, 1), Decimal("100"), Decimal("0")),
        (date(2024, 2, 1), Decimal("50"), Decimal("0")),
        (date(2024, 3, 1), Decimal("0"), Decimal("100")),
    ]
    open_items = _fifo_open_debits(events)
    assert len(open_items) == 1
    assert open_items[0][0] == date(2024, 2, 1)
    assert open_items[0][1] == Decimal("50")
    buckets = _age_open_items(open_items, as_of=date(2024, 3, 15))
    assert buckets["31_60"] == Decimal("50")
    assert sum(buckets.values()) == Decimal("50")


def test_fifo_open_credits_for_ap():
    events = [
        (date(2024, 1, 1), Decimal("0"), Decimal("200")),
        (date(2024, 2, 1), Decimal("50"), Decimal("0")),
    ]
    open_items = _fifo_open_credits(events)
    assert len(open_items) == 1
    assert open_items[0][1] == Decimal("150")


def test_cfs_classification_investing_financing_transfer_fx():
    assert (
        classify_cfs_section(
            document_type="manual_document",
            is_fx_revaluation=True,
            counterpart_account_codes=["10701"],
            counterpart_is_only_cash=False,
        )
        == "fx_and_other"
    )
    assert (
        classify_cfs_section(
            document_type="payment",
            is_fx_revaluation=False,
            counterpart_account_codes=["10703"],
            counterpart_is_only_cash=False,
        )
        == "investing"
    )
    assert (
        classify_cfs_section(
            document_type="receipt",
            is_fx_revaluation=False,
            counterpart_account_codes=["20501"],
            counterpart_is_only_cash=False,
        )
        == "financing"
    )
    assert (
        classify_cfs_section(
            document_type="transfer",
            is_fx_revaluation=False,
            counterpart_account_codes=[],
            counterpart_is_only_cash=True,
        )
        == "transfers"
    )
    assert (
        classify_cfs_section(
            document_type="receipt",
            is_fx_revaluation=False,
            counterpart_account_codes=["10401"],
            counterpart_is_only_cash=False,
        )
        == "operating"
    )


def test_invoice_amount_for_aggregate_contract_in_source():
    """قرارداد: با currency_id بدون تبدیل؛ بدون آن فراخوانی to_base."""
    from pathlib import Path

    src = Path("/opt/hesabix/app/hesabixAPI/app/services/invoice_service.py").read_text(
        encoding="utf-8"
    )
    assert "def _invoice_amount_for_aggregate(" in src
    assert "if currency_id is not None:" in src
    assert "amount_in_document_currency_to_base" in src


def test_trial_balance_supports_include_base_equivalent_param():
    import inspect
    from app.services.trial_balance_service import get_trial_balance_report

    sig = inspect.signature(get_trial_balance_report)
    assert "include_base_equivalent" in sig.parameters


def test_pnl_supports_include_base_equivalent_param():
    import inspect
    from app.services.pnl_service import get_pnl_period_report

    sig = inspect.signature(get_pnl_period_report)
    assert "include_base_equivalent" in sig.parameters
