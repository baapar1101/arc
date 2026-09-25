"""تست تأمین‌کنندگان کالا."""

import pytest

from app.core.responses import ApiError
from adapters.api.v1.schema_models.product import (
    ProductSupplierInput,
    ProductSupplierSocialContactInput,
)
from app.services.product_supplier_service import _validate_supplier_input


def test_validate_supplier_requires_name_or_person():
    with pytest.raises(ApiError) as exc:
        _validate_supplier_input(ProductSupplierInput(), 0)
    assert exc.value.code == "INVALID_PRODUCT_SUPPLIER"


def test_validate_supplier_accepts_name():
    item = _validate_supplier_input(ProductSupplierInput(name="شرکت الف"), 0)
    assert item.name == "شرکت الف"


def test_validate_supplier_accepts_person_id_only():
    item = _validate_supplier_input(ProductSupplierInput(person_id=5), 0)
    assert item.person_id == 5


def test_social_contact_other_requires_label():
    with pytest.raises(ValueError):
        ProductSupplierSocialContactInput(platform_key="other", value="@x")
