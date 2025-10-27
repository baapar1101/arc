from __future__ import annotations

from typing import Dict, Any, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_

from app.core.responses import ApiError
from adapters.db.models.warehouse import Warehouse
from adapters.db.repositories.warehouse_repository import WarehouseRepository
from adapters.api.v1.schema_models.warehouse import WarehouseCreateRequest, WarehouseUpdateRequest


def _to_dict(obj: Warehouse) -> Dict[str, Any]:
    return {
        "id": obj.id,
        "business_id": obj.business_id,
        "code": obj.code,
        "name": obj.name,
        "description": obj.description,
        "is_default": obj.is_default,
        "created_at": obj.created_at,
        "updated_at": obj.updated_at,
    }


def create_warehouse(db: Session, business_id: int, payload: WarehouseCreateRequest) -> Dict[str, Any]:
    code = payload.code.strip()
    dup = db.query(Warehouse).filter(and_(Warehouse.business_id == business_id, Warehouse.code == code)).first()
    if dup:
        raise ApiError("DUPLICATE_WAREHOUSE_CODE", "کد انبار تکراری است", http_status=400)
    repo = WarehouseRepository(db)
    obj = repo.create(
        business_id=business_id,
        code=code,
        name=payload.name.strip(),
        description=payload.description,
        is_default=bool(payload.is_default),
    )
    if obj.is_default:
        db.query(Warehouse).filter(and_(Warehouse.business_id == business_id, Warehouse.id != obj.id)).update({Warehouse.is_default: False})
        db.commit()
    return {"message": "WAREHOUSE_CREATED", "data": _to_dict(obj)}


def list_warehouses(db: Session, business_id: int) -> Dict[str, Any]:
    repo = WarehouseRepository(db)
    rows = repo.list(business_id)
    return {"items": [_to_dict(w) for w in rows]}


def get_warehouse(db: Session, business_id: int, warehouse_id: int) -> Optional[Dict[str, Any]]:
    obj = db.get(Warehouse, warehouse_id)
    if not obj or obj.business_id != business_id:
        return None
    return _to_dict(obj)


def update_warehouse(db: Session, business_id: int, warehouse_id: int, payload: WarehouseUpdateRequest) -> Optional[Dict[str, Any]]:
    repo = WarehouseRepository(db)
    obj = db.get(Warehouse, warehouse_id)
    if not obj or obj.business_id != business_id:
        return None
    if payload.code and payload.code.strip() != obj.code:
        dup = db.query(Warehouse).filter(and_(Warehouse.business_id == business_id, Warehouse.code == payload.code.strip(), Warehouse.id != warehouse_id)).first()
        if dup:
            raise ApiError("DUPLICATE_WAREHOUSE_CODE", "کد انبار تکراری است", http_status=400)

    updated = repo.update(
        warehouse_id,
        code=payload.code.strip() if isinstance(payload.code, str) else None,
        name=payload.name.strip() if isinstance(payload.name, str) else None,
        description=payload.description,
        is_default=payload.is_default if payload.is_default is not None else None,
    )
    if not updated:
        return None
    if updated.is_default:
        db.query(Warehouse).filter(and_(Warehouse.business_id == business_id, Warehouse.id != updated.id)).update({Warehouse.is_default: False})
        db.commit()
    return {"message": "WAREHOUSE_UPDATED", "data": _to_dict(updated)}


def delete_warehouse(db: Session, business_id: int, warehouse_id: int) -> bool:
    obj = db.get(Warehouse, warehouse_id)
    if not obj or obj.business_id != business_id:
        return False
    repo = WarehouseRepository(db)
    return repo.delete(warehouse_id)


