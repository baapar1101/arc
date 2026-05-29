from __future__ import annotations

import contextvars

_legacy_import_active: contextvars.ContextVar[bool] = contextvars.ContextVar(
    "legacy_import_active",
    default=False,
)


def set_legacy_import_active(active: bool) -> contextvars.Token:
    return _legacy_import_active.set(active)


def reset_legacy_import_active(token: contextvars.Token) -> None:
    _legacy_import_active.reset(token)


def is_legacy_import_active() -> bool:
    return bool(_legacy_import_active.get())
