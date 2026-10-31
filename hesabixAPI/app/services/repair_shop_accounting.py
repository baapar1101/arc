"""
یکپارچگی افزونه مدیریت تعمیرگاه با سیستم حسابداری
"""
from __future__ import annotations

import logging
from datetime import datetime, date
from typing import Any, Dict, Optional
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from sqlalchemy import and_

from adapters.db.models.repair_shop import RepairOrder, RepairOrderPart, RepairInvoice, RepairShopSettings
from adapters.db.models.business import Business
from adapters.db.models.product import Product, ProductItemType
from adapters.db.models.document import Document
from adapters.db.repositories.repair_shop_repository import RepairInvoiceRepository, RepairShopSettingsRepository
from app.core.responses import ApiError
from app.core.repair_shop_plugin_dependency import check_repair_shop_plugin_active

logger = logging.getLogger(__name__)


def _ensure_plugin_active(db: Session, business_id: int) -> None:
    if not check_repair_shop_plugin_active(db, business_id):
        raise ApiError("PLUGIN_NOT_ACTIVE", "PLUGIN_NOT_ACTIVE",
            http_status=403,
        )


def _merge_extra_info(order: RepairOrder, updates: Dict[str, Any]) -> None:
    extra = dict(order.extra_info or {})
    extra.update(updates)
    order.extra_info = extra
    flag_modified(order, "extra_info")


def _extract_invoice_id_and_code(result: Any) -> tuple[int, Optional[str]]:
    if not isinstance(result, dict):
        raise ApiError("INVOICE_CREATION_FAILED", "INVOICE_CREATION_FAILED",
            http_status=500,
        )
    data = result.get("data") if isinstance(result.get("data"), dict) else result
    if (not isinstance(data, dict) or data.get("id") is None) and isinstance(result.get("document"), dict):
        data = result["document"]
    if not isinstance(data, dict) or data.get("id") is None:
        raise ApiError("INVOICE_CREATION_FAILED", "INVOICE_CREATION_FAILED",
            http_status=500,
        )
    return int(data["id"]), data.get("code")


def _resolve_or_create_service_product_id(
    db: Session,
    business_id: int,
    settings: Optional[RepairShopSettings],
) -> int:
    if settings and settings.default_service_product_id:
        product = db.query(Product).filter(
            and_(
                Product.id == settings.default_service_product_id,
                Product.business_id == business_id,
            )
        ).first()
        if product:
            return product.id

    service_product = db.query(Product).filter(
        and_(
            Product.business_id == business_id,
            Product.item_type == ProductItemType.SERVICE,
            Product.code.like("SRV-REPAIR%"),
        )
    ).first()
    if service_product:
        if settings and not settings.default_service_product_id:
            settings.default_service_product_id = service_product.id
            db.flush()
        return service_product.id

    named = db.query(Product).filter(
        and_(
            Product.business_id == business_id,
            Product.item_type == ProductItemType.SERVICE,
            Product.name.like("%تعمیر%"),
            Product.is_active == True,  # noqa: E712
        )
    ).first()
    if named:
        if settings and not settings.default_service_product_id:
            settings.default_service_product_id = named.id
            db.flush()
        return named.id

    code = "SRV-REPAIR"
    existing = db.query(Product).filter(
        and_(Product.business_id == business_id, Product.code == code)
    ).first()
    if existing:
        n = 2
        while True:
            candidate = f"SRV-REPAIR-{n}"
            clash = db.query(Product).filter(
                and_(Product.business_id == business_id, Product.code == candidate)
            ).first()
            if not clash:
                code = candidate
                break
            n += 1

    product = Product(
        business_id=business_id,
        item_type=ProductItemType.SERVICE,
        code=code,
        name="خدمات تعمیر",
        track_inventory=False,
        is_active=True,
    )
    db.add(product)
    db.flush()
    if settings:
        settings.default_service_product_id = product.id
        db.flush()
    logger.info("Created default repair service product %s for business %s", product.id, business_id)
    return product.id


def create_repair_invoice_accounting(
    db: Session,
    business_id: int,
    repair_order: RepairOrder,
    user_id: int
) -> Dict[str, Any]:
    """
    ثبت فاکتور تعمیر در سیستم حسابداری
    """
    _ensure_plugin_active(db, business_id)
    from app.services.repair_shop_service import _get_current_fiscal_year

    invoice_repo = RepairInvoiceRepository(db)
    existing = invoice_repo.get_by_order(repair_order.id)

    if existing:
        raise ApiError("INVOICE_ALREADY_EXISTS", "INVOICE_ALREADY_EXISTS",
            http_status=409
        )

    if repair_order.status not in ["completed_fixed", "ready_for_pickup", "delivered"]:
        raise ApiError("INVALID_STATUS_FOR_INVOICE", "INVALID_STATUS_FOR_INVOICE",
            http_status=400
        )

    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "BUSINESS_NOT_FOUND", http_status=404)

    fiscal_year = _get_current_fiscal_year(db, business_id)

    labor_cost = Decimal(str(repair_order.labor_cost or 0))
    parts_cost = Decimal(str(repair_order.parts_cost or 0))

    invoice_payload: Dict[str, Any] = {
        "invoice_type": "invoice_sales",
        "document_date": (
            repair_order.completed_at.date() if repair_order.completed_at else date.today()
        ).isoformat(),
        "currency_id": repair_order.currency_id,
        "fiscal_year_id": fiscal_year.id,
        "person_id": repair_order.customer_person_id,
        "description": f"فاکتور تعمیر - {repair_order.code}",
        "extra_info": {
            "person_id": repair_order.customer_person_id,
            "source_type": "repair_shop",
            "source_id": repair_order.id,
            "repair_code": repair_order.code,
            "totals": {
                "labor_cost": float(labor_cost),
                "parts_cost": float(parts_cost),
                "final_cost": float(repair_order.final_cost or 0),
                "technician_commission": float(repair_order.technician_commission or 0),
            }
        },
        "lines": []
    }

    settings_repo = RepairShopSettingsRepository(db)
    settings = settings_repo.get_by_business(business_id)

    if labor_cost > 0:
        service_product_id = _resolve_or_create_service_product_id(db, business_id, settings)
        invoice_payload["lines"].append({
            "product_id": service_product_id,
            "quantity": 1,
            "unit_price": float(labor_cost),
            "description": f"خدمات تعمیر - {repair_order.product_name}",
            "extra_info": {
                "line_type": "service",
                "repair_order_id": repair_order.id,
                "technician_id": repair_order.assigned_technician_id,
                "technician_commission": float(repair_order.technician_commission or 0),
            }
        })

    parts = db.query(RepairOrderPart).filter(
        RepairOrderPart.repair_order_id == repair_order.id
    ).all()

    for part in parts:
        product = db.query(Product).filter(Product.id == part.product_id).first()
        if not product:
            continue
        line: Dict[str, Any] = {
            "product_id": part.product_id,
            "quantity": float(part.quantity),
            "unit_price": float(part.unit_price),
            "description": part.description or f"قطعه تعمیر - {product.name}",
            "extra_info": {
                "line_type": "part",
                "repair_order_id": repair_order.id,
                "warehouse_id": part.warehouse_id,
                "inventory_tracked": product.track_inventory,
                "movement": "out",
            }
        }
        if part.warehouse_id:
            line["warehouse_id"] = part.warehouse_id
        invoice_payload["lines"].append(line)

    if not invoice_payload["lines"]:
        raise ApiError("NO_INVOICE_LINES", "NO_INVOICE_LINES",
            http_status=400,
        )

    from app.services.invoice_service import create_invoice

    try:
        invoice_result = create_invoice(
            db=db,
            business_id=business_id,
            user_id=user_id,
            data=invoice_payload,
            commit=False,
            lightweight_response=True,
        )
    except ApiError:
        raise
    except Exception as e:
        logger.exception("خطا در ایجاد فاکتور تعمیر")
        raise ApiError("INVOICE_CREATION_FAILED", "INVOICE_CREATION_FAILED",
            http_status=500
        ) from e

    document_id, document_code = _extract_invoice_id_and_code(invoice_result)

    repair_invoice = RepairInvoice(
        repair_order_id=repair_order.id,
        document_id=document_id,
        invoice_type="both" if (labor_cost > 0 and len(parts) > 0) else (
            "repair_service" if labor_cost > 0 else "parts_only"
        ),
    )
    db.add(repair_invoice)

    _merge_extra_info(repair_order, {
        "invoice_document_id": document_id,
        "invoice_code": document_code,
    })

    db.flush()

    return {
        "repair_order_id": repair_order.id,
        "document": {
            "id": document_id,
            "code": document_code,
        },
        "id": document_id,
        "code": document_code,
        "accounting_summary": {
            "labor_cost": float(labor_cost),
            "parts_cost": float(parts_cost),
            "final_cost": float(repair_order.final_cost or 0),
            "technician_commission": float(repair_order.technician_commission or 0),
        },
        "message": "REPAIR_INVOICE_CREATED"
    }


def create_receipt_for_repair_payment(
    db: Session,
    business_id: int,
    repair_order_id: int,
    payment_data: Dict[str, Any],
    user_id: int
) -> Dict[str, Any]:
    """ثبت سند دریافت برای پرداخت هزینه تعمیر"""
    _ensure_plugin_active(db, business_id)
    from app.services.receipt_payment_service import create_receipt_payment
    from adapters.db.repositories.repair_shop_repository import RepairOrderRepository

    repo = RepairOrderRepository(db)
    repair_order = repo.get_by_id(repair_order_id, business_id)

    if not repair_order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "REPAIR_ORDER_NOT_FOUND", http_status=404)

    invoice_repo = RepairInvoiceRepository(db)
    repair_invoice = invoice_repo.get_by_order(repair_order_id)

    if not repair_invoice:
        raise ApiError("NO_INVOICE_FOUND", "NO_INVOICE_FOUND",
            http_status=400
        )

    account_id = payment_data.get("account_id")
    if not account_id:
        raise ApiError("ACCOUNT_REQUIRED", "ACCOUNT_REQUIRED", http_status=400)

    payment_date = payment_data.get("payment_date", date.today())
    if isinstance(payment_date, datetime):
        payment_date = payment_date.date()
    if isinstance(payment_date, date):
        payment_date = payment_date.isoformat()

    receipt_payload = {
        "document_type": "receipt",
        "document_date": payment_date,
        "currency_id": repair_order.currency_id,
        "description": f"دریافت وجه تعمیر - {repair_order.code}",
        "person_lines": [
            {
                "person_id": repair_order.customer_person_id,
                "amount": float(repair_order.final_cost),
                "description": f"بابت هزینه تعمیر - فاکتور {(repair_order.extra_info or {}).get('invoice_code', '')}"
            }
        ],
        "account_lines": [
            {
                "account_id": account_id,
                "amount": float(repair_order.final_cost),
                "description": ""
            }
        ],
        "extra_info": {
            "source_type": "repair_shop",
            "repair_order_id": repair_order.id,
            "repair_code": repair_order.code,
        }
    }

    try:
        receipt_result = create_receipt_payment(
            db=db,
            business_id=business_id,
            user_id=user_id,
            data=receipt_payload,
            commit=False,
        )
    except ApiError:
        raise
    except Exception as e:
        logger.exception("خطا در ایجاد سند دریافت تعمیر")
        raise ApiError("RECEIPT_CREATION_FAILED", "RECEIPT_CREATION_FAILED",
            http_status=500
        ) from e

    return receipt_result


def get_repair_accounting_summary(
    db: Session,
    business_id: int,
    repair_order_id: int
) -> Dict[str, Any]:
    """دریافت خلاصه حسابداری یک سفارش تعمیر"""
    from adapters.db.repositories.repair_shop_repository import RepairOrderRepository

    _ensure_plugin_active(db, business_id)

    repo = RepairOrderRepository(db)
    repair_order = repo.get_by_id(repair_order_id, business_id)

    if not repair_order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "REPAIR_ORDER_NOT_FOUND", http_status=404)

    invoice_repo = RepairInvoiceRepository(db)
    repair_invoice = invoice_repo.get_by_order(repair_order_id)

    invoice_info = None
    if repair_invoice:
        document = db.query(Document).filter(Document.id == repair_invoice.document_id).first()
        if document:
            invoice_info = {
                "document_id": document.id,
                "code": document.code,
                "document_date": document.document_date.isoformat(),
                "type": repair_invoice.invoice_type,
            }

    return {
        "repair_order_id": repair_order.id,
        "repair_code": repair_order.code,
        "customer_person_id": repair_order.customer_person_id,
        "costs": {
            "labor_cost": float(repair_order.labor_cost),
            "parts_cost": float(repair_order.parts_cost),
            "final_cost": float(repair_order.final_cost),
            "technician_commission": float(repair_order.technician_commission),
        },
        "invoice": invoice_info,
        "has_invoice": invoice_info is not None,
    }
