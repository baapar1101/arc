from typing import List, Optional, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func
from adapters.db.models.person import Person, PersonBankAccount, PersonType
from adapters.api.v1.schema_models.person import (
    PersonCreateRequest, PersonUpdateRequest, PersonBankAccountCreateRequest
)
from app.core.responses import success_response


def create_person(db: Session, business_id: int, person_data: PersonCreateRequest) -> Dict[str, Any]:
    """ایجاد شخص جدید"""
    # ایجاد شخص
    person = Person(
        business_id=business_id,
        alias_name=person_data.alias_name,
        first_name=person_data.first_name,
        last_name=person_data.last_name,
        person_type=person_data.person_type,
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
    
    db.commit()
    db.refresh(person)
    
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
    query_info: Dict[str, Any]
) -> Dict[str, Any]:
    """دریافت لیست اشخاص با جستجو و فیلتر"""
    query = db.query(Person).filter(Person.business_id == business_id)
    
    # اعمال جستجو
    if query_info.get('search') and query_info.get('search_fields'):
        search_term = f"%{query_info['search']}%"
        search_conditions = []
        
        for field in query_info['search_fields']:
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
            field = filter_item.get('property')
            operator = filter_item.get('operator')
            value = filter_item.get('value')
            
            if field == 'person_type':
                if operator == '=':
                    query = query.filter(Person.person_type == value)
                elif operator == 'in':
                    query = query.filter(Person.person_type.in_(value))
            elif field == 'is_active':
                if operator == '=':
                    query = query.filter(Person.is_active == value)
            elif field == 'country':
                if operator == '=':
                    query = query.filter(Person.country == value)
                elif operator == 'like':
                    query = query.filter(Person.country.ilike(f"%{value}%"))
            elif field == 'province':
                if operator == '=':
                    query = query.filter(Person.province == value)
                elif operator == 'like':
                    query = query.filter(Person.province.ilike(f"%{value}%"))
    
    # شمارش کل رکوردها
    total = query.count()
    
    # اعمال مرتب‌سازی
    sort_by = query_info.get('sort_by', 'created_at')
    sort_desc = query_info.get('sort_desc', True)
    
    if sort_by == 'alias_name':
        query = query.order_by(Person.alias_name.desc() if sort_desc else Person.alias_name.asc())
    elif sort_by == 'first_name':
        query = query.order_by(Person.first_name.desc() if sort_desc else Person.first_name.asc())
    elif sort_by == 'last_name':
        query = query.order_by(Person.last_name.desc() if sort_desc else Person.last_name.asc())
    elif sort_by == 'person_type':
        query = query.order_by(Person.person_type.desc() if sort_desc else Person.person_type.asc())
    elif sort_by == 'created_at':
        query = query.order_by(Person.created_at.desc() if sort_desc else Person.created_at.asc())
    elif sort_by == 'updated_at':
        query = query.order_by(Person.updated_at.desc() if sort_desc else Person.updated_at.asc())
    else:
        query = query.order_by(Person.created_at.desc())
    
    # اعمال صفحه‌بندی
    skip = query_info.get('skip', 0)
    take = query_info.get('take', 20)
    
    persons = query.offset(skip).limit(take).all()
    
    # تبدیل به دیکشنری
    items = [_person_to_dict(person) for person in persons]
    
    # محاسبه اطلاعات صفحه‌بندی
    total_pages = (total + take - 1) // take
    current_page = (skip // take) + 1
    
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
    for field, value in update_data.items():
        setattr(person, field, value)
    
    db.commit()
    db.refresh(person)
    
    return success_response(
        message="شخص با موفقیت ویرایش شد",
        data=_person_to_dict(person)
    )


def delete_person(db: Session, person_id: int, business_id: int) -> bool:
    """حذف شخص"""
    person = db.query(Person).filter(
        and_(Person.id == person_id, Person.business_id == business_id)
    ).first()
    
    if not person:
        return False
    
    db.delete(person)
    db.commit()
    
    return True


def get_person_summary(db: Session, business_id: int) -> Dict[str, Any]:
    """دریافت خلاصه اشخاص"""
    # تعداد کل اشخاص
    total_persons = db.query(Person).filter(Person.business_id == business_id).count()
    
    # تعداد اشخاص فعال و غیرفعال
    active_persons = db.query(Person).filter(
        and_(Person.business_id == business_id, Person.is_active == True)
    ).count()
    
    inactive_persons = total_persons - active_persons
    
    # تعداد بر اساس نوع
    by_type = {}
    for person_type in PersonType:
        count = db.query(Person).filter(
            and_(Person.business_id == business_id, Person.person_type == person_type)
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
    return {
        'id': person.id,
        'business_id': person.business_id,
        'alias_name': person.alias_name,
        'first_name': person.first_name,
        'last_name': person.last_name,
        'person_type': person.person_type.value,
        'company_name': person.company_name,
        'payment_id': person.payment_id,
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
        'is_active': person.is_active,
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
                'is_active': ba.is_active,
                'created_at': ba.created_at.isoformat(),
                'updated_at': ba.updated_at.isoformat(),
            }
            for ba in person.bank_accounts
        ]
    }
