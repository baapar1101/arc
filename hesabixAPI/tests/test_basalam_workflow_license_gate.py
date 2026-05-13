"""ورک‌فلو و سرویس باسلام بدون لایسنس فعال نباید تریگر/تنظیمات را اجرا کنند."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from app.core.responses import ApiError
from app.services.workflow.triggers.basalam_triggers import BasalamOrderCreatedTrigger
from app.services.workflow.workflow_trigger_service import _trigger_workflows_inner


def test_trigger_workflows_inner_skips_basalam_when_plugin_inactive() -> None:
    db = MagicMock()
    with patch(
        "app.core.basalam_plugin_dependency.check_basalam_plugin_active",
        return_value=False,
    ):
        n = _trigger_workflows_inner(
            db,
            business_id=1,
            trigger_type="basalam.order.created",
            trigger_data={"order_id": "x"},
            user_id=None,
        )
    assert n == 0
    db.execute.assert_not_called()


def test_basalam_trigger_execute_returns_empty_when_plugin_inactive() -> None:
    db = MagicMock()
    with patch(
        "app.core.basalam_plugin_dependency.check_basalam_plugin_active",
        return_value=False,
    ):
        out = BasalamOrderCreatedTrigger().execute(
            {
                "business_id": 5,
                "db": db,
                "trigger_data": {"event_type": "order.created", "order_id": "1"},
                "__workflow_trigger_preview__": True,
            },
            {"enabled": True},
        )
    assert out == {}


def test_get_settings_raises_when_plugin_inactive() -> None:
    from app.services import basalam_integration_service as bas

    row = MagicMock()
    row.extra_info = "{}"

    db = MagicMock()
    with (
        patch.object(bas, "_find_business_plugin", return_value=row),
        patch(
            "app.services.basalam_integration_service.check_basalam_plugin_active",
            return_value=False,
        ),
    ):
        with pytest.raises(ApiError) as ei:
            bas.get_settings(db, 1)
    err = ei.value.detail.get("error") or {}
    assert err.get("code") == "BASALAM_PLUGIN_NOT_ACTIVE"
