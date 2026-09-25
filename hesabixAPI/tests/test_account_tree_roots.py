"""تست ریشه‌های درخت حساب در فیلترهای جزئی."""
from __future__ import annotations

from app.services.account_balance_core import get_root_account_ids


class TestGetRootAccountIds:
    def test_orphan_account_becomes_root_when_parent_filtered_out(self):
        tree = {
            1: {"id": 1, "code": "10203", "parent_id": 99, "children": []},
            2: {"id": 2, "code": "1", "parent_id": None, "children": [3]},
            3: {"id": 3, "code": "101", "parent_id": 2, "children": []},
        }
        roots = get_root_account_ids(tree)
        assert sorted(roots) == [1, 2]

    def test_only_true_roots_when_full_tree(self):
        tree = {
            1: {"id": 1, "code": "1", "parent_id": None, "children": [2]},
            2: {"id": 2, "code": "101", "parent_id": 1, "children": []},
        }
        assert get_root_account_ids(tree) == [1]
