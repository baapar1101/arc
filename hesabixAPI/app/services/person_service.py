from typing import List, Optional, Dict, Any
from decimal import Decimal
from datetime import datetime, time, timezone, date
import json
from sqlalchemy.exc import IntegrityError
from app.core.responses import ApiError
from sqlalchemy.orm import Session, joinedload, selectinload
from sqlalchemy import and_, or_, func, String
from adapters.db.models.person import Person, PersonBankAccount, PersonSocialContact, PersonType
from adapters.db.models.person_group import PersonGroup
from adapters.db.models.business import Business
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.api.v1.schema_models.person import (
    PersonCreateRequest,
    PersonUpdateRequest,
    PersonBankAccountCreateRequest,
    PersonSocialContactInput,
)
from app.core.responses import success_response
from app.core.cache import get_cache
from app.services.person_group_service import (
    assert_assignable_person_group,
    merge_person_create_with_group_defaults,
)
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


def create_person(
    db: Session,
    business_id: int,
    person_data: PersonCreateRequest,
    *,
    defer_cache_invalidation: bool = False,
) -> Dict[str, Any]:
    """ایجاد شخص جدید"""
    person_data = merge_person_create_with_group_defaults(db, business_id, person_data)
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
        person_group_id=getattr(person_data, "person_group_id", None),
        code=code,
        alias_name=person_data.alias_name,
        first_name=person_data.first_name,
        last_name=person_data.last_name,
        # ذخیره مقدار Enum با مقدار فارسی (values_callable در مدل مقادیر فارسی را می‌نویسد)
        # person_types نباید None باشد (nullable=False در مدل)
        person_types=json.dumps(types_list, ensure_ascii=False) if types_list else "[]",
        company_name=person_data.company_name,
        name_prefix=getattr(person_data, "name_prefix", None),
        legal_entity_type=getattr(person_data, "legal_entity_type", None) or "natural",
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
        mobile_2=person_data.mobile_2,
        mobile_3=person_data.mobile_3,
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

    _socials = getattr(person_data, "social_contacts", None) or []
    for i, sc in enumerate(_socials):
        db.add(
            PersonSocialContact(
                person_id=person.id,
                platform_key=sc.platform_key,
                custom_label=sc.custom_label,
                value=sc.value,
                sort_order=i,
            )
        )
    
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ApiError("DUPLICATE_PERSON_CODE", "کد شخص تکراری است", http_status=400)
    db.refresh(person)

    # Invalidate کش لیست اشخاص (در bulk با defer از بیرون یک‌بار invalidate می‌شود)
    if not defer_cache_invalidation:
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


def get_person_by_id(
    db: Session,
    person_id: int,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
) -> Optional[Dict[str, Any]]:
    """دریافت شخص بر اساس شناسه (همراه با تراز و وضعیت مالی در سال مالی انتخاب‌شده یا جاری)"""
    person = (
        db.query(Person)
        .options(
            joinedload(Person.person_group),
            selectinload(Person.bank_accounts),
            selectinload(Person.social_contacts),
        )
        .filter(and_(Person.id == person_id, Person.business_id == business_id))
        .first()
    )
    
    if not person:
        return None
    
    data = _person_to_dict(person)

    fy_id = fiscal_year_id
    if not fy_id:
        fiscal_year = db.query(FiscalYear).filter(
            and_(FiscalYear.business_id == business_id, FiscalYear.is_last == True)
        ).first()
        fy_id = fiscal_year.id if fiscal_year else None

    balance, status = calculate_person_balance(db, person_id, fiscal_year_id=fy_id)
    data["balance"] = balance
    data["status"] = status
    return data


def _person_sort_needs_balance_materialization(query_info: Dict[str, Any]) -> bool:
    if query_info.get("sort_by") in ("balance", "status"):
        return True
    raw = query_info.get("sort")
    if not isinstance(raw, list):
        return False
    for it in raw:
        by = it.get("by") if isinstance(it, dict) else None
        if by in ("balance", "status"):
            return True
    return False


def get_persons_by_business(
    db: Session, 
    business_id: int, 
    query_info: Dict[str, Any],
    fiscal_year_id: Optional[int] = None
) -> Dict[str, Any]:
    """دریافت لیست اشخاص با جستجو و فیلتر"""
    query = (
        db.query(Person)
        .options(
            joinedload(Person.person_group),
            selectinload(Person.bank_accounts),
            selectinload(Person.social_contacts),
        )
        .filter(Person.business_id == business_id)
    )
    
    # بررسی نیاز به محاسبه تراز قبل از pagination
    # (برای فیلتر یا مرتب‌سازی بر اساس تراز/وضعیت)
    needs_balance_before_pagination = _person_sort_needs_balance_materialization(query_info)
    sort_by = query_info.get('sort_by', 'created_at')
    
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
                search_conditions.append(
                    or_(
                        Person.mobile.ilike(search_term),
                        Person.mobile_2.ilike(search_term),
                        Person.mobile_3.ilike(search_term),
                    )
                )
            elif field == 'email':
                search_conditions.append(Person.email.ilike(search_term))
            elif field == 'national_id':
                search_conditions.append(Person.national_id.ilike(search_term))
            elif field == "social_value":
                search_conditions.append(
                    Person.id.in_(
                        db.query(PersonSocialContact.person_id).filter(
                            PersonSocialContact.value.ilike(search_term)
                        )
                    )
                )
        
        if search_conditions:
            query = query.filter(or_(*search_conditions))
    
    def apply_text_filter(base_query, column, operator: str, value):
        q = base_query
        if operator == '=':
            q = q.filter(column == value)
        elif operator in ('like', '*'):
            q = q.filter(column.ilike(f"%{value}%"))
        elif operator == '*?':  # starts with
            q = q.filter(column.ilike(f"{value}%"))
        elif operator == '?*':  # ends with
            q = q.filter(column.ilike(f"%{value}"))
        elif operator == 'in' and isinstance(value, list):
            vals = [v for v in value if v is not None and str(v).strip() != ""]
            if vals:
                q = q.filter(column.in_(vals))
        return q

    def _to_int_or_none(v):
        try:
            return int(v)
        except Exception:
            return None

    column_aliases = {
        # UI ستون نوع شخص را با person_type می‌فرستد ولی در DB/سرویس person_types است.
        'person_type': 'person_types',
    }
    text_columns = {
        'alias_name': Person.alias_name,
        'first_name': Person.first_name,
        'last_name': Person.last_name,
        'company_name': Person.company_name,
        'name_prefix': Person.name_prefix,
        'legal_entity_type': Person.legal_entity_type,
        'mobile': Person.mobile,
        'mobile_2': Person.mobile_2,
        'mobile_3': Person.mobile_3,
        'phone': Person.phone,
        'fax': Person.fax,
        'email': Person.email,
        'website': Person.website,
        'payment_id': Person.payment_id,
        'national_id': Person.national_id,
        'registration_number': Person.registration_number,
        'economic_id': Person.economic_id,
        'country': Person.country,
        'province': Person.province,
        'city': Person.city,
        'address': Person.address,
        'postal_code': Person.postal_code,
    }
    number_columns = {
        'code': Person.code,
        'person_group_id': Person.person_group_id,
        'share_count': Person.share_count,
        'commission_sale_percent': Person.commission_sale_percent,
        'commission_sales_return_percent': Person.commission_sales_return_percent,
        'commission_sales_amount': Person.commission_sales_amount,
        'commission_sales_return_amount': Person.commission_sales_return_amount,
    }

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

            field = column_aliases.get(field, field)

            # فیلترهای عددی
            if field in number_columns:
                col = number_columns[field]
                if operator == '=':
                    if field in ('code', 'person_group_id', 'share_count'):
                        iv = _to_int_or_none(value)
                        if iv is not None:
                            query = query.filter(col == iv)
                    else:
                        query = query.filter(col == value)
                elif operator == 'in' and isinstance(value, list):
                    if field in ('code', 'person_group_id', 'share_count'):
                        ivals = [iv for iv in (_to_int_or_none(v) for v in value) if iv is not None]
                        if ivals:
                            query = query.filter(col.in_(ivals))
                    else:
                        query = query.filter(col.in_(value))
                continue

            # انواع شخص چندانتخابی (رشته JSON)
            if field == 'person_types':
                if operator == '=' and isinstance(value, str):
                    query = query.filter(Person.person_types.ilike(f'%"{value}"%'))
                elif operator == 'in' and isinstance(value, list):
                    sub_filters = [Person.person_types.ilike(f'%"{v}"%') for v in value if v is not None and str(v).strip() != ""]
                    if sub_filters:
                        query = query.filter(or_(*sub_filters))
                continue

            # ستون نمایشی گروه اشخاص در UI (person_group_name)
            if field == 'person_group_name':
                if operator == '=':
                    query = query.filter(Person.person_group.has(PersonGroup.name == value))
                elif operator in ('like', '*'):
                    query = query.filter(Person.person_group.has(PersonGroup.name.ilike(f"%{value}%")))
                elif operator == '*?':
                    query = query.filter(Person.person_group.has(PersonGroup.name.ilike(f"{value}%")))
                elif operator == '?*':
                    query = query.filter(Person.person_group.has(PersonGroup.name.ilike(f"%{value}")))
                elif operator == 'in' and isinstance(value, list):
                    vals = [v for v in value if v is not None and str(v).strip() != ""]
                    if vals:
                        query = query.filter(Person.person_group.has(PersonGroup.name.in_(vals)))
                continue

            # فیلترهای متنی عمومی
            if field in text_columns:
                query = apply_text_filter(query, text_columns[field], operator, value)
                continue
    
    # شمارش کل رکوردها
    total = query.count()
    
    # اعمال مرتب‌سازی (فقط برای فیلدهای دیتابیس؛ چندستونه sort در اولویت)
    sort_desc = query_info.get('sort_desc', True)
    
    if not needs_balance_before_pagination:
        from adapters.api.v1.schemas import QueryInfo as _PersonQI
        from app.services.sort_resolution import effective_sort_specs as _eff_specs

        _sql_allowed = frozenset({"code", "alias_name", "first_name", "last_name", "created_at", "updated_at"})
        _qi = _PersonQI.model_validate({
            "take": int(query_info.get("take", 20) or 20),
            "skip": int(query_info.get("skip", 0) or 0),
            "sort_by": query_info.get("sort_by"),
            "sort_desc": bool(sort_desc),
            "sort": query_info.get("sort") if isinstance(query_info.get("sort"), list) else None,
        })
        _specs = _eff_specs(_qi, allowed=_sql_allowed, default_when_empty=("created_at", True))
        _parts = []
        for _n, _d in _specs:
            if not hasattr(Person, _n):
                continue
            _c = getattr(Person, _n)
            _parts.append(_c.desc() if _d else _c.asc())
        if _parts:
            query = query.order_by(*_parts)
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
        fx_codes = calculate_persons_foreign_currency_codes_bulk(
            db, person_ids, business_id, fiscal_year_id
        )
        
        for person in all_persons:
            item = _person_to_dict(person)
            balance, status = balances.get(person.id, (0.0, "بدون تراکنش"))
            item['balance'] = balance
            item['status'] = status
            item['foreign_currency_codes'] = fx_codes.get(person.id, [])
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
        fx_codes = calculate_persons_foreign_currency_codes_bulk(
            db, person_ids, business_id, fiscal_year_id
        )
        
        for item in items:
            person_id = item['id']
            balance, status = balances.get(person_id, (0.0, "بدون تراکنش"))
            item['balance'] = balance
            item['status'] = status
            item['foreign_currency_codes'] = fx_codes.get(person_id, [])
    
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
    person_data: PersonUpdateRequest,
    *,
    defer_cache_invalidation: bool = False,
) -> Optional[Dict[str, Any]]:
    """ویرایش شخص"""
    person = db.query(Person).filter(
        and_(Person.id == person_id, Person.business_id == business_id)
    ).first()
    
    if not person:
        return None
    
    # به‌روزرسانی فیلدها
    update_data = (
        person_data.model_dump(exclude_unset=True)
        if hasattr(person_data, "model_dump")
        else person_data.dict(exclude_unset=True)
    )

    sync_social: Optional[List[Any]] = None
    if "social_contacts" in update_data:
        sync_social = update_data.pop("social_contacts")
    # مانده افتتاحیه روی persons ذخیره نمی‌شود؛ در person_opening_balance_service مدیریت می‌شود
    update_data.pop("opening_balance", None)

    # مدیریت کد یکتا (شامل پاک کردن صریح با null)
    if 'code' in update_data:
        desired_code = update_data['code']
        if desired_code is not None:
            exists = db.query(Person).filter(
                and_(Person.business_id == business_id, Person.code == desired_code, Person.id != person_id)
            ).first()
            if exists:
                raise ValueError("کد شخص تکراری است")
            person.code = desired_code
        else:
            person.code = None

    # مدیریت انواع شخص چندگانه
    types_list: Optional[List[str]] = None
    if 'person_types' in update_data and update_data['person_types'] is not None:
        incoming = update_data['person_types'] or []
        types_list = [t.value if hasattr(t, 'value') else str(t) for t in incoming]
        person.person_types = json.dumps(types_list, ensure_ascii=False) if types_list else None
        # همگام کردن person_type تکی برای سازگاری
        # person_type handling removed - only person_types is used now

    if 'person_group_id' in update_data:
        pgid = update_data.pop('person_group_id', None)
        if pgid is None:
            person.person_group_id = None
        else:
            assert_assignable_person_group(db, business_id, int(pgid))
            person.person_group_id = int(pgid)

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
        if field in {'code', 'person_types', 'person_type'}:
            continue
        if field == 'legal_entity_type' and update_data[field] is None:
            continue
        setattr(person, field, update_data[field])
    
    if sync_social is not None:
        db.query(PersonSocialContact).filter(PersonSocialContact.person_id == person_id).delete(
            synchronize_session=False
        )
        for i, sc in enumerate(sync_social):
            p = sc if isinstance(sc, PersonSocialContactInput) else PersonSocialContactInput.model_validate(sc)
            db.add(
                PersonSocialContact(
                    person_id=person_id,
                    platform_key=p.platform_key,
                    custom_label=p.custom_label,
                    value=p.value,
                    sort_order=i,
                )
            )

    db.commit()
    db.refresh(person)
    person = (
        db.query(Person)
        .options(selectinload(Person.bank_accounts), selectinload(Person.social_contacts))
        .filter(Person.id == person_id)
        .first()
    ) or person

    if not defer_cache_invalidation:
        invalidate_persons_cache(business_id, fiscal_year_id=None)

    # فراخوانی workflow
    try:
        from app.services.workflow.workflow_trigger_service import trigger_person_updated

        types_list: list = []
        if person.person_types:
            try:
                tmp = json.loads(person.person_types)
                if isinstance(tmp, list):
                    types_list = [str(x) for x in tmp]
            except Exception:
                pass
        trigger_person_updated(
            db=db,
            business_id=business_id,
            person_id=int(person.id),
            person_types=types_list,
            user_id=None,
        )
    except Exception as e:
        logger.warning("person.updated workflow trigger failed: %s", e, exc_info=True)
    
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

    pg = getattr(person, "person_group", None)
    return {
        'id': person.id,
        'business_id': person.business_id,
        'person_group_id': getattr(person, "person_group_id", None),
        'person_group_name': pg.name if pg else None,
        'code': person.code,
        'alias_name': person.alias_name,
        'first_name': person.first_name,
        'last_name': person.last_name,
        'person_types': types_list,
        'company_name': person.company_name,
        'name_prefix': getattr(person, "name_prefix", None),
        'legal_entity_type': getattr(person, "legal_entity_type", None) or "natural",
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
        'mobile_2': person.mobile_2,
        'mobile_3': person.mobile_3,
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
        ],
        'social_contacts': [
            {
                'id': sc.id,
                'person_id': sc.person_id,
                'platform_key': sc.platform_key,
                'custom_label': sc.custom_label,
                'value': sc.value,
                'sort_order': sc.sort_order,
                'created_at': sc.created_at.isoformat(),
                'updated_at': sc.updated_at.isoformat(),
            }
            for sc in sorted(
                getattr(person, "social_contacts", []) or [],
                key=lambda x: (x.sort_order, x.id),
            )
        ],
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
            or_(
                Person.mobile.ilike(f"%{search_query}%"),
                Person.mobile_2.ilike(f"%{search_query}%"),
                Person.mobile_3.ilike(f"%{search_query}%"),
            ),
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
            or_(
                Person.mobile.ilike(f"%{search_query}%"),
                Person.mobile_2.ilike(f"%{search_query}%"),
                Person.mobile_3.ilike(f"%{search_query}%"),
            ),
            Person.email.ilike(f"%{search_query}%"),
            Person.code == int(search_query) if search_query.isdigit() else False
        )
        query = query.filter(search_filter)
    
    return query.count()


def _person_balance_status_from_totals(
    total_credit: Decimal, total_debit: Decimal, balance: Decimal
) -> str:
    if total_credit == 0 and total_debit == 0:
        return "بدون تراکنش"
    if balance > 0:
        return "بستانکار"
    if balance < 0:
        return "بدهکار"
    return "بالانس"


def _document_to_base_currency_rate(
    db: Session,
    business_id: int,
    base_currency_id: int,
    document: Document,
    *,
    rate_cache: Dict[int, Decimal],
) -> Decimal:
    """
    نرخ تبدیل ۱ واحد ارز سند به ارز پایه (هم‌معنا با resolve_rate_to_base).
    اولویت: extra_info.fx.rate ثبت‌شده روی سند، وگرنه نرخ تاریخ سند.
    """
    doc_id = int(document.id)
    if doc_id in rate_cache:
        return rate_cache[doc_id]
    dc = int(document.currency_id or 0)
    if dc == int(base_currency_id):
        rate_cache[doc_id] = Decimal(1)
        return Decimal(1)

    extra = document.extra_info or {}
    fx = extra.get("fx") if isinstance(extra, dict) else None
    if isinstance(fx, dict) and not fx.get("skipped") and fx.get("rate") is not None:
        try:
            rate = Decimal(str(fx["rate"]))
            if rate > 0:
                rate_cache[doc_id] = rate
                return rate
        except Exception:
            pass

    from app.services.business_currency_rate_service import resolve_rate_to_base, _to_utc_aware
    from app.services.invoice_fx_revaluation import compute_fx_as_of_utc, get_fx_revaluation_policy

    b = db.get(Business, int(business_id))
    if not b:
        logger.warning(
            "person balance: business %s not found, using rate=1 for document %s",
            business_id,
            doc_id,
        )
        rate_cache[doc_id] = Decimal(1)
        return Decimal(1)

    policy = get_fx_revaluation_policy(b)
    reg = document.registered_at or datetime.now(timezone.utc)
    if reg.tzinfo is None:
        reg = reg.replace(tzinfo=timezone.utc)
    reg = _to_utc_aware(reg)
    as_of = compute_fx_as_of_utc(document.document_date, reg, policy)
    try:
        res = resolve_rate_to_base(db, int(business_id), dc, as_of)
        rate = res["rate"] if isinstance(res["rate"], Decimal) else Decimal(str(res["rate"]))
        if rate <= 0:
            rate = Decimal(1)
        rate_cache[doc_id] = rate
        return rate
    except ApiError:
        pass
    try:
        fallback_as_of = datetime.combine(
            document.document_date, time(23, 59, 59, 999999), tzinfo=timezone.utc
        )
        res = resolve_rate_to_base(db, int(business_id), dc, fallback_as_of)
        rate = res["rate"] if isinstance(res["rate"], Decimal) else Decimal(str(res["rate"]))
        if rate <= 0:
            rate = Decimal(1)
        rate_cache[doc_id] = rate
        return rate
    except ApiError as e:
        logger.warning(
            "person balance: no FX rate business=%s document=%s currency=%s: %s",
            business_id,
            doc_id,
            dc,
            e,
        )
        rate_cache[doc_id] = Decimal(1)
        return Decimal(1)


def _person_line_amount_to_base(
    db: Session,
    document: Document,
    amount: Any,
    *,
    rate_cache: Dict[int, Decimal],
    base_currency_by_business: Dict[int, Optional[int]],
    line: Optional["DocumentLine"] = None,
    side: Optional[str] = None,
) -> Decimal:
    """
    تبدیل مبلغ به ارز پایه.
    اگر line و side داده شود، اولویت با debit_base/credit_base ذخیره‌شده روی خط است (P2.5).
    """
    try:
        amt = Decimal(str(amount or 0))
    except Exception:
        return Decimal(0)
    if amt == 0:
        return Decimal(0)

    if line is not None and side in ("debit", "credit"):
        from app.services.document_line_fx_service import line_side_amount_to_base

        return line_side_amount_to_base(
            db,
            document,
            line,
            amt,
            side=side,
            rate_cache=rate_cache,
            base_currency_by_business=base_currency_by_business,
        )

    bid = int(document.business_id)
    if bid not in base_currency_by_business:
        bz = db.get(Business, bid)
        base_currency_by_business[bid] = (
            int(bz.default_currency_id) if bz and bz.default_currency_id else None
        )
    base_id = base_currency_by_business[bid]
    if base_id is None:
        return amt
    rate = _document_to_base_currency_rate(db, bid, int(base_id), document, rate_cache=rate_cache)
    return amt * rate


def amount_in_document_currency_to_base(
    db: Session,
    document: Document,
    amount: Any,
    *,
    rate_cache: Dict[int, Decimal],
    base_currency_by_business: Dict[int, Optional[int]],
    line: Optional["DocumentLine"] = None,
    side: Optional[str] = None,
) -> Decimal:
    """تبدیل مبلغ به ارز پایه با همان منطق خط سند (fx ذخیره‌شده یا resolve_rate؛ در نبود نرخ ۱:۱)."""
    return _person_line_amount_to_base(
        db,
        document,
        amount,
        rate_cache=rate_cache,
        base_currency_by_business=base_currency_by_business,
        line=line,
        side=side,
    )


def _filtered_person_balances_in_base(
    db: Session,
    person_ids: List[int],
    *,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from_obj: Optional[date] = None,
    date_to_obj: Optional[date] = None,
) -> Dict[int, Dict[str, Any]]:
    """تراز اشخاص با فیلتر سال مالی/ارز/بازه تاریخ؛ همه مقادیر به ارز پایه."""
    if not person_ids:
        return {}
    q = (
        db.query(DocumentLine, Document)
        .join(Document, DocumentLine.document_id == Document.id)
        .filter(
            DocumentLine.person_id.in_(person_ids),
            Document.is_proforma == False,  # noqa: E712
        )
    )
    if fiscal_year_id:
        q = q.filter(Document.fiscal_year_id == fiscal_year_id)
    if currency_id:
        q = q.filter(Document.currency_id == currency_id)
    if date_from_obj is not None:
        q = q.filter(Document.document_date >= date_from_obj)
    if date_to_obj is not None:
        q = q.filter(Document.document_date <= date_to_obj)

    rows = q.all()
    rate_cache: Dict[int, Decimal] = {}
    base_currency_by_business: Dict[int, Optional[int]] = {}
    credit_by_person: Dict[int, Decimal] = {int(pid): Decimal(0) for pid in person_ids}
    debit_by_person: Dict[int, Decimal] = {int(pid): Decimal(0) for pid in person_ids}
    last_date: Dict[int, Optional[date]] = {int(pid): None for pid in person_ids}

    for line, doc in rows:
        pid = int(line.person_id)
        if pid not in debit_by_person:
            continue
        debit_by_person[pid] += _person_line_amount_to_base(
            db,
            doc,
            line.debit,
            rate_cache=rate_cache,
            base_currency_by_business=base_currency_by_business,
            line=line,
            side="debit",
        )
        credit_by_person[pid] += _person_line_amount_to_base(
            db,
            doc,
            line.credit,
            rate_cache=rate_cache,
            base_currency_by_business=base_currency_by_business,
            line=line,
            side="credit",
        )
        dd = doc.document_date
        if dd is not None:
            cur = last_date.get(pid)
            if cur is None or dd > cur:
                last_date[pid] = dd

    out: Dict[int, Dict[str, Any]] = {}
    for pid in person_ids:
        pid = int(pid)
        tc = credit_by_person[pid]
        td = debit_by_person[pid]
        bal = tc - td
        ld = last_date.get(pid)
        out[pid] = {
            "balance": float(bal),
            "total_credit": float(tc),
            "total_debit": float(td),
            "last_transaction_date": ld.isoformat() if ld else None,
        }
    return out


def calculate_person_balances_by_currency(
    db: Session,
    person_id: int,
    fiscal_year_id: Optional[int] = None,
) -> Dict[str, Any]:
    """
    مانده شخص به تفکیک ارز سند (مبالغ بومی) + معادل ارز پایه.

    قواعد حسابداری:
    - تجمیع عادی بر اساس Document.currency_id و debit/credit بومی
    - اگر خط دارای extra_info.fx_settlement باشد (پرداخت بین‌ارزی):
      ماندهٔ ارز تسویه (settles_currency) با settles_amount جابه‌جا می‌شود
      و مبلغ خط به ارز پرداخت در ماندهٔ شخص لحاظ نمی‌شود (تا AR ارزی دوبار شمرده نشود)
    - base_equivalent از debit_base/credit_base یا تبدیل نرخ
    """
    from adapters.db.models.currency import Currency
    from app.services.fx_rate_provider_service import business_is_multi_currency

    pers = db.query(Person).filter(Person.id == person_id).first()
    if not pers:
        return {
            "person_id": person_id,
            "is_multi_currency": False,
            "base_currency_id": None,
            "balances": [],
            "total_base": 0.0,
            "status": "بدون تراکنش",
        }

    business_id = int(pers.business_id)
    biz = db.get(Business, business_id)
    base_currency_id = int(biz.default_currency_id) if biz and biz.default_currency_id else None
    is_mc = business_is_multi_currency(db, business_id)

    line_query = (
        db.query(DocumentLine, Document)
        .join(Document, DocumentLine.document_id == Document.id)
        .filter(
            DocumentLine.person_id == person_id,
            Document.is_proforma == False,  # noqa: E712
        )
    )
    if fiscal_year_id:
        line_query = line_query.filter(Document.fiscal_year_id == fiscal_year_id)
    rows = line_query.all()

    # currency_id -> {debit, credit, debit_base, credit_base}
    buckets: Dict[int, Dict[str, Decimal]] = {}

    def _bucket(cid: int) -> Dict[str, Decimal]:
        if cid not in buckets:
            buckets[cid] = {
                "debit": Decimal(0),
                "credit": Decimal(0),
                "debit_base": Decimal(0),
                "credit_base": Decimal(0),
            }
        return buckets[cid]

    rate_cache: Dict[int, Decimal] = {}
    base_currency_by_business: Dict[int, Optional[int]] = {}

    for line, doc in rows:
        extra = line.extra_info if isinstance(line.extra_info, dict) else {}
        fx_set = extra.get("fx_settlement") if isinstance(extra, dict) else None

        debit_base = _person_line_amount_to_base(
            db,
            doc,
            line.debit,
            rate_cache=rate_cache,
            base_currency_by_business=base_currency_by_business,
            line=line,
            side="debit",
        )
        credit_base = _person_line_amount_to_base(
            db,
            doc,
            line.credit,
            rate_cache=rate_cache,
            base_currency_by_business=base_currency_by_business,
            line=line,
            side="credit",
        )

        if isinstance(fx_set, dict) and fx_set.get("settles_amount") is not None and fx_set.get("settles_currency_id") is not None:
            try:
                settles_cid = int(fx_set["settles_currency_id"])
                settles_amt = Decimal(str(fx_set["settles_amount"]))
            except Exception:
                settles_cid = int(doc.currency_id)
                settles_amt = Decimal(0)
            if settles_amt < 0:
                settles_amt = Decimal(0)
            b = _bucket(settles_cid)
            # دریافت: کاهش بدهی شخص → credit ؛ پرداخت: کاهش بستانکاری → debit
            # جهت از علامت خطوط شخص سند: اگر credit>0 دریافت/تسویه بدهکار است
            if Decimal(str(line.credit or 0)) > 0:
                b["credit"] += settles_amt
                b["credit_base"] += credit_base
            elif Decimal(str(line.debit or 0)) > 0:
                b["debit"] += settles_amt
                b["debit_base"] += debit_base
            else:
                # fallback: credit
                b["credit"] += settles_amt
                b["credit_base"] += credit_base
            continue

        # تسعیر پایان دوره: فقط ارزش پایه ارز هدف؛ مانده بومی تغییر نمی‌کند
        if extra.get("fx_period_revaluation") and extra.get("account_currency_id") is not None:
            try:
                rev_cid = int(extra["account_currency_id"])
            except Exception:
                continue
            b = _bucket(rev_cid)
            b["debit_base"] += debit_base
            b["credit_base"] += credit_base
            continue

        cid = int(doc.currency_id or 0)
        if cid <= 0:
            continue
        b = _bucket(cid)
        b["debit"] += Decimal(str(line.debit or 0))
        b["credit"] += Decimal(str(line.credit or 0))
        b["debit_base"] += debit_base
        b["credit_base"] += credit_base

    if not buckets:
        return {
            "person_id": person_id,
            "is_multi_currency": is_mc,
            "base_currency_id": base_currency_id,
            "balances": [],
            "total_base": 0.0,
            "status": "بدون تراکنش",
        }

    currency_ids = list(buckets.keys())
    currencies = {
        int(c.id): c
        for c in db.query(Currency).filter(Currency.id.in_(currency_ids)).all()
    }

    balances_out: List[Dict[str, Any]] = []
    total_debit_base = Decimal(0)
    total_credit_base = Decimal(0)

    for cid, tot in sorted(buckets.items(), key=lambda x: x[0]):
        bal = tot["credit"] - tot["debit"]
        bal_base = tot["credit_base"] - tot["debit_base"]
        total_debit_base += tot["debit_base"]
        total_credit_base += tot["credit_base"]
        cur = currencies.get(cid)
        status = _person_balance_status_from_totals(tot["credit"], tot["debit"], bal)
        balances_out.append(
            {
                "currency_id": cid,
                "currency_code": getattr(cur, "code", None) if cur else None,
                "currency_title": getattr(cur, "title", None) if cur else None,
                "currency_symbol": getattr(cur, "symbol", None) if cur else None,
                "decimal_places": int(getattr(cur, "decimal_places", 2) or 2) if cur else 2,
                "total_debit": float(tot["debit"]),
                "total_credit": float(tot["credit"]),
                "balance": float(bal),
                "base_equivalent": float(bal_base),
                "status": status,
                "is_base_currency": base_currency_id is not None and cid == int(base_currency_id),
            }
        )

    total_base = total_credit_base - total_debit_base
    overall_status = _person_balance_status_from_totals(
        total_credit_base, total_debit_base, total_base
    )
    return {
        "person_id": person_id,
        "is_multi_currency": is_mc,
        "base_currency_id": base_currency_id,
        "balances": balances_out,
        "total_base": float(total_base),
        "status": overall_status,
    }


def calculate_person_balance(
    db: Session, 
    person_id: int, 
    fiscal_year_id: Optional[int] = None
) -> tuple[float, str]:
    """
    محاسبه تراز و وضعیت مالی یک شخص (به ارز پایهٔ کسب‌وکار).

    مبالغ خطوط سند که به ارز غیر پایه هستند با نرخ ذخیره‌شده در extra_info.fx
    (در صورت وجود) یا نرخ تاریخ همان سند به ارز پایه تبدیل می‌شوند.
    
    Args:
        db: نشست پایگاه داده
        person_id: شناسه شخص
        fiscal_year_id: شناسه سال مالی (اختیاری)
    
    Returns:
        tuple: (تراز, وضعیت)
        - تراز: بستانکار - بدهکار به ارز پایه
        - وضعیت: "بستانکار" | "بدهکار" | "بالانس" | "بدون تراکنش"
    """
    pers = db.query(Person).filter(Person.id == person_id).first()
    if not pers:
        return 0.0, "بدون تراکنش"

    line_query = (
        db.query(DocumentLine, Document)
        .join(Document, DocumentLine.document_id == Document.id)
        .filter(
            DocumentLine.person_id == person_id,
            Document.is_proforma == False,
        )
    )
    if fiscal_year_id:
        line_query = line_query.filter(Document.fiscal_year_id == fiscal_year_id)
    rows = line_query.all()

    if not rows:
        return 0.0, "بدون تراکنش"

    rate_cache: Dict[int, Decimal] = {}
    base_currency_by_business: Dict[int, Optional[int]] = {}
    total_credit_base = Decimal(0)
    total_debit_base = Decimal(0)
    for line, doc in rows:
        total_debit_base += _person_line_amount_to_base(
            db,
            doc,
            line.debit,
            rate_cache=rate_cache,
            base_currency_by_business=base_currency_by_business,
            line=line,
            side="debit",
        )
        total_credit_base += _person_line_amount_to_base(
            db,
            doc,
            line.credit,
            rate_cache=rate_cache,
            base_currency_by_business=base_currency_by_business,
            line=line,
            side="credit",
        )

    balance = total_credit_base - total_debit_base
    status = _person_balance_status_from_totals(total_credit_base, total_debit_base, balance)
    return float(balance), status


def calculate_persons_balances_bulk(
    db: Session, 
    person_ids: List[int], 
    fiscal_year_id: Optional[int] = None
) -> Dict[int, tuple[float, str]]:
    """
    محاسبه تراز و وضعیت چندین شخص به صورت دسته‌جمعی (به ارز پایهٔ هر کسب‌وکار).

    فرض: person_ids معمولاً همگی متعلق به یک business_id هستند (مثل لیست اشخاص یک کسب‌وکار).
    
    Args:
        db: نشست پایگاه داده
        person_ids: لیست شناسه‌های اشخاص
        fiscal_year_id: شناسه سال مالی (اختیاری)
    
    Returns:
        dict: {person_id: (balance, status)}
    """
    if not person_ids:
        return {}

    balances: Dict[int, tuple[float, str]] = {
        int(pid): (0.0, "بدون تراکنش") for pid in person_ids
    }

    q = (
        db.query(DocumentLine, Document)
        .join(Document, DocumentLine.document_id == Document.id)
        .filter(
            DocumentLine.person_id.in_(person_ids),
            Document.is_proforma == False,
        )
    )
    if fiscal_year_id:
        q = q.filter(Document.fiscal_year_id == fiscal_year_id)

    rows = q.all()
    if not rows:
        return balances

    rate_cache: Dict[int, Decimal] = {}
    base_currency_by_business: Dict[int, Optional[int]] = {}
    credit_by_person: Dict[int, Decimal] = {int(pid): Decimal(0) for pid in person_ids}
    debit_by_person: Dict[int, Decimal] = {int(pid): Decimal(0) for pid in person_ids}

    for line, doc in rows:
        pid = int(line.person_id)
        if pid not in debit_by_person:
            continue
        debit_by_person[pid] += _person_line_amount_to_base(
            db,
            doc,
            line.debit,
            rate_cache=rate_cache,
            base_currency_by_business=base_currency_by_business,
            line=line,
            side="debit",
        )
        credit_by_person[pid] += _person_line_amount_to_base(
            db,
            doc,
            line.credit,
            rate_cache=rate_cache,
            base_currency_by_business=base_currency_by_business,
            line=line,
            side="credit",
        )

    for pid in person_ids:
        pid = int(pid)
        tc = credit_by_person[pid]
        td = debit_by_person[pid]
        bal = tc - td
        status = _person_balance_status_from_totals(tc, td, bal)
        balances[pid] = (float(bal), status)

    return balances


def calculate_persons_foreign_currency_codes_bulk(
    db: Session,
    person_ids: List[int],
    business_id: int,
    fiscal_year_id: Optional[int] = None,
) -> Dict[int, List[str]]:
    """کد ارزهای غیرپایه که شخص در آن‌ها گردش دارد (کشف‌پذیری لیست؛ سبک)."""
    from adapters.db.models.currency import Currency
    from app.services.fx_rate_provider_service import business_is_multi_currency

    out: Dict[int, List[str]] = {int(pid): [] for pid in person_ids}
    if not person_ids or not business_is_multi_currency(db, int(business_id)):
        return out

    biz = db.get(Business, int(business_id))
    base_id = int(biz.default_currency_id) if biz and biz.default_currency_id else None
    if not base_id:
        return out

    q = (
        db.query(DocumentLine.person_id, Document.currency_id)
        .join(Document, DocumentLine.document_id == Document.id)
        .filter(
            DocumentLine.person_id.in_(person_ids),
            Document.is_proforma == False,  # noqa: E712
            Document.currency_id.isnot(None),
            Document.currency_id != int(base_id),
        )
        .distinct()
    )
    if fiscal_year_id:
        q = q.filter(Document.fiscal_year_id == int(fiscal_year_id))

    pairs = q.all()
    # همچنین خطوط تسعیر پایان‌دوره که ارز هدف غیرپایه دارند
    rev_q = (
        db.query(DocumentLine.person_id, DocumentLine.extra_info)
        .join(Document, DocumentLine.document_id == Document.id)
        .filter(
            DocumentLine.person_id.in_(person_ids),
            Document.is_proforma == False,  # noqa: E712
        )
    )
    if fiscal_year_id:
        rev_q = rev_q.filter(Document.fiscal_year_id == int(fiscal_year_id))

    currency_ids: set[int] = set()
    person_cur: Dict[int, set[int]] = {int(pid): set() for pid in person_ids}
    for pid, cid in pairs:
        if pid is None or cid is None:
            continue
        person_cur[int(pid)].add(int(cid))
        currency_ids.add(int(cid))

    for pid, extra in rev_q.all():
        if pid is None or not isinstance(extra, dict):
            continue
        if not extra.get("fx_period_revaluation") and not extra.get("fx_settlement"):
            continue
        cid = None
        if extra.get("fx_period_revaluation") and extra.get("account_currency_id") is not None:
            try:
                cid = int(extra["account_currency_id"])
            except Exception:
                cid = None
        fx_set = extra.get("fx_settlement")
        if cid is None and isinstance(fx_set, dict) and fx_set.get("settles_currency_id") is not None:
            try:
                cid = int(fx_set["settles_currency_id"])
            except Exception:
                cid = None
        if cid is None or cid == int(base_id):
            continue
        person_cur[int(pid)].add(cid)
        currency_ids.add(cid)

    code_map: Dict[int, str] = {}
    if currency_ids:
        for c in db.query(Currency).filter(Currency.id.in_(list(currency_ids))).all():
            code_map[int(c.id)] = str(c.code or c.id)

    for pid, cids in person_cur.items():
        out[pid] = sorted({code_map.get(cid, str(cid)) for cid in cids if cid})
    return out


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

    date_from_d: Optional[date] = None
    date_to_d: Optional[date] = None
    if date_from:
        try:
            date_from_d = datetime.strptime(date_from, "%Y-%m-%d").date()
        except ValueError:
            pass
    if date_to:
        try:
            date_to_d = datetime.strptime(date_to, "%Y-%m-%d").date()
        except ValueError:
            pass

    balances_raw = _filtered_person_balances_in_base(
        db,
        person_ids_list,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from_obj=date_from_d,
        date_to_obj=date_to_d,
    )
    balances_dict: Dict[int, Dict[str, Any]] = {
        pid: balances_raw.get(
            int(pid),
            {
                "balance": 0.0,
                "total_credit": 0.0,
                "total_debit": 0.0,
                "last_transaction_date": None,
            },
        )
        for pid in person_ids_list
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

    date_from_d: Optional[date] = None
    date_to_d: Optional[date] = None
    if date_from:
        try:
            date_from_d = datetime.strptime(date_from, "%Y-%m-%d").date()
        except ValueError:
            pass
    if date_to:
        try:
            date_to_d = datetime.strptime(date_to, "%Y-%m-%d").date()
        except ValueError:
            pass

    balances_raw = _filtered_person_balances_in_base(
        db,
        person_ids_list,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from_obj=date_from_d,
        date_to_obj=date_to_d,
    )
    balances_dict: Dict[int, Dict[str, Any]] = {
        pid: balances_raw.get(
            int(pid),
            {
                "balance": 0.0,
                "total_credit": 0.0,
                "total_debit": 0.0,
                "last_transaction_date": None,
            },
        )
        for pid in person_ids_list
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


# انواع فاکتوری که در حالت «جامع» به ریز اقلام کالا/خدمت گسترش می‌یابند
_PEOPLE_TX_INVOICE_EXPAND_TYPES = frozenset({
    "invoice_sales",
    "invoice_sales_return",
    "invoice_purchase",
    "invoice_purchase_return",
})


def _people_tx_document_type_name(doc_type: str | None) -> str:
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


def _invoice_item_line_amount(quantity: Any, extra_info: Optional[Dict[str, Any]]) -> float:
    """مبلغ ردیف اقلام فاکتور (با احتساب تخفیف و مالیات خط)."""
    info = extra_info or {}
    qty = Decimal(str(quantity or 0))
    if info.get("line_total") is not None:
        try:
            return float(Decimal(str(info.get("line_total") or 0)))
        except Exception:
            pass
    unit_price = Decimal(str(info.get("unit_price", 0) or 0))
    line_discount = Decimal(str(info.get("line_discount", 0) or 0))
    tax_amount = Decimal(str(info.get("tax_amount", 0) or 0))
    return float((qty * unit_price) - line_discount + tax_amount)


def _normalize_people_tx_detail_level(detail_level: Optional[str]) -> str:
    value = (detail_level or "summary").strip().lower()
    if value in ("comprehensive", "detailed", "items", "invoice_lines"):
        return "comprehensive"
    return "summary"


def _expand_people_tx_with_invoice_items(
    db: Session,
    business_id: int,
    base_items: List[Dict[str, Any]],
    *,
    amounts_in_base: bool,
) -> List[Dict[str, Any]]:
    """
    گسترش ردیف‌های فاکتور خرید/فروش به ریز اقلام کالا.
    دریافت/پرداخت و سایر اسناد بدون تغییر می‌مانند.
    هر فاکتور فقط یک‌بار (روی خط اصلی شخص، نه سود اقساط) گسترش می‌یابد تا مبلغ تراز حفظ شود.
    """
    from collections import defaultdict

    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from adapters.db.models.product import Product

    invoice_doc_ids = sorted({
        int(item["document_id"])
        for item in base_items
        if item.get("document_type") in _PEOPLE_TX_INVOICE_EXPAND_TYPES
        and item.get("document_id") is not None
    })
    if not invoice_doc_ids:
        return base_items

    inv_lines = (
        db.query(InvoiceItemLine)
        .filter(InvoiceItemLine.document_id.in_(invoice_doc_ids))
        .order_by(InvoiceItemLine.document_id.asc(), InvoiceItemLine.id.asc())
        .all()
    )
    lines_by_doc: Dict[int, List[Any]] = defaultdict(list)
    product_ids: set[int] = set()
    for inv_line in inv_lines:
        lines_by_doc[int(inv_line.document_id)].append(inv_line)
        if inv_line.product_id is not None:
            product_ids.add(int(inv_line.product_id))

    products_by_id: Dict[int, Any] = {}
    if product_ids:
        for product in (
            db.query(Product)
            .filter(
                Product.business_id == business_id,
                Product.id.in_(list(product_ids)),
            )
            .all()
        ):
            products_by_id[int(product.id)] = product

    expanded: List[Dict[str, Any]] = []
    expanded_docs: set[int] = set()

    for item in base_items:
        doc_id = item.get("document_id")
        doc_type = item.get("document_type")
        line_extra = item.get("line_extra_info") or {}
        is_installment_person_line = bool(
            isinstance(line_extra, dict) and line_extra.get("installment")
        )

        can_expand = (
            doc_type in _PEOPLE_TX_INVOICE_EXPAND_TYPES
            and doc_id is not None
            and int(doc_id) not in expanded_docs
            and not is_installment_person_line
            and int(doc_id) in lines_by_doc
            and len(lines_by_doc[int(doc_id)]) > 0
        )
        if not can_expand:
            row = dict(item)
            row.setdefault("row_kind", "document")
            expanded.append(row)
            continue

        doc_id_int = int(doc_id)
        expanded_docs.add(doc_id_int)
        person_debit_native = float(item.get("debit_native") or 0)
        person_credit_native = float(item.get("credit_native") or 0)
        person_debit_base = float(item.get("debit_base") or 0)
        person_credit_base = float(item.get("credit_base") or 0)
        use_debit_side = person_debit_native >= person_credit_native
        person_native_amount = (
            person_debit_native if use_debit_side else person_credit_native
        )
        person_base_amount = (
            person_debit_base if use_debit_side else person_credit_base
        )

        item_amounts: List[float] = []
        for inv_line in lines_by_doc[doc_id_int]:
            item_amounts.append(
                _invoice_item_line_amount(inv_line.quantity, inv_line.extra_info)
            )
        items_sum = float(sum(Decimal(str(a)) for a in item_amounts))

        for inv_line, amount in zip(lines_by_doc[doc_id_int], item_amounts):
            info = inv_line.extra_info or {}
            product = products_by_id.get(int(inv_line.product_id)) if inv_line.product_id else None
            product_name = product.name if product is not None else None
            product_code = product.code if product is not None else None
            qty = float(inv_line.quantity or 0) if inv_line.quantity is not None else None
            unit_price = None
            try:
                if info.get("unit_price") is not None:
                    unit_price = float(Decimal(str(info.get("unit_price") or 0)))
            except Exception:
                unit_price = None
            line_discount = None
            try:
                if info.get("line_discount") is not None:
                    line_discount = float(Decimal(str(info.get("line_discount") or 0)))
            except Exception:
                line_discount = None
            tax_amount = None
            try:
                if info.get("tax_amount") is not None:
                    tax_amount = float(Decimal(str(info.get("tax_amount") or 0)))
            except Exception:
                tax_amount = None

            desc_parts = []
            if product_name:
                desc_parts.append(product_name)
            if inv_line.description:
                desc_parts.append(str(inv_line.description))
            description = " — ".join(desc_parts) if desc_parts else (item.get("description") or "")

            # Invoice item amounts are native amounts. Allocate their base
            # counterpart from the already persisted base person-line amount so
            # the expanded rows retain the report's aggregate balance exactly.
            base_amount = (
                float(amount) * person_base_amount / items_sum
                if items_sum else 0.0
            )
            debit_native = float(amount) if use_debit_side else 0.0
            credit_native = 0.0 if use_debit_side else float(amount)
            debit_base = base_amount if use_debit_side else 0.0
            credit_base = 0.0 if use_debit_side else base_amount
            row = dict(item)
            row.update({
                "row_kind": "invoice_item",
                "line_id": item.get("line_id"),
                "parent_line_id": item.get("line_id"),
                "invoice_item_line_id": inv_line.id,
                "product_id": int(inv_line.product_id) if inv_line.product_id is not None else None,
                "product_code": product_code,
                "product_name": product_name,
                "quantity": qty,
                "unit_price": unit_price,
                "line_discount": line_discount,
                "tax_amount": tax_amount,
                "line_amount": base_amount if amounts_in_base else float(amount),
                "debit_native": debit_native,
                "credit_native": credit_native,
                "debit_base": debit_base,
                "credit_base": credit_base,
                "debit": debit_base if amounts_in_base else debit_native,
                "credit": credit_base if amounts_in_base else credit_native,
                "description": description,
            })
            expanded.append(row)

        native_remainder = float(
            Decimal(str(person_native_amount)) - Decimal(str(items_sum))
        )
        base_items_sum = sum(
            float(amount) * person_base_amount / items_sum if items_sum else 0.0
            for amount in item_amounts
        )
        base_remainder = person_base_amount - base_items_sum
        if abs(native_remainder) >= 0.01 or abs(base_remainder) >= 0.01:
            if use_debit_side:
                debit_native = native_remainder if native_remainder > 0 else 0.0
                credit_native = -native_remainder if native_remainder < 0 else 0.0
                debit_base = base_remainder if base_remainder > 0 else 0.0
                credit_base = -base_remainder if base_remainder < 0 else 0.0
            else:
                credit_native = native_remainder if native_remainder > 0 else 0.0
                debit_native = -native_remainder if native_remainder < 0 else 0.0
                credit_base = base_remainder if base_remainder > 0 else 0.0
                debit_base = -base_remainder if base_remainder < 0 else 0.0
            row = dict(item)
            row.update({
                "row_kind": "invoice_remainder",
                "line_id": item.get("line_id"),
                "parent_line_id": item.get("line_id"),
                "invoice_item_line_id": None,
                "product_id": None,
                "product_code": None,
                "product_name": None,
                "quantity": None,
                "unit_price": None,
                "line_discount": None,
                "tax_amount": None,
                "line_amount": base_remainder if amounts_in_base else native_remainder,
                "debit_native": debit_native,
                "credit_native": credit_native,
                "debit_base": debit_base,
                "credit_base": credit_base,
                "debit": debit_base if amounts_in_base else debit_native,
                "credit": credit_base if amounts_in_base else credit_native,
                "description": "سایر / مالیات و تعدیلات فاکتور",
            })
            expanded.append(row)

    return expanded


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
    detail_level: Optional[str] = "summary",
) -> Dict[str, Any]:
    """
    گزارش تراکنش‌های اشخاص / معین طرف‌حساب

    detail_level:
      - summary: یک ردیف به‌ازای هر خط حسابداری شخص (مبلغ کل فاکتور)
      - comprehensive: ریز اقلام خرید/فروش + دریافت/پرداخت در یک گردش واحد
    """
    from datetime import datetime

    detail_level_norm = _normalize_people_tx_detail_level(detail_level)
    amounts_in_base = currency_id is None

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

    all_results = query.all()

    if not all_results:
        return {
            'items': [],
            'summary': {
                'total_count': 0,
                'total_debit': 0.0,
                'total_credit': 0.0,
                'detail_level': detail_level_norm,
            },
            'pagination': {
                'total': 0,
                'page': 1,
                'per_page': take,
                'total_pages': 0,
                'has_next': False,
                'has_prev': False,
            },
            'meta': {
                'currency_id': currency_id,
                'amounts_in_base': amounts_in_base,
            },
        }

    base_items: List[Dict[str, Any]] = []
    for line, doc, person in all_results:
        debit_native = float(line.debit or 0)
        credit_native = float(line.credit or 0)
        debit_base = float(
            line.debit_base if line.debit_base is not None else line.debit or 0
        )
        credit_base = float(
            line.credit_base if line.credit_base is not None else line.credit or 0
        )
        debit = debit_base if amounts_in_base else debit_native
        credit = credit_base if amounts_in_base else credit_native

        person_name = None
        if person:
            person_name = (
                person.alias_name or
                person.company_name or
                f"{person.first_name or ''} {person.last_name or ''}".strip()
            )

        document_type_name = _people_tx_document_type_name(doc.document_type)

        item_dict = _person_to_dict(person) if person else {}
        item_dict.update({
            'row_kind': 'document',
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
            'debit_native': debit_native,
            'credit_native': credit_native,
            'debit_base': debit_base,
            'credit_base': credit_base,
            'exchange_rate': (
                float(line.exchange_rate) if line.exchange_rate is not None else None
            ),
            'document_currency_id': doc.currency_id,
            'description': line.description,
            'line_extra_info': line.extra_info or {},
            'product_id': None,
            'product_code': None,
            'product_name': None,
            'quantity': None,
            'unit_price': None,
            'line_discount': None,
            'tax_amount': None,
            'line_amount': None,
            'invoice_item_line_id': None,
            'parent_line_id': None,
        })
        base_items.append(item_dict)

    if detail_level_norm == "comprehensive":
        items = _expand_people_tx_with_invoice_items(
            db, business_id, base_items, amounts_in_base=amounts_in_base
        )
    else:
        items = base_items

    running_balance = 0.0
    for item in items:
        debit = float(item.get('debit') or 0)
        credit = float(item.get('credit') or 0)
        balance_change = credit - debit
        running_balance += balance_change
        item['balance_change'] = balance_change
        item['running_balance'] = running_balance
        # فیلد داخلی؛ برای کلاینت لازم نیست
        item.pop('line_extra_info', None)

    total_count = len(items)
    total_debit = sum(float(item.get('debit') or 0) for item in items)
    total_credit = sum(float(item.get('credit') or 0) for item in items)

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
            'detail_level': detail_level_norm,
        },
        'pagination': {
            'total': total,
            'page': current_page,
            'per_page': take,
            'total_pages': total_pages,
            'has_next': current_page < total_pages,
            'has_prev': current_page > 1,
        },
        'meta': {
            'currency_id': currency_id,
            'amounts_in_base': amounts_in_base,
        },
    }
