from datetime import timedelta

import pytest

from app.services.invoice_service import _compute_available_stock
from app.services.opening_balance_warehouse_sync_service import (
    sync_opening_balance_warehouse_documents as synchronize,
)
from app.services.variant_inventory_service import compute_available_variant_stock
from tests.test_opening_variant_sync import DAY, payload, save
from tests.test_opening_variant_sync import opening_db as opening_db
from tests.test_warehouse_transfer_currency import transfer_db as transfer_db


@pytest.mark.parametrize("unit", ["main", "each"])
def test_opening_is_counted_once_before_and_after_warehouse_mirror(opening_db, unit):
    db = opening_db
    did = save(db, payload(unit=unit))
    for mirrored in (False, True):
        if mirrored:
            synchronize(db, 1, 1, did, [1])
            db.commit()
        quantities = [compute_available_variant_stock(db, 1, 1, 11, vid, DAY) for vid in (1, 2)]
        assert quantities == [8, 12]
        assert _compute_available_stock(db, 1, 1, 11, DAY) == sum(quantities) == 20
        assert compute_available_variant_stock(db, 1, 1, 12, 1, DAY) == 0
        assert compute_available_variant_stock(db, 2, 1, 11, 1, DAY) == 0
        assert compute_available_variant_stock(db, 1, 1, 11, 1, DAY - timedelta(days=1)) == 0
        assert compute_available_variant_stock(db, 1, 1, 11, 1, DAY, exclude_document_id=did) == 0
