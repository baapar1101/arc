from __future__ import annotations

from typing import Any, Dict, List, Optional
from decimal import Decimal
from datetime import datetime, date

from sqlalchemy.orm import Session
from sqlalchemy import and_

from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.product import Product
from adapters.db.models.account import Account
from adapters.db.models.fiscal_year import FiscalYear
from app.core.responses import ApiError
from adapters.db.models.warehouse import Warehouse
from adapters.db.repositories.warehouse_repository import WarehouseRepository
from adapters.api.v1.schema_models.warehouse import WarehouseCreateRequest, WarehouseUpdateRequest
from adapters.api.v1.schemas import QueryInfo, FilterItem
from app.services.query_service import QueryService


def _get_current_fiscal_year(db: Session, business_id: int) -> FiscalYear:
	fy = db.query(FiscalYear).filter(and_(FiscalYear.business_id == business_id, FiscalYear.is_last == True)).first()
	if not fy:
		raise ApiError("NO_FISCAL_YEAR", "No active fiscal year found for this business", http_status=400)
	return fy


def _build_wh_code(prefix_base: str) -> str:
	today = datetime.now().date()
	return f"{prefix_base}-{today.strftime('%Y%m%d')}-{int(datetime.utcnow().timestamp())%100000}"


def _generate_auto_warehouse_code(db: Session, business_id: int) -> str:
	"""تولید کد خودکار برای انبار: WH-00001, WH-00002, ..."""
	from sqlalchemy import func, select
	
	# دریافت آخرین کد انبار
	last_warehouse = (
		db.query(Warehouse)
		.filter(Warehouse.business_id == business_id)
		.order_by(Warehouse.id.desc())
		.first()
	)
	
	if last_warehouse and last_warehouse.code:
		# استخراج عدد از آخر کد (فرمت WH-00001)
		import re
		numbers = re.findall(r'\d+', last_warehouse.code)
		if numbers:
			try:
				last_number = int(numbers[-1])
				return f"WH-{last_number + 1:05d}"
			except ValueError:
				pass
	
	# اگر انبار قبلی نداشت یا فرمت نامعتبر بود
	max_id = db.execute(select(func.max(Warehouse.id))).scalar() or 0
	return f"WH-{max_id + 1:05d}"


def create_from_invoice(
	db: Session,
	business_id: int,
	invoice: Document,
	lines: List[Dict[str, Any]],
	wh_doc_type: str,
	created_by_user_id: Optional[int] = None,
	extra_data: Optional[Dict[str, Any]] = None,
) -> WarehouseDocument:
	"""ساخت حواله انبار draft از روی فاکتور (بدون پست)."""
	fy = _get_current_fiscal_year(db, business_id)
	code = _build_wh_code("WH")
	
	# خواندن انبار کلی از سطح سند فاکتور (extra_info.warehouse_id)
	# این انبار به سطح سند حواله منتقل می‌شود
	invoice_extra_info = invoice.extra_info or {}
	invoice_warehouse_id = invoice_extra_info.get("warehouse_id")
	warehouse_id_from = None
	warehouse_id_to = None
	
	# تعیین انبار سطح سند حواله بر اساس نوع حواله و انبار فاکتور
	if invoice_warehouse_id:
		try:
			invoice_warehouse_id = int(invoice_warehouse_id)
			if wh_doc_type in ("issue", "production_out"):
				# برای حواله خروج: انبار فاکتور به warehouse_id_from منتقل می‌شود
				warehouse_id_from = invoice_warehouse_id
			elif wh_doc_type in ("receipt", "production_in"):
				# برای حواله ورود: انبار فاکتور به warehouse_id_to منتقل می‌شود
				warehouse_id_to = invoice_warehouse_id
		except (ValueError, TypeError):
			pass  # اگر تبدیل به int ناموفق بود، نادیده می‌گیریم
	
	# آماده‌سازی extra_info با فیلدهای ارسال
	extra_data = extra_data or {}
	delivery_fields = {
		"description": extra_data.get("description"),
		"delivery_method": extra_data.get("delivery_method"),
		"carrier_name": extra_data.get("carrier_name"),
		"recipient_name": extra_data.get("recipient_name"),
		"recipient_phone": extra_data.get("recipient_phone"),
		"tracking_number": extra_data.get("tracking_number"),
	}
	# حذف فیلدهای None
	delivery_fields = {k: v for k, v in delivery_fields.items() if v is not None}
	extra_info = delivery_fields if delivery_fields else None
	
	wh = WarehouseDocument(
		business_id=business_id,
		fiscal_year_id=fy.id,
		code=code,
		document_date=invoice.document_date,
		status="draft",
		doc_type=wh_doc_type,
		warehouse_id_from=warehouse_id_from,
		warehouse_id_to=warehouse_id_to,
		source_type="invoice",
		source_document_id=invoice.id,
		created_by_user_id=created_by_user_id,
		extra_info=extra_info,
	)
	db.add(wh)
	db.flush()
	for ln in lines:
		pid = ln.get("product_id")
		qty = Decimal(str(ln.get("quantity") or 0))
		if not pid or qty <= 0:
			continue

		extra = ln.get("extra_info") or {}
		movement_override = ln.get("movement")
		mv = movement_override or extra.get("movement") or ("out" if wh_doc_type in ("issue", "production_out") else "in")

		# دریافت warehouse_id از سطح ردیف خط یا از extra_info
		# منطق fallback: اگر انبار در سطح ردیف مشخص نشده باشد، از انبار سطح سند حواله استفاده می‌شود
		# (که خود از extra_info.warehouse_id فاکتور آمده است)
		warehouse_id = ln.get("warehouse_id") or extra.get("warehouse_id")
		try:
			warehouse_id = int(warehouse_id) if warehouse_id is not None else None
		except Exception:
			warehouse_id = None
		
		# اگر انبار در سطح ردیف مشخص نشده، از انبار سطح سند حواله استفاده کن
		if not warehouse_id:
			if mv == "out":
				warehouse_id = warehouse_id_from
			elif mv == "in":
				warehouse_id = warehouse_id_to

		wline = WarehouseDocumentLine(
			warehouse_document_id=wh.id,
			product_id=int(pid),
			warehouse_id=warehouse_id,
			movement=str(mv),
			quantity=qty,
			extra_info=extra,
		)
		db.add(wline)
	db.flush()
	return wh


def create_manual_warehouse_document(
	db: Session,
	business_id: int,
	user_id: int,
	data: Dict[str, Any],
) -> WarehouseDocument:
	"""ایجاد حواله انبار دستی (بدون فاکتور)."""
	from datetime import date as date_type
	
	# اعتبارسنجی ورودی
	doc_type = data.get("doc_type")
	if not doc_type or doc_type not in ("receipt", "issue", "transfer", "adjustment", "production_in", "production_out"):
		raise ApiError("INVALID_DOC_TYPE", "نوع حواله معتبر نیست", http_status=400)
	
	document_date_str = data.get("document_date")
	if not document_date_str:
		raise ApiError("DATE_REQUIRED", "تاریخ حواله الزامی است", http_status=400)
	
	try:
		document_date = date_type.fromisoformat(document_date_str) if isinstance(document_date_str, str) else document_date_str
	except Exception:
		raise ApiError("INVALID_DATE", "فرمت تاریخ معتبر نیست", http_status=400)
	
	lines_data = data.get("lines", [])
	if not lines_data:
		raise ApiError("LINES_REQUIRED", "حواله باید حداقل یک خط داشته باشد", http_status=400)
	
	# بررسی انبارها برای انواع مختلف حواله
	warehouse_id_from = data.get("warehouse_id_from")
	warehouse_id_to = data.get("warehouse_id_to")
	
	if doc_type == "transfer":
		if not warehouse_id_from or not warehouse_id_to:
			raise ApiError("WAREHOUSES_REQUIRED", "برای حواله انتقال، انبار مبدا و مقصد الزامی است", http_status=400)
		if int(warehouse_id_from) == int(warehouse_id_to):
			raise ApiError("INVALID_WAREHOUSES", "انبار مبدا و مقصد نمی‌توانند یکسان باشند", http_status=400)
	elif doc_type in ("issue", "production_out"):
		if not warehouse_id_from:
			raise ApiError("WAREHOUSE_REQUIRED", "برای حواله خروج، انبار الزامی است", http_status=400)
	elif doc_type in ("receipt", "production_in"):
		if not warehouse_id_to:
			raise ApiError("WAREHOUSE_REQUIRED", "برای حواله ورود، انبار الزامی است", http_status=400)
	
	# بررسی انبارها در business
	if warehouse_id_from:
		wh_from = db.query(Warehouse).filter(and_(Warehouse.id == int(warehouse_id_from), Warehouse.business_id == business_id)).first()
		if not wh_from:
			raise ApiError("WAREHOUSE_NOT_FOUND", "انبار مبدا یافت نشد", http_status=404)
	
	if warehouse_id_to:
		wh_to = db.query(Warehouse).filter(and_(Warehouse.id == int(warehouse_id_to), Warehouse.business_id == business_id)).first()
		if not wh_to:
			raise ApiError("WAREHOUSE_NOT_FOUND", "انبار مقصد یافت نشد", http_status=404)
	
	# بررسی سال مالی
	fy = _get_current_fiscal_year(db, business_id)
	if document_date < fy.start_date or (fy.end_date and document_date > fy.end_date):
		raise ApiError("DATE_OUT_OF_RANGE", f"تاریخ باید در بازه سال مالی ({fy.start_date} تا {fy.end_date or 'نامحدود'}) باشد", http_status=400)
	
	# آماده‌سازی extra_info با فیلدهای ارسال
	existing_extra_info = data.get("extra_info") or {}
	if not isinstance(existing_extra_info, dict):
		existing_extra_info = {}
	
	# استخراج فیلدهای ارسال از payload
	delivery_fields = {
		"description": data.get("description"),
		"delivery_method": data.get("delivery_method"),
		"carrier_name": data.get("carrier_name"),
		"recipient_name": data.get("recipient_name"),
		"recipient_phone": data.get("recipient_phone"),
		"tracking_number": data.get("tracking_number"),
	}
	# حذف فیلدهای None
	delivery_fields = {k: v for k, v in delivery_fields.items() if v is not None}
	
	# ادغام با extra_info موجود
	extra_info = {**existing_extra_info, **delivery_fields}
	
	# ایجاد حواله
	code = _build_wh_code("WH")
	wh = WarehouseDocument(
		business_id=business_id,
		fiscal_year_id=fy.id,
		code=code,
		document_date=document_date,
		status="draft",
		doc_type=doc_type,
		warehouse_id_from=int(warehouse_id_from) if warehouse_id_from else None,
		warehouse_id_to=int(warehouse_id_to) if warehouse_id_to else None,
		source_type="manual",
		source_document_id=None,
		created_by_user_id=user_id,
		extra_info=extra_info if extra_info else None,
	)
	db.add(wh)
	db.flush()
	
	# ایجاد خطوط
	for i, ln in enumerate(lines_data, start=1):
		pid = ln.get("product_id")
		if not pid:
			raise ApiError("PRODUCT_REQUIRED", f"خط {i}: شناسه محصول الزامی است", http_status=400)
		
		qty = Decimal(str(ln.get("quantity") or 0))
		if qty <= 0:
			raise ApiError("INVALID_QUANTITY", f"خط {i}: تعداد باید مثبت باشد", http_status=400)
		
		# بررسی محصول
		product = db.query(Product).filter(and_(Product.id == int(pid), Product.business_id == business_id)).first()
		if not product:
			raise ApiError("PRODUCT_NOT_FOUND", f"خط {i}: محصول یافت نشد", http_status=404)
		
		# بررسی و ایجاد instance های کالای یونیک (فقط برای حواله ورود)
		instance_data = ln.get("instance_data")
		instance_ids = []
		
		if instance_data and isinstance(instance_data, list) and len(instance_data) > 0:
			# بررسی اینکه کالا یونیک است
			if product.inventory_mode != "unique":
				raise ApiError("NOT_UNIQUE_PRODUCT", f"خط {i}: این کالا در حالت یونیک نیست", http_status=400)
			
			# برای حواله ورود، instance ها را ایجاد می‌کنیم
			if doc_type in ("receipt", "production_in"):
				from adapters.db.models.product_instance import ProductInstance
				from datetime import date as date_type
				
				for inst_idx, inst_data in enumerate(instance_data, start=1):
					if not isinstance(inst_data, dict):
						raise ApiError("INVALID_INSTANCE_DATA", f"خط {i}، واحد {inst_idx}: اطلاعات instance معتبر نیست", http_status=400)
					
					serial_number = inst_data.get("serial_number")
					barcode = inst_data.get("barcode")
					custom_attributes = inst_data.get("custom_attributes")
					
					if not serial_number and product.track_serial:
						raise ApiError("SERIAL_REQUIRED", f"خط {i}، واحد {inst_idx}: شماره سریال الزامی است", http_status=400)
					
					# بررسی یکتایی سریال نامبر
					if serial_number:
						existing = db.query(ProductInstance).filter(
							and_(
								ProductInstance.business_id == business_id,
								ProductInstance.serial_number == serial_number,
							)
						).first()
						if existing:
							raise ApiError("DUPLICATE_SERIAL", f"خط {i}، واحد {inst_idx}: شماره سریال {serial_number} تکراری است", http_status=409)
					
					# بررسی یکتایی بارکد
					if barcode:
						existing_barcode = db.query(ProductInstance).filter(
							and_(
								ProductInstance.business_id == business_id,
								ProductInstance.barcode == barcode,
							)
						).first()
						if existing_barcode:
							raise ApiError("DUPLICATE_BARCODE", f"خط {i}، واحد {inst_idx}: بارکد {barcode} تکراری است", http_status=409)
					
					# تعیین انبار
					instance_warehouse_id = line_wh if doc_type in ("receipt", "production_in") else None
					
					# ایجاد instance
					instance = ProductInstance(
						business_id=business_id,
						product_id=int(pid),
						serial_number=serial_number or f"SN-{wh.id}-{i}-{inst_idx}",  # اگر track_serial false باشد
						barcode=barcode,
						warehouse_id=int(instance_warehouse_id) if instance_warehouse_id else None,
						status="available",
						custom_attributes=custom_attributes if custom_attributes else None,
						entry_date=document_date,
					)
					db.add(instance)
					db.flush()  # برای دریافت ID
					instance_ids.append(instance.id)
		
		# برای حواله خروج، instance_ids را پردازش می‌کنیم
		instance_ids_from_line = ln.get("instance_ids")
		if instance_ids_from_line and isinstance(instance_ids_from_line, list) and len(instance_ids_from_line) > 0:
			from adapters.db.models.product_instance import ProductInstance
			
			# بررسی اینکه کالا یونیک است
			if product.inventory_mode != "unique":
				raise ApiError("NOT_UNIQUE_PRODUCT", f"خط {i}: این کالا در حالت یونیک نیست", http_status=400)
			
			# برای حواله خروج، instance ها را به‌روزرسانی می‌کنیم
			if doc_type in ("issue", "production_out"):
				for inst_id in instance_ids_from_line:
					instance = db.query(ProductInstance).filter(
						and_(
							ProductInstance.id == int(inst_id),
							ProductInstance.business_id == business_id,
							ProductInstance.product_id == int(pid),
							ProductInstance.status == "available",
						)
					).first()
					
					if not instance:
						raise ApiError("INSTANCE_NOT_FOUND", f"خط {i}: کالای یونیک با ID {inst_id} یافت نشد یا در دسترس نیست", http_status=404)
					
					# به‌روزرسانی instance
					instance.warehouse_id = None  # از انبار خارج می‌شود
					instance.status = "sold"  # یا می‌توانیم status دیگری استفاده کنیم
					instance.last_movement_date = document_date
		
		# تعیین movement و warehouse_id بر اساس نوع حواله با استفاده از منطق fallback
		# منطق fallback: اگر انبار در سطح ردیف مشخص نشده باشد، از انبار سطح سند استفاده می‌شود
		if doc_type == "transfer":
			# برای انتقال: یک خط out از مبدا و یک خط in به مقصد
			# منطق fallback: line['warehouse_id_from'] ?? warehouse_id_from (سطح سند)
			line_wh_from = ln.get("warehouse_id_from") or warehouse_id_from
			line_wh_to = ln.get("warehouse_id_to") or warehouse_id_to
			if not line_wh_from or not line_wh_to:
				raise ApiError("WAREHOUSES_REQUIRED", f"خط {i}: برای انتقال، انبار مبدا و مقصد باید مشخص باشد (در سطح سند یا ردیف)", http_status=400)
			
			# اضافه کردن instance_ids به extra_info برای transfer
			extra_info_transfer = ln.get("extra_info") or {}
			if instance_ids:
				extra_info_transfer["instance_ids"] = instance_ids
			
			# ایجاد خط خروج از مبدا
			wline_out = WarehouseDocumentLine(
				warehouse_document_id=wh.id,
				product_id=int(pid),
				warehouse_id=int(line_wh_from),
				movement="out",
				quantity=qty,
				extra_info=extra_info_transfer,
				instance_ids=instance_ids if instance_ids else None,
			)
			db.add(wline_out)
			
			# ایجاد خط ورود به مقصد
			wline_in = WarehouseDocumentLine(
				warehouse_document_id=wh.id,
				product_id=int(pid),
				warehouse_id=int(line_wh_to),
				movement="in",
				quantity=qty,
				extra_info=extra_info_transfer,
				instance_ids=instance_ids if instance_ids else None,
			)
			db.add(wline_in)
		else:
			# برای سایر انواع: movement بر اساس doc_type
			# منطق fallback برای انبار:
			# - issue/production_out: line['warehouse_id'] ?? warehouse_id_from (سطح سند)
			# - receipt/production_in: line['warehouse_id'] ?? warehouse_id_to (سطح سند)
			# - adjustment: line['warehouse_id'] ?? warehouse_id_to ?? warehouse_id_from (سطح سند)
			if doc_type in ("issue", "production_out"):
				movement = "out"
				line_wh = ln.get("warehouse_id") or warehouse_id_from
			elif doc_type in ("receipt", "production_in"):
				movement = "in"
				line_wh = ln.get("warehouse_id") or warehouse_id_to
			elif doc_type == "adjustment":
				# برای تعدیل: movement از خط گرفته می‌شود
				movement = ln.get("movement", "in")
				if movement not in ("in", "out"):
					raise ApiError("INVALID_MOVEMENT", f"خط {i}: movement باید 'in' یا 'out' باشد", http_status=400)
				# برای adjustment، انبار باید حتماً در سطح ردیف مشخص شود (fallback به سطح سند فقط برای سازگاری)
				line_wh = ln.get("warehouse_id") or warehouse_id_to or warehouse_id_from
			else:
				movement = "in"
				line_wh = ln.get("warehouse_id") or warehouse_id_to
			
			if not line_wh:
				raise ApiError("WAREHOUSE_REQUIRED", f"خط {i}: انبار الزامی است (در سطح سند یا ردیف)", http_status=400)
			
			# بررسی انبار
			wh_check = db.query(Warehouse).filter(and_(Warehouse.id == int(line_wh), Warehouse.business_id == business_id)).first()
			if not wh_check:
				raise ApiError("WAREHOUSE_NOT_FOUND", f"خط {i}: انبار یافت نشد", http_status=404)
			
			# اضافه کردن instance_ids به extra_info
			extra_info = ln.get("extra_info") or {}
			if instance_ids:
				extra_info["instance_ids"] = instance_ids
			if instance_ids_from_line:
				extra_info["instance_ids"] = instance_ids_from_line
			
			# instance_ids برای خط (از instance_ids یا instance_ids_from_line)
			line_instance_ids = instance_ids_from_line if instance_ids_from_line else (instance_ids if instance_ids else None)
			
			wline = WarehouseDocumentLine(
				warehouse_document_id=wh.id,
				product_id=int(pid),
				warehouse_id=int(line_wh),
				movement=movement,
				quantity=qty,
				extra_info=extra_info,
				instance_ids=line_instance_ids,
			)
			db.add(wline)
	
	db.flush()
	return wh


def update_warehouse_document(
	db: Session,
	business_id: int,
	wh_id: int,
	user_id: int,
	data: Dict[str, Any],
) -> WarehouseDocument:
	"""ویرایش حواله انبار (فقط draft)."""
	from datetime import date as date_type
	
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == wh_id).first()
	if not wh or wh.business_id != business_id:
		raise ApiError("NOT_FOUND", "Warehouse document not found", http_status=404)
	
	if wh.status != "draft":
		raise ApiError("NOT_EDITABLE", "فقط حواله‌های draft قابل ویرایش هستند", http_status=400)
	
	# به‌روزرسانی فیلدهای اصلی
	if "document_date" in data:
		document_date_str = data.get("document_date")
		try:
			document_date = date_type.fromisoformat(document_date_str) if isinstance(document_date_str, str) else document_date_str
		except Exception:
			raise ApiError("INVALID_DATE", "فرمت تاریخ معتبر نیست", http_status=400)
		
		fy = _get_current_fiscal_year(db, business_id)
		if document_date < fy.start_date or (fy.end_date and document_date > fy.end_date):
			raise ApiError("DATE_OUT_OF_RANGE", f"تاریخ باید در بازه سال مالی باشد", http_status=400)
		wh.document_date = document_date
	
	if "warehouse_id_from" in data:
		wh.warehouse_id_from = int(data["warehouse_id_from"]) if data["warehouse_id_from"] else None
		if wh.warehouse_id_from:
			wh_check = db.query(Warehouse).filter(and_(Warehouse.id == wh.warehouse_id_from, Warehouse.business_id == business_id)).first()
			if not wh_check:
				raise ApiError("WAREHOUSE_NOT_FOUND", "انبار مبدا یافت نشد", http_status=404)
	
	if "warehouse_id_to" in data:
		wh.warehouse_id_to = int(data["warehouse_id_to"]) if data["warehouse_id_to"] else None
		if wh.warehouse_id_to:
			wh_check = db.query(Warehouse).filter(and_(Warehouse.id == wh.warehouse_id_to, Warehouse.business_id == business_id)).first()
			if not wh_check:
				raise ApiError("WAREHOUSE_NOT_FOUND", "انبار مقصد یافت نشد", http_status=404)
	
	# به‌روزرسانی extra_info با فیلدهای ارسال
	if "extra_info" in data or any(key in data for key in ["description", "delivery_method", "carrier_name", "recipient_name", "recipient_phone", "tracking_number"]):
		existing_extra_info = wh.extra_info or {}
		if not isinstance(existing_extra_info, dict):
			existing_extra_info = {}
		
		# اگر extra_info کامل ارسال شده، از آن استفاده کن
		if "extra_info" in data and isinstance(data["extra_info"], dict):
			existing_extra_info = data["extra_info"]
		else:
			# در غیر این صورت، فیلدهای ارسال را به extra_info اضافه کن
			delivery_fields = {
				"description": data.get("description"),
				"delivery_method": data.get("delivery_method"),
				"carrier_name": data.get("carrier_name"),
				"recipient_name": data.get("recipient_name"),
				"recipient_phone": data.get("recipient_phone"),
				"tracking_number": data.get("tracking_number"),
			}
			# فقط فیلدهایی که ارسال شده‌اند را به‌روزرسانی کن
			for key, value in delivery_fields.items():
				if key in data:
					if value is None:
						existing_extra_info.pop(key, None)
					else:
						existing_extra_info[key] = value
		
		wh.extra_info = existing_extra_info if existing_extra_info else None
	
	wh.touch()
	db.flush()
	
	# به‌روزرسانی خطوط در صورت ارسال
	if "lines" in data:
		lines_data = data.get("lines")
		if lines_data is not None:
			# حذف خطوط قدیمی
			db.query(WarehouseDocumentLine).filter(WarehouseDocumentLine.warehouse_document_id == wh.id).delete()
			db.flush()
			
			# ایجاد خطوط جدید
			for i, ln in enumerate(lines_data, start=1):
				pid = ln.get("product_id")
				if not pid:
					raise ApiError("PRODUCT_REQUIRED", f"خط {i}: شناسه محصول الزامی است", http_status=400)
				
				qty = Decimal(str(ln.get("quantity") or 0))
				if qty <= 0:
					raise ApiError("INVALID_QUANTITY", f"خط {i}: تعداد باید مثبت باشد", http_status=400)
				
				# بررسی محصول
				product = db.query(Product).filter(and_(Product.id == int(pid), Product.business_id == business_id)).first()
				if not product:
					raise ApiError("PRODUCT_NOT_FOUND", f"خط {i}: محصول یافت نشد", http_status=404)
				
				movement = ln.get("movement", "in")
				if movement not in ("in", "out"):
					raise ApiError("INVALID_MOVEMENT", f"خط {i}: movement باید 'in' یا 'out' باشد", http_status=400)
				
				# منطق fallback برای انبار: اگر انبار در سطح ردیف مشخص نشده باشد، از انبار سطح سند استفاده می‌شود
				# - برای movement="in": line['warehouse_id'] ?? wh.warehouse_id_to (سطح سند)
				# - برای movement="out": line['warehouse_id'] ?? wh.warehouse_id_from (سطح سند)
				line_wh = ln.get("warehouse_id")
				if not line_wh:
					# اگر انبار در خط مشخص نشده، از حواله استفاده کن (fallback به سطح سند)
					line_wh = wh.warehouse_id_to if movement == "in" else wh.warehouse_id_from
				
				if not line_wh:
					raise ApiError("WAREHOUSE_REQUIRED", f"خط {i}: انبار الزامی است (در سطح سند یا ردیف)", http_status=400)
				
				# بررسی انبار
				wh_check = db.query(Warehouse).filter(and_(Warehouse.id == int(line_wh), Warehouse.business_id == business_id)).first()
				if not wh_check:
					raise ApiError("WAREHOUSE_NOT_FOUND", f"خط {i}: انبار یافت نشد", http_status=404)
				
				wline = WarehouseDocumentLine(
					warehouse_document_id=wh.id,
					product_id=int(pid),
					warehouse_id=int(line_wh),
					movement=movement,
					quantity=qty,
					extra_info=ln.get("extra_info") or {},
				)
				db.add(wline)
			
			db.flush()
	
	return wh


def update_warehouse_document_line(
	db: Session,
	business_id: int,
	wh_id: int,
	line_id: int,
	data: Dict[str, Any],
) -> WarehouseDocumentLine:
	"""به‌روزرسانی یک خط حواله (مثلاً برای تعیین انبار)."""
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == wh_id).first()
	if not wh or wh.business_id != business_id:
		raise ApiError("NOT_FOUND", "Warehouse document not found", http_status=404)
	
	if wh.status != "draft":
		raise ApiError("NOT_EDITABLE", "فقط حواله‌های draft قابل ویرایش هستند", http_status=400)
	
	wline = db.query(WarehouseDocumentLine).filter(
		and_(
			WarehouseDocumentLine.id == line_id,
			WarehouseDocumentLine.warehouse_document_id == wh_id
		)
	).first()
	
	if not wline:
		raise ApiError("LINE_NOT_FOUND", "خط حواله یافت نشد", http_status=404)
	
	# به‌روزرسانی فیلدها
	if "warehouse_id" in data:
		warehouse_id = data.get("warehouse_id")
		if warehouse_id:
			wh_check = db.query(Warehouse).filter(and_(Warehouse.id == int(warehouse_id), Warehouse.business_id == business_id)).first()
			if not wh_check:
				raise ApiError("WAREHOUSE_NOT_FOUND", "انبار یافت نشد", http_status=404)
			wline.warehouse_id = int(warehouse_id)
		else:
			wline.warehouse_id = None
	
	if "quantity" in data:
		qty = Decimal(str(data.get("quantity") or 0))
		if qty <= 0:
			raise ApiError("INVALID_QUANTITY", "تعداد باید مثبت باشد", http_status=400)
		wline.quantity = qty
	
	if "movement" in data:
		movement = data.get("movement")
		if movement not in ("in", "out"):
			raise ApiError("INVALID_MOVEMENT", "movement باید 'in' یا 'out' باشد", http_status=400)
		wline.movement = movement
	
	if "extra_info" in data:
		wline.extra_info = data.get("extra_info")
	
	wh.touch()
	db.flush()
	return wline


def post_warehouse_document(db: Session, wh_id: int) -> Dict[str, Any]:
	"""پست حواله: کنترل کسری برای خروج‌ها و به‌روزرسانی موجودی انبار.
	اگر doc_type='transfer' باشد، یک سند حسابداری هم ایجاد می‌شود.
	توجه: محاسبات COGS و ثبت سطرهای حسابداری در بخش فاکتورها انجام می‌شود.
	"""
	from app.services.invoice_service import _ensure_stock_sufficient, _get_current_fiscal_year
	from adapters.db.models.document import Document
	from adapters.db.models.document_line import DocumentLine
	from adapters.db.models.currency import Currency
	from app.services.document_monetization_service import ensure_document_policy_allows_creation
	from datetime import datetime
	
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == wh_id).first()
	if not wh:
		raise ApiError("NOT_FOUND", "Warehouse document not found", http_status=404)
	if wh.status == "posted":
		return {"id": wh.id, "status": wh.status}

	lines = db.query(WarehouseDocumentLine).filter(WarehouseDocumentLine.warehouse_document_id == wh.id).all()
	if not lines:
		raise ApiError("NO_LINES", "حواله باید حداقل یک خط داشته باشد", http_status=400)
	
	# کنترل کسری برای خروج‌ها
	outgoing_lines = []
	for ln in lines:
		if ln.movement == "out":
			if not ln.quantity or Decimal(str(ln.quantity)) <= 0:
				raise ApiError("INVALID_QUANTITY", "تعداد باید مثبت باشد", http_status=400)
			
			if not ln.warehouse_id:
				raise ApiError("WAREHOUSE_REQUIRED", "برای خطوط خروج، انبار باید مشخص باشد", http_status=400)
			
			# بررسی اینکه محصول کنترل موجودی دارد یا نه
			product = db.query(Product).filter(Product.id == ln.product_id).first()
			if product and product.track_inventory:
				outgoing_lines.append({
					"product_id": ln.product_id,
					"quantity": float(ln.quantity),
					"extra_info": {
						"warehouse_id": ln.warehouse_id,
						"movement": "out",
						"inventory_tracked": True,
					},
				})
	
	# کنترل کسری موجودی با استفاده از تابع موجود
	if outgoing_lines:
		try:
			_ensure_stock_sufficient(
				db,
				wh.business_id,
				wh.document_date,
				outgoing_lines,
				exclude_document_id=None,  # این حواله هنوز پست نشده
			)
		except ApiError as e:
			# خطای کسری موجودی را به صورت واضح نمایش بده
			raise ApiError("INSUFFICIENT_STOCK", str(e.message), http_status=409)

	# تغییر وضعیت به posted
	wh.status = "posted"
	wh.touch()
	db.flush()
	
	# اگر doc_type='transfer' باشد، یک سند حسابداری ایجاد کن
	if wh.doc_type == "transfer":
		# دریافت currency_id (از business یا default)
		currency = db.query(Currency).filter(Currency.business_id == wh.business_id).first()
		if not currency:
			# استفاده از currency پیش‌فرض
			currency = db.query(Currency).filter(Currency.code == "IRR").first()
		if not currency:
			raise ApiError("CURRENCY_NOT_FOUND", "Currency not found", http_status=404)
		
		fiscal_year = _get_current_fiscal_year(db, wh.business_id)
		
		# ساخت کد سند (مشابه inventory_transfer_service)
		today = datetime.now().date()
		prefix = f"ITR-{today.strftime('%Y%m%d')}"
		last_doc = db.query(Document).filter(
			and_(
				Document.business_id == wh.business_id,
				Document.code.like(f"{prefix}-%"),
			)
		).order_by(Document.code.desc()).first()
		if last_doc:
			try:
				last_num = int(last_doc.code.split("-")[-1])
				next_num = last_num + 1
			except Exception:
				next_num = 1
		else:
			next_num = 1
		doc_code = f"{prefix}-{next_num:04d}"
		
		# بررسی policy
		ensure_document_policy_allows_creation(
			db,
			wh.business_id,
			document_type="inventory_transfer",
			document_date=wh.document_date,
			amount=Decimal(0),
		)
		
		# ایجاد سند حسابداری
		accounting_doc = Document(
			business_id=wh.business_id,
			fiscal_year_id=fiscal_year.id,
			code=doc_code,
			document_type="inventory_transfer",
			document_date=wh.document_date,
			currency_id=currency.id,
			created_by_user_id=wh.created_by_user_id,
			registered_at=datetime.utcnow(),
			is_proforma=False,
			description=(wh.extra_info.get("description") if wh.extra_info and isinstance(wh.extra_info, dict) else None),
			extra_info={
				"source": "warehouse_document",
				"warehouse_document_id": wh.id,
			},
		)
		db.add(accounting_doc)
		db.flush()
		
		# ایجاد خطوط حسابداری از خطوط حواله
		# برای transfer: یک خط out از مبدا و یک خط in به مقصد
		for wline in lines:
			if wline.movement == "out":
				# خط خروج از انبار مبدا
				db.add(DocumentLine(
					document_id=accounting_doc.id,
					product_id=wline.product_id,
					quantity=wline.quantity,
					debit=Decimal(0),
					credit=Decimal(0),
					description=None,
					extra_info={
						"movement": "out",
						"warehouse_id": wline.warehouse_id,
						"inventory_tracked": True,
					},
				))
			elif wline.movement == "in":
				# خط ورود به انبار مقصد
				db.add(DocumentLine(
					document_id=accounting_doc.id,
					product_id=wline.product_id,
					quantity=wline.quantity,
					debit=Decimal(0),
					credit=Decimal(0),
					description=None,
					extra_info={
						"movement": "in",
						"warehouse_id": wline.warehouse_id,
						"inventory_tracked": True,
					},
				))
		
		# لینک سند حسابداری به Warehouse Document
		if not wh.extra_info:
			wh.extra_info = {}
		elif not isinstance(wh.extra_info, dict):
			wh.extra_info = {}
		wh.extra_info["accounting_document_id"] = accounting_doc.id
		db.flush()
	
	# توجه: محاسبات COGS و ثبت سطرهای حسابداری در بخش فاکتورها انجام می‌شود
	# بخش انبارداری فقط مسئولیت مدیریت موجودی فیزیکی را دارد
	
	return {"id": wh.id, "status": wh.status}


def warehouse_document_to_dict(db: Session, wh: WarehouseDocument) -> Dict[str, Any]:
	lines = db.query(WarehouseDocumentLine).filter(WarehouseDocumentLine.warehouse_document_id == wh.id).all()
	doc_type_movement_map = {
		"receipt": "in",
		"production_in": "in",
		"issue": "out",
		"production_out": "out",
		"transfer": "out",
	}
	movement_filter = doc_type_movement_map.get(wh.doc_type)
	total_quantity = Decimal(0)
	for ln in lines:
		if movement_filter and (ln.movement or "").lower() != movement_filter:
			continue
		try:
			qty = Decimal(str(ln.quantity or 0))
		except Exception:
			qty = Decimal(0)
		if qty <= 0:
			continue
		total_quantity += qty
	if total_quantity < 0:
		total_quantity = Decimal(0)
	# استخراج فیلدهای ارسال از extra_info
	extra_info = wh.extra_info or {}
	delivery_info = {
		"description": extra_info.get("description") if isinstance(extra_info, dict) else None,
		"delivery_method": extra_info.get("delivery_method") if isinstance(extra_info, dict) else None,
		"carrier_name": extra_info.get("carrier_name") if isinstance(extra_info, dict) else None,
		"recipient_name": extra_info.get("recipient_name") if isinstance(extra_info, dict) else None,
		"recipient_phone": extra_info.get("recipient_phone") if isinstance(extra_info, dict) else None,
		"tracking_number": extra_info.get("tracking_number") if isinstance(extra_info, dict) else None,
	}
	
	return {
		"id": wh.id,
		"code": wh.code,
		"business_id": wh.business_id,
		"fiscal_year_id": wh.fiscal_year_id,
		"document_date": wh.document_date.isoformat() if wh.document_date else None,
		"status": wh.status,
		"doc_type": wh.doc_type,
		"warehouse_id_from": wh.warehouse_id_from,
		"warehouse_id_to": wh.warehouse_id_to,
		"source_type": wh.source_type,
		"source_document_id": wh.source_document_id,
		"extra_info": wh.extra_info,
		"description": delivery_info["description"],
		"delivery_method": delivery_info["delivery_method"],
		"carrier_name": delivery_info["carrier_name"],
		"recipient_name": delivery_info["recipient_name"],
		"recipient_phone": delivery_info["recipient_phone"],
		"tracking_number": delivery_info["tracking_number"],
		"total_quantity": float(total_quantity),
		"lines": [
			{
				"id": ln.id,
				"product_id": ln.product_id,
				"warehouse_id": ln.warehouse_id,
				"movement": ln.movement,
				"quantity": float(ln.quantity),
				"extra_info": ln.extra_info,
			}
			for ln in lines
		],
	}


def _to_dict(obj: Warehouse) -> Dict[str, Any]:
	return {
		"id": obj.id,
		"business_id": obj.business_id,
		"code": obj.code,
		"name": obj.name,
		"description": obj.description,
		"warehouse_keeper": obj.warehouse_keeper,
		"phone": obj.phone,
		"address": obj.address,
		"postal_code": obj.postal_code,
		"is_default": obj.is_default,
		"created_at": obj.created_at,
		"updated_at": obj.updated_at,
	}


def create_warehouse(db: Session, business_id: int, payload: WarehouseCreateRequest) -> Dict[str, Any]:
	# تولید خودکار کد در صورت عدم ارسال
	if payload.code is None or not payload.code.strip():
		code = _generate_auto_warehouse_code(db, business_id)
	else:
		code = payload.code.strip()
	
	# بررسی تکراری بودن کد
	dup = db.query(Warehouse).filter(and_(Warehouse.business_id == business_id, Warehouse.code == code)).first()
	if dup:
		raise ApiError("DUPLICATE_WAREHOUSE_CODE", "کد انبار تکراری است", http_status=400)
	
	repo = WarehouseRepository(db)
	obj = repo.create(
		business_id=business_id,
		code=code,
		name=payload.name.strip(),
		description=payload.description,
		warehouse_keeper=payload.warehouse_keeper.strip() if payload.warehouse_keeper else None,
		phone=payload.phone.strip() if payload.phone else None,
		address=payload.address.strip() if payload.address else None,
		postal_code=payload.postal_code.strip() if payload.postal_code else None,
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
		code=payload.code.strip() if isinstance(payload.code, str) and payload.code.strip() else None,
		name=payload.name.strip() if isinstance(payload.name, str) else None,
		description=payload.description,
		warehouse_keeper=payload.warehouse_keeper.strip() if isinstance(payload.warehouse_keeper, str) and payload.warehouse_keeper.strip() else None,
		phone=payload.phone.strip() if isinstance(payload.phone, str) and payload.phone.strip() else None,
		address=payload.address.strip() if isinstance(payload.address, str) and payload.address.strip() else None,
		postal_code=payload.postal_code.strip() if isinstance(payload.postal_code, str) and payload.postal_code.strip() else None,
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


def query_warehouses(db: Session, business_id: int, query_info: QueryInfo) -> Dict[str, Any]:
	# Ensure business scoping via filters
	base_filter = FilterItem(property="business_id", operator="=", value=business_id)
	merged_filters = [base_filter]
	if query_info.filters:
		merged_filters.extend(query_info.filters)

	effective_query = QueryInfo(
		sort_by=query_info.sort_by,
		sort_desc=query_info.sort_desc,
		take=query_info.take,
		skip=query_info.skip,
		search=query_info.search,
		search_fields=query_info.search_fields,
		filters=merged_filters,
	)

	results, total = QueryService.query_with_filters(Warehouse, db, effective_query)
	items = [_to_dict(w) for w in results]
	limit = max(1, effective_query.take)
	page = (effective_query.skip // limit) + 1
	total_pages = (total + limit - 1) // limit

	return {
		"items": items,
		"total": total,
		"page": page,
		"limit": limit,
		"total_pages": total_pages,
	}


def delete_warehouse_document(db: Session, business_id: int, wh_id: int) -> bool:
	"""حذف حواله انبار (فقط draft)."""
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == wh_id).first()
	if not wh or wh.business_id != business_id:
		raise ApiError("NOT_FOUND", "Warehouse document not found", http_status=404)
	
	if wh.status != "draft":
		raise ApiError("NOT_DELETABLE", "فقط حواله‌های draft قابل حذف هستند", http_status=400)
	
	db.delete(wh)
	db.flush()
	return True


def bulk_delete_warehouse_documents(db: Session, business_id: int, doc_ids: List[int]) -> Dict[str, Any]:
	"""حذف گروهی حواله‌های انبار؛ فقط حواله‌های draft و متعلق به همان کسب‌وکار حذف می‌شوند."""
	if not doc_ids:
		return {"deleted_count": 0, "total_requested": 0, "skipped": [], "errors": []}
	
	deleted_count = 0
	skipped: List[Dict[str, Any]] = []
	errors: List[Dict[str, Any]] = []
	
	for doc_id in doc_ids:
		try:
			wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == doc_id).first()
			if not wh:
				errors.append({"id": doc_id, "reason": "NOT_FOUND"})
				continue
			if wh.business_id != business_id:
				errors.append({"id": doc_id, "reason": "BUSINESS_MISMATCH"})
				continue
			if wh.status != "draft":
				skipped.append({"id": doc_id, "code": wh.code, "status": wh.status})
				continue
			
			db.delete(wh)
			deleted_count += 1
		except Exception as exc:
			errors.append({"id": doc_id, "reason": str(exc)})
	
	db.flush()
	return {
		"deleted_count": deleted_count,
		"total_requested": len(doc_ids),
		"skipped": skipped,
		"errors": errors,
	}


def cancel_warehouse_document(db: Session, business_id: int, wh_id: int, user_id: int) -> WarehouseDocument:
	"""لغو حواله posted با ایجاد حواله معکوس."""
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == wh_id).first()
	if not wh or wh.business_id != business_id:
		raise ApiError("NOT_FOUND", "Warehouse document not found", http_status=404)
	
	if wh.status != "posted":
		raise ApiError("NOT_CANCELLABLE", "فقط حواله‌های posted قابل لغو هستند", http_status=400)
	
	# ایجاد حواله معکوس
	lines = db.query(WarehouseDocumentLine).filter(WarehouseDocumentLine.warehouse_document_id == wh.id).all()
	if not lines:
		raise ApiError("NO_LINES", "حواله خطی ندارد", http_status=400)
	
	fy = _get_current_fiscal_year(db, business_id)
	code = _build_wh_code("WH-CANCEL")
	
	# تعیین نوع حواله معکوس
	reverse_doc_type = wh.doc_type
	if wh.doc_type == "receipt":
		reverse_doc_type = "issue"
	elif wh.doc_type == "issue":
		reverse_doc_type = "receipt"
	# برای transfer و adjustment همان نوع باقی می‌ماند
	
	cancel_wh = WarehouseDocument(
		business_id=business_id,
		fiscal_year_id=fy.id,
		code=code,
		document_date=wh.document_date,
		status="draft",  # حواله معکوس به صورت draft ایجاد می‌شود
		doc_type=reverse_doc_type,
		warehouse_id_from=wh.warehouse_id_to,  # معکوس
		warehouse_id_to=wh.warehouse_id_from,  # معکوس
		source_type="manual",
		source_document_id=wh.id,  # لینک به حواله اصلی
		created_by_user_id=user_id,
		extra_info={
			"cancels_warehouse_document_id": wh.id,
			"cancellation_reason": "لغو حواله",
		},
	)
	db.add(cancel_wh)
	db.flush()
	
	# ایجاد خطوط معکوس
	for ln in lines:
		reverse_movement = "in" if ln.movement == "out" else "out"
		reverse_wh = ln.warehouse_id  # برای transfer باید معکوس شود
		
		# برای transfer، انبار باید معکوس شود
		if wh.doc_type == "transfer":
			# پیدا کردن خط جفت (out/in) برای تعیین انبار معکوس
			if ln.movement == "out":
				reverse_wh = wh.warehouse_id_to
			else:
				reverse_wh = wh.warehouse_id_from
		
		cancel_line = WarehouseDocumentLine(
			warehouse_document_id=cancel_wh.id,
			product_id=ln.product_id,
			warehouse_id=reverse_wh,
			movement=reverse_movement,
			quantity=ln.quantity,
			extra_info={
				"cancels_line_id": ln.id,
				**(ln.extra_info or {}),
			},
		)
		db.add(cancel_line)
	
	# تغییر وضعیت حواله اصلی به cancelled
	wh.status = "cancelled"
	wh.touch()
	
	db.flush()
	return cancel_wh


def get_warehouse_stock_report(
	db: Session,
	business_id: int,
	query: Dict[str, Any],
) -> Dict[str, Any]:
	"""گزارش موجودی انبار به تفکیک محصول و انبار."""
	from app.services.invoice_service import _compute_available_stock
	from datetime import date as date_type
	
	# پارامترهای ورودی
	product_ids = query.get("product_ids", [])
	warehouse_ids = query.get("warehouse_ids", [])
	as_of_date_str = query.get("as_of_date")
	include_zero = bool(query.get("include_zero", False))
	
	# تبدیل تاریخ
	as_of_date = datetime.now().date()
	if as_of_date_str:
		try:
			as_of_date = date_type.fromisoformat(as_of_date_str) if isinstance(as_of_date_str, str) else as_of_date_str
		except Exception:
			pass
	
	# دریافت لیست محصولات
	if product_ids:
		products = db.query(Product).filter(
			and_(
				Product.business_id == business_id,
				Product.id.in_([int(p) for p in product_ids]),
				Product.track_inventory == True,
			)
		).all()
	else:
		products = db.query(Product).filter(
			and_(
				Product.business_id == business_id,
				Product.track_inventory == True,
			)
		).all()
	
	# دریافت لیست انبارها
	if warehouse_ids:
		warehouses = db.query(Warehouse).filter(
			and_(
				Warehouse.business_id == business_id,
				Warehouse.id.in_([int(w) for w in warehouse_ids]),
			)
		).all()
	else:
		warehouses = db.query(Warehouse).filter(Warehouse.business_id == business_id).all()
	
	# اگر انباری وجود ندارد، یک رکورد "بدون انبار" اضافه کن
	items = []
	
	for product in products:
		if warehouse_ids:
			# فقط انبارهای انتخاب شده
			wh_list = [w for w in warehouses if w.id in [int(wid) for wid in warehouse_ids]]
		else:
			wh_list = warehouses
		
		# اگر انباری انتخاب نشده، موجودی کل را محاسبه کن
		if not wh_list:
			stock = _compute_available_stock(db, business_id, product.id, None, as_of_date)
			if include_zero or stock > 0:
				items.append({
					"product_id": product.id,
					"product_code": product.code,
					"product_name": product.name,
					"warehouse_id": None,
					"warehouse_code": None,
					"warehouse_name": "بدون انبار / کل",
					"quantity": float(stock),
					"unit": product.unit or "",
				})
		else:
			# موجودی به تفکیک انبار
			for warehouse in wh_list:
				stock = _compute_available_stock(db, business_id, product.id, warehouse.id, as_of_date)
				if include_zero or stock > 0:
					items.append({
						"product_id": product.id,
						"product_code": product.code,
						"product_name": product.name,
						"warehouse_id": warehouse.id,
						"warehouse_code": warehouse.code,
						"warehouse_name": warehouse.name,
						"quantity": float(stock),
						"unit": product.unit or "",
					})
	
	return {
		"items": items,
		"as_of_date": as_of_date.isoformat(),
		"total_items": len(items),
	}


def get_physical_stock_bulk(
	db: Session,
	business_id: int,
	product_ids: List[int],
	as_of_date: Optional[date] = None,
) -> Dict[int, Decimal]:
	"""
	محاسبه موجودی انبارداری (فیزیکی) برای لیستی از کالاها.
	بر اساس حواله‌های انبار با وضعیت posted.
	بازگشت: Dict[product_id, quantity]
	"""
	if not product_ids:
		return {}
	
	if as_of_date is None:
		as_of_date = datetime.now().date()
	
	# دریافت حرکات از حواله‌های انبار با وضعیت posted
	lines = (
		db.query(WarehouseDocumentLine, WarehouseDocument)
		.join(WarehouseDocument, WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id)
		.filter(
			and_(
				WarehouseDocument.business_id == business_id,
				WarehouseDocument.status == "posted",
				WarehouseDocument.document_date <= as_of_date,
				WarehouseDocumentLine.product_id.in_(product_ids),
			)
		)
		.all()
	)
	
	# محاسبه موجودی
	stock_dict: Dict[int, Decimal] = {}
	for line, doc in lines:
		pid = int(line.product_id)
		qty = Decimal(str(line.quantity or 0))
		if qty <= 0:
			continue
		
		if pid not in stock_dict:
			stock_dict[pid] = Decimal(0)
		
		if line.movement == "in":
			stock_dict[pid] += qty
		elif line.movement == "out":
			stock_dict[pid] -= qty
	
	# برای کالاهایی که حرکتی نداشتند، مقدار 0 برگردان
	for pid in product_ids:
		if pid not in stock_dict:
			stock_dict[pid] = Decimal(0)
	
	return stock_dict

