from collections.abc import Iterable
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from adapters.db.models.warehouse import Warehouse
from app.core.responses import ApiError
from app.services.invoice_unit_conversion_service import extra_info_dict


def _warehouse_not_found() -> ApiError:
    return ApiError("WAREHOUSE_NOT_FOUND", "انبار انتخاب‌شده یافت نشد", http_status=404)


def require_owned_warehouses(db: Session, business_id: int, references: Iterable[Any]) -> None:
    """Validate optional warehouse references against the document's business in one query."""
    warehouse_ids: set[int] = set()
    for value in references:
        if value is None or value == "":
            continue
        try:
            warehouse_id = int(value)
        except (TypeError, ValueError, OverflowError) as exc:
            raise _warehouse_not_found() from exc
        if (
            isinstance(value, bool)
            or warehouse_id <= 0
            or (not isinstance(value, str) and value != warehouse_id)
        ):
            raise _warehouse_not_found()
        warehouse_ids.add(warehouse_id)

    if warehouse_ids:
        owned_ids = db.scalars(
            select(Warehouse.id).where(
                Warehouse.business_id == business_id, Warehouse.id.in_(warehouse_ids)
            )
        )
        if warehouse_ids != set(owned_ids):
            raise _warehouse_not_found()


def validate_invoice_warehouse_ownership(
    db: Session, business_id: int, header: Any, lines: Iterable[dict[str, Any]]
) -> None:
    references = [extra_info_dict(header).get("warehouse_id")]
    for line in lines:
        references.extend(
            (line.get("warehouse_id"), extra_info_dict(line.get("extra_info")).get("warehouse_id"))
        )
    require_owned_warehouses(db, business_id, references)
