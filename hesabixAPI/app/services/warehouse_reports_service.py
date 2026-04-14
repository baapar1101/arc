"""
Service functions for warehouse reports
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional
from decimal import Decimal
from datetime import datetime, date, timedelta
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func, case
from sqlalchemy.orm import aliased

from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from adapters.db.models.product import Product
from adapters.db.models.warehouse import Warehouse
from app.core.responses import ApiError
from app.services.invoice_service import _compute_available_stock


def get_warehouse_documents_summary_report(
    db: Session,
    business_id: int,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    doc_types: Optional[List[str]] = None,
    warehouse_ids: Optional[List[int]] = None,
    status: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش خلاصه حواله‌های انبار
    """
    from app.services.transfer_service import _parse_iso_date as _parse_date
    
    query = db.query(WarehouseDocument).filter(
        WarehouseDocument.business_id == business_id
    )
    
    # فیلتر تاریخ
    if date_from:
        try:
            query = query.filter(WarehouseDocument.document_date >= _parse_date(date_from))
        except Exception:
            pass
    
    if date_to:
        try:
            query = query.filter(WarehouseDocument.document_date <= _parse_date(date_to))
        except Exception:
            pass
    
    # فیلتر نوع حواله
    if doc_types:
        query = query.filter(WarehouseDocument.doc_type.in_(doc_types))
    
    # فیلتر انبار
    if warehouse_ids:
        query = query.filter(
            or_(
                WarehouseDocument.warehouse_id_from.in_(warehouse_ids),
                WarehouseDocument.warehouse_id_to.in_(warehouse_ids),
            )
        )
    
    # فیلتر وضعیت
    if status:
        query = query.filter(WarehouseDocument.status == status)
    
    # فقط حواله‌های posted
    query = query.filter(WarehouseDocument.status == "posted")
    
    total = query.count()
    documents = query.order_by(
        WarehouseDocument.document_date.desc(),
        WarehouseDocument.id.desc()
    ).offset(skip).limit(take).all()
    
    # محاسبه آمار
    summary_by_type = {}
    total_documents = 0
    total_items = 0
    total_quantity_in = Decimal(0)
    total_quantity_out = Decimal(0)
    
    for doc in documents:
        doc_type = doc.doc_type
        if doc_type not in summary_by_type:
            summary_by_type[doc_type] = {
                "count": 0,
                "items_count": 0,
                "quantity_in": Decimal(0),
                "quantity_out": Decimal(0),
            }
        
        summary_by_type[doc_type]["count"] += 1
        total_documents += 1
        
        # محاسبه از خطوط
        for line in doc.lines:
            summary_by_type[doc_type]["items_count"] += 1
            total_items += 1
            
            if line.movement == "in":
                qty = Decimal(str(line.quantity))
                summary_by_type[doc_type]["quantity_in"] += qty
                total_quantity_in += qty
            elif line.movement == "out":
                qty = Decimal(str(line.quantity))
                summary_by_type[doc_type]["quantity_out"] += qty
                total_quantity_out += qty
    
    items = []
    for doc in documents:
        items.append({
            "id": doc.id,
            "code": doc.code,
            "document_date": doc.document_date,
            "doc_type": doc.doc_type,
            "status": doc.status,
            "warehouse_from_id": doc.warehouse_id_from,
            "warehouse_to_id": doc.warehouse_id_to,
            "items_count": len(doc.lines),
            "total_quantity": sum(Decimal(str(line.quantity)) for line in doc.lines),
        })
    
    return {
        "items": items,
        "total": total,
        "summary": {
            "by_type": {k: {
                "count": v["count"],
                "items_count": v["items_count"],
                "quantity_in": float(v["quantity_in"]),
                "quantity_out": float(v["quantity_out"]),
            } for k, v in summary_by_type.items()},
            "total_documents": total_documents,
            "total_items": total_items,
            "total_quantity_in": float(total_quantity_in),
            "total_quantity_out": float(total_quantity_out),
        }
    }


def get_slow_moving_items_report(
    db: Session,
    business_id: int,
    days_without_movement: int = 90,
    warehouse_ids: Optional[List[int]] = None,
    category_ids: Optional[List[int]] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش کالاهای کم‌گردش
    """
    cutoff_date = date.today() - timedelta(days=days_without_movement)
    
    # Query محصولات
    query = db.query(Product).filter(Product.business_id == business_id)
    
    if category_ids:
        query = query.filter(Product.category_id.in_(category_ids))
    
    products = query.all()
    
    if not products:
        return {
            "items": [],
            "total": 0,
            "cutoff_date": cutoff_date.isoformat(),
        }
    
    product_ids = [p.id for p in products]
    
    # پیدا کردن محصولاتی که در بازه زمانی حرکت داشته‌اند
    movements_query = db.query(WarehouseDocumentLine.product_id).distinct().join(
        WarehouseDocument,
        WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id
    ).filter(
        and_(
            WarehouseDocument.business_id == business_id,
            WarehouseDocument.status == "posted",
            WarehouseDocument.document_date >= cutoff_date,
            WarehouseDocumentLine.product_id.in_(product_ids),
        )
    )
    
    if warehouse_ids:
        movements_query = movements_query.filter(
            WarehouseDocumentLine.warehouse_id.in_(warehouse_ids)
        )
    
    products_with_movement = {row[0] for row in movements_query.all()}
    
    # محصولات بدون حرکت
    slow_moving = [p for p in products if p.id not in products_with_movement]
    
    items = []
    for product in slow_moving[skip:skip + take]:
        # محاسبه موجودی فعلی
        stock = _compute_available_stock(db, business_id, product.id, None, date.today())
        
        items.append({
            "product_id": product.id,
            "product_code": product.code or "",
            "product_name": product.name,
            "category_id": product.category_id,
            "current_stock": float(stock),
            "unit": product.main_unit or "",
            "days_without_movement": days_without_movement,
        })
    
    return {
        "items": items,
        "total": len(slow_moving),
        "cutoff_date": cutoff_date.isoformat(),
    }


def get_critical_stock_report(
    db: Session,
    business_id: int,
    warehouse_ids: Optional[List[int]] = None,
    category_ids: Optional[List[int]] = None,
    as_of_date: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش کالاهای با موجودی بحرانی
    """
    from app.services.transfer_service import _parse_iso_date as _parse_date
    
    as_of_date_obj = date.today()
    if as_of_date:
        try:
            as_of_date_obj = _parse_date(as_of_date) if isinstance(as_of_date, str) else as_of_date
        except Exception:
            pass
    
    # Query محصولات با حداقل موجودی
    query = db.query(Product).filter(
        and_(
            Product.business_id == business_id,
            Product.track_inventory == True,
            Product.reorder_point.isnot(None),
            Product.reorder_point > 0,
        )
    )
    
    if category_ids:
        query = query.filter(Product.category_id.in_(category_ids))
    
    products = query.all()
    
    if not products:
        return {
            "items": [],
            "total": 0,
            "as_of_date": as_of_date_obj.isoformat(),
        }
    
    # محاسبه موجودی و مقایسه با حداقل
    critical_items = []
    for product in products:
        if warehouse_ids:
            for wh_id in warehouse_ids:
                stock = _compute_available_stock(db, business_id, product.id, wh_id, as_of_date_obj)
                reorder_point = Decimal(str(product.reorder_point or 0))
                if stock < reorder_point:
                    critical_items.append({
                        "product": product,
                        "warehouse_id": wh_id,
                        "stock": stock,
                        "min_stock": reorder_point,
                        "difference": stock - reorder_point,
                    })
        else:
            stock = _compute_available_stock(db, business_id, product.id, None, as_of_date_obj)
            reorder_point = Decimal(str(product.reorder_point or 0))
            if stock < reorder_point:
                critical_items.append({
                    "product": product,
                    "warehouse_id": None,
                    "stock": stock,
                    "min_stock": reorder_point,
                    "difference": stock - reorder_point,
                })
    
    # مرتب‌سازی بر اساس تفاوت (کمترین موجودی اول)
    critical_items.sort(key=lambda x: x["stock"])
    
    items = []
    for item in critical_items[skip:skip + take]:
        product = item["product"]
        warehouse_name = None
        if item["warehouse_id"]:
            wh = db.query(Warehouse).filter(Warehouse.id == item["warehouse_id"]).first()
            if wh:
                warehouse_name = f"{wh.code} - {wh.name}"
        
        items.append({
            "product_id": product.id,
            "product_code": product.code or "",
            "product_name": product.name,
            "category_id": product.category_id,
            "warehouse_id": item["warehouse_id"],
            "warehouse_name": warehouse_name,
            "current_stock": float(item["stock"]),
            "min_stock": float(item["min_stock"]),
            "difference": float(item["difference"]),
            "unit": product.main_unit or "",
        })
    
    return {
        "items": items,
        "total": len(critical_items),
        "as_of_date": as_of_date_obj.isoformat(),
    }


def get_inter_warehouse_transfers_report(
    db: Session,
    business_id: int,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    warehouse_from_ids: Optional[List[int]] = None,
    warehouse_to_ids: Optional[List[int]] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش انتقالات بین انبارها
    """
    from app.services.transfer_service import _parse_iso_date as _parse_date
    
    query = db.query(WarehouseDocument).filter(
        and_(
            WarehouseDocument.business_id == business_id,
            WarehouseDocument.doc_type == "transfer",
            WarehouseDocument.status == "posted",
        )
    )
    
    # فیلتر تاریخ
    if date_from:
        try:
            query = query.filter(WarehouseDocument.document_date >= _parse_date(date_from))
        except Exception:
            pass
    
    if date_to:
        try:
            query = query.filter(WarehouseDocument.document_date <= _parse_date(date_to))
        except Exception:
            pass
    
    # فیلتر انبار مبدا
    if warehouse_from_ids:
        query = query.filter(WarehouseDocument.warehouse_id_from.in_(warehouse_from_ids))
    
    # فیلتر انبار مقصد
    if warehouse_to_ids:
        query = query.filter(WarehouseDocument.warehouse_id_to.in_(warehouse_to_ids))
    
    total = query.count()
    documents = query.order_by(
        WarehouseDocument.document_date.desc(),
        WarehouseDocument.id.desc()
    ).offset(skip).limit(take).all()
    
    # بارگذاری اطلاعات انبارها
    warehouse_ids = set()
    for doc in documents:
        if doc.warehouse_id_from:
            warehouse_ids.add(doc.warehouse_id_from)
        if doc.warehouse_id_to:
            warehouse_ids.add(doc.warehouse_id_to)
    
    warehouses = {}
    if warehouse_ids:
        wh_list = db.query(Warehouse).filter(
            and_(
                Warehouse.business_id == business_id,
                Warehouse.id.in_(list(warehouse_ids)),
            )
        ).all()
        for wh in wh_list:
            warehouses[wh.id] = wh
    
    items = []
    for doc in documents:
        warehouse_from_name = None
        if doc.warehouse_id_from and doc.warehouse_id_from in warehouses:
            wh = warehouses[doc.warehouse_id_from]
            warehouse_from_name = f"{wh.code} - {wh.name}"
        
        warehouse_to_name = None
        if doc.warehouse_id_to and doc.warehouse_id_to in warehouses:
            wh = warehouses[doc.warehouse_id_to]
            warehouse_to_name = f"{wh.code} - {wh.name}"
        
        # محاسبه تعداد اقلام و مقدار
        items_count = len(doc.lines)
        total_quantity = sum(Decimal(str(line.quantity)) for line in doc.lines)
        
        items.append({
            "id": doc.id,
            "code": doc.code,
            "document_date": doc.document_date,
            "warehouse_from_id": doc.warehouse_id_from,
            "warehouse_from_name": warehouse_from_name,
            "warehouse_to_id": doc.warehouse_id_to,
            "warehouse_to_name": warehouse_to_name,
            "items_count": items_count,
            "total_quantity": float(total_quantity),
            "created_by_user_id": doc.created_by_user_id,
        })
    
    return {
        "items": items,
        "total": total,
    }


def get_adjustment_documents_report(
    db: Session,
    business_id: int,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    warehouse_ids: Optional[List[int]] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش حواله‌های تعدیل
    """
    from app.services.transfer_service import _parse_iso_date as _parse_date
    
    query = db.query(WarehouseDocument).filter(
        and_(
            WarehouseDocument.business_id == business_id,
            WarehouseDocument.doc_type == "adjustment",
            WarehouseDocument.status == "posted",
        )
    )
    
    # فیلتر تاریخ
    if date_from:
        try:
            query = query.filter(WarehouseDocument.document_date >= _parse_date(date_from))
        except Exception:
            pass
    
    if date_to:
        try:
            query = query.filter(WarehouseDocument.document_date <= _parse_date(date_to))
        except Exception:
            pass
    
    total = query.count()
    documents = query.order_by(
        WarehouseDocument.document_date.desc(),
        WarehouseDocument.id.desc()
    ).offset(skip).limit(take).all()
    
    # محاسبه آمار تعدیل‌ها
    total_increases = Decimal(0)
    total_decreases = Decimal(0)
    total_items = 0
    
    items = []
    for doc in documents:
        increases = Decimal(0)
        decreases = Decimal(0)
        items_count = 0
        
        for line in doc.lines:
            items_count += 1
            qty = Decimal(str(line.quantity))
            if line.movement == "in":
                increases += qty
            elif line.movement == "out":
                decreases += qty
        
        total_increases += increases
        total_decreases += decreases
        total_items += items_count
        
        items.append({
            "id": doc.id,
            "code": doc.code,
            "document_date": doc.document_date,
            "items_count": items_count,
            "quantity_increase": float(increases),
            "quantity_decrease": float(decreases),
            "net_adjustment": float(increases - decreases),
            "created_by_user_id": doc.created_by_user_id,
        })
    
    return {
        "items": items,
        "total": total,
        "summary": {
            "total_documents": total,
            "total_items": total_items,
            "total_increases": float(total_increases),
            "total_decreases": float(total_decreases),
            "net_adjustment": float(total_increases - total_decreases),
        }
    }


def get_warehouse_performance_report(
    db: Session,
    business_id: int,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    warehouse_ids: Optional[List[int]] = None,
) -> Dict[str, Any]:
    """
    گزارش عملکرد انبارها
    """
    from app.services.transfer_service import _parse_iso_date as _parse_date
    
    # Query انبارها
    query = db.query(Warehouse).filter(Warehouse.business_id == business_id)
    
    if warehouse_ids:
        query = query.filter(Warehouse.id.in_(warehouse_ids))
    
    warehouses = query.all()
    
    if not warehouses:
        return {
            "items": [],
        }
    
    # فیلتر تاریخ برای حواله‌ها
    date_from_obj = None
    date_to_obj = None
    if date_from:
        try:
            date_from_obj = _parse_date(date_from)
        except Exception:
            pass
    
    if date_to:
        try:
            date_to_obj = _parse_date(date_to)
        except Exception:
            pass
    
    items = []
    for warehouse in warehouses:
        # Query حواله‌های این انبار
        docs_query = db.query(WarehouseDocument).filter(
            and_(
                WarehouseDocument.business_id == business_id,
                WarehouseDocument.status == "posted",
                or_(
                    WarehouseDocument.warehouse_id_from == warehouse.id,
                    WarehouseDocument.warehouse_id_to == warehouse.id,
                )
            )
        )
        
        if date_from_obj:
            docs_query = docs_query.filter(WarehouseDocument.document_date >= date_from_obj)
        
        if date_to_obj:
            docs_query = docs_query.filter(WarehouseDocument.document_date <= date_to_obj)
        
        documents = docs_query.all()
        
        # محاسبه آمار
        total_documents = len(documents)
        total_items = 0
        total_quantity_in = Decimal(0)
        total_quantity_out = Decimal(0)
        
        for doc in documents:
            for line in doc.lines:
                # تعیین اینکه آیا این خط مربوط به این انبار است یا نه
                # اگر warehouse_id در خط مشخص باشد، از آن استفاده می‌کنیم
                # در غیر این صورت، از warehouse_id_from یا warehouse_id_to حواله استفاده می‌کنیم
                line_warehouse_id = line.warehouse_id
                if line_warehouse_id is None:
                    # اگر warehouse_id در خط مشخص نباشد، از منطق حواله استفاده می‌کنیم
                    if doc.doc_type == "transfer":
                        # برای انتقال: خط out از مبدا و خط in به مقصد است
                        if line.movement == "out" and doc.warehouse_id_from == warehouse.id:
                            line_warehouse_id = warehouse.id
                        elif line.movement == "in" and doc.warehouse_id_to == warehouse.id:
                            line_warehouse_id = warehouse.id
                    elif doc.doc_type in ("receipt", "production_in"):
                        # برای ورود: خطوط به warehouse_id_to می‌روند
                        if line.movement == "in" and doc.warehouse_id_to == warehouse.id:
                            line_warehouse_id = warehouse.id
                    elif doc.doc_type in ("issue", "production_out"):
                        # برای خروج: خطوط از warehouse_id_from می‌آیند
                        if line.movement == "out" and doc.warehouse_id_from == warehouse.id:
                            line_warehouse_id = warehouse.id
                    else:
                        # برای سایر حواله‌ها (مثل adjustment): از warehouse_id_from یا warehouse_id_to استفاده می‌کنیم
                        if doc.warehouse_id_from == warehouse.id or doc.warehouse_id_to == warehouse.id:
                            line_warehouse_id = warehouse.id
                
                # فقط خطوط مربوط به این انبار
                if line_warehouse_id == warehouse.id:
                    total_items += 1
                    qty = Decimal(str(line.quantity))
                    if line.movement == "in":
                        total_quantity_in += qty
                    elif line.movement == "out":
                        total_quantity_out += qty
        
        # محاسبه موجودی فعلی
        # این نیاز به محاسبه از تمام محصولات دارد که می‌تواند سنگین باشد
        # برای سادگی، فقط تعداد محصولات با موجودی را می‌شماریم
        
        items.append({
            "warehouse_id": warehouse.id,
            "warehouse_code": warehouse.code,
            "warehouse_name": warehouse.name,
            "total_documents": total_documents,
            "total_items": total_items,
            "total_quantity_in": float(total_quantity_in),
            "total_quantity_out": float(total_quantity_out),
            "net_quantity": float(total_quantity_in - total_quantity_out),
        })
    
    return {
        "items": items,
    }


def get_product_movement_history_report(
    db: Session,
    business_id: int,
    product_id: int,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    warehouse_ids: Optional[List[int]] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش تاریخچه حرکات یک کالا
    """
    from app.services.transfer_service import _parse_iso_date as _parse_date
    
    # بررسی وجود محصول
    product = db.query(Product).filter(
        and_(
            Product.id == product_id,
            Product.business_id == business_id,
        )
    ).first()
    
    if not product:
        raise ApiError("PRODUCT_NOT_FOUND", "Product not found", http_status=404)
    
    # Query خطوط حواله‌های مربوط به این محصول
    query = db.query(WarehouseDocumentLine).join(
        WarehouseDocument,
        WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id
    ).filter(
        and_(
            WarehouseDocument.business_id == business_id,
            WarehouseDocument.status == "posted",
            WarehouseDocumentLine.product_id == product_id,
        )
    )
    
    # فیلتر تاریخ
    if date_from:
        try:
            query = query.filter(WarehouseDocument.document_date >= _parse_date(date_from))
        except Exception:
            pass
    
    if date_to:
        try:
            query = query.filter(WarehouseDocument.document_date <= _parse_date(date_to))
        except Exception:
            pass
    
    # فیلتر انبار
    if warehouse_ids:
        query = query.filter(WarehouseDocumentLine.warehouse_id.in_(warehouse_ids))
    
    total = query.count()
    lines = query.order_by(
        WarehouseDocument.document_date.desc(),
        WarehouseDocument.id.desc(),
        WarehouseDocumentLine.id.desc()
    ).offset(skip).limit(take).all()
    
    # بارگذاری اطلاعات انبارها
    warehouse_ids_set = {line.warehouse_id for line in lines if line.warehouse_id}
    warehouses = {}
    if warehouse_ids_set:
        wh_list = db.query(Warehouse).filter(
            and_(
                Warehouse.business_id == business_id,
                Warehouse.id.in_(list(warehouse_ids_set)),
            )
        ).all()
        for wh in wh_list:
            warehouses[wh.id] = wh
    
    items = []
    for line in lines:
        doc = line.document
        warehouse_name = None
        if line.warehouse_id and line.warehouse_id in warehouses:
            wh = warehouses[line.warehouse_id]
            warehouse_name = f"{wh.code} - {wh.name}"
        
        items.append({
            "id": line.id,
            "document_id": doc.id,
            "document_code": doc.code,
            "document_date": doc.document_date,
            "doc_type": doc.doc_type,
            "warehouse_id": line.warehouse_id,
            "warehouse_name": warehouse_name,
            "movement": line.movement,
            "quantity": float(line.quantity),
            "created_by_user_id": doc.created_by_user_id,
        })
    
    return {
        "product_id": product.id,
        "product_code": product.code or "",
        "product_name": product.name,
        "items": items,
        "total": total,
    }


def get_inventory_valuation_report(
    db: Session,
    business_id: int,
    as_of_date: Optional[str] = None,
    warehouse_ids: Optional[List[int]] = None,
    category_ids: Optional[List[int]] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش ارزش موجودی انبار
    """
    from app.services.transfer_service import _parse_iso_date as _parse_date
    
    as_of_date_obj = date.today()
    if as_of_date:
        try:
            as_of_date_obj = _parse_date(as_of_date) if isinstance(as_of_date, str) else as_of_date
        except Exception:
            pass
    
    # Query محصولات
    query = db.query(Product).filter(Product.business_id == business_id)
    
    if category_ids:
        query = query.filter(Product.category_id.in_(category_ids))
    
    products = query.all()
    
    if not products:
        return {
            "items": [],
            "total": 0,
            "total_value": 0.0,
            "as_of_date": as_of_date_obj.isoformat(),
        }
    
    # Query انبارها
    warehouses = []
    if warehouse_ids:
        warehouses = db.query(Warehouse).filter(
            and_(
                Warehouse.business_id == business_id,
                Warehouse.id.in_(warehouse_ids),
            )
        ).all()
    else:
        warehouses = db.query(Warehouse).filter(Warehouse.business_id == business_id).all()
    
    items = []
    total_value = Decimal(0)
    
    for product in products:
        # محاسبه موجودی و ارزش
        if warehouses:
            for warehouse in warehouses:
                stock = _compute_available_stock(db, business_id, product.id, warehouse.id, as_of_date_obj)
                if stock > 0:
                    # استفاده از قیمت تمام شده یا قیمت خرید
                    cost_price = float(product.cost_price or product.purchase_price or 0)
                    value = Decimal(str(stock)) * Decimal(str(cost_price))
                    total_value += value
                    
                    items.append({
                        "product_id": product.id,
                        "product_code": product.code or "",
                        "product_name": product.name,
                        "category_id": product.category_id,
                        "warehouse_id": warehouse.id,
                        "warehouse_code": warehouse.code,
                        "warehouse_name": warehouse.name,
                        "quantity": float(stock),
                        "unit": product.main_unit or "",
                        "cost_price": cost_price,
                        "value": float(value),
                    })
        else:
            stock = _compute_available_stock(db, business_id, product.id, None, as_of_date_obj)
            if stock > 0:
                cost_price = float(product.cost_price or product.purchase_price or 0)
                value = Decimal(str(stock)) * Decimal(str(cost_price))
                total_value += value
                
                items.append({
                    "product_id": product.id,
                    "product_code": product.code or "",
                    "product_name": product.name,
                    "category_id": product.category_id,
                    "warehouse_id": None,
                    "warehouse_code": None,
                    "warehouse_name": "کل",
                    "quantity": float(stock),
                    "unit": product.main_unit or "",
                    "cost_price": cost_price,
                    "value": float(value),
                })
    
    # مرتب‌سازی بر اساس ارزش
    items.sort(key=lambda x: x["value"], reverse=True)
    
    return {
        "items": items[skip:skip + take],
        "total": len(items),
        "total_value": float(total_value),
        "as_of_date": as_of_date_obj.isoformat(),
    }


def get_pending_documents_report(
    db: Session,
    business_id: int,
    warehouse_ids: Optional[List[int]] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش حواله‌های در انتظار تایید
    """
    query = db.query(WarehouseDocument).filter(
        and_(
            WarehouseDocument.business_id == business_id,
            WarehouseDocument.status == "draft",
        )
    )
    
    # فیلتر انبار
    if warehouse_ids:
        query = query.filter(
            or_(
                WarehouseDocument.warehouse_id_from.in_(warehouse_ids),
                WarehouseDocument.warehouse_id_to.in_(warehouse_ids),
            )
        )
    
    total = query.count()
    documents = query.order_by(
        WarehouseDocument.created_at.asc(),
        WarehouseDocument.id.asc()
    ).offset(skip).limit(take).all()
    
    items = []
    for doc in documents:
        # محاسبه مدت زمان انتظار
        days_pending = (date.today() - doc.created_at.date()).days
        
        items.append({
            "id": doc.id,
            "code": doc.code,
            "document_date": doc.document_date,
            "doc_type": doc.doc_type,
            "warehouse_from_id": doc.warehouse_id_from,
            "warehouse_to_id": doc.warehouse_id_to,
            "items_count": len(doc.lines),
            "created_at": doc.created_at,
            "created_by_user_id": doc.created_by_user_id,
            "days_pending": days_pending,
        })
    
    return {
        "items": items,
        "total": total,
    }


def get_inventory_turnover_report(
    db: Session,
    business_id: int,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    warehouse_ids: Optional[List[int]] = None,
    category_ids: Optional[List[int]] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش گردش موجودی
    """
    from app.services.transfer_service import _parse_iso_date as _parse_date
    
    date_from_obj = date.today() - timedelta(days=365)
    date_to_obj = date.today()
    
    if date_from:
        try:
            date_from_obj = _parse_date(date_from)
        except Exception:
            pass
    
    if date_to:
        try:
            date_to_obj = _parse_date(date_to)
        except Exception:
            pass
    
    # Query محصولات
    query = db.query(Product).filter(Product.business_id == business_id)
    
    if category_ids:
        query = query.filter(Product.category_id.in_(category_ids))
    
    products = query.all()
    
    if not products:
        return {
            "items": [],
            "total": 0,
            "pagination": {
                "total": 0,
                "page": 1,
                "per_page": take,
                "total_pages": 0,
            },
            # Backward-compat fields (some clients read these)
            "page": 1,
            "limit": take,
            "total_pages": 0,
        }
    
    product_ids = [p.id for p in products]
    
    # محاسبه گردش برای هر محصول
    items = []
    for product in products:
        # محاسبه موجودی متوسط
        # برای سادگی، از موجودی فعلی استفاده می‌کنیم
        avg_stock = _compute_available_stock(db, business_id, product.id, None, date_to_obj)
        
        # محاسبه تعداد خروج در دوره
        out_query = db.query(func.sum(WarehouseDocumentLine.quantity)).join(
            WarehouseDocument,
            WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id
        ).filter(
            and_(
                WarehouseDocument.business_id == business_id,
                WarehouseDocument.status == "posted",
                WarehouseDocument.document_date >= date_from_obj,
                WarehouseDocument.document_date <= date_to_obj,
                WarehouseDocumentLine.product_id == product.id,
                WarehouseDocumentLine.movement == "out",
            )
        )
        
        if warehouse_ids:
            out_query = out_query.filter(
                WarehouseDocumentLine.warehouse_id.in_(warehouse_ids)
            )
        
        total_out = out_query.scalar() or Decimal(0)
        
        # محاسبه نرخ گردش
        turnover_rate = 0.0
        if avg_stock > 0:
            turnover_rate = float(total_out) / float(avg_stock)
        
        items.append({
            "product_id": product.id,
            "product_code": product.code or "",
            "product_name": product.name,
            "category_id": product.category_id,
            "average_stock": float(avg_stock),
            "total_out": float(total_out),
            "turnover_rate": turnover_rate,
            "unit": product.main_unit or "",
        })
    
    # مرتب‌سازی بر اساس نرخ گردش
    items.sort(key=lambda x: x["turnover_rate"], reverse=True)

    total = len(items)
    per_page = max(int(take or 0), 0)
    safe_per_page = per_page if per_page > 0 else 50
    safe_skip = max(int(skip or 0), 0)
    page = (safe_skip // safe_per_page) + 1
    total_pages = (total + safe_per_page - 1) // safe_per_page if total > 0 else 0

    sliced = items[safe_skip:safe_skip + safe_per_page]

    return {
        "items": sliced,
        "total": total,
        "date_from": date_from_obj.isoformat(),
        "date_to": date_to_obj.isoformat(),
        # New shape used by `DataTableResponse.fromJson` (preferred)
        "pagination": {
            "total": total,
            "page": page,
            "per_page": safe_per_page,
            "total_pages": total_pages,
        },
        # Old shape (compat)
        "page": page,
        "limit": safe_per_page,
        "total_pages": total_pages,
    }

