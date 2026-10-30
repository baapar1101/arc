"""
عملیات پیشرفته افزونه مدیریت تعمیرگاه
(تغییر وضعیت، افزودن قطعات، محاسبه هزینه‌ها)
"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Dict, List, Optional
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from sqlalchemy import and_

from adapters.db.models.repair_shop import (
    RepairOrder,
    RepairOrderPart,
    RepairTechnician,
)
from adapters.db.models.product import Product
from adapters.db.repositories.repair_shop_repository import (
    RepairOrderRepository,
    RepairOrderPartRepository,
    RepairOrderStatusRepository,
    RepairShopSettingsRepository,
)
from app.core.responses import ApiError
from app.core.repair_shop_plugin_dependency import check_repair_shop_plugin_active

logger = logging.getLogger(__name__)

_TERMINAL_STATUSES = {"delivered", "cancelled"}
_COMPLETED_STATUSES = {"completed_fixed", "completed_unfixable", "ready_for_pickup", "delivered"}


def _check_plugin_active(db: Session, business_id: int) -> None:
    if not check_repair_shop_plugin_active(db, business_id):
        raise ApiError(
            "PLUGIN_NOT_ACTIVE",
            "افزونه مدیریت تعمیرگاه فعال نیست",
            http_status=403,
        )


def _merge_extra_info(order: RepairOrder, updates: Dict[str, Any]) -> None:
    extra = dict(order.extra_info or {})
    extra.update(updates)
    order.extra_info = extra
    flag_modified(order, "extra_info")


def _recalculate_parts_cost(db: Session, order: RepairOrder) -> Decimal:
    parts = db.query(RepairOrderPart).filter(
        RepairOrderPart.repair_order_id == order.id
    ).all()
    total = sum((Decimal(str(p.total_price or 0)) for p in parts), Decimal("0"))
    order.parts_cost = total
    order.final_cost = Decimal(str(order.labor_cost or 0)) + total
    return total


def assign_technician_to_order(
    db: Session,
    business_id: int,
    repair_order_id: int,
    technician_id: int,
    user_id: int
) -> Dict[str, Any]:
    """اختصاص تعمیرکار به سفارش"""
    _check_plugin_active(db, business_id)
    from app.services.repair_shop_service import get_repair_order

    repo = RepairOrderRepository(db)
    order = repo.get_by_id(repair_order_id, business_id)

    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)

    if order.status in _TERMINAL_STATUSES:
        raise ApiError(
            "ORDER_NOT_EDITABLE",
            "سفارش تحویل‌شده یا لغوشده قابل اختصاص تعمیرکار نیست",
            http_status=400,
        )

    technician = db.query(RepairTechnician).filter(
        and_(
            RepairTechnician.id == technician_id,
            RepairTechnician.business_id == business_id,
            RepairTechnician.is_active == True  # noqa: E712
        )
    ).first()

    if not technician:
        raise ApiError("TECHNICIAN_NOT_FOUND", "تعمیرکار یافت نشد یا غیرفعال است", http_status=404)

    previous_status = order.status
    order.assigned_technician_id = technician_id
    order.updated_at = datetime.utcnow()

    # فقط سفارش تازه‌دریافت‌شده به «اختصاص داده شده» می‌رود؛
    # سفارش در جریان کار با عوض کردن تعمیرکار عقب نمی‌افتد.
    if previous_status == "received":
        order.status = "assigned"
        history_status = "assigned"
        notes = "اختصاص به تعمیرکار"
    else:
        history_status = previous_status
        notes = "تغییر تعمیرکار اختصاص‌یافته"

    status_repo = RepairOrderStatusRepository(db)
    status_repo.create({
        "repair_order_id": order.id,
        "status": history_status,
        "notes": notes,
        "created_by_user_id": user_id,
    })

    db.commit()

    return get_repair_order(db, business_id, repair_order_id)


def update_repair_order_status(
    db: Session,
    business_id: int,
    repair_order_id: int,
    new_status: str,
    notes: Optional[str],
    user_id: int,
    send_notification: bool = True,
    calendar_type: str = "jalali",
) -> Dict[str, Any]:
    """تغییر وضعیت سفارش تعمیر"""
    _check_plugin_active(db, business_id)
    from app.services.repair_shop_service import get_repair_order, VALID_STATUSES

    if new_status not in VALID_STATUSES:
        raise ApiError("INVALID_STATUS", f"وضعیت نامعتبر: {new_status}", http_status=400)

    repo = RepairOrderRepository(db)
    order = repo.get_by_id(repair_order_id, business_id)

    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)

    if order.status in _TERMINAL_STATUSES and new_status != order.status:
        raise ApiError(
            "ORDER_NOT_EDITABLE",
            f"سفارش در وضعیت {order.status} قابل تغییر وضعیت نیست",
            http_status=400,
        )

    order.status = new_status
    order.updated_at = datetime.utcnow()

    if new_status in ["completed_fixed", "completed_unfixable"]:
        if not order.completed_at:
            order.completed_at = datetime.utcnow()

    elif new_status == "delivered":
        if not order.delivered_at:
            order.delivered_at = datetime.utcnow()

    status_repo = RepairOrderStatusRepository(db)
    status_repo.create({
        "repair_order_id": order.id,
        "status": new_status,
        "notes": notes,
        "created_by_user_id": user_id,
    })

    db.flush()

    if send_notification:
        from app.services.repair_shop_notification import send_repair_notification
        try:
            event_map = {
                "ready_for_pickup": "repair_shop.ready",
                "completed_fixed": "repair_shop.completed",
                "completed_unfixable": "repair_shop.completed",
                "delivered": "repair_shop.delivered"
            }
            event = event_map.get(new_status, "repair_shop.status_changed")

            send_repair_notification(
                db=db,
                business_id=business_id,
                repair_order=order,
                event_type=event,
                triggered_by_user_id=user_id,
                calendar_type=calendar_type,
            )
        except Exception as e:
            logger.error(f"خطا در ارسال نوتیفیکیشن تغییر وضعیت: {e}")

    db.commit()

    return get_repair_order(db, business_id, repair_order_id)


def add_parts_to_repair_order(
    db: Session,
    business_id: int,
    repair_order_id: int,
    parts: List[Dict[str, Any]],
    user_id: int
) -> Dict[str, Any]:
    """افزودن قطعات به سفارش تعمیر"""
    _check_plugin_active(db, business_id)
    from app.services.repair_shop_service import get_repair_order
    from app.services.warehouse_service import get_physical_stock

    repo = RepairOrderRepository(db)
    order = repo.get_by_id(repair_order_id, business_id)

    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)

    if order.status in _TERMINAL_STATUSES:
        raise ApiError(
            "ORDER_NOT_EDITABLE",
            "امکان افزودن قطعه به سفارش تحویل‌شده یا لغوشده وجود ندارد",
            http_status=400,
        )

    if not parts:
        raise ApiError("PARTS_REQUIRED", "حداقل یک قطعه باید اضافه شود", http_status=400)

    settings_repo = RepairShopSettingsRepository(db)
    settings = settings_repo.get_by_business(business_id)
    default_warehouse_id = settings.default_warehouse_id if settings else None

    warehouse_lines = []
    parts_repo = RepairOrderPartRepository(db)

    for part in parts:
        product_id = part.get("product_id")
        quantity = part.get("quantity")
        warehouse_id = part.get("warehouse_id") or default_warehouse_id

        if not product_id or not quantity:
            raise ApiError("INVALID_PART_DATA", "اطلاعات قطعه نامعتبر است", http_status=400)

        product = db.query(Product).filter(
            and_(
                Product.id == product_id,
                Product.business_id == business_id
            )
        ).first()

        if not product:
            raise ApiError("PRODUCT_NOT_FOUND", f"قطعه با ID {product_id} یافت نشد", http_status=404)

        if product.track_inventory:
            if not warehouse_id:
                raise ApiError(
                    "WAREHOUSE_REQUIRED",
                    f"برای قطعه «{product.name}» که کنترل موجودی دارد، انتخاب انبار الزامی است.",
                    http_status=400,
                )
            current_stock = get_physical_stock(db, business_id, product_id, warehouse_id)

            if current_stock < Decimal(str(quantity)):
                from app.services.invoice_service import _format_quantity_for_user_message

                raise ApiError(
                    "INSUFFICIENT_STOCK",
                    f"موجودی کافی نیست. موجودی فعلی: {_format_quantity_for_user_message(current_stock)}، "
                    f"مقدار درخواستی: {_format_quantity_for_user_message(quantity)}",
                    http_status=409,
                    details={
                        "product_id": product_id,
                        "product_name": product.name,
                        "current_stock": float(current_stock),
                        "requested": float(quantity)
                    }
                )

        unit_price_raw = part.get("unit_price")
        if unit_price_raw in (None, "", 0, "0"):
            unit_price = Decimal(str(product.base_sales_price or 0))
        else:
            unit_price = Decimal(str(unit_price_raw))

        quantity_dec = Decimal(str(quantity))
        total_price = unit_price * quantity_dec

        part_data = {
            "repair_order_id": repair_order_id,
            "product_id": product_id,
            "quantity": quantity_dec,
            "unit_price": unit_price,
            "total_price": total_price,
            "warehouse_id": warehouse_id,
            "description": part.get("description"),
        }

        parts_repo.create(part_data)

        if product.track_inventory and warehouse_id:
            warehouse_lines.append({
                "product_id": product_id,
                "quantity": float(quantity_dec),
                "warehouse_id": warehouse_id,
                "movement": "out",
                "description": f"قطعات تعمیر - {order.code}"
            })

    _recalculate_parts_cost(db, order)
    order.updated_at = datetime.utcnow()

    db.flush()

    if warehouse_lines:
        from app.services.warehouse_service import create_manual_warehouse_document

        try:
            warehouse_doc_data = {
                "doc_type": "issue",
                "document_date": datetime.utcnow().date(),
                "status": "draft",
                "warehouse_id_from": warehouse_lines[0]["warehouse_id"],
                "extra_info": {
                    "source_type": "repair_shop",
                    "source_id": order.id,
                    "repair_code": order.code,
                    "description": f"قطعات تعمیر - {order.code}"
                },
                "lines": warehouse_lines
            }

            warehouse_doc = create_manual_warehouse_document(
                db=db,
                business_id=business_id,
                user_id=user_id,
                data=warehouse_doc_data
            )

            extra = dict(order.extra_info or {})
            doc_ids = list(extra.get("warehouse_document_ids") or [])
            if warehouse_doc.id not in doc_ids:
                doc_ids.append(warehouse_doc.id)
            _merge_extra_info(order, {
                "warehouse_document_id": warehouse_doc.id,
                "warehouse_doc_code": warehouse_doc.code,
                "warehouse_document_ids": doc_ids,
            })

        except ApiError:
            raise
        except Exception as e:
            logger.error(f"خطا در ایجاد حواله خروج: {e}")

    db.commit()

    return get_repair_order(db, business_id, repair_order_id)


def remove_part_from_repair_order(
    db: Session,
    business_id: int,
    repair_order_id: int,
    part_id: int,
    user_id: int,
) -> Dict[str, Any]:
    """حذف یک قطعه از سفارش تعمیر"""
    _check_plugin_active(db, business_id)
    from app.services.repair_shop_service import get_repair_order

    repo = RepairOrderRepository(db)
    order = repo.get_by_id(repair_order_id, business_id)
    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)

    if order.status in _TERMINAL_STATUSES or order.status in _COMPLETED_STATUSES:
        extra = order.extra_info or {}
        if extra.get("invoice_document_id"):
            raise ApiError(
                "ORDER_NOT_EDITABLE",
                "پس از صدور فاکتور امکان حذف قطعه وجود ندارد",
                http_status=400,
            )
        if order.status in _TERMINAL_STATUSES:
            raise ApiError(
                "ORDER_NOT_EDITABLE",
                "امکان حذف قطعه از این سفارش وجود ندارد",
                http_status=400,
            )

    parts_repo = RepairOrderPartRepository(db)
    part = parts_repo.get_by_id(part_id, repair_order_id)
    if not part:
        raise ApiError("PART_NOT_FOUND", "قطعه یافت نشد", http_status=404)

    parts_repo.delete(part)
    _recalculate_parts_cost(db, order)
    order.updated_at = datetime.utcnow()
    db.commit()
    return get_repair_order(db, business_id, repair_order_id)


def calculate_repair_costs(
    db: Session,
    business_id: int,
    repair_order_id: int,
    labor_cost: Decimal,
    user_id: int
) -> Dict[str, Any]:
    """محاسبه هزینه‌های نهایی تعمیر"""
    _check_plugin_active(db, business_id)
    from app.services.repair_shop_service import get_repair_order

    repo = RepairOrderRepository(db)
    order = repo.get_by_id(repair_order_id, business_id)

    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)

    if order.status in _TERMINAL_STATUSES:
        raise ApiError(
            "ORDER_NOT_EDITABLE",
            "امکان تغییر هزینه سفارش تحویل‌شده یا لغوشده وجود ندارد",
            http_status=400,
        )

    labor_cost = Decimal(str(labor_cost or 0))
    technician_commission = Decimal("0")

    if order.assigned_technician_id:
        technician = db.query(RepairTechnician).filter(
            RepairTechnician.id == order.assigned_technician_id
        ).first()

        if technician:
            if technician.commission_type == "fixed":
                technician_commission = technician.commission_value
            elif technician.commission_type == "percentage":
                technician_commission = (labor_cost * technician.commission_value) / Decimal("100")

    order.labor_cost = labor_cost
    order.technician_commission = technician_commission
    order.final_cost = Decimal(str(order.parts_cost or 0)) + labor_cost
    order.updated_at = datetime.utcnow()

    db.commit()

    return {
        "repair_order_id": order.id,
        "parts_cost": float(order.parts_cost),
        "labor_cost": float(order.labor_cost),
        "technician_commission": float(order.technician_commission),
        "final_cost": float(order.final_cost),
        "order": get_repair_order(db, business_id, repair_order_id),
    }


def complete_repair_order(
    db: Session,
    business_id: int,
    repair_order_id: int,
    is_fixed: bool,
    user_id: int,
    notes: Optional[str] = None,
    calendar_type: str = "jalali",
) -> Dict[str, Any]:
    """اتمام تعمیر و پست حواله"""
    _check_plugin_active(db, business_id)
    from app.services.repair_shop_service import get_repair_order

    repo = RepairOrderRepository(db)
    order = repo.get_by_id(repair_order_id, business_id)

    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)

    if order.status in _TERMINAL_STATUSES:
        raise ApiError(
            "INVALID_STATUS_FOR_COMPLETE",
            "سفارش تحویل‌شده یا لغوشده قابل تکمیل نیست",
            http_status=400,
        )

    new_status = "completed_fixed" if is_fixed else "completed_unfixable"

    extra = dict(order.extra_info or {})
    warehouse_doc_ids = list(extra.get("warehouse_document_ids") or [])
    single_id = extra.get("warehouse_document_id")
    if single_id and single_id not in warehouse_doc_ids:
        warehouse_doc_ids.append(single_id)

    if warehouse_doc_ids:
        from app.services.warehouse_service import post_warehouse_document

        for warehouse_doc_id in warehouse_doc_ids:
            try:
                post_warehouse_document(db, warehouse_doc_id)
            except ApiError as e:
                if e.code == "INSUFFICIENT_STOCK":
                    raise ApiError(
                        "CANNOT_COMPLETE_REPAIR",
                        f"امکان تکمیل تعمیر وجود ندارد: {e.message}",
                        http_status=409,
                        details=getattr(e, "details", None),
                    ) from e
                if e.code in {"ALREADY_POSTED", "DOCUMENT_ALREADY_POSTED"}:
                    continue
                raise

        _merge_extra_info(order, {
            "warehouse_posted": True,
            "warehouse_posted_at": datetime.utcnow().isoformat(),
        })

    order.status = new_status
    order.completed_at = datetime.utcnow()
    order.updated_at = datetime.utcnow()

    status_repo = RepairOrderStatusRepository(db)
    status_repo.create({
        "repair_order_id": order.id,
        "status": new_status,
        "notes": notes or ("تعمیر موفق" if is_fixed else "غیرقابل تعمیر"),
        "created_by_user_id": user_id,
    })

    db.commit()

    from app.services.repair_shop_notification import send_repair_notification
    try:
        send_repair_notification(
            db=db,
            business_id=business_id,
            repair_order=order,
            event_type="repair_shop.completed",
            triggered_by_user_id=user_id,
            calendar_type=calendar_type,
        )
    except Exception as e:
        logger.error(f"خطا در ارسال نوتیفیکیشن اتمام تعمیر: {e}")

    return get_repair_order(db, business_id, repair_order_id)


def deliver_repair_order(
    db: Session,
    business_id: int,
    repair_order_id: int,
    user_id: int,
    notes: Optional[str] = None
) -> Dict[str, Any]:
    """تحویل کالا به مشتری"""
    _check_plugin_active(db, business_id)
    from app.services.repair_shop_service import get_repair_order

    repo = RepairOrderRepository(db)
    order = repo.get_by_id(repair_order_id, business_id)

    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)

    if order.status not in ["completed_fixed", "completed_unfixable", "ready_for_pickup"]:
        raise ApiError(
            "INVALID_STATUS_FOR_DELIVERY",
            f"سفارش در وضعیت {order.status} قابل تحویل نیست",
            http_status=400
        )

    order.status = "delivered"
    order.delivered_at = datetime.utcnow()
    order.updated_at = datetime.utcnow()

    status_repo = RepairOrderStatusRepository(db)
    status_repo.create({
        "repair_order_id": order.id,
        "status": "delivered",
        "notes": notes or "تحویل کالا به مشتری",
        "created_by_user_id": user_id,
    })

    db.commit()

    return get_repair_order(db, business_id, repair_order_id)


def get_repair_history_by_warranty(
    db: Session,
    business_id: int,
    warranty_code_id: int
) -> List[Dict[str, Any]]:
    """دریافت تاریخچه تعمیرات براساس کد گارانتی"""
    from adapters.db.models.person import Person
    from app.services.repair_shop_service import _person_display_name

    _check_plugin_active(db, business_id)

    orders = db.query(RepairOrder).filter(
        and_(
            RepairOrder.business_id == business_id,
            RepairOrder.warranty_code_id == warranty_code_id
        )
    ).order_by(RepairOrder.received_at.desc()).all()

    result = []
    for order in orders:
        customer = db.query(Person).filter(Person.id == order.customer_person_id).first()

        result.append({
            "id": order.id,
            "code": order.code,
            "customer_name": _person_display_name(customer) if customer else "",
            "problem_description": order.problem_description,
            "status": order.status,
            "final_cost": float(order.final_cost),
            "received_at": order.received_at,
            "completed_at": order.completed_at,
        })

    return result
