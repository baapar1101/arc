"""
قرارداد سبک با basalam.json در ریشهٔ مخزن: مسیرهای HTTP که یکپارچه‌سازی مستقیم فراخوانی می‌کند.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

# از hesabixAPI/tests دو سطح بالاتر = ریشهٔ workspace (آنجا basalam.json قرار دارد)
_REPO_ROOT = Path(__file__).resolve().parents[2]
_OPENAPI_PATH = _REPO_ROOT / "basalam.json"

# (method_upper, path_template) — همان الگوی کلید paths در OpenAPI
_REQUIRED_OPERATIONS: list[tuple[str, str]] = [
    ("GET", "/v1/products"),
    ("POST", "/v1/chats/{chat_id}/messages"),
    ("GET", "/v1/pay/transactions/unverified"),
    ("POST", "/v1/pay/transactions/{hash_id}/verify"),
]


@pytest.fixture(scope="module")
def openapi_spec() -> dict:
    if not _OPENAPI_PATH.is_file():
        pytest.skip(f"OpenAPI bundle not found: {_OPENAPI_PATH}")
    with _OPENAPI_PATH.open(encoding="utf-8") as f:
        return json.load(f)


def test_openapi_bundle_version(openapi_spec: dict) -> None:
    assert openapi_spec.get("openapi"), "expected openapi version field"
    info = openapi_spec.get("info") or {}
    assert info.get("title"), "expected info.title"


@pytest.mark.parametrize("method,path_tpl", _REQUIRED_OPERATIONS)
def test_required_paths_and_methods_exist(openapi_spec: dict, method: str, path_tpl: str) -> None:
    paths = openapi_spec.get("paths") or {}
    assert path_tpl in paths, f"missing path {path_tpl}"
    methods_block = paths[path_tpl]
    assert isinstance(methods_block, dict), f"path {path_tpl} must be an object"
    assert method.lower() in methods_block, f"missing {method} on {path_tpl}"
