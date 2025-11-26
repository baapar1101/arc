# Removed __future__ annotations to fix OpenAPI schema generation

from typing import Dict, Any, List, Optional
from fastapi import APIRouter, Depends, Request, Body, Query
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_
from datetime import date

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import success_response, ApiError
from adapters.db.models.product_instance import ProductInstance
from adapters.db.models.product import Product
from adapters.db.models.warehouse import Warehouse


router = APIRouter(prefix="/product-instances", tags=["product_instances"])


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
    status = payload.get("status", "available")
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
    
    if status:
        query = query.filter(ProductInstance.status == status)
    
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
        })
    
    return success_response(data={"items": items, "total": len(items)}, request=request)


@router.get("/business/{business_id}/product/{product_id}/available")
@require_business_access("business_id")
def get_available_instances(
    request: Request,
    business_id: int,
    product_id: int,
    warehouse_id: Optional[int] = Query(None),
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
    
    # ایجاد کالای یونیک
    instance = ProductInstance(
        business_id=business_id,
        product_id=product_id,
        serial_number=serial_number,
        barcode=barcode,
        warehouse_id=warehouse_id,
        status="available",
        custom_attributes=custom_attributes if custom_attributes else None,
        entry_date=date.fromisoformat(entry_date) if entry_date else date.today(),
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
            
            instance = ProductInstance(
                business_id=business_id,
                product_id=product_id,
                serial_number=serial_number,
                barcode=barcode,
                warehouse_id=warehouse_id,
                status="available",
                custom_attributes=custom_attributes if custom_attributes else None,
                entry_date=date.fromisoformat(entry_date) if entry_date else date.today(),
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
	code: str = Query(..., description="بارکد یا سریال نامبر"),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""جستجوی کالای یونیک با بارکد یا سریال نامبر."""
	if not ctx.has_business_permission("inventory", "read"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
	
	if not code or not code.strip():
		raise ApiError("CODE_REQUIRED", "Barcode or serial number is required", http_status=400)
	
	code_trimmed = code.strip()
	
	# جستجو در بارکد و سریال نامبر
	query = db.query(ProductInstance).filter(
		and_(
			ProductInstance.business_id == business_id,
			ProductInstance.status == "available",
			or_(
				ProductInstance.barcode == code_trimmed,
				ProductInstance.serial_number == code_trimmed,
			),
		)
	)
	
	instance = query.first()
	
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
        instance.custom_attributes = payload.get("custom_attributes")
    
    if "last_movement_date" in payload:
        movement_date = payload.get("last_movement_date")
        if movement_date:
            instance.last_movement_date = date.fromisoformat(movement_date) if isinstance(movement_date, str) else movement_date
    
    db.flush()
    
    return success_response(
        data={
            "id": instance.id,
            "serial_number": instance.serial_number,
            "barcode": instance.barcode,
            "warehouse_id": instance.warehouse_id,
            "status": instance.status,
            "custom_attributes": instance.custom_attributes or {},
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
	from datetime import date as date_type
	
	# محاسبه موجودی فعلی به تفکیک انبار
	stock_report = get_warehouse_stock_report(
		db=db,
		business_id=business_id,
		query={
			"product_ids": [str(product_id)],
			"as_of_date": date_type.today().isoformat(),
			"include_zero": False,
		},
	)
	
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
					
					instance = ProductInstance(
						business_id=business_id,
						product_id=product_id,
						serial_number=serial_number,
						barcode=None,  # می‌تواند بعداً اضافه شود
						warehouse_id=warehouse_id,
						status="available",
						custom_attributes=None,
						entry_date=date_type.today(),
					)
					
					db.add(instance)
					db.flush()
					
					created_instances.append({
						"id": instance.id,
						"serial_number": instance.serial_number,
						"warehouse_id": instance.warehouse_id,
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

