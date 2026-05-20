import pytest

from app.services.public_catalog_utils import normalize_catalog_public_uuid


def test_normalize_catalog_public_uuid_standard():
	u = normalize_catalog_public_uuid("  550e8400-e29b-41d4-a716-446655440000  ")
	assert u == "550e8400-e29b-41d4-a716-446655440000"


def test_normalize_catalog_public_uuid_invalid():
	with pytest.raises(ValueError):
		normalize_catalog_public_uuid("")
	with pytest.raises(ValueError):
		normalize_catalog_public_uuid("not-a-uuid")
