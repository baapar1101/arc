"""تست شناسایی کاندید پاک‌سازی کسب‌وکار یتیم بکاپ."""
from __future__ import annotations

from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch

from app.services.business_backup_orphan_cleanup_service import (
    DEFAULT_NAME_SUBSTRING,
    _name_matches_backup_import,
    find_orphan_backup_business_candidates,
)


def test_name_matches_restore_suffix():
    assert _name_matches_backup_import("فروشگاه من (بازیابی شده)", DEFAULT_NAME_SUBSTRING)


def test_find_candidates_skips_successful_import_log():
    biz_orphan = MagicMock()
    biz_orphan.id = 10
    biz_orphan.name = "تست (بازیابی شده)"
    biz_orphan.owner_id = 1
    biz_orphan.created_at = datetime.utcnow() - timedelta(hours=5)
    biz_orphan.deleted_at = None

    db = MagicMock()
    db.query.return_value.filter.return_value.distinct.return_value.all.return_value = [(99,)]
    db.query.return_value.filter.return_value.order_by.return_value.all.return_value = [biz_orphan]

    with patch(
        "app.services.business_backup_orphan_cleanup_service._tenant_row_counts",
        return_value={"documents": 0, "persons": 0, "products": 0},
    ):
        found = find_orphan_backup_business_candidates(
            db,
            {
                "require_not_in_import_log": True,
                "require_backup_name_marker": True,
                "include_empty_shell": False,
                "min_age_hours": 1,
            },
        )
    assert len(found) == 1
    assert found[0]["business_id"] == 10
    assert "not_in_successful_import_log" in found[0]["reasons"]
