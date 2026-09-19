"""تست پروفایل کاتالوگ شبکهٔ تأمین."""

import pytest

from app.core.responses import ApiError
from app.services.product_catalog_profile_service import (
    catalog_profile_from_product,
    normalize_catalog_specifications,
)


def test_normalize_catalog_specifications_sort_and_trim():
    raw = [
        {"label": "  وزن ", "value": " 2kg ", "sort_order": 2},
        {"label": "جنس", "value": "فولاد", "field_id": 5, "sort_order": 1},
        {"label": "", "value": "ignored"},
    ]
    out = normalize_catalog_specifications(raw)
    assert out is not None
    assert len(out) == 2
    assert out[0]["label"] == "جنس"
    assert out[0]["field_id"] == 5
    assert out[1]["value"] == "2kg"


def test_normalize_catalog_specifications_invalid_type():
    with pytest.raises(ApiError) as exc:
        normalize_catalog_specifications({"bad": True})
    assert exc.value.code == "INVALID_CATALOG_SPECIFICATIONS"


class _FakeProduct:
    catalog_short_description = "خلاصه"
    catalog_expert_review = "بررسی"
    catalog_specifications = [{"label": "A", "value": "B", "sort_order": 0}]
    catalog_brand = "برند"
    catalog_model = "مدل"
    catalog_country_of_origin = "ایران"
    catalog_video_url = "https://example.com/v"


def test_catalog_profile_from_product():
    profile = catalog_profile_from_product(_FakeProduct())
    assert profile["catalog_short_description"] == "خلاصه"
    assert profile["catalog_specifications"][0]["label"] == "A"
    assert profile["catalog_video_url"].startswith("https://")


def test_normalize_catalog_gallery_file_ids():
    from app.services.product_catalog_profile_service import normalize_catalog_gallery_file_ids

    out = normalize_catalog_gallery_file_ids(["a", "b", "a"])
    assert out == ["a", "b"]
