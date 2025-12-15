from typing import List, Optional, Dict, Any
import json
from sqlalchemy.exc import IntegrityError
from app.core.responses import ApiError
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func, String
from adapters.db.models.person import Person, PersonBankAccount, PersonType
from adapters.db.models.business import Business
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.api.v1.schema_models.person import (
    PersonCreateRequest, PersonUpdateRequest, PersonBankAccountCreateRequest
)
from app.core.responses import success_response
from app.core.cache import get_cache
import logging

logger = logging.getLogger(__name__)


def invalidate_persons_cache(business_id: int, fiscal_year_id: Optional[int] = None):
	"""
	حذف تمام کش‌های مربوط به لیست اشخاص یک کسب‌وکار
	
	این تابع از چند روش استفاده می‌کند:
	1. Tag-based invalidation با set ردیس: حذف انتخابی بر اساس business_id و fiscal_year_id (بهینه‌تر)
	2. Pattern-based invalidation: حذف تمام کلیدهای persons_list:* (fallback برای اطمینان)
	3. Redis Pub/Sub: انتشار پیام invalidation برای تمام instanceها
	
	Args:
		business_id: شناسه کسب‌وکار
		fiscal_year_id: شناسه سال مالی (اختیاری)
			- اگر None باشد، تمام کش‌های مربوط به business_id حذف می‌شوند
			- اگر مشخص باشد، فقط کش‌های مربوط به آن fiscal_year_id حذف می‌شوند
	"""
	cache = get_cache()
	if not cache.enabled:
		return
	
	try:
		# روش 1: استفاده از invalidate_by_business (بهینه‌ترین روش)
		# این متد از set ردیس برای نگهداری کلیدها استفاده می‌کند
		deleted_count = cache.invalidate_by_business(business_id, fiscal_year_id)
		if deleted_count > 0:
			logger.info(f"Invalidated {deleted_count} cache keys for business_id {business_id}, fiscal_year_id {fiscal_year_id}")
		
		# روش 2: حذف تمام کلیدهای persons_list:* (fallback برای اطمینان کامل)
		# این کار برای اطمینان از حذف کامل کش انجام می‌شود
		# (در صورت وجود کلیدهای قدیمی که با tag-based ذخیره نشده‌اند)
		pattern = "persons_list:*"
		deleted_pattern = cache.delete_pattern(pattern)
		if deleted_pattern > 0:
			logger.info(f"Invalidated {deleted_pattern} cache keys using pattern: {pattern}")
		
		# روش 3: انتشار پیام invalidation از طریق Redis Pub/Sub
		# این کار باعث می‌شود که تمام instanceهای برنامه کش را invalidate کنند
		invalidation_message = {
			"type": "persons_cache_invalidation",
			"business_id": business_id,
			"fiscal_year_id": fiscal_year_id,
			"timestamp": None
		}
		try:
			import time
			invalidation_message["timestamp"] = time.time()
			cache.publish_invalidation("cache_invalidation", invalidation_message)
			logger.info(f"Published invalidation message for business_id {business_id}, fiscal_year_id {fiscal_year_id}")
		except Exception as pub_error:
			logger.warning(f"Error publishing invalidation message: {pub_error}")
	
	except Exception as e:
		# خطا در invalidate نباید مانع عملیات اصلی شود
		logger.warning(f"Error invalidating persons cache for business_id {business_id}: {e}")


def create_person(db: Session, business_id: int, person_data: PersonCreateRequest) -> Dict[str, Any]:
    """ایجاد شخص جدید"""
    # محاسبه/اعتبارسنجی کد یکتا
    code: Optional[int] = getattr(person_data, 'code', None)
    if code is not None:
        exists = db.query(Person).filter(
            and_(Person.business_id == business_id, Person.code == code)
        ).first()
        if exists:
            raise ApiError("DUPLICATE_PERSON_CODE", "کد شخص تکراری است", http_status=400)
    else:
        # تولید خودکار کد: بیشینه فعلی + 1 (نسبت به همان کسب و کار)
        max_code = db.query(func.max(Person.code)).filter(Person.business_id == business_id).scalar()
        code = (max_code or 0) + 1

    # آماده‌سازی person_types (چندانتخابی) و سازگاری person_type تکی
    types_list: List[str] = []
    if getattr(person_data, 'person_types', None):
        types_list = [t.value if hasattr(t, 'value') else str(t) for t in person_data.person_types]  # type: ignore[attr-defined]
    elif getattr(person_data, 'person_type', None):
        t = person_data.person_type
        types_list = [t.value if hasattr(t, 'value') else str(t)]

    # حداقل یک نوع شخص الزامی است
    if not types_list:
        raise ApiError(
            "PERSON_TYPE_REQUIRED",
            "نوع شخص الزامی است",
            http_status=400,
        )

    # نوع تکی برای استفاده‌های بعدی (قبل از هر استفاده تعریف شود)
    incoming_single_type = getattr(person_data, 'person_type', None)

    # اعتبارسنجی سهام برای سهامدار
    is_shareholder = False
    if types_list:
        is_shareholder = 'سهامدار' in types_list
    if not is_shareholder and incoming_single_type is not None:
        try:
            is_shareholder = (getattr(incoming_single_type, 'value', str(incoming_single_type)) == 'سهامدار')
        except Exception:
            is_shareholder = False
    if is_shareholder:
        sc_val = getattr(person_data, 'share_count', None)
        if sc_val is None or not isinstance(sc_val, int) or sc_val <= 0:
            raise ApiError("INVALID_SHARE_COUNT", "برای سهامدار، تعداد سهام الزامی و باید بزرگتر از صفر باشد", http_status=400)

    # ایجاد شخص
    # نگاشت person_type دریافتی از اسکیما به Enum مدل
    mapped_single_type = None
    if incoming_single_type is not None:
        try:
            # incoming_single_type.value مقدار فارسی مانند "سهامدار"
            mapped_single_type = PersonType(getattr(incoming_single_type, 'value', str(incoming_single_type)))
        except Exception:
            mapped_single_type = None

    # بارگذاری تنظیمات اعتبار پیش‌فرض کسب‌وکار
    business_defaults = db.query(Business).filter(Business.id == business_id).first()
    default_credit_limit = getattr(business_defaults, "default_credit_limit", None) if business_defaults else None
    default_check_enabled = bool(getattr(business_defaults, "check_credit_enabled_by_default", False)) if business_defaults else False

    person = Person(
        business_id=business_id,
        code=code,
        alias_name=person_data.alias_name,
        first_name=person_data.first_name,
        last_name=person_data.last_name,
        # ذخیره مقدار Enum با مقدار فارسی (values_callable در مدل مقادیر فارسی را می‌نویسد)
        # person_types نباید None باشد (nullable=False در مدل)
        person_types=json.dumps(types_list, ensure_ascii=False) if types_list else "[]",
        company_name=person_data.company_name,
        payment_id=person_data.payment_id,
        national_id=person_data.national_id,
        registration_number=person_data.registration_number,
        economic_id=person_data.economic_id,
        country=person_data.country,
        province=person_data.province,
        city=person_data.city,
        address=person_data.address,
        postal_code=person_data.postal_code,
        phone=person_data.phone,
        mobile=person_data.mobile,
        fax=person_data.fax,
        email=person_data.email,
        website=person_data.website,
        share_count=getattr(person_data, 'share_count', None),
        commission_sale_percent=getattr(person_data, 'commission_sale_percent', None),
        commission_sales_return_percent=getattr(person_data, 'commission_sales_return_percent', None),
        commission_sales_amount=getattr(person_data, 'commission_sales_amount', None),
        commission_sales_return_amount=getattr(person_data, 'commission_sales_return_amount', None),
        commission_exclude_discounts=bool(getattr(person_data, 'commission_exclude_discounts', False)),
        commission_exclude_additions_deductions=bool(getattr(person_data, 'commission_exclude_additions_deductions', False)),
        commission_post_in_invoice_document=bool(getattr(person_data, 'commission_post_in_invoice_document', False)),
        # اعتبار: اگر کاربر مقدار نداد، از تنظیمات کسب‌وکار استفاده شود
        credit_limit=(getattr(person_data, 'credit_limit', None) if getattr(person_data, 'credit_limit', None) is not None else default_credit_limit),
        credit_check_enabled=(getattr(person_data, 'credit_check_enabled', None) if getattr(person_data, 'credit_check_enabled', None) is not None else default_check_enabled),
    )
    
    db.add(person)
    db.flush()  # برای دریافت ID
    
    # ایجاد حساب‌های بانکی
    if person_data.bank_accounts:
        for bank_account_data in person_data.bank_accounts:
            bank_account = PersonBankAccount(
                person_id=person.id,
                bank_name=bank_account_data.bank_name,
                account_number=bank_account_data.account_number,
                card_number=bank_account_data.card_number,
                sheba_number=bank_account_data.sheba_number,
            )
            db.add(bank_account)
    
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ApiError("DUPLICATE_PERSON_CODE", "کد شخص تکراری است", http_status=400)
    db.refresh(person)
    
    # Invalidate کش لیست اشخاص
    invalidate_persons_cache(business_id, fiscal_year_id=None)
    
    # فراخوانی workflow triggers
    try:
        from app.services.workflow.workflow_trigger_service import trigger_person_created
        person_types_list = json.loads(person.person_types) if person.person_types else []
        trigger_person_created(
            db=db,
            business_id=business_id,
            person_id=person.id,
            person_types=person_types_list,
            user_id=None  # می‌توان user_id را از context دریافت کرد
        )
    except Exception as e:
        # عدم موفقیت در trigger نباید مانع بازگشت شخص شود
        import logging
        logger = logging.getLogger(__name__)
        logger.warning(f"Failed to trigger workflows for person {person.id}: {e}")
    
    return success_response(
        message="شخص با موفقیت ایجاد شد",
        data=_person_to_dict(person)
    )


def get_person_by_id(db: Session, person_id: int, business_id: int) -> Optional[Dict[str, Any]]:
    """دریافت شخص بر اساس شناسه"""
    person = db.query(Person).filter(
        and_(Person.id == person_id, Person.business_id == business_id)
    ).first()
    
    if not person:
        return None
    
    return _person_to_dict(person)


def get_persons_by_business(
    db: Session, 
    business_id: int, 
    query_info: Dict[str, Any],
    fiscal_year_id: Optional[int] = None
) -> Dict[str, Any]:
    """دریافت لیست اشخاص با جستجو و فیلتر"""
    query = db.query(Person).filter(Person.business_id == business_id)
    
    # بررسی نیاز به محاسبه تراز قبل از pagination
    # (برای فیلتر یا مرتب‌سازی بر اساس تراز/وضعیت)
    needs_balance_before_pagination = False
    sort_by = query_info.get('sort_by', 'created_at')
    if sort_by in ['balance', 'status']:
        needs_balance_before_pagination = True
    
    # بررسی فیلترها برای balance و status
    if query_info.get('filters'):
        for filter_item in query_info['filters']:
            if isinstance(filter_item, dict):
                field = filter_item.get('property')
            else:
                field = getattr(filter_item, 'property', None)
            if field in ['balance', 'status']:
                needs_balance_before_pagination = True
                break
    
    # اعمال جستجو
    if query_info.get('search') and query_info.get('search_fields'):
        search_term = f"%{query_info['search']}%"
        search_conditions = []
        
        for field in query_info['search_fields']:
            if field == 'code':
                # تبدیل به رشته برای جستجو مانند LIKE
                try:
                    code_int = int(query_info['search'])  # type: ignore[arg-type]
                    search_conditions.append(Person.code == code_int)
                except Exception:
                    pass
            if field == 'alias_name':
                search_conditions.append(Person.alias_name.ilike(search_term))
            elif field == 'first_name':
                search_conditions.append(Person.first_name.ilike(search_term))
            elif field == 'last_name':
                search_conditions.append(Person.last_name.ilike(search_term))
            elif field == 'company_name':
                search_conditions.append(Person.company_name.ilike(search_term))
            elif field == 'mobile':
                search_conditions.append(Person.mobile.ilike(search_term))
            elif field == 'email':
                search_conditions.append(Person.email.ilike(search_term))
            elif field == 'national_id':
                search_conditions.append(Person.national_id.ilike(search_term))
        
        if search_conditions:
            query = query.filter(or_(*search_conditions))
    
    # اعمال فیلترها
    if query_info.get('filters'):
        for filter_item in query_info['filters']:
            # پشتیبانی از هر دو حالت: دیکشنری یا شیء Pydantic
            if isinstance(filter_item, dict):
                field = filter_item.get('property')
                operator = filter_item.get('operator')
                value = filter_item.get('value')
            else:
                field = getattr(filter_item, 'property', None)
                operator = getattr(filter_item, 'operator', None)
                value = getattr(filter_item, 'value', None)

            if not field or not operator:
                continue

            # کد
            if field == 'code':
                if operator == '=':
                    query = query.filter(Person.code == value)
                elif operator == 'in' and isinstance(value, list):
                    query = query.filter(Person.code.in_(value))
                continue

            # انواع شخص چندانتخابی (رشته JSON)
            if field == 'person_types':
                if operator == '=' and isinstance(value, str):
                    query = query.filter(Person.person_types.ilike(f'%"{value}"%'))
                elif operator == 'in' and isinstance(value, list):
                    sub_filters = [Person.person_types.ilike(f'%"{v}"%') for v in value]
                    if sub_filters:
                        query = query.filter(or_(*sub_filters))
                continue

            # فیلترهای متنی عمومی (حمایت از عملگرهای contains/startsWith/endsWith)
            def apply_text_filter(column):
                nonlocal query
                if operator == '=':
                    query = query.filter(column == value)
                elif operator == 'like' or operator == '*':
                    query = query.filter(column.ilike(f"%{value}%"))
                elif operator == '*?':  # starts with
                    query = query.filter(column.ilike(f"{value}%"))
                elif operator == '?*':  # ends with
                    query = query.filter(column.ilike(f"%{value}"))

            if field == 'country':
                apply_text_filter(Person.country)
                continue

            if field == 'province':
                apply_text_filter(Person.province)
                continue

            if field == 'alias_name':
                apply_text_filter(Person.alias_name)
                continue

            if field == 'first_name':
                apply_text_filter(Person.first_name)
                continue

            if field == 'last_name':
                apply_text_filter(Person.last_name)
                continue

            if field == 'company_name':
                apply_text_filter(Person.company_name)
                continue

            if field == 'mobile':
                apply_text_filter(Person.mobile)
                continue

            if field == 'email':
                apply_text_filter(Person.email)
                continue

            if field == 'national_id':
                apply_text_filter(Person.national_id)
                continue

            if field == 'registration_number':
                apply_text_filter(Person.registration_number)
                continue

            if field == 'economic_id':
                apply_text_filter(Person.economic_id)
                continue

            if field == 'city':
                apply_text_filter(Person.city)
                continue

            if field == 'address':
                apply_text_filter(Person.address)
                continue
    
    # شمارش کل رکوردها
    total = query.count()
    
    # اعمال مرتب‌سازی (فقط برای فیلدهای دیتابیس)
    sort_desc = query_info.get('sort_desc', True)
    
    if sort_by not in ['balance', 'status']:
        # مرتب‌سازی در دیتابیس
        if sort_by == 'code':
            query = query.order_by(Person.code.desc() if sort_desc else Person.code.asc())
        elif sort_by == 'alias_name':
            query = query.order_by(Person.alias_name.desc() if sort_desc else Person.alias_name.asc())
        elif sort_by == 'first_name':
            query = query.order_by(Person.first_name.desc() if sort_desc else Person.first_name.asc())
        elif sort_by == 'last_name':
            query = query.order_by(Person.last_name.desc() if sort_desc else Person.last_name.asc())
        elif sort_by == 'created_at':
            query = query.order_by(Person.created_at.desc() if sort_desc else Person.created_at.asc())
        elif sort_by == 'updated_at':
            query = query.order_by(Person.updated_at.desc() if sort_desc else Person.updated_at.asc())
        else:
            query = query.order_by(Person.created_at.desc())
    
    skip = query_info.get('skip', 0)
    take = query_info.get('take', 20)
    
    # اگر نیاز به محاسبه تراز قبل از pagination است
    if needs_balance_before_pagination:
        # دریافت همه persons
        all_persons = query.all()
        
        # تبدیل به دیکشنری و محاسبه تراز
        all_items = []
        person_ids = [p.id for p in all_persons]
        balances = calculate_persons_balances_bulk(db, person_ids, fiscal_year_id)
        
        for person in all_persons:
            item = _person_to_dict(person)
            balance, status = balances.get(person.id, (0.0, "بدون تراکنش"))
            item['balance'] = balance
            item['status'] = status
            all_items.append(item)
        
        # اعمال فیلتر balance و status
        if query_info.get('filters'):
            for filter_item in query_info['filters']:
                if isinstance(filter_item, dict):
                    field = filter_item.get('property')
                    operator = filter_item.get('operator')
                    value = filter_item.get('value')
                else:
                    field = getattr(filter_item, 'property', None)
                    operator = getattr(filter_item, 'operator', None)
                    value = getattr(filter_item, 'value', None)
                
                if field == 'balance':
                    if operator == '=':
                        all_items = [item for item in all_items if item['balance'] == value]
                    elif operator == '>':
                        all_items = [item for item in all_items if item['balance'] > value]
                    elif operator == '>=':
                        all_items = [item for item in all_items if item['balance'] >= value]
                    elif operator == '<':
                        all_items = [item for item in all_items if item['balance'] < value]
                    elif operator == '<=':
                        all_items = [item for item in all_items if item['balance'] <= value]
                elif field == 'status':
                    if operator == '=' and isinstance(value, str):
                        all_items = [item for item in all_items if item['status'] == value]
                    elif operator == 'in' and isinstance(value, list):
                        all_items = [item for item in all_items if item['status'] in value]
        
        # مرتب‌سازی
        if sort_by == 'balance':
            all_items.sort(key=lambda x: x['balance'], reverse=sort_desc)
        elif sort_by == 'status':
            all_items.sort(key=lambda x: x['status'], reverse=sort_desc)
        
        # محاسبه total بعد از فیلتر
        total = len(all_items)
        
        # اعمال pagination
        items = all_items[skip:skip + take]
    else:
        # روش معمولی: ابتدا pagination، سپس محاسبه تراز
        persons = query.offset(skip).limit(take).all()
        
        # تبدیل به دیکشنری
        items = [_person_to_dict(person) for person in persons]
        
        # محاسبه تراز برای persons فعلی
        person_ids = [p.id for p in persons]
        balances = calculate_persons_balances_bulk(db, person_ids, fiscal_year_id)
        
        for item in items:
            person_id = item['id']
            balance, status = balances.get(person_id, (0.0, "بدون تراکنش"))
            item['balance'] = balance
            item['status'] = status
    
    # محاسبه اطلاعات صفحه‌بندی
    total_pages = (total + take - 1) // take if take > 0 else 0
    current_page = (skip // take) + 1 if take > 0 else 1
    
    pagination = {
        'total': total,
        'page': current_page,
        'per_page': take,
        'total_pages': total_pages,
        'has_next': current_page < total_pages,
        'has_prev': current_page > 1
    }
    
    return {
        'items': items,
        'pagination': pagination,
        'query_info': query_info
    }


def update_person(
    db: Session, 
    person_id: int, 
    business_id: int, 
    person_data: PersonUpdateRequest
) -> Optional[Dict[str, Any]]:
    """ویرایش شخص"""
    person = db.query(Person).filter(
        and_(Person.id == person_id, Person.business_id == business_id)
    ).first()
    
    if not person:
        return None
    
    # به‌روزرسانی فیلدها
    update_data = person_data.dict(exclude_unset=True)

    # مدیریت کد یکتا
    if 'code' in update_data and update_data['code'] is not None:
        desired_code = update_data['code']
        exists = db.query(Person).filter(
            and_(Person.business_id == business_id, Person.code == desired_code, Person.id != person_id)
        ).first()
        if exists:
            raise ValueError("کد شخص تکراری است")
        person.code = desired_code

    # مدیریت انواع شخص چندگانه
    types_list: Optional[List[str]] = None
    if 'person_types' in update_data and update_data['person_types'] is not None:
        incoming = update_data['person_types'] or []
        types_list = [t.value if hasattr(t, 'value') else str(t) for t in incoming]
        person.person_types = json.dumps(types_list, ensure_ascii=False) if types_list else None
        # همگام کردن person_type تکی برای سازگاری
        # person_type handling removed - only person_types is used now

    # اگر شخص سهامدار شد، share_count معتبر باشد
    resulting_types: List[str] = []
    if person.person_types:
        try:
            tmp = json.loads(person.person_types)
            if isinstance(tmp, list):
                resulting_types = [str(x) for x in tmp]
        except Exception:
            resulting_types = []
    if 'سهامدار' in resulting_types:
        sc_val2 = update_data.get('share_count', person.share_count)
        if sc_val2 is None or (isinstance(sc_val2, int) and sc_val2 <= 0):
            raise ApiError("INVALID_SHARE_COUNT", "برای سهامدار، تعداد سهام الزامی و باید بزرگتر از صفر باشد", http_status=400)

    # سایر فیلدها
    for field in list(update_data.keys()):
        if field in {'code', 'person_types'}:
            continue
        setattr(person, field, update_data[field])
    
    db.commit()
    db.refresh(person)
    
    # Invalidate کش لیست اشخاص
    invalidate_persons_cache(business_id, fiscal_year_id=None)
    
    return success_response(
        message="شخص با موفقیت ویرایش شد",
        data=_person_to_dict(person)
    )


def check_person_has_accounting_documents(db: Session, person_id: int) -> tuple[bool, list[str]]:
    """
    بررسی وجود اسناد حسابداری مرتبط با شخص
    
    Returns:
        tuple: (has_documents, document_types)
        - has_documents: True اگر سند مرتبطی وجود داشته باشد
        - document_types: لیست انواع اسناد مرتبط
    """
    from sqlalchemy import func
    
    # بررسی وجود خطوط سند با person_id در اسناد قطعی (غیر پیش‌نویس)
    document_lines_count = db.query(func.count(DocumentLine.id)).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        DocumentLine.person_id == person_id,
        Document.is_proforma == False
    ).scalar()
    
    if document_lines_count and document_lines_count > 0:
        # دریافت انواع اسناد مرتبط
        document_types = db.query(Document.document_type).join(
            DocumentLine, Document.id == DocumentLine.document_id
        ).filter(
            DocumentLine.person_id == person_id,
            Document.is_proforma == False
        ).distinct().all()
        
        types_list = [doc_type[0] for doc_type in document_types if doc_type[0]]
        
        # تبدیل انواع اسناد به نام‌های فارسی
        type_names = []
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
            if type_name not in type_names:
                type_names.append(type_name)
        
        return True, type_names
    
    return False, []


def delete_person(db: Session, person_id: int, business_id: int) -> tuple[bool, str | None]:
    """
    حذف شخص
    
    Returns:
        tuple: (success, error_message)
        - success: True اگر حذف موفق باشد
        - error_message: پیام خطا در صورت عدم موفقیت
    """
    person = db.query(Person).filter(
        and_(Person.id == person_id, Person.business_id == business_id)
    ).first()
    
    if not person:
        return False, "شخص یافت نشد"
    
    # بررسی وجود اسناد حسابداری مرتبط
    has_documents, document_types = check_person_has_accounting_documents(db, person_id)
    
    if has_documents:
        types_str = "، ".join(document_types)
        error_msg = f"امکان حذف این شخص وجود ندارد زیرا دارای اسناد حسابداری مرتبط است. انواع اسناد: {types_str}"
        return False, error_msg
    
    try:
        db.delete(person)
        db.commit()
        
        # Invalidate کش لیست اشخاص
        invalidate_persons_cache(business_id, fiscal_year_id=None)
        
        return True, None
    except Exception as e:
        db.rollback()
        return False, f"خطا در حذف شخص: {str(e)}"


def get_person_summary(db: Session, business_id: int) -> Dict[str, Any]:
    """دریافت خلاصه اشخاص"""
    # تعداد کل اشخاص
    total_persons = db.query(Person).filter(Person.business_id == business_id).count()
    
    # حذف مفهوم فعال/غیرفعال
    active_persons = 0
    inactive_persons = total_persons
    
    # تعداد بر اساس نوع
    by_type = {}
    for person_type in PersonType:
        count = db.query(Person).filter(
            and_(Person.business_id == business_id, Person.person_types.ilike(f'%"{person_type.value}"%'))
        ).count()
        by_type[person_type.value] = count
    
    return {
        'total_persons': total_persons,
        'by_type': by_type,
        'active_persons': active_persons,
        'inactive_persons': inactive_persons
    }


def _person_to_dict(person: Person) -> Dict[str, Any]:
    """تبدیل مدل Person به دیکشنری"""
    # Parse person_types JSON to list
    types_list: List[str] = []
    if person.person_types:
        try:
            types = json.loads(person.person_types)
            if isinstance(types, list):
                types_list = [str(x) for x in types]
        except Exception:
            types_list = []

    return {
        'id': person.id,
        'business_id': person.business_id,
        'code': person.code,
        'alias_name': person.alias_name,
        'first_name': person.first_name,
        'last_name': person.last_name,
        'person_types': types_list,
        'company_name': person.company_name,
        'payment_id': person.payment_id,
        'share_count': person.share_count,
        'commission_sale_percent': float(person.commission_sale_percent) if getattr(person, 'commission_sale_percent', None) is not None else None,
        'commission_sales_return_percent': float(person.commission_sales_return_percent) if getattr(person, 'commission_sales_return_percent', None) is not None else None,
        'commission_sales_amount': float(person.commission_sales_amount) if getattr(person, 'commission_sales_amount', None) is not None else None,
        'commission_sales_return_amount': float(person.commission_sales_return_amount) if getattr(person, 'commission_sales_return_amount', None) is not None else None,
        'commission_exclude_discounts': bool(person.commission_exclude_discounts),
        'commission_exclude_additions_deductions': bool(person.commission_exclude_additions_deductions),
        'commission_post_in_invoice_document': bool(person.commission_post_in_invoice_document),
        'national_id': person.national_id,
        'registration_number': person.registration_number,
        'economic_id': person.economic_id,
        'country': person.country,
        'province': person.province,
        'city': person.city,
        'address': person.address,
        'postal_code': person.postal_code,
        'phone': person.phone,
        'mobile': person.mobile,
        'fax': person.fax,
        'email': person.email,
        'website': person.website,
        'credit_limit': float(person.credit_limit) if getattr(person, 'credit_limit', None) is not None else None,
        'credit_check_enabled': getattr(person, 'credit_check_enabled', None),
        'created_at': person.created_at.isoformat(),
        'updated_at': person.updated_at.isoformat(),
        'bank_accounts': [
            {
                'id': ba.id,
                'person_id': ba.person_id,
                'bank_name': ba.bank_name,
                'account_number': ba.account_number,
                'card_number': ba.card_number,
                'sheba_number': ba.sheba_number,
                'created_at': ba.created_at.isoformat(),
                'updated_at': ba.updated_at.isoformat(),
            }
            for ba in person.bank_accounts
        ]
    }


def search_persons(db: Session, business_id: int, search_query: Optional[str] = None, 
                  page: int = 1, limit: int = 20) -> List[Person]:
    """جست‌وجو در اشخاص"""
    query = db.query(Person).filter(Person.business_id == business_id)
    
    if search_query:
        # جست‌وجو در نام، نام خانوادگی، نام مستعار، کد، تلفن و ایمیل
        search_filter = or_(
            Person.alias_name.ilike(f"%{search_query}%"),
            Person.first_name.ilike(f"%{search_query}%"),
            Person.last_name.ilike(f"%{search_query}%"),
            Person.company_name.ilike(f"%{search_query}%"),
            Person.phone.ilike(f"%{search_query}%"),
            Person.mobile.ilike(f"%{search_query}%"),
            Person.email.ilike(f"%{search_query}%"),
            Person.code == int(search_query) if search_query.isdigit() else False
        )
        query = query.filter(search_filter)
    
    # مرتب‌سازی بر اساس نام مستعار
    query = query.order_by(Person.alias_name)
    
    # صفحه‌بندی
    offset = (page - 1) * limit
    return query.offset(offset).limit(limit).all()


def count_persons(db: Session, business_id: int, search_query: Optional[str] = None) -> int:
    """شمارش تعداد اشخاص"""
    query = db.query(Person).filter(Person.business_id == business_id)
    
    if search_query:
        # جست‌وجو در نام، نام خانوادگی، نام مستعار، کد، تلفن و ایمیل
        search_filter = or_(
            Person.alias_name.ilike(f"%{search_query}%"),
            Person.first_name.ilike(f"%{search_query}%"),
            Person.last_name.ilike(f"%{search_query}%"),
            Person.company_name.ilike(f"%{search_query}%"),
            Person.phone.ilike(f"%{search_query}%"),
            Person.mobile.ilike(f"%{search_query}%"),
            Person.email.ilike(f"%{search_query}%"),
            Person.code == int(search_query) if search_query.isdigit() else False
        )
        query = query.filter(search_filter)
    
    return query.count()


def calculate_person_balance(
    db: Session, 
    person_id: int, 
    fiscal_year_id: Optional[int] = None
) -> tuple[float, str]:
    """
    محاسبه تراز و وضعیت مالی یک شخص
    
    Args:
        db: نشست پایگاه داده
        person_id: شناسه شخص
        fiscal_year_id: شناسه سال مالی (اختیاری)
    
    Returns:
        tuple: (تراز, وضعیت)
        - تراز: credit - debit
        - وضعیت: "بستانکار" | "بدهکار" | "بالانس" | "بدون تراکنش"
    """
    # Query برای محاسبه مجموع بستانکار و بدهکار
    query = db.query(
        func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit'),
        func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit')
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        DocumentLine.person_id == person_id,
        Document.is_proforma == False  # فقط اسناد قطعی
    )
    
    # اعمال فیلتر سال مالی
    if fiscal_year_id:
        query = query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    result = query.first()
    
    if result is None:
        return 0.0, "بدون تراکنش"
    
    total_credit = float(result.total_credit or 0)
    total_debit = float(result.total_debit or 0)
    
    # محاسبه تراز: بستانکار - بدهکار
    balance = total_credit - total_debit
    
    # تعیین وضعیت
    if total_credit == 0 and total_debit == 0:
        status = "بدون تراکنش"
    elif balance > 0:
        status = "بستانکار"
    elif balance < 0:
        status = "بدهکار"
    else:  # balance == 0
        status = "بالانس"
    
    return balance, status


def calculate_persons_balances_bulk(
    db: Session, 
    person_ids: List[int], 
    fiscal_year_id: Optional[int] = None
) -> Dict[int, tuple[float, str]]:
    """
    محاسبه تراز و وضعیت چندین شخص به صورت دسته‌جمعی
    
    Args:
        db: نشست پایگاه داده
        person_ids: لیست شناسه‌های اشخاص
        fiscal_year_id: شناسه سال مالی (اختیاری)
    
    Returns:
        dict: {person_id: (balance, status)}
    """
    if not person_ids:
        return {}
    
    # Query برای محاسبه مجموع بستانکار و بدهکار برای هر شخص
    query = db.query(
        DocumentLine.person_id,
        func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit'),
        func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit')
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        DocumentLine.person_id.in_(person_ids),
        Document.is_proforma == False  # فقط اسناد قطعی
    )
    
    # اعمال فیلتر سال مالی
    if fiscal_year_id:
        query = query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    # Group by person_id
    query = query.group_by(DocumentLine.person_id)
    
    results = query.all()
    
    # ساخت دیکشنری نتایج
    balances: Dict[int, tuple[float, str]] = {}
    
    # ابتدا همه را به "بدون تراکنش" تنظیم می‌کنیم
    for person_id in person_ids:
        balances[person_id] = (0.0, "بدون تراکنش")
    
    # سپس نتایج واقعی را اعمال می‌کنیم
    for result in results:
        person_id = result.person_id
        total_credit = float(result.total_credit or 0)
        total_debit = float(result.total_debit or 0)
        
        # محاسبه تراز
        balance = total_credit - total_debit
        
        # تعیین وضعیت
        if balance > 0:
            status = "بستانکار"
        elif balance < 0:
            status = "بدهکار"
        else:  # balance == 0
            status = "بالانس"
        
        balances[person_id] = (balance, status)
    
    return balances


def get_debtors_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    min_balance: Optional[float] = None,
    person_ids: Optional[List[int]] = None,
    search: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش بدهکاران
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        min_balance: حداقل بدهی (فقط اشخاص با balance <= -min_balance)
        person_ids: لیست شناسه‌های اشخاص برای فیلتر (اختیاری)
        search: جستجو در نام/کد (اختیاری)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست بدهکاران,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    from datetime import datetime
    from sqlalchemy import case
    
    # Query پایه برای اشخاص
    query = db.query(Person).filter(Person.business_id == business_id)
    
    # فیلتر بر اساس person_ids
    if person_ids:
        query = query.filter(Person.id.in_(person_ids))
    
    # فیلتر جستجو
    if search and search.strip():
        search_filter = or_(
            Person.alias_name.ilike(f'%{search}%'),
            Person.company_name.ilike(f'%{search}%'),
            Person.first_name.ilike(f'%{search}%'),
            Person.last_name.ilike(f'%{search}%'),
            func.cast(Person.code, String).ilike(f'%{search}%'),
        )
        query = query.filter(search_filter)
    
    # دریافت همه اشخاص
    all_persons = query.all()
    
    if not all_persons:
        return {
            'items': [],
            'summary': {
                'total_count': 0,
                'total_debt': 0.0,
                'average_debt': 0.0,
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
    
    person_ids_list = [p.id for p in all_persons]
    
    # Query برای محاسبه تراز هر شخص با فیلتر تاریخ و ارز
    balance_query = db.query(
        DocumentLine.person_id,
        func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit'),
        func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit'),
        func.max(Document.document_date).label('last_transaction_date'),
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        DocumentLine.person_id.in_(person_ids_list),
        Document.is_proforma == False  # فقط اسناد قطعی
    )
    
    # اعمال فیلتر ارز
    if currency_id:
        balance_query = balance_query.filter(Document.currency_id == currency_id)
    
    # اعمال فیلتر سال مالی
    if fiscal_year_id:
        balance_query = balance_query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    # اعمال فیلتر تاریخ
    if date_from:
        try:
            date_from_obj = datetime.strptime(date_from, '%Y-%m-%d').date()
            balance_query = balance_query.filter(Document.document_date >= date_from_obj)
        except ValueError:
            pass
    
    if date_to:
        try:
            date_to_obj = datetime.strptime(date_to, '%Y-%m-%d').date()
            balance_query = balance_query.filter(Document.document_date <= date_to_obj)
        except ValueError:
            pass
    
    # Group by person_id
    balance_query = balance_query.group_by(DocumentLine.person_id)
    
    balance_results = balance_query.all()
    
    # ساخت دیکشنری ترازها
    balances_dict: Dict[int, Dict[str, Any]] = {}
    for person_id in person_ids_list:
        balances_dict[person_id] = {
            'balance': 0.0,
            'total_credit': 0.0,
            'total_debit': 0.0,
            'last_transaction_date': None,
        }
    
    for result in balance_results:
        person_id = result.person_id
        total_credit = float(result.total_credit or 0)
        total_debit = float(result.total_debit or 0)
        balance = total_credit - total_debit
        
        balances_dict[person_id] = {
            'balance': balance,
            'total_credit': total_credit,
            'total_debit': total_debit,
            'last_transaction_date': result.last_transaction_date.isoformat() if result.last_transaction_date else None,
        }
    
    # فیلتر فقط بدهکاران (balance < 0)
    debtors = []
    for person in all_persons:
        balance_info = balances_dict[person.id]
        balance = balance_info['balance']
        
        # فقط بدهکاران (balance < 0)
        if balance < 0:
            # فیلتر بر اساس min_balance
            if min_balance is not None:
                if abs(balance) < min_balance:
                    continue
            
            person_dict = _person_to_dict(person)
            person_dict.update(balance_info)
            
            # تعیین وضعیت
            if balance < 0:
                person_dict['status'] = 'بدهکار'
            else:
                person_dict['status'] = 'بالانس'
            
            debtors.append(person_dict)
    
    # مرتب‌سازی بر اساس balance (از بیشترین بدهی به کمترین)
    debtors.sort(key=lambda x: x['balance'])
    
    # محاسبه خلاصه
    total_debt = sum(abs(d['balance']) for d in debtors)
    total_count = len(debtors)
    average_debt = total_debt / total_count if total_count > 0 else 0.0
    
    # اعمال pagination
    total = len(debtors)
    paginated_debtors = debtors[skip:skip + take]
    
    total_pages = (total + take - 1) // take if take > 0 else 0
    current_page = (skip // take) + 1 if take > 0 else 1
    
    return {
        'items': paginated_debtors,
        'summary': {
            'total_count': total_count,
            'total_debt': total_debt,
            'average_debt': average_debt,
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


def get_creditors_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    min_balance: Optional[float] = None,
    person_ids: Optional[List[int]] = None,
    search: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش بستانکاران
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        min_balance: حداقل بستانکاری (فقط اشخاص با balance >= min_balance)
        person_ids: لیست شناسه‌های اشخاص برای فیلتر (اختیاری)
        search: جستجو در نام/کد (اختیاری)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست بستانکاران,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    from datetime import datetime
    from sqlalchemy import case
    
    # Query پایه برای اشخاص
    query = db.query(Person).filter(Person.business_id == business_id)
    
    # فیلتر بر اساس person_ids
    if person_ids:
        query = query.filter(Person.id.in_(person_ids))
    
    # فیلتر جستجو
    if search and search.strip():
        search_filter = or_(
            Person.alias_name.ilike(f'%{search}%'),
            Person.company_name.ilike(f'%{search}%'),
            Person.first_name.ilike(f'%{search}%'),
            Person.last_name.ilike(f'%{search}%'),
            func.cast(Person.code, String).ilike(f'%{search}%'),
        )
        query = query.filter(search_filter)
    
    # دریافت همه اشخاص
    all_persons = query.all()
    
    if not all_persons:
        return {
            'items': [],
            'summary': {
                'total_count': 0,
                'total_credit': 0.0,
                'average_credit': 0.0,
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
    
    person_ids_list = [p.id for p in all_persons]
    
    # Query برای محاسبه تراز هر شخص با فیلتر تاریخ و ارز
    balance_query = db.query(
        DocumentLine.person_id,
        func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit'),
        func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit'),
        func.max(Document.document_date).label('last_transaction_date'),
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        DocumentLine.person_id.in_(person_ids_list),
        Document.is_proforma == False  # فقط اسناد قطعی
    )
    
    # اعمال فیلتر ارز
    if currency_id:
        balance_query = balance_query.filter(Document.currency_id == currency_id)
    
    # اعمال فیلتر سال مالی
    if fiscal_year_id:
        balance_query = balance_query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    # اعمال فیلتر تاریخ
    if date_from:
        try:
            date_from_obj = datetime.strptime(date_from, '%Y-%m-%d').date()
            balance_query = balance_query.filter(Document.document_date >= date_from_obj)
        except ValueError:
            pass
    
    if date_to:
        try:
            date_to_obj = datetime.strptime(date_to, '%Y-%m-%d').date()
            balance_query = balance_query.filter(Document.document_date <= date_to_obj)
        except ValueError:
            pass
    
    # Group by person_id
    balance_query = balance_query.group_by(DocumentLine.person_id)
    
    balance_results = balance_query.all()
    
    # ساخت دیکشنری ترازها
    balances_dict: Dict[int, Dict[str, Any]] = {}
    for person_id in person_ids_list:
        balances_dict[person_id] = {
            'balance': 0.0,
            'total_credit': 0.0,
            'total_debit': 0.0,
            'last_transaction_date': None,
        }
    
    for result in balance_results:
        person_id = result.person_id
        total_credit = float(result.total_credit or 0)
        total_debit = float(result.total_debit or 0)
        balance = total_credit - total_debit
        
        balances_dict[person_id] = {
            'balance': balance,
            'total_credit': total_credit,
            'total_debit': total_debit,
            'last_transaction_date': result.last_transaction_date.isoformat() if result.last_transaction_date else None,
        }
    
    # فیلتر فقط بستانکاران (balance > 0)
    creditors = []
    for person in all_persons:
        balance_info = balances_dict[person.id]
        balance = balance_info['balance']
        
        # فقط بستانکاران (balance > 0)
        if balance > 0:
            # فیلتر بر اساس min_balance
            if min_balance is not None:
                if balance < min_balance:
                    continue
            
            person_dict = _person_to_dict(person)
            person_dict.update(balance_info)
            
            # تعیین وضعیت
            if balance > 0:
                person_dict['status'] = 'بستانکار'
            elif balance == 0:
                person_dict['status'] = 'بالانس'
            else:
                person_dict['status'] = 'بدون تراکنش'
            
            creditors.append(person_dict)
    
    # مرتب‌سازی بر اساس balance (از بیشترین بستانکاری به کمترین)
    creditors.sort(key=lambda x: x['balance'], reverse=True)
    
    # محاسبه خلاصه
    total_credit = sum(d['balance'] for d in creditors)
    total_count = len(creditors)
    average_credit = total_credit / total_count if total_count > 0 else 0.0
    
    # اعمال pagination
    total = len(creditors)
    paginated_creditors = creditors[skip:skip + take]
    
    total_pages = (total + take - 1) // take if take > 0 else 0
    current_page = (skip // take) + 1 if take > 0 else 1
    
    return {
        'items': paginated_creditors,
        'summary': {
            'total_count': total_count,
            'total_credit': total_credit,
            'average_credit': average_credit,
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


def get_people_transactions_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    person_ids: Optional[List[int]] = None,
    document_type: Optional[str] = None,  # receipt, payment, or None for all
    search: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش تراکنش‌های اشخاص
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        person_ids: لیست شناسه‌های اشخاص برای فیلتر (اختیاری)
        document_type: نوع سند (receipt, payment) یا None برای همه
        search: جستجو در کد سند یا نام شخص (اختیاری)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست تراکنش‌ها,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    from datetime import datetime
    
    # Query پایه: DocumentLine join Document و Person
    query = db.query(
        DocumentLine,
        Document,
        Person
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).outerjoin(
        Person, DocumentLine.person_id == Person.id
    ).filter(
        Document.business_id == business_id,
        Document.is_proforma == False,  # فقط اسناد قطعی
        DocumentLine.person_id.isnot(None)  # فقط خطوط با person_id
    )
    
    # فیلتر سال مالی
    if fiscal_year_id:
        query = query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    # فیلتر ارز
    if currency_id:
        query = query.filter(Document.currency_id == currency_id)
    
    # فیلتر تاریخ
    if date_from:
        try:
            date_from_obj = datetime.strptime(date_from, '%Y-%m-%d').date()
            query = query.filter(Document.document_date >= date_from_obj)
        except ValueError:
            pass
    
    if date_to:
        try:
            date_to_obj = datetime.strptime(date_to, '%Y-%m-%d').date()
            query = query.filter(Document.document_date <= date_to_obj)
        except ValueError:
            pass
    
    # فیلتر اشخاص
    if person_ids:
        query = query.filter(DocumentLine.person_id.in_(person_ids))
    
    # فیلتر نوع سند - پشتیبانی از همه انواع اسناد
    if document_type:
        query = query.filter(Document.document_type == document_type)
    
    # فیلتر جستجو
    if search and search.strip():
        search_filter = or_(
            Document.code.ilike(f'%{search}%'),
            Person.alias_name.ilike(f'%{search}%'),
            Person.company_name.ilike(f'%{search}%'),
            Person.first_name.ilike(f'%{search}%'),
            Person.last_name.ilike(f'%{search}%'),
        )
        query = query.filter(search_filter)
    
    # مرتب‌سازی: تاریخ سند، کد سند، شناسه خط
    query = query.order_by(
        Document.document_date.asc(),
        Document.id.asc(),
        DocumentLine.id.asc()
    )
    
    # دریافت همه نتایج برای محاسبه running balance
    all_results = query.all()
    
    if not all_results:
        return {
            'items': [],
            'summary': {
                'total_count': 0,
                'total_debit': 0.0,
                'total_credit': 0.0,
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
    
    # محاسبه running balance و ساخت لیست آیتم‌ها
    items = []
    running_balance = 0.0
    
    for line, doc, person in all_results:
        debit = float(line.debit or 0)
        credit = float(line.credit or 0)
        balance_change = credit - debit
        running_balance += balance_change
        
        # نام شخص
        person_name = None
        if person:
            person_name = (
                person.alias_name or
                person.company_name or
                f"{person.first_name or ''} {person.last_name or ''}".strip()
            )
        
        # نوع سند (نام فارسی) - استفاده از mapping کامل
        def _get_document_type_name(doc_type: str | None) -> str:
            """تبدیل document_type به نام فارسی"""
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
        
        document_type_name = _get_document_type_name(doc.document_type)
        
        item_dict = _person_to_dict(person) if person else {}
        item_dict.update({
            'line_id': line.id,
            'document_id': doc.id,
            'document_code': doc.code,
            'document_date': doc.document_date.isoformat(),
            'document_type': doc.document_type,
            'document_type_name': document_type_name,
            'person_id': line.person_id,
            'person_name': person_name,
            'debit': debit,
            'credit': credit,
            'balance_change': balance_change,
            'running_balance': running_balance,
            'description': line.description,
        })
        items.append(item_dict)
    
    # محاسبه خلاصه
    total_count = len(items)
    total_debit = sum(item['debit'] for item in items)
    total_credit = sum(item['credit'] for item in items)
    
    # اعمال pagination
    total = len(items)
    paginated_items = items[skip:skip + take]
    
    total_pages = (total + take - 1) // take if take > 0 else 0
    current_page = (skip // take) + 1 if take > 0 else 1
    
    return {
        'items': paginated_items,
        'summary': {
            'total_count': total_count,
            'total_debit': total_debit,
            'total_credit': total_credit,
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
