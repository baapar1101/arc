"""سیاست حالت اجرا — تأیید نوشتن در خودکار فقط برای عملیات پرریسک."""
from __future__ import annotations

from app.services.ai.ai_execution_policy import (
    EXECUTION_MODE_AUTONOMOUS,
    EXECUTION_MODE_SUPERVISED,
    is_high_risk_write,
    should_require_write_approval,
)


class _Fn:
    def __init__(self, risk_level: str = "medium", requires_approval: bool = True):
        self.risk_level = risk_level
        self.requires_approval = requires_approval
        self.is_readonly = False


class _Reg:
    def __init__(self, fns):
        self._fns = fns

    def get_function(self, name):
        return self._fns.get(name)


def test_autonomous_skips_approval_for_medium_create_invoice():
    reg = _Reg({"create_invoice": _Fn("medium")})
    assert not is_high_risk_write("create_invoice", reg)
    assert not should_require_write_approval(
        EXECUTION_MODE_AUTONOMOUS,
        "create_invoice",
        approve_writes=False,
        registry=reg,
    )


def test_supervised_still_requires_approval_for_create_invoice():
    reg = _Reg({"create_invoice": _Fn("medium")})
    assert should_require_write_approval(
        EXECUTION_MODE_SUPERVISED,
        "create_invoice",
        approve_writes=False,
        registry=reg,
    )
    assert not should_require_write_approval(
        EXECUTION_MODE_SUPERVISED,
        "create_invoice",
        approve_writes=True,
        registry=reg,
    )


def test_autonomous_still_requires_approval_for_high_risk_delete():
    reg = _Reg({"delete_invoice": _Fn("high")})
    assert is_high_risk_write("delete_invoice", reg)
    assert should_require_write_approval(
        EXECUTION_MODE_AUTONOMOUS,
        "delete_invoice",
        approve_writes=False,
        registry=reg,
    )
