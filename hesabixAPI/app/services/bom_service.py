from __future__ import annotations

from typing import Dict, Any, Optional, List
from decimal import Decimal
from sqlalchemy.orm import Session
from sqlalchemy import and_

from app.core.responses import ApiError
from adapters.db.models.product import Product
from adapters.db.models.product_bom import ProductBOM, ProductBOMItem, ProductBOMOutput, ProductBOMOperation
from adapters.db.repositories.product_bom_repository import ProductBOMRepository
from adapters.api.v1.schema_models.product_bom import (
    ProductBOMCreateRequest,
    ProductBOMUpdateRequest,
    BOMExplosionRequest,
    ProductionDraftRequest,
)


def _to_bom_dict(bom: ProductBOM, db: Session) -> Dict[str, Any]:
    items = db.query(ProductBOMItem).filter(ProductBOMItem.bom_id == bom.id).order_by(ProductBOMItem.line_no).all()
    outputs = db.query(ProductBOMOutput).filter(ProductBOMOutput.bom_id == bom.id).order_by(ProductBOMOutput.line_no).all()
    operations = db.query(ProductBOMOperation).filter(ProductBOMOperation.bom_id == bom.id).order_by(ProductBOMOperation.line_no).all()
    return {
        "id": bom.id,
        "business_id": bom.business_id,
        "product_id": bom.product_id,
        "version": bom.version,
        "name": bom.name,
        "is_default": bom.is_default,
        "effective_from": bom.effective_from,
        "effective_to": bom.effective_to,
        "yield_percent": bom.yield_percent,
        "wastage_percent": bom.wastage_percent,
        "status": bom.status,
        "notes": bom.notes,
        "created_at": bom.created_at,
        "updated_at": bom.updated_at,
        "items": [
            {
                "line_no": it.line_no,
                "component_product_id": it.component_product_id,
                "qty_per": it.qty_per,
                "uom": it.uom,
                "wastage_percent": it.wastage_percent,
                "is_optional": it.is_optional,
                "substitute_group": it.substitute_group,
                "suggested_warehouse_id": it.suggested_warehouse_id,
            }
            for it in items
        ],
        "outputs": [
            {
                "line_no": ot.line_no,
                "output_product_id": ot.output_product_id,
                "ratio": ot.ratio,
                "uom": ot.uom,
            }
            for ot in outputs
        ],
        "operations": [
            {
                "line_no": op.line_no,
                "operation_name": op.operation_name,
                "cost_fixed": op.cost_fixed,
                "cost_per_unit": op.cost_per_unit,
                "cost_uom": op.cost_uom,
                "work_center": op.work_center,
            }
            for op in operations
        ],
    }


def create_bom(db: Session, business_id: int, payload: ProductBOMCreateRequest) -> Dict[str, Any]:
    # product must belong to business
    product = db.get(Product, payload.product_id)
    if not product or product.business_id != business_id:
        raise ApiError("INVALID_PRODUCT", "کالای انتخابی معتبر نیست", http_status=400)

    repo = ProductBOMRepository(db)
    bom = repo.create_bom(
        business_id=business_id,
        product_id=payload.product_id,
        version=payload.version.strip(),
        name=payload.name.strip(),
        is_default=bool(payload.is_default),
        effective_from=payload.effective_from,
        effective_to=payload.effective_to,
        yield_percent=payload.yield_percent,
        wastage_percent=payload.wastage_percent,
        status=payload.status,
        notes=payload.notes,
    )

    # Replace child rows
    items = [it.model_dump() for it in payload.items]
    outputs = [ot.model_dump() for ot in payload.outputs]
    operations = [op.model_dump() for op in payload.operations]
    repo.replace_items(bom.id, items)
    repo.replace_outputs(bom.id, outputs)
    repo.replace_operations(bom.id, operations)

    # enforce single default per product
    if bom.is_default:
        db.query(ProductBOM).filter(
            and_(ProductBOM.business_id == business_id, ProductBOM.product_id == payload.product_id, ProductBOM.id != bom.id)
        ).update({ProductBOM.is_default: False})
        db.commit()

    return {"message": "BOM_CREATED", "data": _to_bom_dict(bom, db)}


def get_bom(db: Session, business_id: int, bom_id: int) -> Optional[Dict[str, Any]]:
    repo = ProductBOMRepository(db)
    bom = repo.get_bom(bom_id, business_id)
    if not bom:
        return None
    return _to_bom_dict(bom, db)


def list_boms(db: Session, business_id: int, product_id: Optional[int] = None) -> Dict[str, Any]:
    repo = ProductBOMRepository(db)
    rows = repo.list_boms(business_id, product_id)
    return {"items": [_to_bom_dict(b, db) for b in rows]}


def update_bom(db: Session, business_id: int, bom_id: int, payload: ProductBOMUpdateRequest) -> Optional[Dict[str, Any]]:
    repo = ProductBOMRepository(db)
    bom = repo.get_bom(bom_id, business_id)
    if not bom:
        return None

    updated = repo.update_bom(
        bom_id,
        version=payload.version.strip() if isinstance(payload.version, str) else None,
        name=payload.name.strip() if isinstance(payload.name, str) else None,
        is_default=payload.is_default if payload.is_default is not None else None,
        effective_from=payload.effective_from,
        effective_to=payload.effective_to,
        yield_percent=payload.yield_percent,
        wastage_percent=payload.wastage_percent,
        status=payload.status,
        notes=payload.notes,
    )
    if not updated:
        return None

    if payload.items is not None:
        repo.replace_items(bom_id, [it.model_dump() for it in payload.items])
    if payload.outputs is not None:
        repo.replace_outputs(bom_id, [ot.model_dump() for ot in payload.outputs])
    if payload.operations is not None:
        repo.replace_operations(bom_id, [op.model_dump() for op in payload.operations])

    if updated.is_default:
        db.query(ProductBOM).filter(
            and_(ProductBOM.business_id == business_id, ProductBOM.product_id == updated.product_id, ProductBOM.id != updated.id)
        ).update({ProductBOM.is_default: False})
        db.commit()

    return {"message": "BOM_UPDATED", "data": _to_bom_dict(updated, db)}


def delete_bom(db: Session, business_id: int, bom_id: int) -> bool:
    repo = ProductBOMRepository(db)
    bom = repo.get_bom(bom_id, business_id)
    if not bom:
        return False
    return repo.delete_bom(bom_id)


def explode_bom(db: Session, business_id: int, req: BOMExplosionRequest) -> Dict[str, Any]:
    # minimal explosion without stock checks
    if not req.bom_id and not req.product_id:
        raise ApiError("INVALID_REQUEST", "bom_id یا product_id الزامی است", http_status=400)

    bom: Optional[ProductBOM] = None
    if req.bom_id:
        bom = db.get(ProductBOM, req.bom_id)
        if not bom or bom.business_id != business_id:
            raise ApiError("NOT_FOUND", "BOM یافت نشد", http_status=404)
    else:
        # pick default bom for product
        bom = db.query(ProductBOM).filter(
            and_(ProductBOM.business_id == business_id, ProductBOM.product_id == req.product_id, ProductBOM.is_default == True)
        ).first()
        if not bom:
            raise ApiError("NOT_FOUND", "برای این کالا فرمول پیش‌فرضی تعریف نشده است", http_status=404)

    items = db.query(ProductBOMItem).filter(ProductBOMItem.bom_id == bom.id).order_by(ProductBOMItem.line_no).all()
    outputs = db.query(ProductBOMOutput).filter(ProductBOMOutput.bom_id == bom.id).order_by(ProductBOMOutput.line_no).all()

    # Prepare product lookup for enriching names/units in response
    product_ids: set[int] = set([it.component_product_id for it in items] + [ot.output_product_id for ot in outputs])
    products_by_id: dict[int, Product] = {}
    if product_ids:
        for p in db.query(Product).filter(Product.id.in_(product_ids)).all():
            products_by_id[p.id] = p

    qty = Decimal(str(req.quantity))

    # Apply BOM-level wastage and yield to inputs
    # factor_inputs scales required input quantities. Example: yield 80% => factor 1.25; wastage 5% => factor * 1.05
    factor_inputs = Decimal("1")
    if bom.wastage_percent:
        factor_inputs *= (Decimal("1.0") + Decimal(str(bom.wastage_percent)) / Decimal("100"))
    if bom.yield_percent:
        try:
            y = Decimal(str(bom.yield_percent))
            if y > 0:
                factor_inputs *= (Decimal("100") / y)
        except Exception:
            pass
    explosion_items: List[Dict[str, Any]] = []
    for it in items:
        base = Decimal(str(it.qty_per)) * qty
        # apply line wastage
        if it.wastage_percent:
            base = base * (Decimal("1.0") + Decimal(str(it.wastage_percent)) / Decimal("100"))
        # apply BOM-level factors
        base = base * factor_inputs
        prod = products_by_id.get(it.component_product_id)

        # Unit conversion to main unit (if BOM line uom equals secondary and factor exists)
        required_qty_main_unit = None
        main_unit = getattr(prod, "main_unit", None) if prod else None
        secondary_unit = getattr(prod, "secondary_unit", None) if prod else None
        unit_factor = getattr(prod, "unit_conversion_factor", None) if prod else None
        if it.uom and prod and secondary_unit and main_unit and unit_factor is not None:
            try:
                # When line uom is secondary, convert to main by multiplying factor
                if str(it.uom) == str(secondary_unit):
                    required_qty_main_unit = base * Decimal(str(unit_factor))
                elif str(it.uom) == str(main_unit):
                    required_qty_main_unit = base
                else:
                    required_qty_main_unit = None
            except Exception:
                required_qty_main_unit = None
        explosion_items.append({
            "component_product_id": it.component_product_id,
            "required_qty": base,
            "uom": it.uom,
            "suggested_warehouse_id": it.suggested_warehouse_id,
            "is_optional": it.is_optional,
            "substitute_group": it.substitute_group,
            # enriched (optional) fields for UI friendliness
            "component_product_name": getattr(prod, "name", None) if prod else None,
            "component_product_code": getattr(prod, "code", None) if prod else None,
            "component_product_main_unit": getattr(prod, "main_unit", None) if prod else None,
            "required_qty_main_unit": required_qty_main_unit,
            "main_unit": main_unit,
        })

    # outputs scaling
    out_scaled = []
    for ot in outputs:
        prod = products_by_id.get(ot.output_product_id)
        # Convert output to main unit if needed
        ratio_val = Decimal(str(ot.ratio)) * qty
        ratio_main_unit = None
        try:
            main_unit = getattr(prod, "main_unit", None) if prod else None
            secondary_unit = getattr(prod, "secondary_unit", None) if prod else None
            unit_factor = getattr(prod, "unit_conversion_factor", None) if prod else None
            if ot.uom and prod and secondary_unit and main_unit and unit_factor is not None:
                if str(ot.uom) == str(secondary_unit):
                    ratio_main_unit = ratio_val * Decimal(str(unit_factor))
                elif str(ot.uom) == str(main_unit):
                    ratio_main_unit = ratio_val
        except Exception:
            ratio_main_unit = None
        out_scaled.append({
            "line_no": ot.line_no,
            "output_product_id": ot.output_product_id,
            "ratio": ratio_val,
            "uom": ot.uom,
            # enriched optional fields
            "output_product_name": getattr(prod, "name", None) if prod else None,
            "output_product_code": getattr(prod, "code", None) if prod else None,
            "ratio_main_unit": ratio_main_unit,
            "main_unit": getattr(prod, "main_unit", None) if prod else None,
        })

    return {"items": explosion_items, "outputs": out_scaled}


def produce_draft(db: Session, business_id: int, req: ProductionDraftRequest) -> Dict[str, Any]:
    """Create a draft payload for a production document based on BOM explosion (no persistence)."""
    exp = explode_bom(db, business_id, BOMExplosionRequest(product_id=req.product_id, bom_id=req.bom_id, quantity=req.quantity))

    # Build draft lines: for UI to prefill later; debit/credit left 0 to be set by user
    lines: list[dict[str, Any]] = []
    for it in exp["items"]:
        lines.append({
            "product_id": it["component_product_id"],
            "quantity": it["required_qty"],
            "debit": 0,
            "credit": 0,
            "description": f"مصرف مواد برای تولید",
            "extra_info": {
                "uom": it.get("uom"),
                "suggested_warehouse_id": it.get("suggested_warehouse_id"),
                "is_optional": it.get("is_optional"),
                "substitute_group": it.get("substitute_group"),
            },
        })

    for ot in exp["outputs"]:
        lines.append({
            "product_id": ot["output_product_id"],
            "quantity": ot["ratio"],
            "debit": 0,
            "credit": 0,
            "description": "خروجی تولید",
            "extra_info": {"uom": ot.get("uom")},
        })

    desc = "پیش‌نویس سند تولید بر اساس BOM"
    return {
        "document_type": "production",
        "description": desc,
        "lines": lines,
        "extra_info": {"source": "bom", "bom_id": int(req.bom_id) if req.bom_id else None, "product_id": int(req.product_id) if req.product_id else None, "quantity": str(req.quantity)},
    }


