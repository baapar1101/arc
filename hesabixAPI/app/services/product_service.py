from __future__ import annotations

from typing import Dict, Any, Optional, List, Tuple
from datetime import datetime, date, timedelta
from sqlalchemy.orm import Session, load_only
from sqlalchemy import select, and_, or_, func, case, desc
from sqlalchemy.types import Numeric
from decimal import Decimal
import logging
import re
import uuid as uuid_module

from app.core.responses import ApiError
from app.core.cache import get_cache
from adapters.db.models.product import Product, ProductItemType
from adapters.db.models.product_attribute import ProductAttribute
from adapters.db.models.product_attribute_link import ProductAttributeLink
from adapters.db.repositories.product_repository import ProductRepository
from adapters.api.v1.schema_models.product import ProductCreateRequest, ProductUpdateRequest
from adapters.db.models.category import BusinessCategory
from sqlalchemy.exc import IntegrityError

from app.services.product_general_barcode_service import (
    normalize_general_barcodes_storage,
    assert_tokens_unique_among_products,
    assert_tokens_not_used_by_unique_instances,
    replace_general_barcode_aliases,
    split_raw_general_barcodes,
)
from app.services.public_catalog_service import invalidate_public_catalog_caches

logger = logging.getLogger(__name__)


def _resolve_create_general_barcodes_raw(payload: ProductCreateRequest) -> Optional[str]:
    gb = payload.general_barcodes
    if isinstance(gb, str) and gb.strip():
        return gb
    if payload.barcode and str(payload.barcode).strip():
        return str(payload.barcode).strip()
    return None


def _legacy_barcode_field_from_general_csv(csv_val: Optional[str]) -> Optional[str]:
    tokens = split_raw_general_barcodes(csv_val)
    return tokens[0] if tokens else None


def invalidate_products_cache(business_id: int, product_id: Optional[int] = None, category_id: Optional[int] = None):
	"""
	حذف تمام کش‌های مربوط به لیست محصولات یک کسب‌وکار
	
	این تابع از چند روش استفاده می‌کند:
	1. Tag-based invalidation با set ردیس: حذف انتخابی بر اساس business_id و category_id (بهینه‌تر)
	2. Pattern-based invalidation: حذف تمام کلیدهای products_search:* (fallback برای اطمینان)
	3. Redis Pub/Sub: انتشار پیام invalidation برای تمام instanceها
	
	Args:
		business_id: شناسه کسب‌وکار
		product_id: شناسه محصول خاص (اختیاری)
			- اگر مشخص باشد، کش محصول خاص هم حذف می‌شود
		category_id: شناسه دسته‌بندی (اختیاری)
			- اگر None باشد، تمام کش‌های مربوط به business_id حذف می‌شوند
			- اگر مشخص باشد، فقط کش‌های مربوط به آن category_id حذف می‌شوند
	"""
	cache = get_cache()
	if not cache.enabled:
		return
	
	try:
		# روش 1: استفاده از invalidate_products_by_business (بهینه‌ترین روش)
		# این متد از set ردیس برای نگهداری کلیدها استفاده می‌کند
		deleted_count = cache.invalidate_products_by_business(business_id, category_id, product_id)
		if deleted_count > 0:
			logger.info(f"Invalidated {deleted_count} cache keys for business_id {business_id}, category_id {category_id}, product_id {product_id}")
		
		# روش 2: حذف تمام کلیدهای products_search:* (fallback برای اطمینان کامل)
		# این کار برای اطمینان از حذف کامل کش انجام می‌شود
		# (در صورت وجود کلیدهای قدیمی که با tag-based ذخیره نشده‌اند)
		pattern = f"products_search:{business_id}:*"
		deleted_pattern = cache.delete_pattern(pattern)
		if deleted_pattern > 0:
			logger.info(f"Invalidated {deleted_pattern} cache keys using pattern: {pattern}")
		
		# حذف کش محصول خاص اگر مشخص شده باشد
		if product_id:
			product_pattern = f"product:{business_id}:{product_id}*"
			deleted_product = cache.delete_pattern(product_pattern)
			if deleted_product > 0:
				logger.info(f"Invalidated {deleted_product} cache keys for product_id {product_id} using pattern: {product_pattern}")
		
		# روش 3: انتشار پیام invalidation از طریق Redis Pub/Sub
		# این کار باعث می‌شود که تمام instanceهای برنامه کش را invalidate کنند
		invalidation_message = {
			"type": "products_cache_invalidation",
			"business_id": business_id,
			"product_id": product_id,
			"category_id": category_id,
			"timestamp": None
		}
		try:
			import time
			invalidation_message["timestamp"] = time.time()
			cache.publish_invalidation("cache_invalidation", invalidation_message)
			logger.info(f"Published invalidation message for business_id {business_id}, category_id {category_id}, product_id {product_id}")
		except Exception as pub_error:
			logger.warning(f"Error publishing invalidation message: {pub_error}")
	
	except Exception as e:
		# خطا در invalidate نباید مانع عملیات اصلی شود
		logger.warning(f"Error invalidating products cache for business_id {business_id}: {e}")


def _generate_auto_code_by_category(
    db: Session, 
    business_id: int, 
    category_id: int | None
) -> str | None:
    """
    تولید کد خودکار بر اساس دسته‌بندی (با Row Locking برای جلوگیری از Race Condition)
    
    Args:
        db: Session دیتابیس
        business_id: شناسه کسب‌وکار
        category_id: شناسه دسته‌بندی
    
    Returns:
        کد پیشنهادی یا None اگر نتوان کد تولید کرد
    """
    if category_id is None:
        return None
    
    # استفاده از Row Locking برای جلوگیری از Race Condition
    # قفل کردن ردیف‌های مربوط به این دسته‌بندی
    products = db.query(Product).filter(
        and_(
            Product.business_id == business_id,
            Product.category_id == category_id,
            Product.code.isnot(None)
        )
    ).with_for_update().order_by(Product.id.desc()).limit(100).all()
    
    if not products:
        # هیچ کالایی در این دسته وجود ندارد
        return None
    
    # استخراج آخرین کد عددی
    max_code = None
    for product in products:
        code_str = product.code.strip()
        if code_str.isdigit():
            try:
                code_num = int(code_str)
                if max_code is None or code_num > max_code:
                    max_code = code_num
            except ValueError:
                continue
    
    if max_code is None:
        # هیچ کد عددی در این دسته وجود ندارد
        return None
    
    # تولید کد بعدی
    return str(max_code + 1)


def _generate_auto_code(db: Session, business_id: int, category_id: int | None = None) -> str:
    """
    تولید کد خودکار (با پشتیبانی از دسته‌بندی)
    
    اول سعی می‌کند بر اساس دسته‌بندی کد تولید کند،
    اگر موفق نشد از منطق قبلی استفاده می‌کند.
    
    Args:
        db: Session دیتابیس
        business_id: شناسه کسب‌وکار
        category_id: شناسه دسته‌بندی (اختیاری)
    
    Returns:
        کد خودکار تولید شده
    """
    # اگر category_id مشخص است، سعی کن بر اساس دسته کد تولید کنی
    if category_id is not None:
        category_code = _generate_auto_code_by_category(db, business_id, category_id)
        if category_code:
            return category_code
    
    # منطق قبلی (تولید کد بدون توجه به دسته‌بندی)
    codes = [
        r[0] for r in db.execute(
            select(Product.code).where(Product.business_id == business_id)
        ).all()
    ]
    max_num = 0
    for c in codes:
        if c and c.isdigit():
            try:
                max_num = max(max_num, int(c))
            except ValueError:
                continue
    if max_num > 0:
        return str(max_num + 1)
    max_id = (
        db.execute(select(func.max(Product.id)).where(Product.business_id == business_id)).scalar()
        or 0
    )
    return f"P{max_id + 1:06d}"


def _allocate_unique_product_code(db: Session, business_id: int, candidate: str, *, max_len: int = 64) -> str:
    """
    تضمین یکتایی کد کالا در سطح کسب‌وکار (پس از تولید خودکار یا هر پیشنهاد اولیه).
    """
    raw = (candidate or "").strip() or "1"
    if len(raw) > max_len:
        raw = raw[:max_len]

    def _exists(c: str) -> bool:
        return (
            db.query(Product.id)
            .filter(and_(Product.business_id == business_id, Product.code == c))
            .first()
            is not None
        )

    if not _exists(raw):
        return raw

    if raw.isdigit():
        n = int(raw)
        for _ in range(100_000):
            n += 1
            cand = str(n)
            if len(cand) > max_len:
                cand = cand[:max_len]
            if not _exists(cand):
                return cand
        raise ApiError(
            "PRODUCT_CODE_ALLOCATION_FAILED",
            "تخصیص کد یکتا برای کالا ناموفق بود؛ لطفاً دوباره تلاش کنید.",
            http_status=500,
        )

    m = re.fullmatch(r"(?i)P(\d+)", raw)
    if m:
        n = int(m.group(1))
        for _ in range(100_000):
            n += 1
            cand = f"P{n:06d}"[:max_len]
            if not _exists(cand):
                return cand
        raise ApiError(
            "PRODUCT_CODE_ALLOCATION_FAILED",
            "تخصیص کد یکتا برای کالا ناموفق بود؛ لطفاً دوباره تلاش کنید.",
            http_status=500,
        )

    base = raw[: max(1, max_len - 10)]
    for i in range(2, 100_000):
        cand = f"{base}-{i}"[:max_len]
        if not _exists(cand):
            return cand
    raise ApiError(
        "PRODUCT_CODE_ALLOCATION_FAILED",
        "تخصیص کد یکتا برای کالا ناموفق بود؛ لطفاً دوباره تلاش کنید.",
        http_status=500,
    )


def _validate_tax(payload: ProductCreateRequest | ProductUpdateRequest) -> None:
    if getattr(payload, 'is_sales_taxable', False) and getattr(payload, 'sales_tax_rate', None) is None:
        pass
    if getattr(payload, 'is_purchase_taxable', False) and getattr(payload, 'purchase_tax_rate', None) is None:
        pass


def _validate_item_type_inventory(payload: ProductCreateRequest | ProductUpdateRequest, existing_item_type: Optional[str] = None) -> None:
    """بررسی می‌کند که برای خدمات، کنترل موجودی غیرفعال باشد"""
    item_type = getattr(payload, 'item_type', None) or existing_item_type
    if item_type == ProductItemType.SERVICE.value:
        # برای خدمات، track_inventory باید false باشد
        track_inventory = getattr(payload, 'track_inventory', None)
        if track_inventory is True:
            raise ApiError("INVALID_INVENTORY_FOR_SERVICE", "برای خدمات نمی‌توان کنترل موجودی را فعال کرد", http_status=400)
        # برای خدمات، default_warehouse_id باید null باشد
        # اما به جای validation، در update_product آن را null می‌کنیم


def _validate_units(main_unit: Optional[str], secondary_unit: Optional[str], factor: Optional[Decimal]) -> None:
    if secondary_unit and not factor:
        raise ApiError("INVALID_UNIT_FACTOR", "برای واحد فرعی تعیین ضریب تبدیل الزامی است", http_status=400)
def _validate_unit_string(unit: Optional[str]) -> Optional[str]:
    """Validate and clean unit string"""
    if unit is None:
        return None
    cleaned = str(unit).strip()
    if not cleaned:
        return None
    if len(cleaned) > 32:
        raise ApiError("INVALID_UNIT_LENGTH", "واحد شمارش نمی‌تواند بیش از 32 کاراکتر باشد", http_status=400)
    return cleaned



def _upsert_attributes(db: Session, product_id: int, business_id: int, attribute_ids: Optional[List[int]], auto_commit: bool = True) -> None:
    """
    ایجاد یا به‌روزرسانی ویژگی‌های کالا
    
    Args:
        db: Session دیتابیس
        product_id: شناسه کالا
        business_id: شناسه کسب‌وکار
        attribute_ids: لیست شناسه‌های ویژگی‌ها
        auto_commit: اگر True باشد، خودش commit می‌کند (برای سازگاری با کد قدیمی)
    """
    if attribute_ids is None:
        return
    db.query(ProductAttributeLink).filter(ProductAttributeLink.product_id == product_id).delete()
    if not attribute_ids:
        if auto_commit:
            db.commit()
        return
    valid_ids = [
        a.id for a in db.query(ProductAttribute.id, ProductAttribute.business_id)
        .filter(ProductAttribute.id.in_(attribute_ids), ProductAttribute.business_id == business_id)
        .all()
    ]
    for aid in valid_ids:
        db.add(ProductAttributeLink(product_id=product_id, attribute_id=aid))
    if auto_commit:
        db.commit()


def create_product(
    db: Session,
    business_id: int,
    payload: ProductCreateRequest,
    *,
    defer_cache_invalidation: bool = False,
) -> Dict[str, Any]:
    """
    ایجاد کالا/خدمت جدید (با Retry Logic برای مدیریت Race Condition)
    """
    logger.info(f"[CREATE_PRODUCT] Starting - business_id={business_id}, name='{payload.name}', code='{payload.code}'")
    repo = ProductRepository(db)
    _validate_tax(payload)
    _validate_item_type_inventory(payload)
    # Validate and clean unit strings
    main_unit = _validate_unit_string(payload.main_unit)
    secondary_unit = _validate_unit_string(payload.secondary_unit)
    _validate_units(main_unit, secondary_unit, payload.unit_conversion_factor)
    logger.debug(f"[CREATE_PRODUCT] Validation passed - main_unit='{main_unit}', secondary_unit='{secondary_unit}'")

    raw_gb_create = _resolve_create_general_barcodes_raw(payload)
    stored_gb_create, gb_tokens_create = normalize_general_barcodes_storage(raw_gb_create)

    # Retry Logic برای مدیریت Race Condition در تولید کد خودکار
    max_retries = 10
    retry_count = 0
    
    while retry_count < max_retries:
        logger.debug(f"[CREATE_PRODUCT] Attempt {retry_count + 1}/{max_retries}")
        try:
            # پردازش کد: اگر خالی، None یا برابر نام کالا باشد، کد خودکار تولید می‌شود
            code = None
            manual_code = False  # آیا کد دستی وارد شده است؟
            
            if payload.code:
                code_str = payload.code.strip() if isinstance(payload.code, str) else str(payload.code).strip()
                # اگر کد خالی نباشد و برابر نام کالا نباشد، استفاده کن
                if code_str and code_str != payload.name.strip():
                    code = code_str
                    manual_code = True
                    dup = db.query(Product).filter(and_(Product.business_id == business_id, Product.code == code)).first()
                    if dup:
                        raise ApiError("DUPLICATE_PRODUCT_CODE", "کد کالا/خدمت تکراری است", http_status=400)
            
            # اگر کد خالی است یا برابر نام کالا است، کد خودکار تولید کن
            if not code:
                # استفاده از category_id برای تولید کد خودکار بر اساس دسته‌بندی
                logger.debug(f"[CREATE_PRODUCT] Generating auto code - category_id={payload.category_id}")
                suggested = _generate_auto_code(db, business_id, payload.category_id)
                code = _allocate_unique_product_code(db, business_id, suggested)
                logger.info(f"[CREATE_PRODUCT] Auto-generated code: '{code}' (suggested='{suggested}')")
            else:
                logger.info(f"[CREATE_PRODUCT] Using manual code: '{code}'")

            # ایجاد Product مستقیماً (بدون استفاده از repo.create که commit می‌کند)
            # تا همه چیز در یک transaction باشد و بتوانیم در صورت خطا rollback کنیم
            obj = Product(
                business_id=business_id,
                item_type=payload.item_type,
                code=code,
                name=payload.name.strip(),
                description=payload.description,
                category_id=payload.category_id,
                main_unit=main_unit,
                secondary_unit=secondary_unit,
                unit_conversion_factor=payload.unit_conversion_factor,
                base_sales_price=payload.base_sales_price,
                base_sales_note=payload.base_sales_note,
                base_purchase_price=payload.base_purchase_price,
                base_purchase_note=payload.base_purchase_note,
                track_inventory=payload.track_inventory,
                reorder_point=payload.reorder_point,
                min_order_qty=payload.min_order_qty,
                lead_time_days=payload.lead_time_days,
                inventory_mode=payload.inventory_mode or "bulk",
                track_serial=payload.track_serial if payload.track_serial is not None else False,
                track_barcode=payload.track_barcode if payload.track_barcode is not None else False,
                is_sales_taxable=payload.is_sales_taxable,
                is_purchase_taxable=payload.is_purchase_taxable,
                sales_tax_rate=payload.sales_tax_rate,
                purchase_tax_rate=payload.purchase_tax_rate,
                tax_type_id=payload.tax_type_id,
                tax_code=payload.tax_code,
                tax_unit_id=payload.tax_unit_id,
                image_file_id=payload.image_file_id,
                default_warehouse_id=payload.default_warehouse_id,
                is_active=payload.is_active if payload.is_active is not None else True,  # پیش‌فرض True
                general_barcodes=stored_gb_create,
                is_public_catalog=bool(payload.is_public_catalog),
                catalog_public_uuid=str(uuid_module.uuid4()) if payload.is_public_catalog else None,
            )
            logger.debug(f"[CREATE_PRODUCT] Adding product to session - code='{code}', name='{payload.name}'")
            db.add(obj)
            logger.debug(f"[CREATE_PRODUCT] Flushing to get ID...")
            db.flush()  # Flush برای دریافت id، اما commit نمی‌کند
            logger.info(f"[CREATE_PRODUCT] Product flushed - ID={obj.id}")

            assert_tokens_unique_among_products(db, business_id, gb_tokens_create, exclude_product_id=None)
            assert_tokens_not_used_by_unique_instances(db, business_id, gb_tokens_create, exclude_product_id=None)
            replace_general_barcode_aliases(db, business_id, obj.id, gb_tokens_create)

            # _upsert_attributes را بدون commit صدا می‌زنیم تا همه چیز در یک transaction باشد
            logger.debug(f"[CREATE_PRODUCT] Upserting attributes - attribute_ids={payload.attribute_ids}")
            _upsert_attributes(db, obj.id, business_id, payload.attribute_ids, auto_commit=False)
            
            # Commit همه چیز (product و attributes)
            logger.info(f"[CREATE_PRODUCT] Committing transaction for product ID={obj.id}...")
            db.commit()
            logger.info(f"[CREATE_PRODUCT] ✅ Transaction COMMITTED successfully for product ID={obj.id}")
            db.refresh(obj)  # Refresh برای دریافت اطلاعات کامل
            logger.debug(f"[CREATE_PRODUCT] Product refreshed - final code='{obj.code}', name='{obj.name}'")

            data = _to_dict(obj, db)
            # enrich titles from payload if provided
            if getattr(payload, 'main_unit_title', None):
                data["main_unit_title"] = str(getattr(payload, 'main_unit_title'))
            if getattr(payload, 'secondary_unit_title', None):
                data["secondary_unit_title"] = str(getattr(payload, 'secondary_unit_title'))

            if not defer_cache_invalidation:
                logger.debug(f"[CREATE_PRODUCT] Invalidating cache - business_id={business_id}, category_id={payload.category_id}")
                invalidate_products_cache(
                    business_id=business_id,
                    category_id=payload.category_id
                )
                invalidate_public_catalog_caches()

            logger.info(f"[CREATE_PRODUCT] ✅ Product created successfully - ID={obj.id}, code='{obj.code}', name='{obj.name}'")
            return {"message": "PRODUCT_CREATED", "data": data}
            
        except IntegrityError as e:
            # خطای تکراری بودن کد (UniqueConstraint violation)
            logger.warning(f"[CREATE_PRODUCT] IntegrityError caught (attempt {retry_count + 1}): {e}")
            logger.debug(f"[CREATE_PRODUCT] Rolling back transaction...")
            db.rollback()
            err_txt = str(getattr(e, "orig", e)).lower()
            if "uq_product_general_barcode_business_token" in err_txt or "product_general_barcode_aliases" in err_txt:
                raise ApiError(
                    "DUPLICATE_GENERAL_BARCODE",
                    "بارکد عمومی تکراری است یا قبلاً برای کالای دیگری ثبت شده است",
                    http_status=409,
                )
            retry_count += 1
            logger.info(f"[CREATE_PRODUCT] Will retry (retry_count={retry_count}/{max_retries})")
            
            # اگر کد دستی بود و تکراری است، بلافاصله خطا بده
            if manual_code:
                raise ApiError("DUPLICATE_PRODUCT_CODE", "کد کالا/خدمت تکراری است", http_status=400)
            
            # اگر کد خودکار بود و تکراری شد، دوباره تلاش کن
            if retry_count >= max_retries:
                if manual_code:
                    raise ApiError(
                        "DUPLICATE_PRODUCT_CODE",
                        "کد کالا/خدمت تکراری است",
                        http_status=400,
                    )
                raise ApiError(
                    "PRODUCT_CREATE_RETRY_EXHAUSTED",
                    "ثبت کالا پس از چند تلاش ناموفق بود؛ لطفاً دوباره تلاش کنید.",
                    http_status=503,
                )
            
            # Retry: کد خودکار دوباره تولید می‌شود
            continue
            
        except ApiError:
            # خطاهای دیگر (مثل DUPLICATE_PRODUCT_CODE از بررسی دستی) را propagate کن
            db.rollback()
            raise
            
        except Exception as e:
            # سایر خطاها
            logger.error(f"[CREATE_PRODUCT] ❌ Unexpected exception (attempt {retry_count + 1}): {e}", exc_info=True)
            logger.error(f"[CREATE_PRODUCT] Exception type: {type(e).__name__}, args: {e.args}")
            db.rollback()
            logger.debug(f"[CREATE_PRODUCT] Transaction rolled back due to exception")
            raise


def list_products(db: Session, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
    repo = ProductRepository(db)
    take = int(query.get("take", 20) or 20)
    skip = int(query.get("skip", 0) or 0)
    sort_by = query.get("sort_by")
    sort_desc = bool(query.get("sort_desc", True))
    sort_multi = query.get("sort") if isinstance(query.get("sort"), list) else None
    search = query.get("search")
    filters = query.get("filters")
    include_inventory = bool(query.get("include_inventory", False))
    inventory_as_of_date = query.get("inventory_as_of_date")
    raw_category_ids = query.get("category_ids")
    raw_sf = query.get("search_fields") or query.get("searchFields")
    search_fields: Optional[List[str]] = raw_sf if isinstance(raw_sf, list) else None
    category_ids: Optional[List[int]] = None
    if isinstance(raw_category_ids, list) and raw_category_ids:
        category_ids = []
        for x in raw_category_ids:
            try:
                if x is not None:
                    category_ids.append(int(x))
            except (TypeError, ValueError):
                pass
        if not category_ids:
            category_ids = None
    return repo.search(
        business_id=business_id,
        take=take,
        skip=skip,
        sort_by=sort_by,
        sort_desc=sort_desc,
        sort=sort_multi,
        search=search,
        search_fields=search_fields,
        filters=filters,
        category_ids=category_ids,
        include_inventory=include_inventory,
        inventory_as_of_date=inventory_as_of_date,
    )


def list_recent_sales_invoice_products(
    db: Session,
    business_id: int,
    take: int = 10,
    category_ids: Optional[List[int]] = None,
) -> Dict[str, Any]:
    """
    کالاهایی که اخیراً در فاکتور فروش (غیر پیش‌فاکتور) در ردیف‌های فاکتور آمده‌اند،
    به ترتیب جدیدترین فاکتور (بر اساس created_at سند).
    """
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from adapters.db.models.document import Document
    from app.services.invoice_service import INVOICE_SALES

    take = max(1, min(50, int(take)))
    last_at = func.max(Document.created_at).label("last_at")
    stmt = (
        select(InvoiceItemLine.product_id, last_at)
        .join(Document, Document.id == InvoiceItemLine.document_id)
        .where(
            Document.business_id == int(business_id),
            Document.document_type == INVOICE_SALES,
            Document.is_proforma.is_(False),
        )
    )
    if category_ids:
        stmt = stmt.join(Product, Product.id == InvoiceItemLine.product_id).where(
            Product.business_id == int(business_id),
            Product.category_id.in_(list(category_ids)),
        )
    stmt = (
        stmt.group_by(InvoiceItemLine.product_id)
        .order_by(desc(last_at))
        .limit(take * 3)
    )
    rows = list(db.execute(stmt).all())
    ordered_ids: List[int] = []
    for r in rows:
        pid = r[0]
        if pid is None:
            continue
        try:
            ordered_ids.append(int(pid))
        except (TypeError, ValueError):
            continue

    items: List[Dict[str, Any]] = []
    seen: set[int] = set()
    for pid in ordered_ids:
        if pid in seen:
            continue
        seen.add(pid)
        row = get_product(db, pid, business_id)
        if row is None:
            continue
        if row.get("is_active") is False:
            continue
        items.append(row)
        if len(items) >= take:
            break

    return {
        "items": items,
        "total_count": len(items),
        "has_more": False,
        "pagination": {
            "total": len(items),
            "page": 1,
            "per_page": take,
            "total_pages": 1,
            "has_next": False,
            "has_prev": False,
        },
    }


def get_product(db: Session, product_id: int, business_id: int) -> Optional[Dict[str, Any]]:
    obj = db.get(Product, product_id)
    if not obj or obj.business_id != business_id:
        return None
    return _to_dict(obj, db)


def update_product(
    db: Session,
    product_id: int,
    business_id: int,
    payload: ProductUpdateRequest,
    *,
    defer_cache_invalidation: bool = False,
) -> Optional[Dict[str, Any]]:
    repo = ProductRepository(db)
    obj = db.get(Product, product_id)
    if not obj or obj.business_id != business_id:
        return None

    # Process code: اگر code خالی یا None باشد، باید None بماند تا کد خودکار تولید نشود
    # اما در update، اگر code موجود است و خالی نیست، باید بررسی تکراری شود
    code_value = None
    if payload.code is not None:
        code_str = payload.code.strip() if isinstance(payload.code, str) else str(payload.code).strip()
        if code_str:  # فقط اگر کد خالی نباشد
            code_value = code_str
            if code_value != obj.code:  # اگر کد تغییر کرده
                dup = db.query(Product).filter(and_(Product.business_id == business_id, Product.code == code_value, Product.id != product_id)).first()
                if dup:
                    raise ApiError("DUPLICATE_PRODUCT_CODE", "کد کالا/خدمت تکراری است", http_status=400)

    _validate_tax(payload)
    # از فیلدهای explicitly-set برای تشخیص پاک‌سازی (None) استفاده کن
    fields_set = getattr(payload, 'model_fields_set', getattr(payload, '__fields_set__', set()))
    # بررسی نوع کالا (از payload یا مقدار موجود)
    item_type = payload.item_type if 'item_type' in fields_set else obj.item_type.value if hasattr(obj.item_type, 'value') else str(obj.item_type)
    _validate_item_type_inventory(payload, existing_item_type=item_type)
    # برای default_warehouse_id، بررسی می‌کنیم که آیا در fields_set است یا نه
    default_warehouse_id_updated = 'default_warehouse_id' in fields_set
    # اگر default_warehouse_id در fields_set است، مقدار آن را استفاده می‌کنیم (حتی اگر null باشد)
    # در غیر این صورت، مقدار قبلی را نگه می‌داریم
    # Validate and clean unit strings
    main_unit_val = (_validate_unit_string(payload.main_unit) if 'main_unit' in fields_set else obj.main_unit)
    secondary_unit_val = (_validate_unit_string(payload.secondary_unit) if 'secondary_unit' in fields_set else obj.secondary_unit)
    factor_val = payload.unit_conversion_factor if 'unit_conversion_factor' in fields_set else obj.unit_conversion_factor
    _validate_units(main_unit_val, secondary_unit_val, factor_val)

    gb_handled = False
    general_barcodes_val: Optional[str] = None
    general_tokens: List[str] = []
    if 'general_barcodes' in fields_set:
        gb_handled = True
        general_barcodes_val, general_tokens = normalize_general_barcodes_storage(payload.general_barcodes)
    elif 'barcode' in fields_set:
        gb_handled = True
        bc = payload.barcode
        if bc is None or (isinstance(bc, str) and not str(bc).strip()):
            general_barcodes_val, general_tokens = normalize_general_barcodes_storage(None)
        else:
            general_barcodes_val, general_tokens = normalize_general_barcodes_storage(str(bc).strip())

    if gb_handled:
        assert_tokens_unique_among_products(db, business_id, general_tokens, exclude_product_id=product_id)
        assert_tokens_not_used_by_unique_instances(db, business_id, general_tokens, exclude_product_id=product_id)

    # فقط اگر code در fields_set است و مقدار دارد، آن را به‌روزرسانی کن
    # اگر code در fields_set نیست یا None است، مقدار قبلی را نگه می‌داریم
    code_to_update = code_value if 'code' in fields_set else None

    # بررسی تغییر inventory_mode از bulk به unique
    old_inventory_mode = obj.inventory_mode or "bulk"
    new_inventory_mode = payload.inventory_mode if 'inventory_mode' in fields_set else old_inventory_mode
    converting_to_unique = (old_inventory_mode != "unique" and new_inventory_mode == "unique")
    
    # اگر در حال تبدیل به unique هستیم و موجودی داریم، باید instance ها ایجاد شوند
    if converting_to_unique and obj.track_inventory:
        from app.services.warehouse_service import get_warehouse_stock_report
        from datetime import date as date_type
        from adapters.db.models.product_instance import ProductInstance
        from decimal import Decimal
        
        # محاسبه موجودی فعلی
        stock_report = get_warehouse_stock_report(
            db=db,
            business_id=business_id,
            query={
                "product_ids": [str(product_id)],
                "as_of_date": date_type.today().isoformat(),
                "include_zero": False,
            },
        )
        
        total_stock = sum(item.get("quantity", 0) for item in stock_report.get("items", []))
        
        if total_stock > 0:
            # اگر موجودی داریم، باید هشدار بدهیم یا instance ها را ایجاد کنیم
            # در اینجا فقط هشدار می‌دهیم و از کاربر می‌خواهیم که از endpoint تبدیل استفاده کند
            raise ApiError(
                "CONVERSION_REQUIRES_INSTANCES",
                f"برای تبدیل کالا به حالت یونیک، باید برای {int(total_stock)} واحد موجودی instance ایجاد شود. لطفاً از endpoint تبدیل استفاده کنید: POST /api/v1/product-instances/business/{business_id}/product/{product_id}/convert-to-unique",
                http_status=400
            )

    gb_kw = {}
    if gb_handled:
        gb_kw["general_barcodes"] = general_barcodes_val

    catalog_uuid_kw: Dict[str, Any] = {}
    if "is_public_catalog" in fields_set and payload.is_public_catalog and not getattr(obj, "catalog_public_uuid", None):
        catalog_uuid_kw["catalog_public_uuid"] = str(uuid_module.uuid4())

    updated = repo.update(
        product_id,
        commit=False,
        item_type=payload.item_type if payload.item_type is not None else None,
        code=code_to_update,
        name=payload.name.strip() if isinstance(payload.name, str) else None,
        description=payload.description,
        category_id=payload.category_id,
        main_unit=main_unit_val if 'main_unit' in fields_set else None,
        secondary_unit=secondary_unit_val if 'secondary_unit' in fields_set else None,
        unit_conversion_factor=payload.unit_conversion_factor,
        base_sales_price=payload.base_sales_price,
        base_sales_note=payload.base_sales_note,
        base_purchase_price=payload.base_purchase_price,
        base_purchase_note=payload.base_purchase_note,
        track_inventory=payload.track_inventory if payload.track_inventory is not None else None,
        reorder_point=payload.reorder_point,
        min_order_qty=payload.min_order_qty,
        lead_time_days=payload.lead_time_days,
        inventory_mode=payload.inventory_mode if 'inventory_mode' in fields_set else None,
        track_serial=(
            payload.track_serial if payload.track_serial is not None else False
        ) if 'track_serial' in fields_set else None,
        track_barcode=(
            payload.track_barcode if payload.track_barcode is not None else False
        ) if 'track_barcode' in fields_set else None,
        is_sales_taxable=(
            payload.is_sales_taxable if payload.is_sales_taxable is not None else False
        ) if 'is_sales_taxable' in fields_set else None,
        is_purchase_taxable=(
            payload.is_purchase_taxable if payload.is_purchase_taxable is not None else False
        ) if 'is_purchase_taxable' in fields_set else None,
        sales_tax_rate=payload.sales_tax_rate,
        purchase_tax_rate=payload.purchase_tax_rate,
        tax_type_id=payload.tax_type_id,
        tax_code=payload.tax_code,
        tax_unit_id=payload.tax_unit_id,
        image_file_id=payload.image_file_id if 'image_file_id' in fields_set else None,
        is_active=(
            payload.is_active if payload.is_active is not None else True
        ) if 'is_active' in fields_set else None,
        is_public_catalog=(
            payload.is_public_catalog if payload.is_public_catalog is not None else False
        ) if 'is_public_catalog' in fields_set else None,
        default_warehouse_id=(
            None if item_type == ProductItemType.SERVICE.value
            else (
                payload.default_warehouse_id if default_warehouse_id_updated
                else obj.default_warehouse_id
            )
        ),
        **catalog_uuid_kw,
        **gb_kw,
    )
    if not updated:
        return None

    if gb_handled:
        replace_general_barcode_aliases(db, business_id, product_id, general_tokens)

    _upsert_attributes(db, product_id, business_id, payload.attribute_ids, auto_commit=False)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ApiError(
            "GENERAL_BARCODE_CONFLICT",
            "بارکد عمومی تکراری است یا با دادهٔ دیگر در تداخل است",
            http_status=409,
        )
    db.refresh(updated)
    
    if not defer_cache_invalidation:
        old_category_id = obj.category_id if obj else None
        new_category_id = payload.category_id if 'category_id' in fields_set else old_category_id

        invalidate_products_cache(
            business_id=business_id,
            product_id=product_id,
            category_id=old_category_id
        )

        if new_category_id != old_category_id and new_category_id is not None:
            invalidate_products_cache(
                business_id=business_id,
                category_id=new_category_id
            )
        invalidate_public_catalog_caches()

    data = _to_dict(updated, db)
    return {"message": "PRODUCT_UPDATED", "data": data}


def preview_bulk_default_warehouse_update(
    db: Session,
    business_id: int,
    payload: Any,
) -> Dict[str, Any]:
    """
    پیش‌نمایش تغییر گروهی انبار پیش‌فرض کالاها.
    payload: BulkDefaultWarehouseRequest (به دلیل جلوگیری از import cycle به صورت Any)
    """
    from sqlalchemy import and_
    from adapters.db.models.product import Product
    from adapters.db.models.warehouse import Warehouse
    from adapters.api.v1.schema_models.product import ProductItemType

    ids = list({int(x) for x in (payload.ids or []) if x})
    if not ids:
        return {
            "total_requested": 0,
            "found_count": 0,
            "will_update_count": 0,
            "skipped": [],
            "notes": [],
        }

    # Validate warehouse id (if provided)
    if payload.default_warehouse_id is not None:
        wh = db.query(Warehouse).filter(
            and_(Warehouse.business_id == business_id, Warehouse.id == int(payload.default_warehouse_id))
        ).first()
        if not wh:
            raise ApiError("WAREHOUSE_NOT_FOUND", "انبار انتخاب‌شده یافت نشد", http_status=404)

    # Load products
    rows = (
        db.query(Product)
        .filter(and_(Product.business_id == business_id, Product.id.in_(ids)))
        .all()
    )
    by_id = {int(p.id): p for p in rows}

    apply_scope = str(getattr(payload, "apply_scope", "all"))
    skipped = []
    will_update = 0
    notes = []

    def _scope_ok(p: Product) -> bool:
        if apply_scope == "track_inventory_true":
            return bool(getattr(p, "track_inventory", False)) is True
        if apply_scope == "track_inventory_false":
            return bool(getattr(p, "track_inventory", False)) is False
        return True

    # Missing ids
    missing = [pid for pid in ids if pid not in by_id]
    for pid in missing:
        skipped.append({"id": pid, "reason": "NOT_FOUND"})

    forced_service_to_null = 0

    for pid in ids:
        p = by_id.get(pid)
        if not p:
            continue
        if not _scope_ok(p):
            skipped.append({"id": pid, "reason": "SCOPE_MISMATCH", "code": getattr(p, "code", None), "name": getattr(p, "name", None)})
            continue

        # خدمات: انبار پیش‌فرض باید null باشد
        item_type_val = getattr(p, "item_type", None)
        item_type_str = item_type_val.value if hasattr(item_type_val, "value") else str(item_type_val or "")
        if item_type_str == ProductItemType.SERVICE.value:
            target = None
            if getattr(p, "default_warehouse_id", None) is None:
                skipped.append({"id": pid, "reason": "SERVICE_ALREADY_NULL", "code": getattr(p, "code", None), "name": getattr(p, "name", None)})
            else:
                forced_service_to_null += 1
                will_update += 1
            continue

        target = payload.default_warehouse_id
        if getattr(p, "default_warehouse_id", None) == target:
            skipped.append({"id": pid, "reason": "ALREADY_SET", "code": getattr(p, "code", None), "name": getattr(p, "name", None)})
            continue
        will_update += 1

    if forced_service_to_null:
        notes.append(f"{forced_service_to_null} خدمت به‌صورت خودکار بدون انبار پیش‌فرض ذخیره می‌شود.")

    return {
        "total_requested": len(ids),
        "found_count": len(rows),
        "will_update_count": will_update,
        "forced_service_null_count": forced_service_to_null,
        "skipped": skipped,
        "notes": notes,
    }


def apply_bulk_default_warehouse_update(
    db: Session,
    business_id: int,
    user_id: int | None,
    payload: Any,
) -> Dict[str, Any]:
    """
    اعمال تغییر گروهی انبار پیش‌فرض کالاها.
    payload: BulkDefaultWarehouseRequest (به دلیل جلوگیری از import cycle به صورت Any)
    """
    from sqlalchemy import and_
    from adapters.db.models.product import Product
    from adapters.db.models.warehouse import Warehouse
    from adapters.api.v1.schema_models.product import ProductItemType

    ids = list({int(x) for x in (payload.ids or []) if x})
    if not ids:
        return {
            "total_requested": 0,
            "found_count": 0,
            "updated_count": 0,
            "skipped": [],
            "notes": [],
        }

    # Validate warehouse id (if provided)
    if payload.default_warehouse_id is not None:
        wh = db.query(Warehouse).filter(
            and_(Warehouse.business_id == business_id, Warehouse.id == int(payload.default_warehouse_id))
        ).first()
        if not wh:
            raise ApiError("WAREHOUSE_NOT_FOUND", "انبار انتخاب‌شده یافت نشد", http_status=404)

    rows = (
        db.query(Product)
        .filter(and_(Product.business_id == business_id, Product.id.in_(ids)))
        .all()
    )
    by_id = {int(p.id): p for p in rows}

    apply_scope = str(getattr(payload, "apply_scope", "all"))
    skipped = []
    updated_count = 0
    notes = []

    def _scope_ok(p: Product) -> bool:
        if apply_scope == "track_inventory_true":
            return bool(getattr(p, "track_inventory", False)) is True
        if apply_scope == "track_inventory_false":
            return bool(getattr(p, "track_inventory", False)) is False
        return True

    # Missing ids
    missing = [pid for pid in ids if pid not in by_id]
    for pid in missing:
        skipped.append({"id": pid, "reason": "NOT_FOUND"})

    forced_service_to_null = 0

    for pid in ids:
        p = by_id.get(pid)
        if not p:
            continue
        if not _scope_ok(p):
            skipped.append({"id": pid, "reason": "SCOPE_MISMATCH", "code": getattr(p, "code", None), "name": getattr(p, "name", None)})
            continue

        # خدمات: انبار پیش‌فرض باید null باشد
        item_type_val = getattr(p, "item_type", None)
        item_type_str = item_type_val.value if hasattr(item_type_val, "value") else str(item_type_val or "")
        if item_type_str == ProductItemType.SERVICE.value:
            target = None
            if getattr(p, "default_warehouse_id", None) is None:
                skipped.append({"id": pid, "reason": "SERVICE_ALREADY_NULL", "code": getattr(p, "code", None), "name": getattr(p, "name", None)})
                continue
            p.default_warehouse_id = None
            forced_service_to_null += 1
            updated_count += 1
            # Cache invalidation
            invalidate_products_cache(
                business_id=business_id,
                product_id=pid,
                category_id=getattr(p, "category_id", None),
            )
            continue

        target = payload.default_warehouse_id
        if getattr(p, "default_warehouse_id", None) == target:
            skipped.append({"id": pid, "reason": "ALREADY_SET", "code": getattr(p, "code", None), "name": getattr(p, "name", None)})
            continue
        p.default_warehouse_id = target
        updated_count += 1
        invalidate_products_cache(
            business_id=business_id,
            product_id=pid,
            category_id=getattr(p, "category_id", None),
        )

    if forced_service_to_null:
        notes.append(f"{forced_service_to_null} خدمت به‌صورت خودکار بدون انبار پیش‌فرض ذخیره شد.")

    db.flush()
    return {
        "total_requested": len(ids),
        "found_count": len(rows),
        "updated_count": updated_count,
        "forced_service_null_count": forced_service_to_null,
        "skipped": skipped,
        "notes": notes,
    }


def check_product_has_related_documents(db: Session, product_id: int) -> tuple[bool, list[str]]:
    """
    بررسی وجود اسناد حسابداری، حواله‌های انبار و خطوط فاکتور مرتبط با کالا
    
    Returns:
        tuple: (has_documents, document_types)
        - has_documents: True اگر سند مرتبطی وجود داشته باشد
        - document_types: لیست انواع اسناد مرتبط
    """
    from adapters.db.models.document import Document
    from adapters.db.models.document_line import DocumentLine
    from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    
    related_types = []
    
    # بررسی وجود خطوط سند با product_id در اسناد قطعی (غیر پیش‌نویس)
    document_lines_count = db.query(func.count(DocumentLine.id)).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        DocumentLine.product_id == product_id,
        Document.is_proforma == False
    ).scalar()
    
    if document_lines_count and document_lines_count > 0:
        # دریافت انواع اسناد مرتبط
        document_types = db.query(Document.document_type).join(
            DocumentLine, Document.id == DocumentLine.document_id
        ).filter(
            DocumentLine.product_id == product_id,
            Document.is_proforma == False
        ).distinct().all()
        
        types_list = [doc_type[0] for doc_type in document_types if doc_type[0]]
        
        # تبدیل انواع اسناد به نام‌های فارسی
        type_mapping = {
            "invoice_sales": "فاکتور فروش",
            "invoice_sales_return": "برگشت از فروش",
            "invoice_purchase": "فاکتور خرید",
            "invoice_purchase_return": "برگشت از خرید",
            "invoice_direct_consumption": "مصرف مستقیم",
            "invoice_production": "تولید",
            "invoice_waste": "ضایعات",
            "receipt": "دریافت",
            "payment": "پرداخت",
            "expense": "هزینه",
            "income": "درآمد",
            "transfer": "انتقال",
            "manual": "سند دستی",
            "check": "چک",
        }
        
        for doc_type in types_list:
            type_name = type_mapping.get(doc_type, doc_type)
            if type_name not in related_types:
                related_types.append(type_name)
    
    # بررسی وجود حواله‌های انبار مرتبط
    warehouse_lines_count = db.query(func.count(WarehouseDocumentLine.id)).filter(
        WarehouseDocumentLine.product_id == product_id
    ).scalar()
    
    if warehouse_lines_count and warehouse_lines_count > 0:
        if "حواله انبار" not in related_types:
            related_types.append("حواله انبار")
    
    # بررسی وجود خطوط فاکتور مرتبط
    invoice_lines_count = db.query(func.count(InvoiceItemLine.id)).filter(
        InvoiceItemLine.product_id == product_id
    ).scalar()
    
    if invoice_lines_count and invoice_lines_count > 0:
        if "خط فاکتور" not in related_types:
            related_types.append("خط فاکتور")
    
    # بررسی استفاده در فرمول تولید (BOM) - component یا output
    from adapters.db.models.product_bom import ProductBOMItem, ProductBOMOutput
    bom_component_count = db.query(func.count(ProductBOMItem.id)).filter(
        ProductBOMItem.component_product_id == product_id
    ).scalar()
    bom_output_count = db.query(func.count(ProductBOMOutput.id)).filter(
        ProductBOMOutput.output_product_id == product_id
    ).scalar()
    if (bom_component_count and bom_component_count > 0) or (bom_output_count and bom_output_count > 0):
        if "فرمول تولید (BOM)" not in related_types:
            related_types.append("فرمول تولید (BOM)")
    
    return len(related_types) > 0, related_types


def delete_product(db: Session, product_id: int, business_id: int) -> tuple[bool, str | None]:
    """
    حذف کالا
    
    Returns:
        tuple: (success, error_message)
        - success: True اگر حذف موفق باشد
        - error_message: پیام خطا در صورت عدم موفقیت
    """
    obj = db.get(Product, product_id)
    if not obj or obj.business_id != business_id:
        return False, "کالا یافت نشد"
    
    # بررسی وجود اسناد مرتبط
    has_documents, document_types = check_product_has_related_documents(db, product_id)
    
    if has_documents:
        types_str = "، ".join(document_types)
        error_msg = f"امکان حذف این کالا وجود ندارد زیرا دارای اسناد مرتبط است. انواع اسناد: {types_str}"
        return False, error_msg
    
    try:
        # دریافت category_id قبل از حذف
        category_id = obj.category_id if obj else None
        
        repo = ProductRepository(db)
        success = repo.delete(product_id)
        if success:
            # Invalidate cache بعد از حذف موفق محصول
            invalidate_products_cache(
                business_id=business_id,
                product_id=product_id,
                category_id=category_id
            )
            if getattr(obj, "is_public_catalog", False):
                invalidate_public_catalog_caches()
            return True, None
        else:
            return False, "خطا در حذف کالا"
    except Exception as e:
        return False, f"خطا در حذف کالا: {str(e)}"


def _get_image_url(obj: Product) -> str | None:
    """تولید URL برای نمایش عکس محصول (فایل اصلی)"""
    if not obj.image_file_id:
        return None
    return f"/api/v1/business/{obj.business_id}/storage/files/{obj.image_file_id}/download"


def _get_thumbnail_url(obj: Product) -> str | None:
    """تولید URL برای نمایش thumbnail عکس محصول"""
    if not obj.image_file_id:
        return None
    return f"/api/v1/business/{obj.business_id}/storage/files/{obj.image_file_id}/thumbnail?size=small"


def _to_dict(obj: Product, db: Optional[Session] = None) -> Dict[str, Any]:
    # دریافت attribute_ids از ProductAttributeLink
    attribute_ids = []
    if db is not None:
        links = db.query(ProductAttributeLink).filter(ProductAttributeLink.product_id == obj.id).all()
        attribute_ids = [link.attribute_id for link in links]
    
    return {
        "id": obj.id,
        "business_id": obj.business_id,
        "item_type": obj.item_type.value if hasattr(obj.item_type, 'value') else str(obj.item_type),
        "code": obj.code,
        "name": obj.name,
        "description": obj.description,
        "category_id": obj.category_id,
        "main_unit": obj.main_unit,
        "secondary_unit": obj.secondary_unit,
        "unit_conversion_factor": obj.unit_conversion_factor,
        "base_sales_price": obj.base_sales_price,
        "base_sales_note": obj.base_sales_note,
        "base_purchase_price": obj.base_purchase_price,
        "base_purchase_note": obj.base_purchase_note,
        "track_inventory": obj.track_inventory,
        "reorder_point": obj.reorder_point,
        "min_order_qty": obj.min_order_qty,
        "lead_time_days": obj.lead_time_days,
        "inventory_mode": obj.inventory_mode or "bulk",
        "track_serial": obj.track_serial,
        "track_barcode": obj.track_barcode,
        "is_sales_taxable": obj.is_sales_taxable,
        "is_purchase_taxable": obj.is_purchase_taxable,
        "sales_tax_rate": obj.sales_tax_rate,
        "purchase_tax_rate": obj.purchase_tax_rate,
        "tax_type_id": obj.tax_type_id,
        "tax_code": obj.tax_code,
        "tax_unit_id": obj.tax_unit_id,
        "attribute_ids": attribute_ids,
        "image_file_id": obj.image_file_id,
        "image_url": _get_image_url(obj) if obj.image_file_id else None,
        "thumbnail_url": _get_thumbnail_url(obj) if obj.image_file_id else None,
        "default_warehouse_id": obj.default_warehouse_id,
        "default_warehouse_name": obj.default_warehouse.name if obj.default_warehouse else None,
        "default_warehouse_code": obj.default_warehouse.code if obj.default_warehouse else None,
        "general_barcodes": getattr(obj, "general_barcodes", None),
        "barcode": _legacy_barcode_field_from_general_csv(getattr(obj, "general_barcodes", None)),
        "is_active": obj.is_active if hasattr(obj, 'is_active') else True,  # مقدار پیش‌فرض True در صورت عدم وجود فیلد
        "is_public_catalog": bool(getattr(obj, "is_public_catalog", False)),
        "catalog_public_uuid": getattr(obj, "catalog_public_uuid", None),
        "created_at": obj.created_at,
        "updated_at": obj.updated_at,
    }


def get_item_movements_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    product_ids: Optional[List[int]] = None,
    warehouse_ids: Optional[List[int]] = None,
    category_ids: Optional[List[int]] = None,
    include_zero_balance: bool = False,
    search: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش گردش کالا
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        product_ids: لیست شناسه‌های کالاها (اختیاری)
        warehouse_ids: لیست شناسه‌های انبارها (اختیاری)
        category_ids: لیست شناسه‌های دسته‌بندی‌ها (اختیاری)
        include_zero_balance: نمایش کالاهای با مانده صفر
        search: جستجو در کد یا نام کالا (اختیاری)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست کالاها با آمار گردش,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    from app.services.invoice_service import _compute_available_stock, _iter_product_movements
    
    # Query پایه: فقط کالاهای با کنترل موجودی
    # Join با Category برای دریافت نام دسته‌بندی
    # استفاده از load_only برای بارگذاری فقط فیلدهای مورد نیاز (برای جلوگیری از خطای فیلدهای جدید)
    query = db.query(Product).options(
        load_only(
            Product.id,
            Product.code,
            Product.name,
            Product.category_id,
            Product.main_unit,
            Product.track_inventory,
        )
    ).outerjoin(
        BusinessCategory, Product.category_id == BusinessCategory.id
    ).filter(
        Product.business_id == business_id,
        Product.track_inventory == True,  # فقط کالاهای با کنترل موجودی
    )
    
    # فیلتر کالاها
    if product_ids:
        query = query.filter(Product.id.in_(product_ids))
    
    # فیلتر دسته‌بندی
    if category_ids:
        query = query.filter(Product.category_id.in_(category_ids))
    
    # فیلتر جستجو
    if search and search.strip():
        search_filter = or_(
            Product.code.ilike(f'%{search}%'),
            Product.name.ilike(f'%{search}%'),
        )
        query = query.filter(search_filter)
    
    # دریافت همه کالاهای فیلتر شده
    # query محصولات و دسته‌بندی‌ها را با هم برمی‌گرداند
    results = query.all()
    products = results
    
    # ساخت dict برای دسترسی سریع به category
    category_dict = {}
    if results:
        category_ids_from_results = {p.category_id for p in results if p.category_id}
        if category_ids_from_results:
            categories = db.query(BusinessCategory).filter(
                BusinessCategory.id.in_(list(category_ids_from_results))
            ).all()
            for cat in categories:
                # استخراج نام از title_translations (اول fa، سپس en)
                title = ''
                if isinstance(cat.title_translations, dict):
                    title = cat.title_translations.get('fa') or cat.title_translations.get('en') or cat.title_translations.get('default') or ''
                category_dict[cat.id] = {
                    'name': title,
                    'code': str(cat.id),  # از ID به عنوان code استفاده می‌کنیم
                }
    
    # تبدیل تاریخ‌ها
    date_from_obj = None
    date_to_obj = None
    date_before_from = None
    
    if date_from:
        try:
            date_from_obj = datetime.strptime(date_from, '%Y-%m-%d').date()
            date_before_from = date_from_obj - timedelta(days=1)
        except Exception:
            pass
    
    if date_to:
        try:
            date_to_obj = datetime.strptime(date_to, '%Y-%m-%d').date()
        except Exception:
            pass
    
    # اگر تاریخ‌ها مشخص نشده‌اند، از سال مالی استفاده کن
    if date_from_obj is None or date_to_obj is None:
        try:
            from adapters.db.models.fiscal_year import FiscalYear
            if fiscal_year_id:
                fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
            else:
                fiscal_year = db.query(FiscalYear).filter(
                    and_(
                        FiscalYear.business_id == business_id,
                        FiscalYear.is_last == True
                    )
                ).first()
            
            if fiscal_year:
                if date_from_obj is None:
                    date_from_obj = fiscal_year.start_date
                    date_before_from = date_from_obj - timedelta(days=1)
                if date_to_obj is None:
                    date_to_obj = fiscal_year.end_date if fiscal_year.end_date else date.today()
        except Exception:
            pass
    
    # اگر هنوز تاریخ مشخص نشده
    if date_to_obj is None:
        date_to_obj = date.today()
    if date_from_obj is None:
        date_from_obj = date.today()
        date_before_from = date_from_obj - timedelta(days=1)
    
    # محاسبه گردش برای هر کالا
    items = []
    
    for product in products:
        # مانده ابتدای دوره (تا یک روز قبل از date_from)
        opening_balance = Decimal(0)
        if date_before_from:
            if warehouse_ids:
                # محاسبه به تفکیک انبار
                opening_balance = sum(
                    _compute_available_stock(db, business_id, product.id, wh_id, date_before_from)
                    for wh_id in warehouse_ids
                )
            else:
                # محاسبه کل (بدون تفکیک انبار)
                opening_balance = _compute_available_stock(db, business_id, product.id, None, date_before_from)
        else:
            opening_balance = Decimal(0)
        
        # محاسبه ورود و خروج در دوره (بین date_from و date_to)
        total_in = Decimal(0)
        total_out = Decimal(0)
        
        # دریافت حرکات تا date_to
        movements = _iter_product_movements(
            db,
            business_id,
            [product.id],
            warehouse_ids,
            date_to_obj,
        )
        
        # فیلتر حرکات در بازه دوره
        for mv in movements:
            mv_date = mv.get("document_date")
            if not mv_date:
                continue
            
            # فقط حرکات بین date_from و date_to
            if mv_date < date_from_obj:
                continue
            if mv_date > date_to_obj:
                continue
            
            qty = Decimal(str(mv.get("quantity") or 0))
            movement = mv.get("movement")
            
            if movement == "in":
                total_in += qty
            elif movement == "out":
                total_out += qty
        
        # مانده انتهای دوره
        closing_balance = opening_balance + total_in - total_out
        
        # اگر include_zero_balance=False و همه مقادیر صفر است، از لیست خارج کن
        if not include_zero_balance:
            if opening_balance == 0 and total_in == 0 and total_out == 0 and closing_balance == 0:
                continue
        
        # نام دسته‌بندی
        category_name = ''
        if product.category_id and product.category_id in category_dict:
            category_name = category_dict[product.category_id]['name']
        
        items.append({
            'product_id': product.id,
            'product_code': product.code or '',
            'product_name': product.name or '',
            'unit': product.main_unit or '',
            'category_name': category_name,
            'opening_balance': float(opening_balance),
            'total_in': float(total_in),
            'total_out': float(total_out),
            'closing_balance': float(closing_balance),
        })
    
    # مرتب‌سازی بر اساس نام کالا
    items.sort(key=lambda x: x.get('product_name', ''))
    
    # اعمال pagination
    total = len(items)
    paginated_items = items[skip:skip + take]
    
    total_pages = (total + take - 1) // take if take > 0 else 0
    current_page = (skip // take) + 1 if take > 0 else 1
    
    # محاسبه مجموع‌ها
    total_opening = sum(item.get('opening_balance', 0) for item in items)
    total_in_sum = sum(item.get('total_in', 0) for item in items)
    total_out_sum = sum(item.get('total_out', 0) for item in items)
    total_closing = sum(item.get('closing_balance', 0) for item in items)
    
    return {
        'items': paginated_items,
        'summary': {
            'total_count': total,
            'total_opening_balance': float(total_opening),
            'total_in': float(total_in_sum),
            'total_out': float(total_out_sum),
            'total_closing_balance': float(total_closing),
        },
        'pagination': {
            'total': total,
            'page': current_page,
            'per_page': take,
            'total_pages': total_pages,
            'has_next': current_page < total_pages,
            'has_prev': current_page > 1,
        }
    }


def get_sales_by_product_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    product_ids: Optional[List[int]] = None,
    category_ids: Optional[List[int]] = None,
    warehouse_ids: Optional[List[int]] = None,
    include_zero_sales: bool = False,
    search: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش فروش به تفکیک کالا
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        product_ids: لیست شناسه‌های کالاها (اختیاری)
        category_ids: لیست شناسه‌های دسته‌بندی‌ها (اختیاری)
        warehouse_ids: لیست شناسه‌های انبارها (اختیاری، فعلاً استفاده نمی‌شود)
        include_zero_sales: نمایش کالاهای با فروش صفر
        search: جستجو در کد یا نام کالا (اختیاری)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست کالاها با آمار فروش,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from app.services.invoice_service import INVOICE_SALES
    
    # Query پایه: فقط کالاها
    query = db.query(Product).filter(
        Product.business_id == business_id,
    )
    
    # فیلتر کالاها
    if product_ids:
        query = query.filter(Product.id.in_(product_ids))
    
    # فیلتر دسته‌بندی
    if category_ids:
        query = query.filter(Product.category_id.in_(category_ids))
    
    # فیلتر جستجو
    if search and search.strip():
        search_filter = or_(
            Product.code.ilike(f'%{search}%'),
            Product.name.ilike(f'%{search}%'),
        )
        query = query.filter(search_filter)
    
    # دریافت همه کالاهای فیلتر شده
    products = query.all()
    
    if not products:
        return {
            'items': [],
            'summary': {
                'total_count': 0,
                'total_quantity': 0.0,
                'total_amount': 0.0,
            },
            'pagination': {
                'total': 0,
                'page': 1,
                'per_page': take,
                'total_pages': 0,
                'has_next': False,
                'has_prev': False,
            }
        }
    
    # تبدیل تاریخ‌ها
    date_from_obj = None
    date_to_obj = None
    
    if date_from:
        try:
            date_from_obj = datetime.strptime(date_from, '%Y-%m-%d').date()
        except Exception:
            pass
    
    if date_to:
        try:
            date_to_obj = datetime.strptime(date_to, '%Y-%m-%d').date()
        except Exception:
            pass
    
    # اگر تاریخ‌ها مشخص نشده‌اند، از سال مالی استفاده کن
    if date_from_obj is None or date_to_obj is None:
        try:
            from adapters.db.models.fiscal_year import FiscalYear
            if fiscal_year_id:
                fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
            else:
                fiscal_year = db.query(FiscalYear).filter(
                    and_(
                        FiscalYear.business_id == business_id,
                        FiscalYear.is_last == True
                    )
                ).first()
            
            if fiscal_year:
                if date_from_obj is None:
                    date_from_obj = fiscal_year.start_date
                if date_to_obj is None:
                    date_to_obj = fiscal_year.end_date if fiscal_year.end_date else date.today()
        except Exception:
            pass
    
    # اگر هنوز تاریخ مشخص نشده
    if date_to_obj is None:
        date_to_obj = date.today()
    if date_from_obj is None:
        date_from_obj = date.today()
    
    # دریافت فاکتورهای فروش در بازه زمانی
    from adapters.db.models.document import Document
    
    sales_invoice_query = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == INVOICE_SALES,
            Document.is_proforma == False,
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    if currency_id:
        sales_invoice_query = sales_invoice_query.filter(Document.currency_id == currency_id)
    
    if fiscal_year_id:
        sales_invoice_query = sales_invoice_query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    sales_invoices = sales_invoice_query.all()
    invoice_ids = [inv.id for inv in sales_invoices]
    
    if not invoice_ids:
        # اگر هیچ فاکتور فروشی وجود ندارد، فقط لیست کالاها را برگردان
        items = []
        category_dict = {}
        product_category_ids = {p.category_id for p in products if p.category_id}
        if product_category_ids:
            categories = db.query(BusinessCategory).filter(
                BusinessCategory.id.in_(list(product_category_ids))
            ).all()
            for cat in categories:
                title = ''
                if isinstance(cat.title_translations, dict):
                    title = cat.title_translations.get('fa') or cat.title_translations.get('en') or cat.title_translations.get('default') or ''
                category_dict[cat.id] = title
        
        for product in products:
            category_name = category_dict.get(product.category_id, '') if product.category_id else ''
            
            if not include_zero_sales:
                continue
            
            items.append({
                'product_id': product.id,
                'product_code': product.code or '',
                'product_name': product.name or '',
                'unit': product.main_unit or '',
                'category_name': category_name,
                'total_quantity': 0.0,
                'total_amount': 0.0,
                'average_price': None,
                'last_sale_date': None,
            })
        
        return {
            'items': items[skip:skip + take],
            'summary': {
                'total_count': len(items),
                'total_quantity': 0.0,
                'total_amount': 0.0,
            },
            'pagination': {
                'total': len(items),
                'page': (skip // take) + 1 if take > 0 else 1,
                'per_page': take,
                'total_pages': (len(items) + take - 1) // take if take > 0 else 0,
                'has_next': (skip + take) < len(items),
                'has_prev': skip > 0,
            }
        }
    
    # دریافت خطوط فاکتور فروش
    sales_lines = db.query(InvoiceItemLine).filter(
        InvoiceItemLine.document_id.in_(invoice_ids)
    ).all()
    
    # گروه‌بندی خطوط بر اساس product_id
    product_sales = {}
    product_ids_with_sales = set()
    
    for line in sales_lines:
        if not line.product_id:
            continue
        
        product_ids_with_sales.add(line.product_id)
        
        if line.product_id not in product_sales:
            product_sales[line.product_id] = {
                'total_quantity': Decimal(0),
                'total_amount': Decimal(0),
                'last_sale_date': None,
                'invoice_dates': [],
            }
        
        qty = Decimal(str(line.quantity or 0))
        line_total = Decimal(0)
        
        # محاسبه line_total از extra_info
        extra_info = line.extra_info or {}
        
        # استفاده از line_total از extra_info اگر موجود باشد
        if 'line_total' in extra_info and extra_info['line_total'] is not None:
            line_total = Decimal(str(extra_info['line_total']))
        else:
            # محاسبه line_total از unit_price، discount و tax
            unit_price = Decimal(str(extra_info.get('unit_price', 0) or 0))
            line_discount = Decimal(str(extra_info.get('line_discount', 0) or 0))
            tax_amount = Decimal(str(extra_info.get('tax_amount', 0) or 0))
            
            if unit_price > 0 and qty > 0:
                line_total = (unit_price * qty) - line_discount + tax_amount
        
        product_sales[line.product_id]['total_quantity'] += qty
        product_sales[line.product_id]['total_amount'] += line_total
        
        # پیدا کردن تاریخ آخرین فروش
        try:
            invoice = next((inv for inv in sales_invoices if inv.id == line.document_id), None)
            if invoice:
                product_sales[line.product_id]['invoice_dates'].append(invoice.document_date)
        except Exception:
            pass
    
    # پیدا کردن آخرین تاریخ فروش برای هر کالا
    for product_id in product_sales:
        dates = product_sales[product_id]['invoice_dates']
        if dates:
            product_sales[product_id]['last_sale_date'] = max(dates)
    
    # ساخت dict برای دسته‌بندی‌ها
    category_dict = {}
    product_category_ids = {p.category_id for p in products if p.category_id}
    if product_category_ids:
        categories = db.query(BusinessCategory).filter(
            BusinessCategory.id.in_(list(product_category_ids))
        ).all()
        for cat in categories:
            title = ''
            if isinstance(cat.title_translations, dict):
                title = cat.title_translations.get('fa') or cat.title_translations.get('en') or cat.title_translations.get('default') or ''
            category_dict[cat.id] = title
    
    # ساخت لیست نتایج
    items = []
    
    for product in products:
        sales_data = product_sales.get(product.id, {})
        total_quantity = float(sales_data.get('total_quantity', Decimal(0)))
        total_amount = float(sales_data.get('total_amount', Decimal(0)))
        last_sale_date = sales_data.get('last_sale_date')
        
        # اگر include_zero_sales=False و فروش صفر است، از لیست خارج کن
        if not include_zero_sales and total_quantity == 0:
            continue
        
        # محاسبه میانگین قیمت
        average_price = None
        if total_quantity > 0 and total_amount > 0:
            average_price = float(total_amount / total_quantity)
        
        category_name = category_dict.get(product.category_id, '') if product.category_id else ''
        
        items.append({
            'product_id': product.id,
            'product_code': product.code or '',
            'product_name': product.name or '',
            'unit': product.main_unit or '',
            'category_name': category_name,
            'total_quantity': total_quantity,
            'total_amount': total_amount,
            'average_price': average_price,
            'last_sale_date': last_sale_date.isoformat() if last_sale_date else None,
        })
    
    # مرتب‌سازی بر اساس نام کالا
    items.sort(key=lambda x: x.get('product_name', ''))
    
    # اعمال pagination
    total = len(items)
    paginated_items = items[skip:skip + take]
    
    total_pages = (total + take - 1) // take if take > 0 else 0
    current_page = (skip // take) + 1 if take > 0 else 1
    
    # محاسبه مجموع‌ها
    total_quantity_sum = sum(item.get('total_quantity', 0) for item in items)
    total_amount_sum = sum(item.get('total_amount', 0) for item in items)
    
    return {
        'items': paginated_items,
        'summary': {
            'total_count': total,
            'total_quantity': float(total_quantity_sum),
            'total_amount': float(total_amount_sum),
        },
        'pagination': {
            'total': total,
            'page': current_page,
            'per_page': take,
            'total_pages': total_pages,
            'has_next': current_page < total_pages,
            'has_prev': current_page > 1,
        }
    }


def get_inventory_kardex_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    product_ids: Optional[List[int]] = None,
    warehouse_ids: Optional[List[int]] = None,
    category_ids: Optional[List[int]] = None,
    search: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش کاردکس موجودی
    
    نمایش جزئیات حرکات هر کالا در یک بازه زمانی با محاسبه مانده تجمعی
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        product_ids: لیست شناسه‌های کالاها (اختیاری)
        warehouse_ids: لیست شناسه‌های انبارها (اختیاری)
        category_ids: لیست شناسه‌های دسته‌بندی‌ها (اختیاری)
        search: جستجو در کد یا نام کالا (اختیاری)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست حرکات کاردکس,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    from datetime import date, timedelta
    from sqlalchemy import or_
    from app.services.invoice_service import _iter_product_movements, _compute_available_stock
    from adapters.db.models.document import Document
    from adapters.db.models.warehouse import Warehouse
    from adapters.db.models.category import BusinessCategory
    
    # تبدیل تاریخ‌ها
    date_from_obj = None
    date_to_obj = None
    if date_from:
        try:
            from datetime import datetime
            date_from_obj = datetime.strptime(date_from, '%Y-%m-%d').date()
        except Exception:
            pass
    if date_to:
        try:
            from datetime import datetime
            date_to_obj = datetime.strptime(date_to, '%Y-%m-%d').date()
        except Exception:
            pass
    
    # اگر date_from مشخص نشده، از ابتدای سال مالی استفاده کن
    if date_from_obj is None and fiscal_year_id:
        try:
            from adapters.db.models.fiscal_year import FiscalYear
            fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
            if fiscal_year:
                date_from_obj = fiscal_year.start_date
        except Exception:
            pass
    
    # اگر date_to مشخص نشده، تا امروز استفاده کن
    if date_to_obj is None:
        date_to_obj = date.today()
    
    # اگر date_from مشخص نشده، از تاریخ روز استفاده کن
    if date_from_obj is None:
        date_from_obj = date.today()
    
    # Query کالاها برای فیلتر
    query = db.query(Product).filter(
        Product.business_id == business_id,
        Product.track_inventory == True,  # فقط کالاهای با کنترل موجودی
        Product.item_type == ProductItemType.PRODUCT,  # فقط کالاها
    )
    
    # فیلتر کالاها
    if product_ids:
        query = query.filter(Product.id.in_(product_ids))
    
    # فیلتر دسته‌بندی
    if category_ids:
        query = query.filter(Product.category_id.in_(category_ids))
    
    # فیلتر جستجو
    if search and search.strip():
        search_filter = or_(
            Product.code.ilike(f'%{search}%'),
            Product.name.ilike(f'%{search}%'),
        )
        query = query.filter(search_filter)
    
    products = query.all()
    
    if not products:
        return {
            'items': [],
            'summary': {
                'total_count': 0,
            },
            'pagination': {
                'total': 0,
                'page': 1,
                'per_page': take,
                'total_pages': 0,
                'has_next': False,
                'has_prev': False,
            }
        }
    
    product_id_list = [p.id for p in products]
    
    # دریافت تمام حرکات تا date_to
    all_movements = _iter_product_movements(
        db,
        business_id,
        product_id_list,
        warehouse_ids,
        date_to_obj,
    )
    
    # فیلتر حرکات در بازه تاریخ و فیلتر انبار
    filtered_movements = []
    for mv in all_movements:
        mv_date = mv.get("document_date")
        if not mv_date:
            continue
        
        # فیلتر تاریخ
        if mv_date < date_from_obj:
            continue
        if mv_date > date_to_obj:
            continue
        
        # فیلتر انبار
        if warehouse_ids:
            mv_wh_id = mv.get("warehouse_id")
            if mv_wh_id is None:
                continue
            if int(mv_wh_id) not in warehouse_ids:
                continue
        
        filtered_movements.append(mv)
    
    # دریافت اطلاعات سند برای هر حرکت
    document_ids = list(set(mv.get("document_id") for mv in filtered_movements if mv.get("document_id")))
    documents_dict = {}
    if document_ids:
        documents = db.query(Document).filter(Document.id.in_(document_ids)).all()
        for doc in documents:
            documents_dict[doc.id] = doc
    
    # دریافت اطلاعات انبار
    warehouse_dict = {}
    if warehouse_ids:
        warehouses = db.query(Warehouse).filter(Warehouse.id.in_(warehouse_ids)).all()
        for wh in warehouses:
            warehouse_dict[wh.id] = wh
    
    # تابع برای تبدیل document_type به نام فارسی
    def _get_document_type_name(doc_type: str | None) -> str:
        if not doc_type:
            return ""
        doc_type = doc_type.strip()
        mapping = {
            "invoice_sales": "فروش",
            "invoice_sales_return": "برگشت از فروش",
            "invoice_purchase": "خرید",
            "invoice_purchase_return": "برگشت از خرید",
            "invoice_direct_consumption": "مصرف مستقیم",
            "invoice_production": "تولید",
            "invoice_waste": "ضایعات",
            "inventory_transfer": "انتقال موجودی",
            "production": "تولید",
            "opening_balance": "موجودی اولیه",
            "expense": "هزینه",
            "income": "درآمد",
            "receipt": "دریافت",
            "payment": "پرداخت",
            "transfer": "انتقال",
            "manual": "سند دستی",
            "invoice": "فاکتور",
            "check": "چک",
        }
        return mapping.get(doc_type, doc_type)
    
    # ساخت dict برای کالاها
    products_dict = {p.id: p for p in products}
    
    # ساخت لیست حرکات کاردکس با محاسبه مانده تجمعی
    kardex_items = []
    balance_by_product = {}  # {product_id: Decimal}
    
    # مرتب‌سازی حرکات بر اساس تاریخ و document_id
    filtered_movements.sort(key=lambda x: (x.get("document_date"), x.get("document_id"), x.get("product_id")))
    
    for mv in filtered_movements:
        product_id = mv.get("product_id")
        if not product_id:
            continue
        
        product = products_dict.get(product_id)
        if not product:
            continue
        
        document_id = mv.get("document_id")
        document = documents_dict.get(document_id) if document_id else None
        
        mv_date = mv.get("document_date")
        movement = mv.get("movement")  # "in" or "out"
        quantity = Decimal(str(mv.get("quantity") or 0))
        cost_price = mv.get("cost_price")
        warehouse_id = mv.get("warehouse_id")
        
        # محاسبه مانده تجمعی
        if product_id not in balance_by_product:
            # محاسبه مانده ابتدای دوره
            if date_from_obj:
                date_before_from = date_from_obj - timedelta(days=1)
                balance_by_product[product_id] = _compute_available_stock(
                    db, business_id, product_id, warehouse_id, date_before_from
                )
            else:
                balance_by_product[product_id] = Decimal(0)
        
        # به‌روزرسانی مانده
        if movement == "in":
            balance_by_product[product_id] += quantity
        elif movement == "out":
            balance_by_product[product_id] -= quantity
        
        # محاسبه مبلغ کل
        total_amount = None
        if cost_price is not None and quantity > 0:
            try:
                total_amount = float(Decimal(str(cost_price)) * quantity)
            except Exception:
                pass
        
        # اطلاعات انبار
        warehouse_name = None
        if warehouse_id and warehouse_id in warehouse_dict:
            warehouse_name = warehouse_dict[warehouse_id].name
        
        # اطلاعات سند
        document_type_name = ""
        document_code = ""
        document_description = None
        if document:
            document_type_name = _get_document_type_name(document.document_type)
            document_code = document.code or ""
            document_description = document.description
        
        kardex_items.append({
            'product_id': product_id,
            'product_code': product.code or '',
            'product_name': product.name or '',
            # keep as date object so format_datetime_fields can apply jalali/gregorian consistently
            'document_date': mv_date,
            'document_type': document.document_type if document else None,
            'document_type_name': document_type_name,
            'document_code': document_code,
            'document_id': document_id,
            'movement': movement,
            'quantity_in': float(quantity) if movement == "in" else 0.0,
            'quantity_out': float(quantity) if movement == "out" else 0.0,
            'balance': float(balance_by_product[product_id]),
            'unit_price': float(cost_price) if cost_price is not None else None,
            'total_amount': total_amount,
            'warehouse_id': warehouse_id,
            'warehouse_name': warehouse_name,
            'description': document_description or '',
        })
    
    # مرتب‌سازی بر اساس تاریخ، product_id
    kardex_items.sort(key=lambda x: (
        x.get('document_date') or '',
        x.get('product_id', 0),
        x.get('document_id', 0),
    ))
    
    # اعمال pagination
    total = len(kardex_items)
    paginated_items = kardex_items[skip:skip + take]
    
    total_pages = (total + take - 1) // take if take > 0 else 0
    current_page = (skip // take) + 1 if take > 0 else 1
    
    return {
        'items': paginated_items,
        'summary': {
            'total_count': total,
        },
        'pagination': {
            'total': total,
            'page': current_page,
            'per_page': take,
            'total_pages': total_pages,
            'has_next': current_page < total_pages,
            'has_prev': current_page > 1,
        }
    }


def get_inventory_stock_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    product_ids: Optional[List[int]] = None,
    warehouse_ids: Optional[List[int]] = None,
    category_ids: Optional[List[int]] = None,
    as_of_date: Optional[str] = None,
    track_inventory: Optional[bool] = None,
    only_negative_stock: bool = False,
    only_without_movements: bool = False,
    include_zero: bool = False,
    search: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
    *,
    for_export: bool = False,
) -> Dict[str, Any]:
    """
    گزارش موجودی انبار (موجودی کالا)
    
    نمایش موجودی محصولات به تفکیک انبار با فیلترهای مختلف
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        product_ids: لیست شناسه‌های کالاها (اختیاری)
        warehouse_ids: لیست شناسه‌های انبارها (اختیاری)
        category_ids: لیست شناسه‌های دسته‌بندی‌ها (اختیاری)
        as_of_date: تاریخ گزارش (اختیاری، فرمت YYYY-MM-DD، پیش‌فرض: امروز)
        track_inventory: فیلتر کنترل موجودی (None=همه، True=فقط با کنترل، False=فقط بدون کنترل)
        only_negative_stock: فقط موجودی‌های منفی
        only_without_movements: فقط محصولات فاقد حواله/حرکت
        include_zero: نمایش موجودی صفر
        search: جستجو در کد یا نام کالا (اختیاری)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
        for_export: برای خروجی اکسل/PDF سقف take تا ۱۰۰۰۰ مجاز می‌شود
    
    Returns:
        dict: {
            'items': لیست موجودی‌ها,
            'as_of_date': تاریخ گزارش,
            'total_items': تعداد کل,
            'summary': خلاصه آمار
        }
    """
    from app.services.invoice_service import _compute_available_stock, _iter_product_movements
    from adapters.db.models.warehouse import Warehouse
    from adapters.db.models.warehouse_document import WarehouseDocument
    from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
    from datetime import date as date_type
    
    # تبدیل تاریخ
    as_of_date_obj = date.today()
    if as_of_date:
        try:
            as_of_date_obj = date_type.fromisoformat(as_of_date) if isinstance(as_of_date, str) else as_of_date
        except Exception:
            pass
    
    # Query محصولات
    query = db.query(Product).filter(Product.business_id == business_id)
    
    # فیلتر کنترل موجودی
    if track_inventory is True:
        query = query.filter(Product.track_inventory == True)
    elif track_inventory is False:
        query = query.filter(Product.track_inventory == False)
    # اگر None باشد، همه محصولات
    
    # فیلتر کالاها
    if product_ids:
        query = query.filter(Product.id.in_(product_ids))
    
    # فیلتر دسته‌بندی
    if category_ids:
        query = query.filter(Product.category_id.in_(category_ids))
    
    # فیلتر جستجو
    if search and search.strip():
        search_filter = or_(
            Product.code.ilike(f'%{search}%'),
            Product.name.ilike(f'%{search}%'),
        )
        query = query.filter(search_filter)
    
    # دریافت لیست محصولات
    products = query.all()
    
    _max_take = 10000 if for_export else 500
    
    if not products:
        # اعتبارسنجی take و skip
        if take > _max_take:
            take = _max_take
        if take < 1:
            take = 50
        if skip < 0:
            skip = 0
        total_pages = 0
        current_page = (skip // take) + 1 if take > 0 else 1
        
        return {
            "items": [],
            "as_of_date": as_of_date_obj.isoformat(),
            "total": 0,
            "total_items": 0,  # برای سازگاری با کدهای قدیمی
            "summary": {
                "total_products": 0,
                "total_with_stock": 0,
                "total_zero_stock": 0,
                "total_negative_stock": 0,
                "total_without_movements": 0,
            },
            "pagination": {
                "total": 0,
                "page": current_page,
                "per_page": take,
                "limit": take,  # برای سازگاری با کدهای قدیمی
                "total_pages": total_pages,
                "has_next": False,
                "has_prev": False,
            }
        }
    
    product_id_list = [p.id for p in products]
    
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
    
    # بررسی حرکات برای فیلتر فاقد حواله
    products_with_movements = set()
    if only_without_movements:
        # بررسی حرکات از DocumentLine
        movements_doc = _iter_product_movements(
            db,
            business_id,
            product_id_list,
            warehouse_ids,
            as_of_date_obj,
        )
        for mv in movements_doc:
            products_with_movements.add(mv['product_id'])
        
        # بررسی حرکات از WarehouseDocumentLine
        movements_wh_query = db.query(WarehouseDocumentLine.product_id).distinct().join(
            WarehouseDocument,
            WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id
        ).filter(
            and_(
                WarehouseDocument.business_id == business_id,
                WarehouseDocument.status == "posted",
                WarehouseDocument.document_date <= as_of_date_obj,
                WarehouseDocumentLine.product_id.in_(product_id_list),
            )
        )
        if warehouse_ids:
            movements_wh_query = movements_wh_query.filter(
                WarehouseDocumentLine.warehouse_id.in_([int(w) for w in warehouse_ids])
            )
        movements_wh = movements_wh_query.all()
        for mv_line in movements_wh:
            products_with_movements.add(mv_line.product_id)
    
    # ساخت لیست آیتم‌ها
    items = []
    
    for product in products:
        # اگر فیلتر فاقد حواله فعال است و این محصول حرکت دارد، رد کن
        if only_without_movements and product.id in products_with_movements:
            continue
        
        # تعیین لیست انبارها برای این محصول
        if warehouse_ids:
            wh_list = [w for w in warehouses if w.id in [int(wid) for wid in warehouse_ids]]
        else:
            wh_list = warehouses
        
        # اگر انباری انتخاب نشده، موجودی کل را محاسبه کن
        if not wh_list:
            stock = _compute_available_stock(db, business_id, product.id, None, as_of_date_obj)
            
            # بررسی فیلتر موجودی صفر
            if not include_zero and stock == 0:
                continue
            
            # بررسی فیلتر موجودی منفی
            if only_negative_stock and stock >= 0:
                continue
            
            # بررسی اینکه آیا این محصول حرکت دارد یا نه
            has_movements = product.id in products_with_movements if only_without_movements else True
            
            items.append({
                "product_id": product.id,
                "product_code": product.code or "",
                "product_name": product.name,
                "category_id": product.category_id,
                "category_name": None,  # می‌توان بعداً join کرد
                "warehouse_id": None,
                "warehouse_code": None,
                "warehouse_name": "بدون انبار / کل",
                "quantity": float(stock),
                "unit": product.main_unit or "",
                "track_inventory": product.track_inventory,
                "has_movements": has_movements,
            })
        else:
            # موجودی به تفکیک انبار
            for warehouse in wh_list:
                stock = _compute_available_stock(db, business_id, product.id, warehouse.id, as_of_date_obj)
                
                # بررسی فیلتر موجودی صفر
                if not include_zero and stock == 0:
                    continue
                
                # بررسی فیلتر موجودی منفی
                if only_negative_stock and stock >= 0:
                    continue
                
                # بررسی اینکه آیا این محصول حرکت دارد یا نه
                has_movements = product.id in products_with_movements if only_without_movements else True
                
                items.append({
                    "product_id": product.id,
                    "product_code": product.code or "",
                    "product_name": product.name,
                    "category_id": product.category_id,
                    "category_name": None,
                    "warehouse_id": warehouse.id,
                    "warehouse_code": warehouse.code or "",
                    "warehouse_name": warehouse.name,
                    "quantity": float(stock),
                    "unit": product.main_unit or "",
                    "track_inventory": product.track_inventory,
                    "has_movements": has_movements,
                })
    
    # محاسبه خلاصه آمار
    total_products = len(set(item['product_id'] for item in items))
    total_with_stock = len([item for item in items if item['quantity'] > 0])
    total_zero_stock = len([item for item in items if item['quantity'] == 0])
    total_negative_stock = len([item for item in items if item['quantity'] < 0])
    total_without_movements = len([item for item in items if not item.get('has_movements', True)])
    
    # Pagination
    total = len(items)
    if take > _max_take:
        take = _max_take
    if take < 1:
        take = 50
    if skip < 0:
        skip = 0
    
    paginated_items = items[skip:skip + take]
    
    # محاسبه اطلاعات pagination
    total_pages = (total + take - 1) // take if take > 0 else 0
    current_page = (skip // take) + 1 if take > 0 else 1
    
    # دریافت نام دسته‌بندی‌ها
    category_ids_set = set(item['category_id'] for item in paginated_items if item['category_id'])
    if category_ids_set:
        categories = db.query(BusinessCategory).filter(
            BusinessCategory.id.in_(list(category_ids_set))
        ).all()
        category_dict = {}
        for cat in categories:
            # استخراج نام از title_translations (اول fa، سپس en)
            if isinstance(cat.title_translations, dict):
                title = cat.title_translations.get('fa') or cat.title_translations.get('en') or cat.title_translations.get('default') or ''
            else:
                title = ''
            category_dict[cat.id] = title
        for item in paginated_items:
            if item['category_id']:
                item['category_name'] = category_dict.get(item['category_id'])
    
    return {
        "items": paginated_items,
        "as_of_date": as_of_date_obj.isoformat(),
        "total": total,
        "total_items": total,  # برای سازگاری با کدهای قدیمی
        "summary": {
            "total_products": total_products,
            "total_with_stock": total_with_stock,
            "total_zero_stock": total_zero_stock,
            "total_negative_stock": total_negative_stock,
            "total_without_movements": total_without_movements,
        },
        "pagination": {
            "total": total,
            "page": current_page,
            "per_page": take,
            "limit": take,  # برای سازگاری با کدهای قدیمی
            "total_pages": total_pages,
            "has_next": current_page < total_pages,
            "has_prev": current_page > 1,
        }
    }


