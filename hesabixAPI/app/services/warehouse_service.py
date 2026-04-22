from __future__ import annotations

from typing import Any, Dict, List, Optional
from decimal import Decimal
from datetime import datetime, date
import logging

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_
from sqlalchemy.exc import IntegrityError

logger = logging.getLogger(__name__)

from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.product import Product
from adapters.db.models.account import Account
from adapters.db.models.fiscal_year import FiscalYear
from app.core.responses import ApiError
from adapters.db.models.warehouse import Warehouse
from adapters.db.models.user import User
from adapters.db.models.category import BusinessCategory
from adapters.db.repositories.warehouse_repository import WarehouseRepository
from adapters.api.v1.schema_models.warehouse import WarehouseCreateRequest, WarehouseUpdateRequest
from adapters.api.v1.schemas import QueryInfo, FilterItem
from app.services.query_service import QueryService
from app.services.product_attribute_service import validate_custom_attributes
from app.services.document_numbering_service import generate_document_code


def _get_current_fiscal_year(db: Session, business_id: int) -> FiscalYear:
	fy = db.query(FiscalYear).filter(and_(FiscalYear.business_id == business_id, FiscalYear.is_last == True)).first()
	if not fy:
		raise ApiError("NO_FISCAL_YEAR", "No active fiscal year found for this business", http_status=400)
	return fy


def _generate_warehouse_document_code(db: Session, business_id: int, document_date: date) -> str:
	"""کد حواله انبار بر اساس تنظیمات شماره‌گذاری اسناد (نوع warehouse_document)."""
	return generate_document_code(db, business_id, "warehouse_document", document_date)


def _is_duplicate_warehouse_document_code_error(exc: IntegrityError) -> bool:
	"""تشخیص برخورد یکتایی روی کد حواله انبار (PostgreSQL و MySQL، قبل/بعد از migration ترکیبی)."""
	text = f"{exc} {getattr(exc, 'orig', '')}".lower()
	if "uq_warehouse_documents_business_id_code" in text:
		return True
	if "ix_warehouse_documents_code" in text:
		return True
	if "duplicate entry" in text and ("warehouse_documents.code" in text or "`code`" in text):
		return True
	return False


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


def _optional_line_int(value: Any) -> Optional[int]:
	if value is None or value == "":
		return None
	try:
		return int(value)
	except Exception:
		return None


def _warehouse_location_id_from_payload(ln: Dict[str, Any]) -> Optional[int]:
	v = ln.get("warehouse_location_id")
	if v is None and isinstance(ln.get("extra_info"), dict):
		v = ln["extra_info"].get("warehouse_location_id")
	return _optional_line_int(v)


def _transfer_location_pair_from_payload(ln: Dict[str, Any]) -> tuple[Optional[int], Optional[int]]:
	o = ln.get("warehouse_location_id_from") or ln.get("warehouse_location_out")
	i = ln.get("warehouse_location_id_to") or ln.get("warehouse_location_in")
	return _optional_line_int(o), _optional_line_int(i)


def invoice_lines_have_trackable_inventory_products(
	db: Session,
	business_id: int,
	lines: List[Dict[str, Any]],
) -> bool:
	"""آیا حداقل یک ردیف فاکتور وجود دارد که در create_from_invoice به خط حواله انبار تبدیل شود؟
	(همان فیلتر product معتبر، quantity مثبت، track_inventory=True)
	"""
	for ln in lines:
		pid = ln.get("product_id")
		try:
			qty = Decimal(str(ln.get("quantity") or 0))
		except Exception:
			qty = Decimal(0)
		if not pid or qty <= 0:
			continue
		product = db.query(Product).filter(and_(Product.id == int(pid), Product.business_id == business_id)).first()
		if not product or not getattr(product, "track_inventory", False):
			continue
		return True
	return False


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
	
	# تولید code و INSERT اولیه حواله باید در برابر برخورد unique مقاوم باشد.
	# از SAVEPOINT استفاده می‌کنیم تا در صورت IntegrityError فقط همین INSERT برگشت بخورد
	# و تراکنش اصلی ساخت فاکتور از بین نرود.
	wh: Optional[WarehouseDocument] = None
	for attempt in range(10):
		code = _generate_warehouse_document_code(db, business_id, invoice.document_date)
		try:
			with db.begin_nested():
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
			break
		except IntegrityError as e:
			if _is_duplicate_warehouse_document_code_error(e) and attempt < 9:
				continue
			raise

	if wh is None:
		raise ApiError("WAREHOUSE_CODE_CONFLICT", "Failed to generate unique warehouse document code", http_status=500)
	for ln in lines:
		pid = ln.get("product_id")
		qty = Decimal(str(ln.get("quantity") or 0))
		if not pid or qty <= 0:
			continue

		# بررسی محصول
		product = db.query(Product).filter(and_(Product.id == int(pid), Product.business_id == business_id)).first()
		if not product:
			continue  # اگر محصول یافت نشد، خط را رد می‌کنیم
		
		# اقلام غیرانبارداری (مثل خدمات) نباید وارد حواله انبار شوند
		# در غیر این صورت ممکن است حواله‌ای با warehouse_id=None یا حرکت‌های اشتباه ساخته شود.
		if not getattr(product, "track_inventory", False):
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
		
		# برای اقلام انبارداری، warehouse_id الزامی است
		if not warehouse_id:
			raise ApiError("WAREHOUSE_REQUIRED", "warehouse_id برای خطوط انبارداری الزامی است", http_status=400)

		# بررسی و ایجاد instance های کالای یونیک (فقط برای حواله ورود)
		instance_data = ln.get("instance_data")
		instance_ids = []
		
		if instance_data and isinstance(instance_data, list) and len(instance_data) > 0:
			# بررسی اینکه کالا یونیک است
			if product.inventory_mode != "unique":
				raise ApiError("NOT_UNIQUE_PRODUCT", f"خط با product_id {pid}: این کالا در حالت یونیک نیست", http_status=400)
			
			# برای حواله ورود، instance ها را ایجاد می‌کنیم
			if wh_doc_type in ("receipt", "production_in"):
				from adapters.db.models.product_instance import ProductInstance
				
				for inst_idx, inst_data in enumerate(instance_data, start=1):
					if not isinstance(inst_data, dict):
						raise ApiError("INVALID_INSTANCE_DATA", f"خط با product_id {pid}، واحد {inst_idx}: اطلاعات instance معتبر نیست", http_status=400)
					
					serial_number = inst_data.get("serial_number")
					barcode = inst_data.get("barcode")
					custom_attributes = inst_data.get("custom_attributes")
					
					if not serial_number and product.track_serial:
						raise ApiError("SERIAL_REQUIRED", f"خط با product_id {pid}، واحد {inst_idx}: شماره سریال الزامی است", http_status=400)
					
					# بررسی یکتایی سریال نامبر
					if serial_number:
						existing = db.query(ProductInstance).filter(
							and_(
								ProductInstance.business_id == business_id,
								ProductInstance.serial_number == serial_number,
							)
						).first()
						if existing:
							raise ApiError("DUPLICATE_SERIAL", f"خط با product_id {pid}، واحد {inst_idx}: شماره سریال {serial_number} تکراری است", http_status=409)
					
					# بررسی یکتایی بارکد
					if barcode:
						existing_barcode = db.query(ProductInstance).filter(
							and_(
								ProductInstance.business_id == business_id,
								ProductInstance.barcode == barcode,
							)
						).first()
						if existing_barcode:
							raise ApiError("DUPLICATE_BARCODE", f"خط با product_id {pid}، واحد {inst_idx}: بارکد {barcode} تکراری است", http_status=409)
					
					# اعتبارسنجی custom_attributes
					if custom_attributes:
						is_valid, error_message = validate_custom_attributes(
							db=db,
							business_id=business_id,
							product_id=int(pid),
							custom_attributes=custom_attributes
						)
						if not is_valid:
							raise ApiError("INVALID_CUSTOM_ATTRIBUTES", f"خط با product_id {pid}، واحد {inst_idx}: {error_message or 'مقادیر ویژگی‌های کالا معتبر نیست'}", http_status=400)
					
					# تعیین انبار - برای حواله ورود از warehouse_id استفاده می‌کنیم
					instance_warehouse_id = warehouse_id if wh_doc_type in ("receipt", "production_in") else None
					
					# ایجاد instance
					instance = ProductInstance(
						business_id=business_id,
						product_id=int(pid),
						serial_number=serial_number or f"SN-{wh.id}-{pid}-{inst_idx}",  # اگر track_serial false باشد
						barcode=barcode,
						warehouse_id=int(instance_warehouse_id) if instance_warehouse_id else None,
						status="available",
						custom_attributes=custom_attributes if custom_attributes else None,
						entry_date=invoice.document_date,
					)
					db.add(instance)
					db.flush()  # برای دریافت ID
					instance_ids.append(instance.id)
		
		# برای حواله خروج، instance_ids را پردازش می‌کنیم
		# اول بررسی می‌کنیم که آیا selected_instance_ids از فاکتور آمده است
		instance_ids_from_line = ln.get("instance_ids")
		selected_instance_ids_from_invoice = extra.get("selected_instance_ids")
		
		# اگر selected_instance_ids از فاکتور آمده و instance_ids مستقیم در خط نباشد، از selected_instance_ids استفاده می‌کنیم
		if not instance_ids_from_line and selected_instance_ids_from_invoice and isinstance(selected_instance_ids_from_invoice, list) and len(selected_instance_ids_from_invoice) > 0:
			instance_ids_from_line = selected_instance_ids_from_invoice
		
		if instance_ids_from_line and isinstance(instance_ids_from_line, list) and len(instance_ids_from_line) > 0:
			from adapters.db.models.product_instance import ProductInstance
			
			# بررسی اینکه کالا یونیک است
			if product.inventory_mode != "unique":
				raise ApiError("NOT_UNIQUE_PRODUCT", f"خط با product_id {pid}: این کالا در حالت یونیک نیست", http_status=400)
			
			# برای حواله خروج، instance ها را به‌روزرسانی می‌کنیم
			if wh_doc_type in ("issue", "production_out"):
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
						raise ApiError("INSTANCE_NOT_FOUND", f"خط با product_id {pid}: کالای یونیک با ID {inst_id} یافت نشد یا در دسترس نیست", http_status=404)
					
					# به‌روزرسانی instance
					instance.warehouse_id = None  # از انبار خارج می‌شود
					instance.status = "sold"  # یا می‌توانیم status دیگری استفاده کنیم
					instance.last_movement_date = invoice.document_date
					instance_ids.append(instance.id)  # برای ذخیره در خط

		# پیوند به ردیف فاکتور برای شناسایی بهای تمام‌شده قطعی و گزارش‌ها
		if ln.get("invoice_item_line_id") is not None:
			try:
				extra = dict(extra or {})
				extra["invoice_item_line_id"] = int(ln["invoice_item_line_id"])
			except Exception:
				pass

		# اضافه کردن instance_ids به extra_info
		if instance_ids:
			extra["instance_ids"] = instance_ids
		if instance_ids_from_line and not instance_ids:
			extra["instance_ids"] = instance_ids_from_line

		# instance_ids برای خط (از instance_ids یا instance_ids_from_line)
		line_instance_ids = instance_ids_from_line if instance_ids_from_line else (instance_ids if instance_ids else None)
		
		# بررسی تعداد instance ها برای کالاهای یونیک
		if product.inventory_mode == "unique" and line_instance_ids:
			instance_count = len(line_instance_ids) if isinstance(line_instance_ids, list) else 0
			if instance_count > 0:
				# برای کالاهای یونیک، تعداد instance ها باید با quantity برابر باشد
				if instance_count > int(qty):
					raise ApiError("INSTANCE_COUNT_EXCEEDS_QUANTITY", f"خط با product_id {pid}: تعداد کالاهای یونیک ({instance_count}) نمی‌تواند از تعداد وارد شده ({int(qty)}) بیشتر باشد", http_status=400)

		line_wh_loc = _warehouse_location_id_from_payload(
			{"warehouse_location_id": ln.get("warehouse_location_id"), "extra_info": extra}
		)
		wline = WarehouseDocumentLine(
			warehouse_document_id=wh.id,
			product_id=int(pid),
			warehouse_id=warehouse_id,
			warehouse_location_id=line_wh_loc,
			movement=str(mv),
			quantity=qty,
			extra_info=extra,
			instance_ids=line_instance_ids,
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
	
	# ایجاد حواله — تولید code و INSERT در برابر برخورد unique روی warehouse_documents.code
	wh: Optional[WarehouseDocument] = None
	for attempt in range(10):
		code = _generate_warehouse_document_code(db, business_id, document_date)
		try:
			with db.begin_nested():
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
			break
		except IntegrityError as e:
			if _is_duplicate_warehouse_document_code_error(e) and attempt < 9:
				continue
			raise

	if wh is None:
		raise ApiError("WAREHOUSE_CODE_CONFLICT", "Failed to generate unique warehouse document code", http_status=500)
	
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
		
		# تعیین movement و warehouse_id بر اساس نوع حواله با استفاده از منطق fallback
		# این باید قبل از پردازش instance_data انجام شود چون برای تعیین انبار instance ها نیاز داریم
		line_wh = None
		if doc_type == "transfer":
			# برای transfer، انبار instance ها از warehouse_id_to استفاده می‌شود
			line_wh = ln.get("warehouse_id_to") or warehouse_id_to
		elif doc_type in ("issue", "production_out"):
			line_wh = ln.get("warehouse_id") or warehouse_id_from
		elif doc_type in ("receipt", "production_in"):
			line_wh = ln.get("warehouse_id") or warehouse_id_to
		elif doc_type == "adjustment":
			line_wh = ln.get("warehouse_id") or warehouse_id_to or warehouse_id_from
		
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
					
					# اعتبارسنجی custom_attributes
					if custom_attributes:
						is_valid, error_message = validate_custom_attributes(
							db=db,
							business_id=business_id,
							product_id=int(pid),
							custom_attributes=custom_attributes
						)
						if not is_valid:
							raise ApiError("INVALID_CUSTOM_ATTRIBUTES", f"خط {i}، واحد {inst_idx}: {error_message or 'مقادیر ویژگی‌های کالا معتبر نیست'}", http_status=400)
					
					# تعیین انبار - برای حواله ورود از line_wh استفاده می‌کنیم
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
		
		# برای حواله خروج و انتقال، instance_ids را پردازش می‌کنیم
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
					instance_ids.append(instance.id)  # برای ذخیره در خط
			
			# برای حواله انتقال، instance_ids را برای استفاده بعدی ذخیره می‌کنیم
			# (به‌روزرسانی انبار در زمان پست انجام می‌شود)
			elif doc_type == "transfer":
				# تعیین انبار مبدا (برای بررسی instance ها)
				line_wh_from_temp = ln.get("warehouse_id_from") or warehouse_id_from
				
				# بررسی وجود instance ها در انبار مبدا
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
					
					# بررسی اینکه instance در انبار مبدا است
					if instance.warehouse_id != int(line_wh_from_temp):
						raise ApiError("INSTANCE_WRONG_WAREHOUSE", f"خط {i}: کالای یونیک با ID {inst_id} در انبار مبدا نیست", http_status=400)
					
					instance_ids.append(instance.id)  # برای ذخیره در خط
		
		# تعیین movement و warehouse_id بر اساس نوع حواله با استفاده از منطق fallback
		# منطق fallback: اگر انبار در سطح ردیف مشخص نشده باشد، از انبار سطح سند استفاده می‌شود
		if doc_type == "transfer":
			# برای انتقال: یک خط out از مبدا و یک خط in به مقصد
			# منطق fallback: line['warehouse_id_from'] ?? warehouse_id_from (سطح سند)
			line_wh_from = ln.get("warehouse_id_from") or warehouse_id_from
			line_wh_to = ln.get("warehouse_id_to") or warehouse_id_to
			if not line_wh_from or not line_wh_to:
				raise ApiError("WAREHOUSES_REQUIRED", f"خط {i}: برای انتقال، انبار مبدا و مقصد باید مشخص باشد (در سطح سند یا ردیف)", http_status=400)
			
			# برای کالاهای یونیک، بررسی وجود instance_ids
			if product.inventory_mode == "unique":
				if not instance_ids and not instance_ids_from_line:
					raise ApiError("INSTANCE_IDS_REQUIRED", f"خط {i}: برای انتقال کالای یونیک، instance_ids الزامی است", http_status=400)
			
			# اضافه کردن instance_ids به extra_info برای transfer
			extra_info_transfer = ln.get("extra_info") or {}
			# استفاده از instance_ids (از instance_ids_from_line که پردازش شده) یا instance_ids_from_line مستقیم
			final_instance_ids = instance_ids if instance_ids else instance_ids_from_line
			if final_instance_ids:
				extra_info_transfer["instance_ids"] = final_instance_ids
			
			loc_from, loc_to = _transfer_location_pair_from_payload(ln)

			# ایجاد خط خروج از مبدا
			wline_out = WarehouseDocumentLine(
				warehouse_document_id=wh.id,
				product_id=int(pid),
				warehouse_id=int(line_wh_from),
				warehouse_location_id=loc_from,
				movement="out",
				quantity=qty,
				extra_info=extra_info_transfer,
				instance_ids=final_instance_ids if final_instance_ids else None,
			)
			db.add(wline_out)
			
			# ایجاد خط ورود به مقصد
			wline_in = WarehouseDocumentLine(
				warehouse_document_id=wh.id,
				product_id=int(pid),
				warehouse_id=int(line_wh_to),
				warehouse_location_id=loc_to,
				movement="in",
				quantity=qty,
				extra_info=extra_info_transfer,
				instance_ids=final_instance_ids if final_instance_ids else None,
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
				# line_wh قبلاً تعریف شده است
			elif doc_type in ("receipt", "production_in"):
				movement = "in"
				# line_wh قبلاً تعریف شده است
			elif doc_type == "adjustment":
				# برای تعدیل: movement از خط گرفته می‌شود
				movement = ln.get("movement", "in")
				if movement not in ("in", "out"):
					raise ApiError("INVALID_MOVEMENT", f"خط {i}: movement باید 'in' یا 'out' باشد", http_status=400)
				# line_wh قبلاً تعریف شده است
			else:
				movement = "in"
				# line_wh قبلاً تعریف شده است
			
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
			
			# بررسی تعداد instance ها برای کالاهای یونیک
			if product.inventory_mode == "unique" and line_instance_ids:
				instance_count = len(line_instance_ids) if isinstance(line_instance_ids, list) else 0
				if instance_count > 0:
					# برای کالاهای یونیک، تعداد instance ها باید با quantity برابر باشد
					if instance_count > int(qty):
						raise ApiError("INSTANCE_COUNT_EXCEEDS_QUANTITY", f"خط {i}: تعداد کالاهای یونیک ({instance_count}) نمی‌تواند از تعداد وارد شده ({int(qty)}) بیشتر باشد", http_status=400)
			
			line_wh_loc = _warehouse_location_id_from_payload(ln)
			wline = WarehouseDocumentLine(
				warehouse_document_id=wh.id,
				product_id=int(pid),
				warehouse_id=int(line_wh),
				warehouse_location_id=line_wh_loc,
				movement=movement,
				quantity=qty,
				extra_info=extra_info,
				instance_ids=line_instance_ids,
			)
			db.add(wline)
	
	db.flush()
	
	# Invalidate cache بعد از ایجاد موفق سند انبار
	invalidate_warehouse_docs_cache(
		business_id=business_id,
		fiscal_year_id=wh.fiscal_year_id,
		doc_type=wh.doc_type,
		warehouse_id=wh.warehouse_id_from or wh.warehouse_id_to,
		status=wh.status,
		document_id=wh.id
	)
	# اگر transfer باشد، هر دو انبار را invalidate کن
	if wh.doc_type == "transfer" and wh.warehouse_id_from and wh.warehouse_id_to:
		invalidate_warehouse_docs_cache(
			business_id=business_id,
			fiscal_year_id=wh.fiscal_year_id,
			doc_type=wh.doc_type,
			warehouse_id=wh.warehouse_id_to,
			status=wh.status
		)
	
	return wh


def update_warehouse_document(
	db: Session,
	business_id: int,
	wh_id: int,
	user_id: int,
	data: Dict[str, Any],
) -> WarehouseDocument:
	"""ویرایش حواله انبار (draft و posted)."""
	from datetime import date as date_type
	
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == wh_id).first()
	if not wh or wh.business_id != business_id:
		raise ApiError("NOT_FOUND", "Warehouse document not found", http_status=404)
	
	# حواله‌های draft و posted قابل ویرایش هستند
	# حواله‌های cancelled قابل ویرایش نیستند
	if wh.status == "cancelled":
		raise ApiError("NOT_EDITABLE", "حواله‌های لغو شده قابل ویرایش نیستند", http_status=400)
	
	# برای حواله‌های posted، فقط اجازه ویرایش اطلاعات کالاهای یونیک را می‌دهیم
	is_posted = wh.status == "posted"
	
	# برای حواله‌های posted، اجازه تغییر فیلدهای اصلی سند را نمی‌دهیم
	if is_posted:
		# بررسی اینکه آیا فیلدهای غیرمجاز ارسال شده‌اند
		restricted_fields = ["document_date", "warehouse_id_from", "warehouse_id_to", "extra_info", "description", "delivery_method", "carrier_name", "recipient_name", "recipient_phone", "tracking_number"]
		for field in restricted_fields:
			if field in data:
				raise ApiError("NOT_EDITABLE", f"برای حواله‌های قطعی شده، فقط اطلاعات کالاهای یونیک قابل ویرایش هستند. فیلد '{field}' قابل تغییر نیست", http_status=400)
	
	# به‌روزرسانی فیلدهای اصلی (فقط برای draft)
	if not is_posted and "document_date" in data:
		document_date_str = data.get("document_date")
		try:
			document_date = date_type.fromisoformat(document_date_str) if isinstance(document_date_str, str) else document_date_str
		except Exception:
			raise ApiError("INVALID_DATE", "فرمت تاریخ معتبر نیست", http_status=400)
		
		fy = _get_current_fiscal_year(db, business_id)
		if document_date < fy.start_date or (fy.end_date and document_date > fy.end_date):
			raise ApiError("DATE_OUT_OF_RANGE", f"تاریخ باید در بازه سال مالی باشد", http_status=400)
		wh.document_date = document_date
	
	if not is_posted and "warehouse_id_from" in data:
		wh.warehouse_id_from = int(data["warehouse_id_from"]) if data["warehouse_id_from"] else None
		if wh.warehouse_id_from:
			wh_check = db.query(Warehouse).filter(and_(Warehouse.id == wh.warehouse_id_from, Warehouse.business_id == business_id)).first()
			if not wh_check:
				raise ApiError("WAREHOUSE_NOT_FOUND", "انبار مبدا یافت نشد", http_status=404)
	
	if not is_posted and "warehouse_id_to" in data:
		wh.warehouse_id_to = int(data["warehouse_id_to"]) if data["warehouse_id_to"] else None
		if wh.warehouse_id_to:
			wh_check = db.query(Warehouse).filter(and_(Warehouse.id == wh.warehouse_id_to, Warehouse.business_id == business_id)).first()
			if not wh_check:
				raise ApiError("WAREHOUSE_NOT_FOUND", "انبار مقصد یافت نشد", http_status=404)
	
	# به‌روزرسانی extra_info با فیلدهای ارسال (فقط برای draft)
	if not is_posted and ("extra_info" in data or any(key in data for key in ["description", "delivery_method", "carrier_name", "recipient_name", "recipient_phone", "tracking_number"])):
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
			# برای حواله‌های posted، فقط اجازه به‌روزرسانی instance_data و instance_ids را می‌دهیم
			if is_posted:
				# دریافت خطوط موجود
				existing_lines = db.query(WarehouseDocumentLine).filter(WarehouseDocumentLine.warehouse_document_id == wh.id).all()
				existing_lines_map = {line.id: line for line in existing_lines}
				
				# شناسایی instance های قدیمی که باید حذف شوند (فقط برای حواله ورود)
				old_instance_ids_to_delete = []
				if wh.doc_type in ("receipt", "production_in"):
					from adapters.db.models.product_instance import ProductInstance
					for old_line in existing_lines:
						if old_line.instance_ids and isinstance(old_line.instance_ids, list):
							for inst_id in old_line.instance_ids:
								try:
									inst_id_int = int(inst_id) if not isinstance(inst_id, int) else inst_id
									old_instance_ids_to_delete.append(inst_id_int)
								except Exception:
									pass
				
				all_new_instance_ids = []  # برای نگهداری همه instance_ids جدید
				
				# به‌روزرسانی خطوط موجود (فقط instance_data و instance_ids)
				for i, ln in enumerate(lines_data, start=1):
					line_id = ln.get("id")
					if not line_id:
						raise ApiError("LINE_ID_REQUIRED", f"خط {i}: برای حواله‌های قطعی شده، شناسه خط الزامی است", http_status=400)
					
					existing_line = existing_lines_map.get(int(line_id))
					if not existing_line:
						raise ApiError("LINE_NOT_FOUND", f"خط {i}: خط با شناسه {line_id} یافت نشد", http_status=404)
					
					# بررسی اینکه فیلدهای غیرمجاز تغییر نکرده‌اند
					if "product_id" in ln and ln.get("product_id") != existing_line.product_id:
						raise ApiError("NOT_EDITABLE", f"خط {i}: برای حواله‌های قطعی شده، product_id قابل تغییر نیست", http_status=400)
					if "quantity" in ln and Decimal(str(ln.get("quantity") or 0)) != existing_line.quantity:
						raise ApiError("NOT_EDITABLE", f"خط {i}: برای حواله‌های قطعی شده، quantity قابل تغییر نیست", http_status=400)
					if "warehouse_id" in ln and ln.get("warehouse_id") != existing_line.warehouse_id:
						raise ApiError("NOT_EDITABLE", f"خط {i}: برای حواله‌های قطعی شده، warehouse_id قابل تغییر نیست", http_status=400)
					if "movement" in ln and ln.get("movement") != existing_line.movement:
						raise ApiError("NOT_EDITABLE", f"خط {i}: برای حواله‌های قطعی شده، movement قابل تغییر نیست", http_status=400)
					
					# استفاده از مقادیر موجود برای پردازش
					pid = existing_line.product_id
					qty = existing_line.quantity
					movement = existing_line.movement
					line_wh = existing_line.warehouse_id
					
					# بررسی محصول
					product = db.query(Product).filter(and_(Product.id == int(pid), Product.business_id == business_id)).first()
					if not product:
						raise ApiError("PRODUCT_NOT_FOUND", f"خط {i}: محصول یافت نشد", http_status=404)
					
					# پردازش فقط instance_data و instance_ids
					instance_data = ln.get("instance_data")
					instance_ids = []
					
					if instance_data and isinstance(instance_data, list) and len(instance_data) > 0:
						# بررسی اینکه کالا یونیک است
						if product.inventory_mode != "unique":
							raise ApiError("NOT_UNIQUE_PRODUCT", f"خط {i}: این کالا در حالت یونیک نیست", http_status=400)
						
						# برای حواله ورود، instance ها را ایجاد یا به‌روزرسانی می‌کنیم
						if wh.doc_type in ("receipt", "production_in") and movement == "in":
							from adapters.db.models.product_instance import ProductInstance
							from datetime import date as date_type
							
							document_date = wh.document_date
							
							# دریافت instance های قبلی که به این حواله مربوط بودند
							old_line_instance_ids = []
							if existing_line.instance_ids and isinstance(existing_line.instance_ids, list):
								old_line_instance_ids = [int(x) for x in existing_line.instance_ids if x is not None]
							
							for inst_idx, inst_data in enumerate(instance_data, start=1):
								if not isinstance(inst_data, dict):
									raise ApiError("INVALID_INSTANCE_DATA", f"خط {i}، واحد {inst_idx}: اطلاعات instance معتبر نیست", http_status=400)
								
								serial_number = inst_data.get("serial_number")
								barcode = inst_data.get("barcode")
								custom_attributes = inst_data.get("custom_attributes")
								instance_id = inst_data.get("id")  # ID instance موجود (اگر وجود داشته باشد)
								
								if not serial_number and product.track_serial:
									raise ApiError("SERIAL_REQUIRED", f"خط {i}، واحد {inst_idx}: شماره سریال الزامی است", http_status=400)
								
								instance = None
								
								# اگر instance قبلاً ایجاد شده (id موجود است)
								if instance_id:
									instance = db.query(ProductInstance).filter(
										and_(
											ProductInstance.id == int(instance_id),
											ProductInstance.business_id == business_id,
											ProductInstance.product_id == int(pid),
										)
									).first()
									
									if not instance:
										raise ApiError("INSTANCE_NOT_FOUND", f"خط {i}، واحد {inst_idx}: instance با ID {instance_id} یافت نشد", http_status=404)
									
									# به‌روزرسانی instance موجود
									# بررسی یکتایی سریال نامبر (فقط اگر تغییر کرده باشد)
									if serial_number and instance.serial_number != serial_number:
										existing_serial = db.query(ProductInstance).filter(
											and_(
												ProductInstance.business_id == business_id,
												ProductInstance.serial_number == serial_number,
												ProductInstance.id != int(instance_id),
											)
										).first()
										if existing_serial:
											raise ApiError("DUPLICATE_SERIAL", f"خط {i}، واحد {inst_idx}: شماره سریال {serial_number} تکراری است", http_status=409)
										instance.serial_number = serial_number
									
									# بررسی یکتایی بارکد (فقط اگر تغییر کرده باشد)
									if barcode and instance.barcode != barcode:
										existing_barcode = db.query(ProductInstance).filter(
											and_(
												ProductInstance.business_id == business_id,
												ProductInstance.barcode == barcode,
												ProductInstance.id != int(instance_id),
											)
										).first()
										if existing_barcode:
											raise ApiError("DUPLICATE_BARCODE", f"خط {i}، واحد {inst_idx}: بارکد {barcode} تکراری است", http_status=409)
										instance.barcode = barcode
									
									# به‌روزرسانی سایر فیلدها
									if custom_attributes is not None:
										# اعتبارسنجی custom_attributes
										if custom_attributes:
											is_valid, error_message = validate_custom_attributes(
												db=db,
												business_id=business_id,
												product_id=int(pid),
												custom_attributes=custom_attributes
											)
											if not is_valid:
												raise ApiError("INVALID_CUSTOM_ATTRIBUTES", f"خط {i}، واحد {inst_idx}: {error_message or 'مقادیر ویژگی‌های کالا معتبر نیست'}", http_status=400)
										instance.custom_attributes = custom_attributes if custom_attributes else None
									
									instance_warehouse_id = line_wh if wh.doc_type in ("receipt", "production_in") else instance.warehouse_id
									if instance_warehouse_id:
										instance.warehouse_id = int(instance_warehouse_id)
									
									instance_ids.append(instance.id)
								else:
									# ایجاد instance جدید (فقط برای حواله ورود)
									# بررسی یکتایی سریال نامبر
									if serial_number:
										existing_serial = db.query(ProductInstance).filter(
											and_(
												ProductInstance.business_id == business_id,
												ProductInstance.serial_number == serial_number,
											)
										).first()
										if existing_serial:
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
									
									# اعتبارسنجی custom_attributes
									if custom_attributes:
										is_valid, error_message = validate_custom_attributes(
											db=db,
											business_id=business_id,
											product_id=int(pid),
											custom_attributes=custom_attributes
										)
										if not is_valid:
											raise ApiError("INVALID_CUSTOM_ATTRIBUTES", f"خط {i}، واحد {inst_idx}: {error_message or 'مقادیر ویژگی‌های کالا معتبر نیست'}", http_status=400)
									
									# تعیین انبار - برای حواله ورود از line_wh استفاده می‌کنیم
									instance_warehouse_id = line_wh if wh.doc_type in ("receipt", "production_in") else None
									
									# ایجاد instance جدید
									instance = ProductInstance(
										business_id=business_id,
										product_id=int(pid),
										serial_number=serial_number or f"SN-{wh.id}-{i}-{inst_idx}",
										barcode=barcode,
										warehouse_id=int(instance_warehouse_id) if instance_warehouse_id else None,
										status="available",
										custom_attributes=custom_attributes if custom_attributes else None,
										entry_date=document_date,
									)
									db.add(instance)
									db.flush()
									instance_ids.append(instance.id)
							
							# حذف instance های قدیمی که دیگر استفاده نمی‌شوند
							if old_line_instance_ids:
								for old_inst_id in old_line_instance_ids:
									if old_inst_id not in instance_ids:
										old_instance = db.query(ProductInstance).filter(
											and_(
												ProductInstance.id == old_inst_id,
												ProductInstance.business_id == business_id,
											)
										).first()
										if old_instance and old_instance.status == "available":
											db.delete(old_instance)
					
					# پردازش instance_ids برای حواله خروج و انتقال
					instance_ids_from_line = ln.get("instance_ids")
					if instance_ids_from_line and isinstance(instance_ids_from_line, list) and len(instance_ids_from_line) > 0:
						from adapters.db.models.product_instance import ProductInstance
						
						# بررسی اینکه کالا یونیک است
						if product.inventory_mode != "unique":
							raise ApiError("NOT_UNIQUE_PRODUCT", f"خط {i}: این کالا در حالت یونیک نیست", http_status=400)
						
						# برای حواله خروج، فقط بررسی می‌کنیم که instance ها موجود باشند
						if wh.doc_type in ("issue", "production_out") and movement == "out":
							for inst_id in instance_ids_from_line:
								instance = db.query(ProductInstance).filter(
									and_(
										ProductInstance.id == int(inst_id),
										ProductInstance.business_id == business_id,
										ProductInstance.product_id == int(pid),
									)
								).first()
								
								if not instance:
									raise ApiError("INSTANCE_NOT_FOUND", f"خط {i}: کالای یونیک با ID {inst_id} یافت نشد", http_status=404)
								
								instance_ids.append(instance.id)
						
						# برای حواله انتقال، بررسی می‌کنیم
						elif wh.doc_type == "transfer":
							line_wh_from_temp = existing_line.warehouse_id  # استفاده از انبار موجود
							
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
								
								if instance.warehouse_id != int(line_wh_from_temp):
									raise ApiError("INSTANCE_WRONG_WAREHOUSE", f"خط {i}: کالای یونیک با ID {inst_id} در انبار مبدا نیست", http_status=400)
								
								instance_ids.append(instance.id)
					
					# اضافه کردن instance_ids به extra_info
					extra_info = existing_line.extra_info or {}
					final_instance_ids = instance_ids if instance_ids else instance_ids_from_line
					
					# بررسی تعداد instance ها برای کالاهای یونیک
					if product.inventory_mode == "unique" and final_instance_ids:
						instance_count = len(final_instance_ids) if isinstance(final_instance_ids, list) else 0
						if instance_count > 0:
							if instance_count > int(qty):
								raise ApiError("INSTANCE_COUNT_EXCEEDS_QUANTITY", f"خط {i}: تعداد کالاهای یونیک ({instance_count}) نمی‌تواند از تعداد وارد شده ({int(qty)}) بیشتر باشد", http_status=400)
					
					if final_instance_ids:
						extra_info["instance_ids"] = final_instance_ids
						if isinstance(final_instance_ids, list):
							all_new_instance_ids.extend([int(x) for x in final_instance_ids if x is not None])
					
					# به‌روزرسانی خط موجود (فقط instance_ids)
					existing_line.instance_ids = final_instance_ids if final_instance_ids else existing_line.instance_ids
					existing_line.extra_info = extra_info
					
				# حذف instance های قدیمی که دیگر استفاده نمی‌شوند (فقط برای حواله ورود)
				if wh.doc_type in ("receipt", "production_in") and old_instance_ids_to_delete:
					from adapters.db.models.product_instance import ProductInstance
					for old_inst_id in old_instance_ids_to_delete:
						if old_inst_id not in all_new_instance_ids:
							old_instance = db.query(ProductInstance).filter(
								and_(
									ProductInstance.id == old_inst_id,
									ProductInstance.business_id == business_id,
									ProductInstance.status == "available",
								)
							).first()
							if old_instance:
								db.delete(old_instance)
				
				db.flush()
			else:
				# برای حواله‌های draft، منطق قبلی (حذف و ایجاد مجدد خطوط)
				# دریافت خطوط قدیمی قبل از حذف
				old_lines = db.query(WarehouseDocumentLine).filter(WarehouseDocumentLine.warehouse_document_id == wh.id).all()
				
				# شناسایی instance های قدیمی که باید حذف شوند (فقط برای حواله ورود)
				old_instance_ids_to_delete = []
				if wh.doc_type in ("receipt", "production_in"):
					from adapters.db.models.product_instance import ProductInstance
					for old_line in old_lines:
						if old_line.instance_ids and isinstance(old_line.instance_ids, list):
							for inst_id in old_line.instance_ids:
								try:
									inst_id_int = int(inst_id) if not isinstance(inst_id, int) else inst_id
									old_instance_ids_to_delete.append(inst_id_int)
								except Exception:
									pass
				
				# حذف خطوط قدیمی
				db.query(WarehouseDocumentLine).filter(WarehouseDocumentLine.warehouse_document_id == wh.id).delete()
				db.flush()
				
				# ایجاد خطوط جدید
				all_new_instance_ids = []  # برای نگهداری همه instance_ids جدید
				
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
				
				# پردازش instance_data و instance_ids برای کالاهای یونیک
				instance_data = ln.get("instance_data")
				instance_ids = []
				
				if instance_data and isinstance(instance_data, list) and len(instance_data) > 0:
					# بررسی اینکه کالا یونیک است
					if product.inventory_mode != "unique":
						raise ApiError("NOT_UNIQUE_PRODUCT", f"خط {i}: این کالا در حالت یونیک نیست", http_status=400)
					
					# برای حواله ورود، instance ها را ایجاد یا به‌روزرسانی می‌کنیم
					if wh.doc_type in ("receipt", "production_in") and movement == "in":
						from adapters.db.models.product_instance import ProductInstance
						from datetime import date as date_type
						
						document_date = wh.document_date
						
						# دریافت instance های قبلی که به این حواله مربوط بودند
						old_line_instance_ids = []
						if ln.get("instance_ids") and isinstance(ln.get("instance_ids"), list):
							old_line_instance_ids = [int(x) for x in ln.get("instance_ids") if x is not None]
						
						for inst_idx, inst_data in enumerate(instance_data, start=1):
							if not isinstance(inst_data, dict):
								raise ApiError("INVALID_INSTANCE_DATA", f"خط {i}، واحد {inst_idx}: اطلاعات instance معتبر نیست", http_status=400)
							
							serial_number = inst_data.get("serial_number")
							barcode = inst_data.get("barcode")
							custom_attributes = inst_data.get("custom_attributes")
							instance_id = inst_data.get("id")  # ID instance موجود (اگر وجود داشته باشد)
							
							if not serial_number and product.track_serial:
								raise ApiError("SERIAL_REQUIRED", f"خط {i}، واحد {inst_idx}: شماره سریال الزامی است", http_status=400)
							
							instance = None
							
							# اگر instance قبلاً ایجاد شده (id موجود است)
							if instance_id:
								instance = db.query(ProductInstance).filter(
									and_(
										ProductInstance.id == int(instance_id),
										ProductInstance.business_id == business_id,
										ProductInstance.product_id == int(pid),
									)
								).first()
								
								if not instance:
									raise ApiError("INSTANCE_NOT_FOUND", f"خط {i}، واحد {inst_idx}: instance با ID {instance_id} یافت نشد", http_status=404)
								
								# به‌روزرسانی instance موجود
								# بررسی یکتایی سریال نامبر (فقط اگر تغییر کرده باشد)
								if serial_number and instance.serial_number != serial_number:
									existing_serial = db.query(ProductInstance).filter(
										and_(
											ProductInstance.business_id == business_id,
											ProductInstance.serial_number == serial_number,
											ProductInstance.id != int(instance_id),
										)
									).first()
									if existing_serial:
										raise ApiError("DUPLICATE_SERIAL", f"خط {i}، واحد {inst_idx}: شماره سریال {serial_number} تکراری است", http_status=409)
									instance.serial_number = serial_number
								
								# بررسی یکتایی بارکد (فقط اگر تغییر کرده باشد)
								if barcode and instance.barcode != barcode:
									existing_barcode = db.query(ProductInstance).filter(
										and_(
											ProductInstance.business_id == business_id,
											ProductInstance.barcode == barcode,
											ProductInstance.id != int(instance_id),
										)
									).first()
									if existing_barcode:
										raise ApiError("DUPLICATE_BARCODE", f"خط {i}، واحد {inst_idx}: بارکد {barcode} تکراری است", http_status=409)
									instance.barcode = barcode
								
								# به‌روزرسانی سایر فیلدها
								if custom_attributes is not None:
									# اعتبارسنجی custom_attributes
									if custom_attributes:
										is_valid, error_message = validate_custom_attributes(
											db=db,
											business_id=business_id,
											product_id=int(pid),
											custom_attributes=custom_attributes
										)
										if not is_valid:
											raise ApiError("INVALID_CUSTOM_ATTRIBUTES", f"خط {i}، واحد {inst_idx}: {error_message or 'مقادیر ویژگی‌های کالا معتبر نیست'}", http_status=400)
									instance.custom_attributes = custom_attributes if custom_attributes else None
								
								instance_warehouse_id = line_wh if wh.doc_type in ("receipt", "production_in") else instance.warehouse_id
								if instance_warehouse_id:
									instance.warehouse_id = int(instance_warehouse_id)
								
								instance_ids.append(instance.id)
							else:
								# ایجاد instance جدید
								# بررسی یکتایی سریال نامبر
								if serial_number:
									existing_serial = db.query(ProductInstance).filter(
										and_(
											ProductInstance.business_id == business_id,
											ProductInstance.serial_number == serial_number,
										)
									).first()
									if existing_serial:
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
								
								# اعتبارسنجی custom_attributes
								if custom_attributes:
									is_valid, error_message = validate_custom_attributes(
										db=db,
										business_id=business_id,
										product_id=int(pid),
										custom_attributes=custom_attributes
									)
									if not is_valid:
										raise ApiError("INVALID_CUSTOM_ATTRIBUTES", f"خط {i}، واحد {inst_idx}: {error_message or 'مقادیر ویژگی‌های کالا معتبر نیست'}", http_status=400)
								
								# تعیین انبار - برای حواله ورود از line_wh استفاده می‌کنیم
								instance_warehouse_id = line_wh if wh.doc_type in ("receipt", "production_in") else None
								
								# ایجاد instance جدید
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
						
						# حذف instance های قدیمی که دیگر استفاده نمی‌شوند
						if old_line_instance_ids:
							for old_inst_id in old_line_instance_ids:
								if old_inst_id not in instance_ids:
									# این instance دیگر استفاده نمی‌شود - حذف می‌کنیم
									old_instance = db.query(ProductInstance).filter(
										and_(
											ProductInstance.id == old_inst_id,
											ProductInstance.business_id == business_id,
										)
									).first()
									if old_instance and old_instance.status == "available":
										# فقط اگر instance در دسترس است، حذف می‌کنیم
										# (اگر instance به فروش رفته یا استفاده شده، نباید حذف شود)
										db.delete(old_instance)
				
				# پردازش instance_ids برای حواله خروج و انتقال
				instance_ids_from_line = ln.get("instance_ids")
				if instance_ids_from_line and isinstance(instance_ids_from_line, list) and len(instance_ids_from_line) > 0:
					from adapters.db.models.product_instance import ProductInstance
					
					# بررسی اینکه کالا یونیک است
					if product.inventory_mode != "unique":
						raise ApiError("NOT_UNIQUE_PRODUCT", f"خط {i}: این کالا در حالت یونیک نیست", http_status=400)
					
					# برای حواله خروج، instance ها را به‌روزرسانی می‌کنیم (در زمان پست)
					if wh.doc_type in ("issue", "production_out") and movement == "out":
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
							
							instance_ids.append(instance.id)
					
					# برای حواله انتقال، instance_ids را برای استفاده بعدی ذخیره می‌کنیم
					elif wh.doc_type == "transfer":
						# تعیین انبار مبدا (برای بررسی instance ها)
						line_wh_from_temp = ln.get("warehouse_id_from") or wh.warehouse_id_from
						
						# بررسی وجود instance ها در انبار مبدا
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
							
							# بررسی اینکه instance در انبار مبدا است
							if instance.warehouse_id != int(line_wh_from_temp):
								raise ApiError("INSTANCE_WRONG_WAREHOUSE", f"خط {i}: کالای یونیک با ID {inst_id} در انبار مبدا نیست", http_status=400)
							
							instance_ids.append(instance.id)
				
				# اضافه کردن instance_ids به extra_info
				extra_info = ln.get("extra_info") or {}
				final_instance_ids = instance_ids if instance_ids else instance_ids_from_line
				
				# بررسی تعداد instance ها برای کالاهای یونیک
				if product.inventory_mode == "unique" and final_instance_ids:
					instance_count = len(final_instance_ids) if isinstance(final_instance_ids, list) else 0
					if instance_count > 0:
						# برای کالاهای یونیک، تعداد instance ها باید با quantity برابر باشد
						if instance_count > int(qty):
							raise ApiError("INSTANCE_COUNT_EXCEEDS_QUANTITY", f"خط {i}: تعداد کالاهای یونیک ({instance_count}) نمی‌تواند از تعداد وارد شده ({int(qty)}) بیشتر باشد", http_status=400)
				
				if final_instance_ids:
					extra_info["instance_ids"] = final_instance_ids
					# اضافه کردن به لیست کلی instance های جدید
					if isinstance(final_instance_ids, list):
						all_new_instance_ids.extend([int(x) for x in final_instance_ids if x is not None])
				
				line_wh_loc = _warehouse_location_id_from_payload(ln)
				wline = WarehouseDocumentLine(
					warehouse_document_id=wh.id,
					product_id=int(pid),
					warehouse_id=int(line_wh),
					warehouse_location_id=line_wh_loc,
					movement=movement,
					quantity=qty,
					extra_info=extra_info,
					instance_ids=final_instance_ids if final_instance_ids else None,
				)
				db.add(wline)
			
			# حذف instance های قدیمی که دیگر استفاده نمی‌شوند (فقط برای حواله ورود)
			if wh.doc_type in ("receipt", "production_in") and old_instance_ids_to_delete:
				from adapters.db.models.product_instance import ProductInstance
				for old_inst_id in old_instance_ids_to_delete:
					if old_inst_id not in all_new_instance_ids:
						# این instance دیگر استفاده نمی‌شود - حذف می‌کنیم
						old_instance = db.query(ProductInstance).filter(
							and_(
								ProductInstance.id == old_inst_id,
								ProductInstance.business_id == business_id,
								ProductInstance.status == "available",
							)
						).first()
						if old_instance:
							# فقط اگر instance در دسترس است، حذف می‌کنیم
							# (اگر instance به فروش رفته یا استفاده شده، نباید حذف شود)
							db.delete(old_instance)
			
			db.flush()
	
	# دریافت اطلاعات قبل از به‌روزرسانی برای invalidation
	old_fiscal_year_id = wh.fiscal_year_id
	old_doc_type = wh.doc_type
	old_warehouse_id_from = wh.warehouse_id_from
	old_warehouse_id_to = wh.warehouse_id_to
	old_status = wh.status
	
	# Invalidate cache بعد از به‌روزرسانی موفق سند انبار
	invalidate_warehouse_docs_cache(
		business_id=business_id,
		fiscal_year_id=old_fiscal_year_id,
		doc_type=old_doc_type,
		warehouse_id=old_warehouse_id_from or old_warehouse_id_to,
		status=old_status,
		document_id=wh.id
	)
	# اگر transfer باشد، هر دو انبار را invalidate کن
	if old_doc_type == "transfer" and old_warehouse_id_from and old_warehouse_id_to:
		invalidate_warehouse_docs_cache(
			business_id=business_id,
			fiscal_year_id=old_fiscal_year_id,
			doc_type=old_doc_type,
			warehouse_id=old_warehouse_id_to,
			status=old_status
		)
	
	# اگر fiscal_year_id، doc_type، warehouse_id یا status تغییر کرده، cache جدید را هم invalidate کن
	if wh.fiscal_year_id != old_fiscal_year_id or wh.doc_type != old_doc_type or wh.status != old_status:
		invalidate_warehouse_docs_cache(
			business_id=business_id,
			fiscal_year_id=wh.fiscal_year_id,
			doc_type=wh.doc_type,
			warehouse_id=wh.warehouse_id_from or wh.warehouse_id_to,
			status=wh.status,
			document_id=wh.id
		)
		if wh.doc_type == "transfer" and wh.warehouse_id_from and wh.warehouse_id_to:
			invalidate_warehouse_docs_cache(
				business_id=business_id,
				fiscal_year_id=wh.fiscal_year_id,
				doc_type=wh.doc_type,
				warehouse_id=wh.warehouse_id_to,
				status=wh.status
			)
	
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

	if "warehouse_location_id" in data:
		from app.services.warehouse_placement_sync import validate_warehouse_location_for_line

		raw_loc = data.get("warehouse_location_id")
		if raw_loc is None or raw_loc == "":
			wline.warehouse_location_id = None
		else:
			try:
				lid = int(raw_loc)
			except Exception:
				raise ApiError("INVALID_LOCATION", "شناسه محل انبار نامعتبر است", http_status=400)
			if wline.warehouse_id:
				validate_warehouse_location_for_line(db, business_id, int(wline.warehouse_id), lid)
			wline.warehouse_location_id = lid
	
	wh.touch()
	db.flush()
	return wline


def post_warehouse_document(db: Session, wh_id: int) -> Dict[str, Any]:
	"""پست حواله: کنترل کسری برای خروج‌ها و به‌روزرسانی موجودی انبار.
	اگر doc_type='transfer' باشد، یک سند حسابداری هم ایجاد می‌شود.
	توجه: محاسبات COGS و ثبت سطرهای حسابداری در بخش فاکتورها انجام می‌شود.
	"""
	from app.services.invoice_service import (
		_ensure_stock_sufficient,
		_get_current_fiscal_year,
		filter_outgoing_lines_for_stock_enforcement,
	)
	from adapters.db.models.business import Business
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
	
	# کنترل کسری موجودی (با رعایت سیاست کسب‌وکار: فله / یونیک / انتقال)
	if outgoing_lines:
		biz = db.query(Business).filter(Business.id == int(wh.business_id)).first()
		allow_bulk = bool(getattr(biz, "allow_negative_inventory_for_bulk", False)) if biz else False
		allow_unique = bool(getattr(biz, "allow_negative_inventory_for_unique", False)) if biz else False
		transfer_strict = bool(getattr(biz, "warehouse_transfer_require_positive_stock", True)) if biz else True
		lines_to_check = filter_outgoing_lines_for_stock_enforcement(
			db,
			int(wh.business_id),
			outgoing_lines,
			allow_negative_for_bulk=allow_bulk,
			allow_negative_for_unique=allow_unique,
			warehouse_doc_type=getattr(wh, "doc_type", None),
			transfer_require_positive_stock=transfer_strict,
		)
		if lines_to_check:
			try:
				_ensure_stock_sufficient(
					db,
					wh.business_id,
					wh.document_date,
					lines_to_check,
					exclude_document_id=None,  # این حواله هنوز پست نشده
				)
			except ApiError as e:
				# خطای کسری موجودی را به صورت واضح نمایش بده
				raise ApiError("INSUFFICIENT_STOCK", str(e), http_status=409)

	# برای حواله‌های transfer، به‌روزرسانی instance های کالاهای یونیک
	if wh.doc_type == "transfer":
		from adapters.db.models.product_instance import ProductInstance
		
		# برای هر خط out، instance ها را پیدا کرده و به انبار مقصد منتقل کن
		for ln_out in lines:
			if ln_out.movement == "out" and ln_out.instance_ids:
				# پیدا کردن خط in متناظر
				ln_in = next(
					(ln for ln in lines if ln.movement == "in" and ln.product_id == ln_out.product_id),
					None
				)
				
				if not ln_in:
					continue  # اگر خط in پیدا نشد، ادامه بده
				
				# به‌روزرسانی instance ها
				if isinstance(ln_out.instance_ids, list):
					for inst_id in ln_out.instance_ids:
						try:
							inst_id_int = int(inst_id) if not isinstance(inst_id, int) else inst_id
							instance = db.query(ProductInstance).filter(
								and_(
									ProductInstance.id == inst_id_int,
									ProductInstance.business_id == wh.business_id,
								)
							).first()
							
							if instance:
								# انتقال instance از انبار مبدا به انبار مقصد
								instance.warehouse_id = ln_in.warehouse_id
								instance.last_movement_date = wh.document_date
								# status را available نگه می‌داریم (چون فقط انتقال است)
						except Exception:
							# در صورت خطا، ادامه بده
							pass
	
	# همگام‌سازی قرارگیری فیزیکی با خطوط دارای محل انبار (قبل از قطعی شدن سند)
	from app.services.warehouse_placement_sync import apply_placement_effects_for_posted_document

	apply_placement_effects_for_posted_document(db, int(wh.business_id), wh, lines)

	# دریافت اطلاعات قبل از تغییر status برای invalidation
	old_status = wh.status
	business_id = wh.business_id
	fiscal_year_id = wh.fiscal_year_id
	doc_type = wh.doc_type
	warehouse_id_from = wh.warehouse_id_from
	warehouse_id_to = wh.warehouse_id_to
	
	# تغییر وضعیت به posted
	wh.status = "posted"
	wh.touch()
	db.flush()
	
	# Invalidate cache بعد از تغییر status به posted
	invalidate_warehouse_docs_cache(
		business_id=business_id,
		fiscal_year_id=fiscal_year_id,
		doc_type=doc_type,
		warehouse_id=warehouse_id_from or warehouse_id_to,
		status=old_status,
		document_id=wh.id
	)
	invalidate_warehouse_docs_cache(
		business_id=business_id,
		fiscal_year_id=fiscal_year_id,
		doc_type=doc_type,
		warehouse_id=warehouse_id_from or warehouse_id_to,
		status="posted",
		document_id=wh.id
	)
	# اگر transfer باشد، هر دو انبار را invalidate کن
	if doc_type == "transfer" and warehouse_id_from and warehouse_id_to:
		invalidate_warehouse_docs_cache(
			business_id=business_id,
			fiscal_year_id=fiscal_year_id,
			doc_type=doc_type,
			warehouse_id=warehouse_id_to,
			status=old_status
		)
		invalidate_warehouse_docs_cache(
			business_id=business_id,
			fiscal_year_id=fiscal_year_id,
			doc_type=doc_type,
			warehouse_id=warehouse_id_to,
			status="posted"
		)
	
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

	# ورک‌فلو: موجودی کم (reorder_point)
	try:
		from app.services.workflow.workflow_trigger_service import maybe_fire_inventory_low_triggers

		seen_pairs: set[tuple[int, Optional[int]]] = set()
		for ln in lines:
			if not ln.product_id:
				continue
			prod = db.query(Product).filter(Product.id == int(ln.product_id)).first()
			if not prod or not getattr(prod, "track_inventory", False):
				continue
			wid = int(ln.warehouse_id) if ln.warehouse_id else None
			key = (int(ln.product_id), wid)
			if key in seen_pairs:
				continue
			seen_pairs.add(key)
			maybe_fire_inventory_low_triggers(
				db,
				int(business_id),
				int(ln.product_id),
				wid,
				user_id=getattr(wh, "created_by_user_id", None),
			)
	except Exception as inv_wf_err:
		logger.warning(
			"warehouse_workflow_inventory_low_failed wh_id=%s err=%s",
			wh.id,
			inv_wf_err,
			exc_info=True,
		)

	# شناسایی بهای تمام‌شده قطعی روی خطوط فاکتور مبدأ (در صورت تنظیم کسب‌وکار)
	try:
		from app.services.invoice_profit_ledger_service import on_warehouse_document_posted

		on_warehouse_document_posted(db, int(wh.id))
	except Exception as ledger_hook_err:
		logger.warning(
			"warehouse_post ledger recognition hook failed wh_id=%s err=%s",
			getattr(wh, "id", None),
			ledger_hook_err,
			exc_info=True,
		)

	return {"id": wh.id, "status": wh.status}


def _get_line_dict_with_instances(db: Session, ln: WarehouseDocumentLine, business_id: int) -> Dict[str, Any]:
	"""تبدیل خط حواله به دیکشنری با اطلاعات کامل instance ها در صورت وجود"""
	line_dict = {
		"id": ln.id,
		"product_id": ln.product_id,
		"warehouse_id": ln.warehouse_id,
		"warehouse_location_id": getattr(ln, "warehouse_location_id", None),
		"movement": ln.movement,
		"quantity": float(ln.quantity),
		"extra_info": ln.extra_info,
		"instance_ids": ln.instance_ids,
	}
	
	# اگر instance_ids وجود دارد، اطلاعات کامل instance ها را بارگذاری کن
	if ln.instance_ids and isinstance(ln.instance_ids, list) and len(ln.instance_ids) > 0:
		from adapters.db.models.product_instance import ProductInstance
		instance_data = []
		for inst_id in ln.instance_ids:
			try:
				inst_id_int = int(inst_id) if not isinstance(inst_id, int) else inst_id
				# برای حواله‌های خروج، instance ها ممکن است status="sold" داشته باشند
				# پس فیلتر بر اساس status نمی‌کنیم
				instance = db.query(ProductInstance).filter(
					and_(
						ProductInstance.id == inst_id_int,
						ProductInstance.business_id == business_id,
					)
				).first()
				if instance:
					instance_data.append({
						"id": instance.id,
						"serial_number": instance.serial_number,
						"barcode": instance.barcode,
						"custom_attributes": instance.custom_attributes or {},
					})
			except Exception:
				# در صورت خطا، از instance_id استفاده کن
				pass
		
		if instance_data:
			line_dict["instance_data"] = instance_data
	
	return line_dict


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

	product_ids = {int(ln.product_id) for ln in lines if ln.product_id}
	wh_ids: set[int] = set()
	for ln in lines:
		if ln.warehouse_id is not None:
			wh_ids.add(int(ln.warehouse_id))
	if wh.warehouse_id_from is not None:
		wh_ids.add(int(wh.warehouse_id_from))
	if wh.warehouse_id_to is not None:
		wh_ids.add(int(wh.warehouse_id_to))

	products_map: Dict[int, Product] = {}
	if product_ids:
		for p in db.query(Product).filter(
			and_(Product.business_id == wh.business_id, Product.id.in_(product_ids))
		).all():
			products_map[int(p.id)] = p

	category_ids = {int(p.category_id) for p in products_map.values() if getattr(p, "category_id", None)}
	categories_map: Dict[int, BusinessCategory] = {}
	if category_ids:
		for c in db.query(BusinessCategory).filter(
			and_(BusinessCategory.business_id == wh.business_id, BusinessCategory.id.in_(category_ids))
		).all():
			categories_map[int(c.id)] = c

	warehouses_map: Dict[int, Warehouse] = {}
	if wh_ids:
		for w in db.query(Warehouse).filter(
			and_(Warehouse.business_id == wh.business_id, Warehouse.id.in_(wh_ids))
		).all():
			warehouses_map[int(w.id)] = w

	source_document_code: Optional[str] = None
	if wh.source_type == "invoice" and wh.source_document_id:
		src_doc = db.query(Document).filter(
			and_(Document.id == int(wh.source_document_id), Document.business_id == wh.business_id)
		).first()
		if src_doc is not None:
			source_document_code = src_doc.code

	fiscal_year_title: Optional[str] = None
	if wh.fiscal_year_id:
		fy = db.query(FiscalYear).filter(FiscalYear.id == int(wh.fiscal_year_id)).first()
		if fy is not None:
			fiscal_year_title = fy.title

	created_by_name: Optional[str] = None
	if wh.created_by_user_id:
		u = db.query(User).filter(User.id == int(wh.created_by_user_id)).first()
		if u is not None:
			parts = [x for x in (u.first_name, u.last_name) if x]
			created_by_name = " ".join(parts).strip() or (u.email or u.mobile or str(u.id))

	def _warehouse_label(wid: Optional[int]) -> Optional[str]:
		if wid is None:
			return None
		obj = warehouses_map.get(int(wid))
		return obj.name if obj is not None else None

	accounting_document_id = extra_info.get("accounting_document_id") if isinstance(extra_info, dict) else None

	def _category_display_title(cat: Optional[BusinessCategory]) -> Optional[str]:
		if cat is None:
			return None
		trans = cat.title_translations or {}
		if isinstance(trans, dict):
			return trans.get("fa") or trans.get("en") or trans.get("default") or None
		return None

	line_out: List[Dict[str, Any]] = []
	for ln in lines:
		d = _get_line_dict_with_instances(db, ln, wh.business_id)
		p = products_map.get(int(ln.product_id)) if ln.product_id else None
		if p is not None:
			d["product_name"] = p.name
			d["product_code"] = p.code
			d["product_main_unit"] = p.main_unit
			if p.category_id:
				cat = categories_map.get(int(p.category_id))
				cat_title = _category_display_title(cat)
				if cat_title:
					d["product_category_name"] = cat_title
		if ln.warehouse_id is not None:
			wobj = warehouses_map.get(int(ln.warehouse_id))
			if wobj is not None:
				d["warehouse_name"] = wobj.name
		line_out.append(d)

	return {
		"id": wh.id,
		"code": wh.code,
		"business_id": wh.business_id,
		"fiscal_year_id": wh.fiscal_year_id,
		"fiscal_year_title": fiscal_year_title,
		"document_date": wh.document_date.isoformat() if wh.document_date else None,
		"status": wh.status,
		"doc_type": wh.doc_type,
		"warehouse_id_from": wh.warehouse_id_from,
		"warehouse_id_to": wh.warehouse_id_to,
		"warehouse_name_from": _warehouse_label(wh.warehouse_id_from),
		"warehouse_name_to": _warehouse_label(wh.warehouse_id_to),
		"source_type": wh.source_type,
		"source_document_id": wh.source_document_id,
		"source_document_code": source_document_code,
		"extra_info": wh.extra_info,
		"description": delivery_info["description"],
		"delivery_method": delivery_info["delivery_method"],
		"carrier_name": delivery_info["carrier_name"],
		"recipient_name": delivery_info["recipient_name"],
		"recipient_phone": delivery_info["recipient_phone"],
		"tracking_number": delivery_info["tracking_number"],
		"total_quantity": float(total_quantity),
		"created_at": wh.created_at.isoformat() if wh.created_at else None,
		"updated_at": wh.updated_at.isoformat() if wh.updated_at else None,
		"created_by_user_id": wh.created_by_user_id,
		"created_by_name": created_by_name,
		"accounting_document_id": accounting_document_id,
		"lines": line_out,
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


def invalidate_warehouses_cache(business_id: int):
	"""
	Invalidate cache برای لیست انبارها
	"""
	from app.core.cache import get_cache
	cache = get_cache()
	if cache.enabled:
		try:
			deleted_count = cache.invalidate_warehouses_by_business(business_id)
			logger.info(f"Invalidated {deleted_count} cache keys for warehouses, business_id {business_id}")
		except Exception as e:
			logger.warning(f"Error invalidating warehouses cache for business_id {business_id}: {e}")


def invalidate_warehouse_docs_cache(business_id: int, fiscal_year_id: Optional[int] = None, doc_type: Optional[str] = None, warehouse_id: Optional[int] = None, status: Optional[str] = None, document_id: Optional[int] = None):
	"""
	Invalidate cache برای اسناد انبار
	"""
	from app.core.cache import get_cache
	cache = get_cache()
	if cache.enabled:
		try:
			deleted_count = cache.invalidate_warehouse_docs_by_business(
				business_id=business_id,
				fiscal_year_id=fiscal_year_id,
				doc_type=doc_type,
				warehouse_id=warehouse_id,
				status=status,
				document_id=document_id
			)
			logger.info(f"Invalidated {deleted_count} cache keys for warehouse_docs, business_id {business_id}, fiscal_year_id {fiscal_year_id}, doc_type {doc_type}, warehouse_id {warehouse_id}, status {status}, document_id {document_id}")
		except Exception as e:
			logger.warning(f"Error invalidating warehouse_docs cache for business_id {business_id}: {e}")


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
	
	# Invalidate cache بعد از ایجاد موفق انبار
	invalidate_warehouses_cache(business_id)
	
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
	
	# Invalidate cache بعد از به‌روزرسانی موفق انبار
	invalidate_warehouses_cache(business_id)
	
	return {"message": "WAREHOUSE_UPDATED", "data": _to_dict(updated)}


def delete_warehouse(db: Session, business_id: int, warehouse_id: int) -> bool:
	obj = db.get(Warehouse, warehouse_id)
	if not obj or obj.business_id != business_id:
		return False

	# جلوگیری از حذف انباری که در هدر یا خطوط حواله انبار استفاده شده است
	has_doc = (
		db.query(WarehouseDocument.id)
		.filter(
			WarehouseDocument.business_id == business_id,
			or_(
				WarehouseDocument.warehouse_id_from == warehouse_id,
				WarehouseDocument.warehouse_id_to == warehouse_id,
			),
		)
		.first()
	)
	if has_doc is not None:
		raise ApiError(
			"WAREHOUSE_HAS_WAREHOUSE_DOCUMENTS",
			"به‌دلیل وجود حواله انبار مرتبط با این انبار، حذف امکان‌پذیر نیست؛ ابتدا حواله‌ها را اصلاح یا حذف کنید.",
			http_status=400,
		)

	has_line = (
		db.query(WarehouseDocumentLine.id)
		.join(WarehouseDocument, WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id)
		.filter(
			WarehouseDocument.business_id == business_id,
			WarehouseDocumentLine.warehouse_id == warehouse_id,
		)
		.first()
	)
	if has_line is not None:
		raise ApiError(
			"WAREHOUSE_HAS_LINE_MOVEMENTS",
			"به‌دلیل وجود حواله انبار با ردیف‌های مرتبط با این انبار، حذف امکان‌پذیر نیست.",
			http_status=400,
		)

	repo = WarehouseRepository(db)
	try:
		result = repo.delete(warehouse_id)
	except IntegrityError:
		db.rollback()
		raise ApiError(
			"WAREHOUSE_DELETE_CONFLICT",
			"حذف انبار به‌دلیل وابستگی‌های دیگر در سیستم امکان‌پذیر نیست.",
			http_status=400,
		) from None
	
	# Invalidate cache بعد از حذف موفق انبار
	if result:
		invalidate_warehouses_cache(business_id)
		# همچنین اسناد انبار مرتبط با این انبار را هم invalidate کن
		from app.core.cache import get_cache
		cache = get_cache()
		if cache.enabled:
			try:
				cache.invalidate_warehouse_docs_by_business(
					business_id=business_id,
					warehouse_id=warehouse_id
				)
			except Exception as e:
				logger.warning(f"Error invalidating warehouse_docs cache for warehouse_id {warehouse_id}: {e}")
	
	return result


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
	
	# دریافت اطلاعات قبل از حذف برای invalidation
	fiscal_year_id = wh.fiscal_year_id
	doc_type = wh.doc_type
	warehouse_id_from = wh.warehouse_id_from
	warehouse_id_to = wh.warehouse_id_to
	status = wh.status
	
	db.delete(wh)
	db.flush()
	
	# Invalidate cache بعد از حذف موفق سند انبار
	invalidate_warehouse_docs_cache(
		business_id=business_id,
		fiscal_year_id=fiscal_year_id,
		doc_type=doc_type,
		warehouse_id=warehouse_id_from or warehouse_id_to,
		status=status,
		document_id=wh_id
	)
	# اگر transfer باشد، هر دو انبار را invalidate کن
	if doc_type == "transfer" and warehouse_id_from and warehouse_id_to:
		invalidate_warehouse_docs_cache(
			business_id=business_id,
			fiscal_year_id=fiscal_year_id,
			doc_type=doc_type,
			warehouse_id=warehouse_id_to,
			status=status
		)
	
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

	from app.services.warehouse_placement_sync import reverse_placement_effects_for_cancelled_document

	reverse_placement_effects_for_cancelled_document(db, business_id, lines)
	
	fy = _get_current_fiscal_year(db, business_id)

	# تعیین نوع حواله معکوس
	reverse_doc_type = wh.doc_type
	if wh.doc_type == "receipt":
		reverse_doc_type = "issue"
	elif wh.doc_type == "issue":
		reverse_doc_type = "receipt"
	# برای transfer و adjustment همان نوع باقی می‌ماند

	cancel_wh: Optional[WarehouseDocument] = None
	for attempt in range(10):
		code = _generate_warehouse_document_code(db, business_id, wh.document_date)
		try:
			with db.begin_nested():
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
			break
		except IntegrityError as e:
			if _is_duplicate_warehouse_document_code_error(e) and attempt < 9:
				continue
			raise

	if cancel_wh is None:
		raise ApiError("WAREHOUSE_CODE_CONFLICT", "Failed to generate unique warehouse document code", http_status=500)

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
	
	# دریافت اطلاعات قبل از تغییر status برای invalidation
	old_status = wh.status
	business_id = wh.business_id
	fiscal_year_id = wh.fiscal_year_id
	doc_type = wh.doc_type
	warehouse_id_from = wh.warehouse_id_from
	warehouse_id_to = wh.warehouse_id_to
	
	# تغییر وضعیت حواله اصلی به cancelled
	wh.status = "cancelled"
	wh.touch()
	
	db.flush()
	
	# Invalidate cache بعد از تغییر status به cancelled و ایجاد حواله معکوس
	invalidate_warehouse_docs_cache(
		business_id=business_id,
		fiscal_year_id=fiscal_year_id,
		doc_type=doc_type,
		warehouse_id=warehouse_id_from or warehouse_id_to,
		status=old_status,
		document_id=wh.id
	)
	invalidate_warehouse_docs_cache(
		business_id=business_id,
		fiscal_year_id=fiscal_year_id,
		doc_type=doc_type,
		warehouse_id=warehouse_id_from or warehouse_id_to,
		status="cancelled",
		document_id=wh.id
	)
	# برای حواله معکوس جدید
	invalidate_warehouse_docs_cache(
		business_id=business_id,
		fiscal_year_id=cancel_wh.fiscal_year_id,
		doc_type=cancel_wh.doc_type,
		warehouse_id=cancel_wh.warehouse_id_from or cancel_wh.warehouse_id_to,
		status=cancel_wh.status,
		document_id=cancel_wh.id
	)
	# اگر transfer باشد، هر دو انبار را invalidate کن
	if doc_type == "transfer" and warehouse_id_from and warehouse_id_to:
		invalidate_warehouse_docs_cache(
			business_id=business_id,
			fiscal_year_id=fiscal_year_id,
			doc_type=doc_type,
			warehouse_id=warehouse_id_to,
			status=old_status
		)
		invalidate_warehouse_docs_cache(
			business_id=business_id,
			fiscal_year_id=fiscal_year_id,
			doc_type=doc_type,
			warehouse_id=warehouse_id_to,
			status="cancelled"
		)
	if cancel_wh.doc_type == "transfer" and cancel_wh.warehouse_id_from and cancel_wh.warehouse_id_to:
		invalidate_warehouse_docs_cache(
			business_id=business_id,
			fiscal_year_id=cancel_wh.fiscal_year_id,
			doc_type=cancel_wh.doc_type,
			warehouse_id=cancel_wh.warehouse_id_to,
			status=cancel_wh.status
		)
	
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
					"unit": product.main_unit or "",
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
						"unit": product.main_unit or "",
					})
	
	return {
		"items": items,
		"as_of_date": as_of_date.isoformat(),
		"total_items": len(items),
	}


def start_stock_count(
	db: Session,
	business_id: int,
	warehouse_id: Optional[int] = None,
	product_ids: Optional[List[int]] = None,
	as_of_date: Optional[date] = None,
) -> Dict[str, Any]:
	"""شروع انبار گردانی: دریافت لیست محصولات با موجودی سیستم."""
	from app.services.invoice_service import _compute_available_stock
	
	if as_of_date is None:
		as_of_date = datetime.now().date()
	
	# دریافت لیست محصولات
	products_query = db.query(Product).filter(
		and_(
			Product.business_id == business_id,
			Product.track_inventory == True,
		)
	)
	
	if product_ids:
		products_query = products_query.filter(Product.id.in_([int(p) for p in product_ids]))
	
	products = products_query.all()
	
	# دریافت لیست انبارها
	if warehouse_id:
		warehouses = db.query(Warehouse).filter(
			and_(
				Warehouse.business_id == business_id,
				Warehouse.id == warehouse_id,
			)
		).all()
	else:
		warehouses = db.query(Warehouse).filter(Warehouse.business_id == business_id).all()
	
	# ساخت لیست محصولات با موجودی سیستم
	items = []
	for product in products:
		if warehouse_id:
			# فقط انبار انتخاب شده
			stock = _compute_available_stock(db, business_id, product.id, warehouse_id, as_of_date)
			items.append({
				"product_id": product.id,
				"product_code": product.code or "",
				"product_name": product.name,
				"warehouse_id": warehouse_id,
				"warehouse_code": None,
				"warehouse_name": None,
				"system_quantity": float(stock),
				"unit": product.main_unit or "",
			})
		else:
			# همه انبارها
			if warehouses:
				for warehouse in warehouses:
					stock = _compute_available_stock(db, business_id, product.id, warehouse.id, as_of_date)
					items.append({
						"product_id": product.id,
						"product_code": product.code or "",
						"product_name": product.name,
						"warehouse_id": warehouse.id,
						"warehouse_code": warehouse.code,
						"warehouse_name": warehouse.name,
						"system_quantity": float(stock),
						"unit": product.main_unit or "",
					})
			else:
				# بدون انبار
				stock = _compute_available_stock(db, business_id, product.id, None, as_of_date)
				items.append({
					"product_id": product.id,
					"product_code": product.code or "",
					"product_name": product.name,
					"warehouse_id": None,
					"warehouse_code": None,
					"warehouse_name": "بدون انبار / کل",
					"system_quantity": float(stock),
					"unit": product.main_unit or "",
				})
	
	return {
		"items": items,
		"as_of_date": as_of_date.isoformat(),
		"total_items": len(items),
	}


def calculate_stock_count_differences(
	db: Session,
	business_id: int,
	items: List[Dict[str, Any]],
) -> Dict[str, Any]:
	"""محاسبه تفاوت‌های انبار گردانی."""
	from app.services.invoice_service import _compute_available_stock
	from datetime import date as date_type
	
	result_items = []
	
	for item in items:
		product_id = item.get("product_id")
		warehouse_id = item.get("warehouse_id")
		system_quantity = Decimal(str(item.get("system_quantity", 0)))
		physical_quantity = Decimal(str(item.get("physical_quantity", 0)))
		
		if not product_id:
			continue
		
		# محاسبه تفاوت
		difference = physical_quantity - system_quantity
		
		# تعیین نوع حرکت برای حواله تعدیل
		movement = None
		if difference > 0:
			movement = "in"  # افزایش موجودی
		elif difference < 0:
			movement = "out"  # کاهش موجودی
		
		result_items.append({
			"product_id": int(product_id),
			"warehouse_id": int(warehouse_id) if warehouse_id else None,
			"system_quantity": float(system_quantity),
			"physical_quantity": float(physical_quantity),
			"difference": float(difference),
			"movement": movement,
			"quantity": float(abs(difference)) if difference != 0 else 0.0,
		})
	
	# محاسبه خلاصه
	total_items = len(result_items)
	items_with_difference = len([i for i in result_items if i["difference"] != 0])
	items_increased = len([i for i in result_items if i["difference"] > 0])
	items_decreased = len([i for i in result_items if i["difference"] < 0])
	
	return {
		"items": result_items,
		"summary": {
			"total_items": total_items,
			"items_with_difference": items_with_difference,
			"items_increased": items_increased,
			"items_decreased": items_decreased,
		},
	}


def create_stock_count_adjustment(
	db: Session,
	business_id: int,
	user_id: Optional[int],
	stock_count_code: str,
	stock_count_date: date,
	items: List[Dict[str, Any]],
	notes: Optional[str] = None,
) -> WarehouseDocument:
	"""ایجاد حواله تعدیل از تفاوت‌های انبار گردانی."""
	fy = _get_current_fiscal_year(db, business_id)

	# فیلتر کردن فقط آیتم‌هایی که تفاوت دارند
	adjustment_items = [item for item in items if item.get("difference", 0) != 0]
	
	if not adjustment_items:
		raise ApiError("NO_DIFFERENCES", "هیچ تفاوتی برای ایجاد حواله تعدیل وجود ندارد", http_status=400)
	
	# ایجاد حواله تعدیل
	wh: Optional[WarehouseDocument] = None
	for attempt in range(10):
		code = _generate_warehouse_document_code(db, business_id, stock_count_date)
		try:
			with db.begin_nested():
				wh = WarehouseDocument(
					business_id=business_id,
					fiscal_year_id=fy.id,
					code=code,
					document_date=stock_count_date,
					status="draft",
					doc_type="adjustment",
					warehouse_id_from=None,
					warehouse_id_to=None,
					source_type="manual",
					source_document_id=None,
					created_by_user_id=user_id,
					extra_info={
						"stock_count_code": stock_count_code,
						"stock_count_date": stock_count_date.isoformat(),
						"notes": notes,
					},
				)
				db.add(wh)
				db.flush()
			break
		except IntegrityError as e:
			if _is_duplicate_warehouse_document_code_error(e) and attempt < 9:
				continue
			raise

	if wh is None:
		raise ApiError("WAREHOUSE_CODE_CONFLICT", "Failed to generate unique warehouse document code", http_status=500)

	# ایجاد خطوط حواله
	for item in adjustment_items:
		product_id = item.get("product_id")
		warehouse_id = item.get("warehouse_id")
		movement = item.get("movement")
		quantity = Decimal(str(item.get("quantity", 0)))
		
		if not product_id or not movement or quantity <= 0:
			continue
		
		# بررسی محصول
		product = db.query(Product).filter(
			and_(Product.id == int(product_id), Product.business_id == business_id)
		).first()
		if not product:
			continue
		
		line = WarehouseDocumentLine(
			warehouse_document_id=wh.id,
			product_id=int(product_id),
			warehouse_id=int(warehouse_id) if warehouse_id else None,
			movement=movement,
			quantity=quantity,
			extra_info={
				"system_quantity": item.get("system_quantity"),
				"physical_quantity": item.get("physical_quantity"),
				"difference": item.get("difference"),
			},
		)
		db.add(line)
	
	db.flush()
	return wh


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

