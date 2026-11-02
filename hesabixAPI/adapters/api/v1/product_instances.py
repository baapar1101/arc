# Removed __future__ annotations to fix OpenAPI schema generation

from typing import Dict, Any, List, Optional
from fastapi import APIRouter, Depends, Request, Body, Query
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func
from datetime import date

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.business_calendar import business_today
from app.core.permissions import require_business_access
from app.core.responses import success_response, ApiError
from adapters.db.models.product_instance import ProductInstance
from adapters.db.models.product import Product
from adapters.db.models.product_general_barcode_alias import ProductGeneralBarcodeAlias
from adapters.db.models.warehouse import Warehouse
from app.services.product_attribute_service import validate_custom_attributes


router = APIRouter(prefix="/product-instances", tags=["product_instances"])


def _instance_dates(inst: ProductInstance) -> Dict[str, Any]:
    return {
        "manufacturing_date": inst.manufacturing_date.isoformat() if getattr(inst, "manufacturing_date", None) else None,
        "expiry_date": inst.expiry_date.isoformat() if getattr(inst, "expiry_date", None) else None,
    }


def _parse_instance_date(value: Any) -> Optional[date]:
    if not value:
        return None
    return date.fromisoformat(str(value)[:10])


def _require_instance_dates(product: Product, manufacturing_date: Optional[date], expiry_date: Optional[date]) -> None:
    from app.services.inventory_lot_service import is_expiry_tracked_product

    if not is_expiry_tracked_product(product):
        return
    if manufacturing_date is None and expiry_date is None:
        raise ApiError(
            "INSTANCE_DATES_REQUIRED",
            "برای کالای تاریخ‌دار باید تاریخ تولید یا انقضا روی هر واحد ثبت شود",
            http_status=422,
        )


def _instance_is_expired(instance: ProductInstance, product: Product, as_of: Optional[date] = None) -> bool:
    from app.services.inventory_lot_service import STATUS_BLOCKED, STATUS_EXPIRED, instance_expiry_view

    as_of = as_of or business_today(getattr(product, "business_id", None))
    status = str(instance_expiry_view(instance, product, as_of).get("status") or "")
    return status in {STATUS_EXPIRED, STATUS_BLOCKED}


def _instance_search_payload(inst: ProductInstance) -> Dict[str, Any]:
    warehouse_name = None
    if inst.warehouse_id and getattr(inst, "warehouse", None) is not None:
        warehouse_name = inst.warehouse.name
    product = getattr(inst, "product", None)
    product_name = product.name if product is not None else None
    return {
        "id": inst.id,
        "product_id": inst.product_id,
        "product_name": product_name,
        "serial_number": inst.serial_number,
        "barcode": inst.barcode,
        "warehouse_id": inst.warehouse_id,
        "warehouse_name": warehouse_name,
        "status": inst.status,
        "custom_attributes": inst.custom_attributes or {},
        "entry_date": inst.entry_date.isoformat() if inst.entry_date else None,
        **_instance_dates(inst),
        "is_expired": _instance_is_expired(inst, product) if product is not None else False,
    }


@router.post("/business/{business_id}/search")
@require_business_access("business_id")
def search_product_instances(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """جستجوی کالاهای یونیک."""
    if not ctx.has_business_permission("inventory", "read"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    
    product_id = payload.get("product_id")
    warehouse_id = payload.get("warehouse_id")
    serial_number = payload.get("serial_number")
    barcode = payload.get("barcode")
    search_term = payload.get("search")
    
    query = db.query(ProductInstance).filter(
        ProductInstance.business_id == business_id
    )
    
    if product_id:
        query = query.filter(ProductInstance.product_id == product_id)
    
    if warehouse_id:
        query = query.filter(ProductInstance.warehouse_id == warehouse_id)
    
    # وضعیت: اگر کلید status ارسال نشود، پیش‌فرض فقط available (سازگاری با کلاینتهای قدیمی).
    # اگر status صریحاً null یا رشته خالی باشد، یا all_statuses=true، فیلتر وضعیت اعمال نمی‌شود.
    if payload.get("all_statuses") is True:
        pass
    elif "status" in payload:
        status = payload.get("status")
        if status:
            query = query.filter(ProductInstance.status == status)
    else:
        query = query.filter(ProductInstance.status == "available")
    
    if serial_number:
        query = query.filter(ProductInstance.serial_number.ilike(f"%{serial_number}%"))
    
    if barcode:
        query = query.filter(ProductInstance.barcode.ilike(f"%{barcode}%"))
    
    if search_term:
        query = query.filter(
            or_(
                ProductInstance.serial_number.ilike(f"%{search_term}%"),
                ProductInstance.barcode.ilike(f"%{search_term}%"),
            )
        )
    
    instances = query.order_by(ProductInstance.created_at.desc()).all()
    product = None
    if product_id:
        product = db.query(Product).filter(
            and_(Product.id == int(product_id), Product.business_id == business_id)
        ).first()
    
    items = []
    for inst in instances:
        items.append({
            "id": inst.id,
            "product_id": inst.product_id,
            "serial_number": inst.serial_number,
            "barcode": inst.barcode,
            "warehouse_id": inst.warehouse_id,
            "status": inst.status,
            "custom_attributes": inst.custom_attributes or {},
            "entry_date": inst.entry_date.isoformat() if inst.entry_date else None,
            "last_movement_date": inst.last_movement_date.isoformat() if inst.last_movement_date else None,
            "current_invoice_id": inst.current_invoice_id,
            **_instance_dates(inst),
            "is_expired": _instance_is_expired(inst, product) if product else False,
        })
    
    return success_response(data={"items": items, "total": len(items)}, request=request)


@router.get("/business/{business_id}/product/{product_id}/available")
@require_business_access("business_id")
def get_available_instances(
    request: Request,
    business_id: int,
    product_id: int,
    warehouse_id: Optional[int] = Query(None),
    include_expired: bool = Query(False),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """دریافت کالاهای یونیک موجود برای یک محصول."""
    if not ctx.has_business_permission("inventory", "read"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    
    # بررسی وجود محصول
    product = db.query(Product).filter(
        and_(Product.id == product_id, Product.business_id == business_id)
    ).first()
    if not product:
        raise ApiError("NOT_FOUND", "Product not found", http_status=404)
    
    query = db.query(ProductInstance).filter(
        and_(
            ProductInstance.business_id == business_id,
            ProductInstance.product_id == product_id,
            ProductInstance.status == "available",
        )
    )
    
    if warehouse_id:
        query = query.filter(ProductInstance.warehouse_id == warehouse_id)
    
    instances = query.order_by(ProductInstance.entry_date.desc()).all()
    from app.services.inventory_lot_service import is_expiry_tracked_product
    expiry_tracked = is_expiry_tracked_product(product)
    if expiry_tracked and not include_expired:
        instances = [inst for inst in instances if not _instance_is_expired(inst, product)]
    
    items = []
    for inst in instances:
        warehouse_name = None
        if inst.warehouse_id and inst.warehouse:
            warehouse_name = inst.warehouse.name
        
        items.append({
            "id": inst.id,
            "serial_number": inst.serial_number,
            "barcode": inst.barcode,
            "warehouse_id": inst.warehouse_id,
            "warehouse_name": warehouse_name,
            "custom_attributes": inst.custom_attributes or {},
            "entry_date": inst.entry_date.isoformat() if inst.entry_date else None,
            "manufacturing_date": inst.manufacturing_date.isoformat() if getattr(inst, "manufacturing_date", None) else None,
            "expiry_date": inst.expiry_date.isoformat() if getattr(inst, "expiry_date", None) else None,
            "is_expired": _instance_is_expired(inst, product) if expiry_tracked else False,
        })
    
    return success_response(data={"items": items, "total": len(items)}, request=request)


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_product_instance(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """ایجاد کالای یونیک."""
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    
    product_id = payload.get("product_id")
    serial_number = payload.get("serial_number")
    barcode = payload.get("barcode")
    warehouse_id = payload.get("warehouse_id")
    custom_attributes = payload.get("custom_attributes", {})
    entry_date = payload.get("entry_date")
    
    if not product_id:
        raise ApiError("PRODUCT_REQUIRED", "Product ID is required", http_status=400)
    
    if not serial_number:
        raise ApiError("SERIAL_REQUIRED", "Serial number is required", http_status=400)
    
    # بررسی وجود محصول
    product = db.query(Product).filter(
        and_(Product.id == product_id, Product.business_id == business_id)
    ).first()
    if not product:
        raise ApiError("NOT_FOUND", "Product not found", http_status=404)
    
    # بررسی یکتایی سریال نامبر
    existing = db.query(ProductInstance).filter(
        and_(
            ProductInstance.business_id == business_id,
            ProductInstance.serial_number == serial_number,
        )
    ).first()
    if existing:
        raise ApiError("DUPLICATE_SERIAL", f"Serial number {serial_number} already exists", http_status=409)
    
    # بررسی یکتایی بارکد (اگر ارائه شده)
    if barcode:
        existing_barcode = db.query(ProductInstance).filter(
            and_(
                ProductInstance.business_id == business_id,
                ProductInstance.barcode == barcode,
            )
        ).first()
        if existing_barcode:
            raise ApiError("DUPLICATE_BARCODE", f"Barcode {barcode} already exists", http_status=409)
    
    # بررسی وجود انبار (اگر ارائه شده)
    if warehouse_id:
        warehouse = db.query(Warehouse).filter(
            and_(Warehouse.id == warehouse_id, Warehouse.business_id == business_id)
        ).first()
        if not warehouse:
            raise ApiError("WAREHOUSE_NOT_FOUND", "Warehouse not found", http_status=404)
    
    # اعتبارسنجی custom_attributes
    if custom_attributes:
        is_valid, error_message = validate_custom_attributes(
            db=db,
            business_id=business_id,
            product_id=product_id,
            custom_attributes=custom_attributes
        )
        if not is_valid:
            raise ApiError("INVALID_CUSTOM_ATTRIBUTES", error_message or "مقادیر ویژگی‌های کالا معتبر نیست", http_status=400)
    
    manufacturing_date = _parse_instance_date(payload.get("manufacturing_date"))
    expiry_date = _parse_instance_date(payload.get("expiry_date"))
    _require_instance_dates(product, manufacturing_date, expiry_date)

    # ایجاد کالای یونیک
    instance = ProductInstance(
        business_id=business_id,
        product_id=product_id,
        serial_number=serial_number,
        barcode=barcode,
        warehouse_id=warehouse_id,
        status="available",
        custom_attributes=custom_attributes if custom_attributes else None,
        entry_date=date.fromisoformat(entry_date) if entry_date else business_today(business_id),
        manufacturing_date=manufacturing_date,
        expiry_date=expiry_date,
    )
    
    db.add(instance)
    db.flush()
    
    return success_response(
        data={
            "id": instance.id,
            "serial_number": instance.serial_number,
            "barcode": instance.barcode,
            "warehouse_id": instance.warehouse_id,
            "status": instance.status,
            "custom_attributes": instance.custom_attributes or {},
            **_instance_dates(instance),
        },
        request=request,
    )


@router.post("/business/{business_id}/bulk")
@require_business_access("business_id")
def create_bulk_product_instances(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """ایجاد چند کالای یونیک به صورت یکجا."""
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    
    instances_data = payload.get("instances", [])
    if not instances_data:
        raise ApiError("INSTANCES_REQUIRED", "At least one instance is required", http_status=400)
    
    created = []
    errors = []
    
    for idx, inst_data in enumerate(instances_data):
        try:
            product_id = inst_data.get("product_id")
            serial_number = inst_data.get("serial_number")
            barcode = inst_data.get("barcode")
            warehouse_id = inst_data.get("warehouse_id")
            custom_attributes = inst_data.get("custom_attributes", {})
            entry_date = inst_data.get("entry_date")
            
            if not product_id or not serial_number:
                errors.append({"index": idx, "error": "Product ID and serial number are required"})
                continue
            product = db.query(Product).filter(
                and_(Product.id == product_id, Product.business_id == business_id)
            ).first()
            if not product:
                errors.append({"index": idx, "error": "Product not found"})
                continue
            manufacturing_date = _parse_instance_date(inst_data.get("manufacturing_date"))
            expiry_date = _parse_instance_date(inst_data.get("expiry_date"))
            try:
                _require_instance_dates(product, manufacturing_date, expiry_date)
            except ApiError as exc:
                errors.append({"index": idx, "error": exc.message})
                continue
            
            # بررسی یکتایی
            existing = db.query(ProductInstance).filter(
                and_(
                    ProductInstance.business_id == business_id,
                    ProductInstance.serial_number == serial_number,
                )
            ).first()
            if existing:
                errors.append({"index": idx, "error": f"Serial number {serial_number} already exists"})
                continue
            
            if barcode:
                existing_barcode = db.query(ProductInstance).filter(
                    and_(
                        ProductInstance.business_id == business_id,
                        ProductInstance.barcode == barcode,
                    )
                ).first()
                if existing_barcode:
                    errors.append({"index": idx, "error": f"Barcode {barcode} already exists"})
                    continue
            
            # اعتبارسنجی custom_attributes
            if custom_attributes:
                is_valid, error_message = validate_custom_attributes(
                    db=db,
                    business_id=business_id,
                    product_id=product_id,
                    custom_attributes=custom_attributes
                )
                if not is_valid:
                    errors.append({"index": idx, "error": error_message or "مقادیر ویژگی‌های کالا معتبر نیست"})
                    continue
            
            instance = ProductInstance(
                business_id=business_id,
                product_id=product_id,
                serial_number=serial_number,
                barcode=barcode,
                warehouse_id=warehouse_id,
                status="available",
                custom_attributes=custom_attributes if custom_attributes else None,
                entry_date=date.fromisoformat(entry_date) if entry_date else business_today(business_id),
                manufacturing_date=manufacturing_date,
                expiry_date=expiry_date,
            )
            
            db.add(instance)
            created.append({
                "index": idx,
                "id": instance.id,
                "serial_number": instance.serial_number,
            })
        except Exception as e:
            errors.append({"index": idx, "error": str(e)})
    
    db.flush()
    
    return success_response(
        data={
            "created": created,
            "errors": errors,
            "total_created": len(created),
            "total_errors": len(errors),
        },
        request=request,
    )


@router.get("/business/{business_id}/search-by-code")
@require_business_access("business_id")
def search_instance_by_code(
	request: Request,
	business_id: int,
	code: str = Query(..., description="بارکد یا سریال نامبر (می‌تواند جزئی باشد)"),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""جستجوی کالای یونیک با بارکد یا سریال نامبر (پشتیبانی از جستجوی جزئی)."""
	if not ctx.has_business_permission("inventory", "read"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
	
	if not code or not code.strip():
		raise ApiError("CODE_REQUIRED", "Barcode or serial number is required", http_status=400)
	
	code_trimmed = code.strip()
	
	# ابتدا سعی می‌کنیم تطابق دقیق پیدا کنیم (برای سازگاری با کد قبلی)
	exact_query = db.query(ProductInstance).filter(
		and_(
			ProductInstance.business_id == business_id,
			or_(
				ProductInstance.barcode == code_trimmed,
				ProductInstance.serial_number == code_trimmed,
			),
		)
	)
	
	exact_instance = exact_query.first()
	
	# اگر تطابق دقیق پیدا شد، همان را برگردان
	if exact_instance:
		return success_response(
			data=_instance_search_payload(exact_instance),
			request=request,
		)
	
	# اگر تطابق دقیق پیدا نشد، جستجوی جزئی در کالاهای یونیک انجام می‌دهیم
	partial_query = db.query(ProductInstance).filter(
		and_(
			ProductInstance.business_id == business_id,
			or_(
				ProductInstance.barcode.ilike(f"%{code_trimmed}%"),
				ProductInstance.serial_number.ilike(f"%{code_trimmed}%"),
			),
		)
	)
	
	instances = partial_query.order_by(ProductInstance.created_at.desc()).limit(20).all()
	
	if not instances:
		# fallback: جستجو در بارکدهای عمومی کالا (products.general_barcodes)
		code_norm = code_trimmed.lower()
		product_query = db.query(Product).filter(Product.business_id == business_id)

		# تلاش برای تطابق دقیق توکن از جدول alias
		exact_product_by_alias = (
			product_query.join(
				ProductGeneralBarcodeAlias,
				and_(
					ProductGeneralBarcodeAlias.product_id == Product.id,
					ProductGeneralBarcodeAlias.business_id == business_id,
				),
			)
			.filter(ProductGeneralBarcodeAlias.token_normalized == code_norm)
			.first()
		)

		if exact_product_by_alias:
			return success_response(
				data={
					"id": None,
					"product_id": exact_product_by_alias.id,
					"product_name": exact_product_by_alias.name,
					"serial_number": None,
					"barcode": code_trimmed,
					"warehouse_id": None,
					"warehouse_name": None,
					"status": "general_barcode",
					"custom_attributes": {},
					"entry_date": None,
				},
				request=request,
			)

		# جستجوی جزئی در alias و رشته خام general_barcodes
		partial_products = (
			product_query.outerjoin(
				ProductGeneralBarcodeAlias,
				and_(
					ProductGeneralBarcodeAlias.product_id == Product.id,
					ProductGeneralBarcodeAlias.business_id == business_id,
				),
			)
			.filter(
				or_(
					Product.general_barcodes.ilike(f"%{code_trimmed}%"),
					func.lower(ProductGeneralBarcodeAlias.token_normalized).ilike(f"%{code_norm}%"),
				)
			)
			.order_by(Product.created_at.desc())
			.limit(20)
			.distinct()
			.all()
		)

		if not partial_products:
			raise ApiError("NOT_FOUND", "Product instance not found", http_status=404)

		if len(partial_products) == 1:
			product = partial_products[0]
			return success_response(
				data={
					"id": None,
					"product_id": product.id,
					"product_name": product.name,
					"serial_number": None,
					"barcode": code_trimmed,
					"warehouse_id": None,
					"warehouse_name": None,
					"status": "general_barcode",
					"custom_attributes": {},
					"entry_date": None,
				},
				request=request,
			)

		items = []
		for product in partial_products:
			items.append({
				"id": None,
				"product_id": product.id,
				"product_name": product.name,
				"serial_number": None,
				"barcode": code_trimmed,
				"warehouse_id": None,
				"warehouse_name": None,
				"status": "general_barcode",
				"custom_attributes": {},
				"entry_date": None,
			})

		return success_response(
			data={
				"items": items,
				"total": len(items),
				"multiple_results": True,
			},
			request=request,
		)
	
	# اگر فقط یک نتیجه پیدا شد، همان را برگردان (برای سازگاری با API قبلی)
	if len(instances) == 1:
		return success_response(
			data=_instance_search_payload(instances[0]),
			request=request,
		)
	
	# اگر چند نتیجه پیدا شد، لیست را برگردان
	items = [_instance_search_payload(instance) for instance in instances]
	
	return success_response(
		data={
			"items": items,
			"total": len(items),
			"multiple_results": True,
		},
		request=request,
	)


@router.get("/business/{business_id}/{instance_id}")
@require_business_access("business_id")
def get_product_instance(
    request: Request,
    business_id: int,
    instance_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """دریافت اطلاعات یک کالای یونیک."""
    if not ctx.has_business_permission("inventory", "read"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    
    instance = db.query(ProductInstance).filter(
        and_(
            ProductInstance.id == instance_id,
            ProductInstance.business_id == business_id,
        )
    ).first()
    
    if not instance:
        raise ApiError("NOT_FOUND", "Product instance not found", http_status=404)
    
    warehouse_name = None
    if instance.warehouse_id and instance.warehouse:
        warehouse_name = instance.warehouse.name
    
    product_name = None
    if instance.product:
        product_name = instance.product.name
    
    return success_response(
        data={
            "id": instance.id,
            "product_id": instance.product_id,
            "product_name": product_name,
            "serial_number": instance.serial_number,
            "barcode": instance.barcode,
            "warehouse_id": instance.warehouse_id,
            "warehouse_name": warehouse_name,
            "status": instance.status,
            "custom_attributes": instance.custom_attributes or {},
            "entry_date": instance.entry_date.isoformat() if instance.entry_date else None,
            "last_movement_date": instance.last_movement_date.isoformat() if instance.last_movement_date else None,
            "current_invoice_id": instance.current_invoice_id,
            **_instance_dates(instance),
        },
        request=request,
    )


@router.put("/business/{business_id}/{instance_id}")
@require_business_access("business_id")
def update_product_instance(
    request: Request,
    business_id: int,
    instance_id: int,
    payload: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """به‌روزرسانی کالای یونیک."""
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    
    instance = db.query(ProductInstance).filter(
        and_(
            ProductInstance.id == instance_id,
            ProductInstance.business_id == business_id,
        )
    ).first()
    
    if not instance:
        raise ApiError("NOT_FOUND", "Product instance not found", http_status=404)
    
    # به‌روزرسانی فیلدها
    if "barcode" in payload:
        barcode = payload.get("barcode")
        if barcode:
            existing = db.query(ProductInstance).filter(
                and_(
                    ProductInstance.business_id == business_id,
                    ProductInstance.barcode == barcode,
                    ProductInstance.id != instance_id,
                )
            ).first()
            if existing:
                raise ApiError("DUPLICATE_BARCODE", f"Barcode {barcode} already exists", http_status=409)
        instance.barcode = barcode
    
    if "warehouse_id" in payload:
        warehouse_id = payload.get("warehouse_id")
        if warehouse_id:
            warehouse = db.query(Warehouse).filter(
                and_(Warehouse.id == warehouse_id, Warehouse.business_id == business_id)
            ).first()
            if not warehouse:
                raise ApiError("WAREHOUSE_NOT_FOUND", "Warehouse not found", http_status=404)
        instance.warehouse_id = warehouse_id
    
    if "status" in payload:
        instance.status = payload.get("status")
    
    if "custom_attributes" in payload:
        custom_attributes = payload.get("custom_attributes")
        # اعتبارسنجی custom_attributes
        if custom_attributes:
            is_valid, error_message = validate_custom_attributes(
                db=db,
                business_id=business_id,
                product_id=instance.product_id,
                custom_attributes=custom_attributes
            )
            if not is_valid:
                raise ApiError("INVALID_CUSTOM_ATTRIBUTES", error_message or "مقادیر ویژگی‌های کالا معتبر نیست", http_status=400)
        instance.custom_attributes = custom_attributes
    
    if "last_movement_date" in payload:
        movement_date = payload.get("last_movement_date")
        if movement_date:
            instance.last_movement_date = date.fromisoformat(movement_date) if isinstance(movement_date, str) else movement_date
    if "manufacturing_date" in payload:
        instance.manufacturing_date = _parse_instance_date(payload.get("manufacturing_date"))
    if "expiry_date" in payload:
        instance.expiry_date = _parse_instance_date(payload.get("expiry_date"))
    product = db.query(Product).filter(
        and_(Product.id == instance.product_id, Product.business_id == business_id)
    ).first()
    if product is not None:
        _require_instance_dates(product, instance.manufacturing_date, instance.expiry_date)
    
    db.flush()
    
    return success_response(
        data={
            "id": instance.id,
            "serial_number": instance.serial_number,
            "barcode": instance.barcode,
            "warehouse_id": instance.warehouse_id,
            "status": instance.status,
            "custom_attributes": instance.custom_attributes or {},
            **_instance_dates(instance),
        },
        request=request,
    )


@router.delete("/business/{business_id}/{instance_id}")
@require_business_access("business_id")
def delete_product_instance(
    request: Request,
    business_id: int,
    instance_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """حذف کالای یونیک."""
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    
    instance = db.query(ProductInstance).filter(
        and_(
            ProductInstance.id == instance_id,
            ProductInstance.business_id == business_id,
        )
    ).first()
    
    if not instance:
        raise ApiError("NOT_FOUND", "Product instance not found", http_status=404)
    
    # بررسی اینکه کالا فروخته نشده باشد
    if instance.status == "sold":
        raise ApiError("CANNOT_DELETE_SOLD", "Cannot delete sold product instance", http_status=400)
    
    db.delete(instance)
    db.flush()
    
    return success_response(data={"deleted": True}, request=request)


@router.post("/business/{business_id}/product/{product_id}/convert-to-unique")
@require_business_access("business_id")
def convert_product_to_unique(
	request: Request,
	business_id: int,
	product_id: int,
	payload: Dict[str, Any] = Body(default={}),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""
	تبدیل کالای فله‌ای به یونیک و ایجاد instance ها برای موجودی فعلی.
	
	این endpoint:
	1. موجودی فعلی کالا را به تفکیک انبار محاسبه می‌کند
	2. برای هر واحد موجودی، یک instance ایجاد می‌کند
	3. inventory_mode را به "unique" تغییر می‌دهد
	
	پارامترهای payload:
	- auto_generate_serial: اگر true باشد، سریال نامبر به صورت خودکار تولید می‌شود (پیش‌فرض: true)
	- serial_prefix: پیشوند برای سریال نامبر (پیش‌فرض: کد کالا)
	- create_for_existing_stock: اگر true باشد، برای موجودی فعلی instance ایجاد می‌کند (پیش‌فرض: true)
	"""
	if not ctx.has_business_permission("inventory", "write"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
	
	# بررسی وجود کالا
	product = db.query(Product).filter(
		and_(Product.id == product_id, Product.business_id == business_id)
	).first()
	if not product:
		raise ApiError("NOT_FOUND", "Product not found", http_status=404)
	
	# بررسی اینکه کالا در حالت bulk است
	if product.inventory_mode == "unique":
		raise ApiError("ALREADY_UNIQUE", "Product is already in unique mode", http_status=400)
	
	# بررسی اینکه کالا موجودی را ردیابی می‌کند
	if not product.track_inventory:
		raise ApiError("NOT_TRACKING_INVENTORY", "Product does not track inventory", http_status=400)
	
	# پارامترها
	auto_generate_serial = payload.get("auto_generate_serial", True)
	serial_prefix = payload.get("serial_prefix", product.code or f"PRD{product_id}")
	create_for_existing_stock = payload.get("create_for_existing_stock", True)
	
	from app.services.warehouse_service import get_warehouse_stock_report
	from app.services.inventory_lot_service import (
		is_expiry_tracked_product,
		list_lot_balances,
		unit_dates_from_lot_balances,
	)

	today = business_today(business_id)
	stock_report = get_warehouse_stock_report(
		db=db,
		business_id=business_id,
		query={
			"product_ids": [str(product_id)],
			"as_of_date": today.isoformat(),
			"include_zero": False,
		},
	)
	lot_queues: Dict[int, list] = {}
	if is_expiry_tracked_product(product):
		for item in stock_report.get("items", []):
			wh_id = item.get("warehouse_id")
			qty = int(item.get("quantity", 0) or 0)
			if not wh_id or qty <= 0:
				continue
			balances = list_lot_balances(
				db, business_id, product_id, int(wh_id), today, sellable_only=False
			)
			lot_queues[int(wh_id)] = unit_dates_from_lot_balances(balances, qty)
	
	created_instances = []
	errors = []
	
	if create_for_existing_stock:
		# ایجاد instance برای موجودی فعلی
		for item in stock_report.get("items", []):
			warehouse_id = item.get("warehouse_id")
			quantity = int(item.get("quantity", 0))
			
			if quantity <= 0:
				continue
			
			# ایجاد instance برای هر واحد
			for i in range(quantity):
				try:
					# تولید سریال نامبر
					if auto_generate_serial:
						# شمارنده برای سریال نامبر
						existing_count = db.query(ProductInstance).filter(
							ProductInstance.business_id == business_id
						).count()
						serial_number = f"{serial_prefix}-{existing_count + i + 1:06d}"
					else:
						# اگر خودکار نباشد، باید از کاربر دریافت شود
						# در این حالت، باید endpoint دیگری برای ایجاد دستی استفاده شود
						serial_number = f"{serial_prefix}-{i + 1:06d}"
					
					# بررسی یکتایی سریال نامبر
					existing = db.query(ProductInstance).filter(
						and_(
							ProductInstance.business_id == business_id,
							ProductInstance.serial_number == serial_number,
						)
					).first()
					if existing:
						# اگر تکراری بود، شماره دیگری امتحان کن
						counter = 1
						while existing:
							serial_number = f"{serial_prefix}-{existing_count + i + 1 + counter:06d}"
							existing = db.query(ProductInstance).filter(
								and_(
									ProductInstance.business_id == business_id,
									ProductInstance.serial_number == serial_number,
								)
							).first()
							counter += 1
					
					mfg = exp = None
					queue = lot_queues.get(int(warehouse_id)) if warehouse_id is not None else None
					if queue:
						mfg_raw, exp_raw = queue.pop(0)
						if mfg_raw:
							mfg = date.fromisoformat(str(mfg_raw)[:10])
						if exp_raw:
							exp = date.fromisoformat(str(exp_raw)[:10])
					instance = ProductInstance(
						business_id=business_id,
						product_id=product_id,
						serial_number=serial_number,
						barcode=None,
						warehouse_id=warehouse_id,
						status="available",
						custom_attributes=None,
						entry_date=today,
						manufacturing_date=mfg,
						expiry_date=exp,
					)
					
					db.add(instance)
					db.flush()
					
					created_instances.append({
						"id": instance.id,
						"serial_number": instance.serial_number,
						"warehouse_id": instance.warehouse_id,
						"manufacturing_date": mfg.isoformat() if mfg else None,
						"expiry_date": exp.isoformat() if exp else None,
					})
				except Exception as e:
					errors.append({
						"warehouse_id": warehouse_id,
						"index": i,
						"error": str(e),
					})
	
	# تغییر inventory_mode به unique
	product.inventory_mode = "unique"
	
	# اگر track_serial در payload مشخص شده باشد، آن را تنظیم کن
	if "track_serial" in payload:
		product.track_serial = bool(payload["track_serial"])
	else:
		# به صورت پیش‌فرض، اگر instance ایجاد شد، track_serial را true کن
		if created_instances:
			product.track_serial = True
	
	if "track_barcode" in payload:
		product.track_barcode = bool(payload["track_barcode"])
	
	db.flush()
	
	return success_response(
		data={
			"product_id": product_id,
			"inventory_mode": "unique",
			"created_instances_count": len(created_instances),
			"created_instances": created_instances[:100],  # فقط 100 تا اول را برگردان
			"errors": errors,
			"stock_summary": {
				"total_warehouses": len(set(item.get("warehouse_id") for item in stock_report.get("items", []) if item.get("warehouse_id"))),
				"total_quantity": sum(item.get("quantity", 0) for item in stock_report.get("items", [])),
			},
		},
		request=request,
	)

