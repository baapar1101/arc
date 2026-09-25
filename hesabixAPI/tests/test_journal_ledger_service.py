from __future__ import annotations

from app.services.journal_ledger_service import (
    _compute_branch_max_depths,
    _find_detail_account,
    _find_general_account,
    _find_subsidiary_account,
)


def _four_level_accounts_map() -> dict:
    """نمودار استاندارد ۴ سطحی: گروه / کل / معین / تفصیل."""
    return {
        1: {"id": 1, "code": "1", "name": "دارایی ها", "parent_id": None},
        2: {"id": 2, "code": "101", "name": "دارایی های جاری", "parent_id": 1},
        3: {"id": 3, "code": "102", "name": "موجودی نقد و بانک", "parent_id": 2},
        4: {"id": 4, "code": "10201", "name": "تنخواه گردان", "parent_id": 3},
        5: {"id": 5, "code": "41", "name": "فروش", "parent_id": 1},
    }


def _three_level_accounts_map() -> dict:
    """نمودار ۳ سطحی بدون گروه: کل / معین / تفصیل."""
    return {
        1: {"id": 1, "code": "11", "name": "موجودی نقد", "parent_id": None},
        2: {"id": 2, "code": "1101", "name": "صندوق", "parent_id": 1},
        3: {"id": 3, "code": "110101", "name": "صندوق مرکزی", "parent_id": 2},
        4: {"id": 4, "code": "41", "name": "فروش", "parent_id": None},
    }


class TestFourLevelChart:
    def setup_method(self) -> None:
        self.accounts = _four_level_accounts_map()
        self.branch_max_depths = _compute_branch_max_depths(self.accounts)

    def test_detail_account_resolves_general_and_subsidiary(self) -> None:
        general = _find_general_account(4, self.accounts, self.branch_max_depths)
        subsidiary = _find_subsidiary_account(4, self.accounts, general, self.branch_max_depths)
        detail = _find_detail_account(4, self.accounts, subsidiary, self.branch_max_depths)

        assert general is not None
        assert general["code"] == "101"
        assert subsidiary is not None
        assert subsidiary["code"] == "102"
        assert detail is not None
        assert detail["code"] == "10201"

    def test_subsidiary_level_account(self) -> None:
        general = _find_general_account(3, self.accounts, self.branch_max_depths)
        subsidiary = _find_subsidiary_account(3, self.accounts, general, self.branch_max_depths)
        detail = _find_detail_account(3, self.accounts, subsidiary, self.branch_max_depths)

        assert general is not None
        assert general["code"] == "101"
        assert subsidiary is not None
        assert subsidiary["code"] == "102"
        assert detail is None

    def test_general_level_account(self) -> None:
        general = _find_general_account(2, self.accounts, self.branch_max_depths)
        subsidiary = _find_subsidiary_account(2, self.accounts, general, self.branch_max_depths)

        assert general is not None
        assert general["code"] == "101"
        assert subsidiary is None

    def test_group_level_account_has_no_general(self) -> None:
        assert _find_general_account(1, self.accounts, self.branch_max_depths) is None
        assert _find_subsidiary_account(1, self.accounts, None, self.branch_max_depths) is None

    def test_does_not_show_group_as_general(self) -> None:
        general = _find_general_account(4, self.accounts, self.branch_max_depths)
        assert general is not None
        assert general["code"] != "1"


class TestThreeLevelChart:
    def setup_method(self) -> None:
        self.accounts = _three_level_accounts_map()
        self.branch_max_depths = _compute_branch_max_depths(self.accounts)

    def test_detail_account_below_subsidiary(self) -> None:
        subsidiary = _find_subsidiary_account(3, self.accounts, None, self.branch_max_depths)
        detail = _find_detail_account(3, self.accounts, subsidiary, self.branch_max_depths)

        assert _find_general_account(3, self.accounts, self.branch_max_depths)["code"] == "11"
        assert subsidiary is not None
        assert subsidiary["code"] == "1101"
        assert detail is not None
        assert detail["code"] == "110101"

    def test_subsidiary_level_account(self) -> None:
        general = _find_general_account(2, self.accounts, self.branch_max_depths)
        subsidiary = _find_subsidiary_account(2, self.accounts, general, self.branch_max_depths)
        detail = _find_detail_account(2, self.accounts, subsidiary, self.branch_max_depths)

        assert general["code"] == "11"
        assert subsidiary["code"] == "1101"
        assert detail is None

    def test_general_level_account(self) -> None:
        general = _find_general_account(1, self.accounts, self.branch_max_depths)
        subsidiary = _find_subsidiary_account(1, self.accounts, general, self.branch_max_depths)

        assert general["code"] == "11"
        assert subsidiary is None
