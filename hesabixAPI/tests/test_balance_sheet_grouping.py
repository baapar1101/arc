"""تست گروه‌بندی و جمع‌بندی گزارش ترازنامه."""
from __future__ import annotations

from decimal import Decimal

from app.services.balance_sheet_service import (
    _group_nodes_by_subsection,
    _sum_section_amount,
)


def _node(code: str, subsection: str | None, amount: float, children: list | None = None) -> dict:
    return {
        "account_code": code,
        "subsection": subsection,
        "amount": amount,
        "children": children or [],
    }


class TestBalanceSheetGrouping:
    def test_distributes_asset_children_from_root(self):
        tree = [
            _node(
                "1",
                None,
                1_000_000,
                [
                    _node("101", "current_assets", 600_000, [_node("10101", "current_assets", 100_000)]),
                    _node("102", "current_assets", 300_000, [_node("10203", "current_assets", 250_000)]),
                    _node("106", "non_current_assets", 100_000),
                ],
            ),
            _node("2", None, 400_000, [_node("201", "current_liabilities", 400_000)]),
            _node("3", "equity", 600_000, [_node("301", "equity", 600_000)]),
        ]

        grouped = _group_nodes_by_subsection(tree)

        assert len(grouped["current_assets"]) == 2
        assert grouped["current_assets"][0]["account_code"] == "101"
        assert grouped["current_assets"][1]["account_code"] == "102"
        assert len(grouped["non_current_assets"]) == 1
        assert grouped["non_current_assets"][0]["account_code"] == "106"
        assert len(grouped["current_liabilities"]) == 1
        assert grouped["current_liabilities"][0]["account_code"] == "201"
        assert len(grouped["equity"]) == 1
        assert grouped["equity"][0]["account_code"] == "3"

    def test_section_totals_do_not_double_count_children(self):
        items = [
            _node("102", "current_assets", 300_000, [_node("10203", "current_assets", 250_000)]),
            _node("101", "current_assets", 600_000),
        ]
        total = _sum_section_amount(items)
        assert total == Decimal("900000")

    def test_empty_tree_returns_empty_sections(self):
        grouped = _group_nodes_by_subsection([])
        assert all(len(v) == 0 for v in grouped.values())
