from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from adapters.api.v1.schema_models.project_workspace import (
    ProjectCycleCarryOverRequest,
)
from app.services.project_service import _carry_over_task_ids


def test_carry_over_selects_only_incomplete_missing_target_tasks() -> None:
    rows = [
        (10, None),
        (11, datetime(2026, 9, 1, tzinfo=timezone.utc)),
        (12, None),
        (13, None),
    ]

    result = _carry_over_task_ids(rows, {12, 99})

    assert result == [10, 13]


def test_carry_over_is_idempotent_for_existing_target_membership() -> None:
    rows = [(21, None), (22, None)]

    assert _carry_over_task_ids(rows, {21, 22}) == []


def test_carry_over_request_requires_positive_target_cycle() -> None:
    assert ProjectCycleCarryOverRequest(target_cycle_id=7).target_cycle_id == 7

    with pytest.raises(ValidationError):
        ProjectCycleCarryOverRequest(target_cycle_id=0)
