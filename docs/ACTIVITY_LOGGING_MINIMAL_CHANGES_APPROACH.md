# راهکار لاگ‌گیری با حداقل تغییرات در Endpoint ها

## 🎯 هدف

پیاده‌سازی سیستم لاگ‌گیری با **حداقل تغییرات** در endpoint های موجود با استفاده از:
1. **SQLAlchemy Events** - برای لاگ‌گیری خودکار عملیات CRUD
2. **Decorator** - برای لاگ‌گیری عملیات خاص
3. **Context Manager** - برای ذخیره اطلاعات کاربر در session

---

## 🔧 راهکار 1: SQLAlchemy Events (بهترین راهکار)

### مزایا
- ✅ **بدون تغییر endpoint ها** - لاگ‌گیری کاملاً خودکار
- ✅ **پوشش کامل** - تمام عملیات create, update, delete را پوشش می‌دهد
- ✅ **عملکرد خوب** - در سطح ORM اجرا می‌شود
- ✅ **قابل اعتماد** - حتی اگر از repository یا service استفاده نشود، کار می‌کند

### پیاده‌سازی

**فایل:** `hesabixAPI/adapters/db/session.py` (یا فایل جدید `activity_log_hooks.py`)

```python
from sqlalchemy import event
from sqlalchemy.orm import Session
from datetime import datetime
from typing import Dict, Any, Optional
from adapters.db.models.activity_log import ActivityLog
from adapters.db.models import (
    Document, WarehouseDocument, Product, Person, 
    Business, Account, User, FiscalYear
)

# Context برای ذخیره اطلاعات کاربر جاری در session
class ActivityLogContext:
    """Context برای ذخیره اطلاعات کاربر و request در session"""
    _contexts: Dict[int, Dict[str, Any]] = {}  # session_id -> context
    
    @classmethod
    def set_context(cls, session: Session, user_id: int, business_id: Optional[int] = None, request: Optional[Any] = None):
        """تنظیم context برای session"""
        session_id = id(session)
        cls._contexts[session_id] = {
            "user_id": user_id,
            "business_id": business_id,
            "request": request,
            "session": session
        }
    
    @classmethod
    def get_context(cls, session: Session) -> Optional[Dict[str, Any]]:
        """دریافت context از session"""
        session_id = id(session)
        return cls._contexts.get(session_id)
    
    @classmethod
    def clear_context(cls, session: Session):
        """پاک کردن context بعد از commit"""
        session_id = id(session)
        cls._contexts.pop(session_id, None)


# Mapping مدل‌ها به category و entity_type
MODEL_CATEGORY_MAP = {
    Document: ("accounting", "document"),
    WarehouseDocument: ("warehouse", "warehouse_document"),
    Product: ("product", "product"),
    Person: ("person", "person"),
    Business: ("business", "business"),
    Account: ("accounting", "account"),
    User: ("user", "user"),
    FiscalYear: ("accounting", "fiscal_year"),
}

# Helper function برای استخراج business_id از instance
def get_business_id(instance) -> Optional[int]:
    """استخراج business_id از instance"""
    if hasattr(instance, 'business_id'):
        return getattr(instance, 'business_id')
    # برای User که business_id ندارد
    return None

# Helper function برای ساخت description
def build_description(instance, action: str) -> str:
    """ساخت description قابل خواندن"""
    model_name = instance.__class__.__name__
    
    # استخراج نام یا کد برای نمایش
    name = None
    if hasattr(instance, 'name'):
        name = getattr(instance, 'name')
    elif hasattr(instance, 'code'):
        name = getattr(instance, 'code')
    elif hasattr(instance, 'first_name') and hasattr(instance, 'last_name'):
        name = f"{getattr(instance, 'first_name', '')} {getattr(instance, 'last_name', '')}".strip()
    elif hasattr(instance, 'email'):
        name = getattr(instance, 'email')
    
    name_str = f" '{name}'" if name else ""
    
    action_map = {
        "create": "ایجاد شد",
        "update": "ویرایش شد",
        "delete": "حذف شد"
    }
    action_persian = action_map.get(action, action)
    
    # نام فارسی برای مدل‌ها
    model_name_map = {
        "Document": "سند",
        "WarehouseDocument": "حواله انبار",
        "Product": "محصول",
        "Person": "شخص",
        "Business": "کسب و کار",
        "Account": "حساب",
        "User": "کاربر",
        "FiscalYear": "سال مالی"
    }
    model_persian = model_name_map.get(model_name, model_name)
    
    return f"{model_persian}{name_str} {action_persian}"

# Helper function برای استخراج داده‌های مهم
def extract_key_fields(instance) -> Dict[str, Any]:
    """استخراج فیلدهای مهم برای لاگ"""
    key_fields = {}
    
    # فیلدهای مشترک
    if hasattr(instance, 'id'):
        key_fields['id'] = getattr(instance, 'id')
    if hasattr(instance, 'code'):
        key_fields['code'] = getattr(instance, 'code')
    if hasattr(instance, 'name'):
        key_fields['name'] = getattr(instance, 'name')
    
    # فیلدهای خاص برای Document
    if isinstance(instance, Document):
        if hasattr(instance, 'document_type'):
            key_fields['document_type'] = getattr(instance, 'document_type')
        if hasattr(instance, 'document_date'):
            key_fields['document_date'] = str(getattr(instance, 'document_date'))
    
    # فیلدهای خاص برای Product
    if isinstance(instance, Product):
        if hasattr(instance, 'base_sales_price'):
            key_fields['base_sales_price'] = float(getattr(instance, 'base_sales_price') or 0)
    
    # فیلدهای خاص برای Person
    if isinstance(instance, Person):
        if hasattr(instance, 'first_name'):
            key_fields['first_name'] = getattr(instance, 'first_name')
        if hasattr(instance, 'last_name'):
            key_fields['last_name'] = getattr(instance, 'last_name')
    
    return key_fields


# Event Handlers

@event.listens_for(Session, "after_flush")
def receive_after_flush(session: Session, flush_context):
    """لاگ‌گیری بعد از flush (قبل از commit)"""
    context = ActivityLogContext.get_context(session)
    if not context:
        return  # اگر context تنظیم نشده، لاگ نگیر
    
    user_id = context.get("user_id")
    business_id = context.get("business_id")
    request = context.get("request")
    
    if not user_id:
        return
    
    # پردازش instances جدید (insert)
    for instance in session.new:
        if instance.__class__ not in MODEL_CATEGORY_MAP:
            continue
        
        category, entity_type = MODEL_CATEGORY_MAP[instance.__class__]
        instance_business_id = get_business_id(instance) or business_id
        
        # برای User، business_id نداریم
        if isinstance(instance, User):
            instance_business_id = None
        
        description = build_description(instance, "create")
        after_data = extract_key_fields(instance)
        
        # استخراج extra_info از request
        extra_info = {}
        if request:
            if hasattr(request, 'client') and request.client:
                extra_info['ip_address'] = request.client.host
            if hasattr(request, 'headers'):
                user_agent = request.headers.get("User-Agent")
                if user_agent:
                    extra_info['user_agent'] = user_agent
        
        log = ActivityLog(
            user_id=user_id,
            business_id=instance_business_id,
            category=category,
            action="create",
            entity_type=entity_type,
            entity_id=getattr(instance, 'id', None),
            description=description,
            after_data=after_data,
            extra_info=extra_info if extra_info else None,
            created_at=datetime.utcnow()
        )
        session.add(log)
    
    # پردازش instances تغییر یافته (update)
    for instance in session.dirty:
        if instance.__class__ not in MODEL_CATEGORY_MAP:
            continue
        
        category, entity_type = MODEL_CATEGORY_MAP[instance.__class__]
        instance_business_id = get_business_id(instance) or business_id
        
        if isinstance(instance, User):
            instance_business_id = None
        
        # استخراج تغییرات
        before_data = {}
        after_data = {}
        
        # SQLAlchemy history برای تغییرات
        from sqlalchemy.orm.attributes import get_history
        
        for attr_name in instance.__table__.columns.keys():
            if attr_name in ['id', 'created_at', 'updated_at']:
                continue
            
            history = get_history(instance, attr_name)
            if history.has_changes():
                # مقدار قبلی
                if history.deleted:
                    before_data[attr_name] = history.deleted[0]
                # مقدار جدید
                if history.added:
                    after_data[attr_name] = history.added[0]
        
        # فقط اگر تغییری وجود داشت
        if before_data or after_data:
            description = build_description(instance, "update")
            
            extra_info = {}
            if request:
                if hasattr(request, 'client') and request.client:
                    extra_info['ip_address'] = request.client.host
                if hasattr(request, 'headers'):
                    user_agent = request.headers.get("User-Agent")
                    if user_agent:
                        extra_info['user_agent'] = user_agent
            
            log = ActivityLog(
                user_id=user_id,
                business_id=instance_business_id,
                category=category,
                action="update",
                entity_type=entity_type,
                entity_id=getattr(instance, 'id', None),
                description=description,
                before_data=before_data if before_data else None,
                after_data=after_data if after_data else None,
                extra_info=extra_info if extra_info else None,
                created_at=datetime.utcnow()
            )
            session.add(log)
    
    # پردازش instances حذف شده (delete)
    for instance in session.deleted:
        if instance.__class__ not in MODEL_CATEGORY_MAP:
            continue
        
        category, entity_type = MODEL_CATEGORY_MAP[instance.__class__]
        instance_business_id = get_business_id(instance) or business_id
        
        if isinstance(instance, User):
            instance_business_id = None
        
        description = build_description(instance, "delete")
        before_data = extract_key_fields(instance)
        
        extra_info = {}
        if request:
            if hasattr(request, 'client') and request.client:
                extra_info['ip_address'] = request.client.host
            if hasattr(request, 'headers'):
                user_agent = request.headers.get("User-Agent")
                if user_agent:
                    extra_info['user_agent'] = user_agent
        
        log = ActivityLog(
            user_id=user_id,
            business_id=instance_business_id,
            category=category,
            action="delete",
            entity_type=entity_type,
            entity_id=getattr(instance, 'id', None),
            description=description,
            before_data=before_data,
            extra_info=extra_info if extra_info else None,
            created_at=datetime.utcnow()
        )
        session.add(log)


@event.listens_for(Session, "after_commit")
def receive_after_commit(session: Session):
    """پاک کردن context بعد از commit"""
    ActivityLogContext.clear_context(session)


@event.listens_for(Session, "after_rollback")
def receive_after_rollback(session: Session):
    """پاک کردن context بعد از rollback"""
    ActivityLogContext.clear_context(session)
```

### استفاده در Dependency

**فایل:** `hesabixAPI/app/core/auth_dependency.py` (تغییر کوچک)

```python
from adapters.db.activity_log_hooks import ActivityLogContext

def get_current_user(
    request: Request,
    db: Session = Depends(get_db)
) -> AuthContext:
    # ... کد موجود ...
    
    auth_context = AuthContext(
        user=user, 
        api_key_id=obj.id,
        language=language,
        calendar_type=calendar_type,
        timezone=timezone,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        db=db
    )
    
    # تنظیم context برای لاگ‌گیری خودکار
    ActivityLogContext.set_context(
        session=db,
        user_id=user.id,
        business_id=business_id,
        request=request
    )
    
    return auth_context
```

**نتیجه:** با این تغییر کوچک، تمام عملیات CRUD به صورت خودکار لاگ می‌شوند! 🎉

---

## 🔧 راهکار 2: Decorator برای عملیات خاص

برای عملیات‌هایی که در SQLAlchemy Events نمی‌گنجند (مثل post, cancel, approve):

**فایل:** `hesabixAPI/app/core/activity_log_decorator.py`

```python
from functools import wraps
from typing import Callable, Any, Optional
from fastapi import Request
from sqlalchemy.orm import Session
from app.services.activity_log_service import log_activity
from app.core.auth_dependency import get_current_user

def log_activity_decorator(
    category: str,
    action: str,
    entity_type: Optional[str] = None,
    description_template: Optional[str] = None,
    get_entity_id: Optional[Callable] = None,
    get_business_id: Optional[Callable] = None
):
    """
    Decorator برای لاگ‌گیری خودکار endpoint ها
    
    استفاده:
        @log_activity_decorator(
            category="warehouse",
            action="post",
            entity_type="warehouse_document",
            description_template="حواله انبار {code} پست شد",
            get_entity_id=lambda result: result.get("id"),
            get_business_id=lambda kwargs: kwargs.get("business_id")
        )
        def post_warehouse_document(...):
            ...
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # استخراج request و db از kwargs
            request: Optional[Request] = kwargs.get('request')
            db: Optional[Session] = kwargs.get('db')
            ctx = kwargs.get('ctx')
            
            if not db or not ctx:
                # اگر ctx یا db نبود، تابع را بدون لاگ اجرا کن
                result = func(*args, **kwargs)
                if hasattr(result, '__await__'):
                    result = await result
                return result
            
            # اجرای تابع اصلی
            result = func(*args, **kwargs)
            if hasattr(result, '__await__'):
                result = await result
            
            # استخراج اطلاعات برای لاگ
            entity_id = None
            if get_entity_id:
                try:
                    entity_id = get_entity_id(result, *args, **kwargs)
                except:
                    pass
            
            business_id = None
            if get_business_id:
                try:
                    business_id = get_business_id(*args, **kwargs)
                except:
                    pass
            elif ctx and hasattr(ctx, 'business_id'):
                business_id = ctx.business_id
            
            # ساخت description
            description = description_template or f"{action} performed"
            if description_template and entity_id:
                # اگر template داشتیم و entity_id را پیدا کردیم، می‌توانیم اطلاعات بیشتری بگیریم
                try:
                    # می‌توانیم entity را از db بخوانیم و description را کامل کنیم
                    pass
                except:
                    pass
            
            # لاگ‌گیری
            try:
                log_activity(
                    db=db,
                    user_id=ctx.get_user_id() if hasattr(ctx, 'get_user_id') else ctx.user.id,
                    category=category,
                    action=action,
                    description=description,
                    business_id=business_id,
                    entity_type=entity_type,
                    entity_id=entity_id,
                    request=request
                )
            except Exception as e:
                # لاگ خطا را بگیر اما endpoint را fail نکن
                import logging
                logger = logging.getLogger(__name__)
                logger.error(f"Failed to log activity: {e}")
            
            return result
        return wrapper
    return decorator
```

**استفاده:**

```python
@router.post("/business/{business_id}/warehouse-docs/{wh_id}/post")
@log_activity_decorator(
    category="warehouse",
    action="post",
    entity_type="warehouse_document",
    description_template="حواله انبار پست شد",
    get_entity_id=lambda result, **kwargs: kwargs.get("wh_id"),
    get_business_id=lambda **kwargs: kwargs.get("business_id")
)
def post_warehouse_document(
    request: Request,
    business_id: int,
    wh_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # کد موجود بدون تغییر
    ...
```

---

## 🔧 راهکار 3: Context Manager برای عملیات پیچیده

برای عملیات‌هایی که چندین تغییر در یک transaction انجام می‌دهند:

**فایل:** `hesabixAPI/app/core/activity_log_context.py`

```python
from contextlib import contextmanager
from typing import Optional
from sqlalchemy.orm import Session
from app.services.activity_log_service import log_activity
from fastapi import Request

@contextmanager
def activity_log_context(
    db: Session,
    user_id: int,
    category: str,
    action: str,
    business_id: Optional[int] = None,
    entity_type: Optional[str] = None,
    entity_id: Optional[int] = None,
    description: Optional[str] = None,
    request: Optional[Request] = None
):
    """
    Context manager برای لاگ‌گیری عملیات پیچیده
    
    استفاده:
        with activity_log_context(
            db=db,
            user_id=user_id,
            category="accounting",
            action="post",
            business_id=business_id,
            entity_type="invoice",
            entity_id=invoice_id,
            description="فاکتور پست شد"
        ):
            # عملیات پیچیده
            ...
    """
    try:
        yield
        # اگر exception نیفتاد، لاگ را ثبت کن
        log_activity(
            db=db,
            user_id=user_id,
            category=category,
            action=action,
            description=description or f"{action} performed",
            business_id=business_id,
            entity_type=entity_type,
            entity_id=entity_id,
            request=request
        )
    except Exception as e:
        # لاگ خطا
        log_activity(
            db=db,
            user_id=user_id,
            category=category,
            action=f"{action}_failed",
            description=f"{description or action} با خطا مواجه شد: {str(e)}",
            business_id=business_id,
            entity_type=entity_type,
            entity_id=entity_id,
            request=request,
            extra_info={"error": str(e)}
        )
        raise
```

---

## 📊 مقایسه راهکارها

| راهکار | پوشش | تغییرات لازم | پیچیدگی | مناسب برای |
|--------|------|--------------|----------|------------|
| **SQLAlchemy Events** | ✅ کامل (CRUD) | ✅ حداقل (فقط dependency) | ⭐⭐ | عملیات CRUD ساده |
| **Decorator** | ⚠️ انتخابی | ⭐⭐ متوسط | ⭐⭐⭐ | عملیات خاص (post, cancel) |
| **Context Manager** | ⚠️ دستی | ⭐⭐⭐ زیاد | ⭐⭐ | عملیات پیچیده چند مرحله‌ای |
| **فراخوانی مستقیم** | ⚠️ دستی | ⭐⭐⭐⭐ زیاد | ⭐ | فعالیت‌های خاص (password change) |

---

## 🎯 راهکار پیشنهادی: ترکیبی

### 1. **SQLAlchemy Events** برای 80% عملیات
- ✅ تمام create, update, delete به صورت خودکار
- ✅ فقط یک تغییر کوچک در `get_current_user`

### 2. **Decorator** برای عملیات خاص
- ✅ post, cancel, approve, reject
- ✅ فقط decorator اضافه می‌شود، کد endpoint تغییر نمی‌کند

### 3. **فراخوانی مستقیم** برای موارد خاص
- ✅ تغییر رمز عبور
- ✅ عملیات‌های پیچیده که نیاز به لاگ خاص دارند

---

## 📝 مثال پیاده‌سازی کامل

### مرحله 1: ایجاد فایل Events (یک بار)

```python
# hesabixAPI/adapters/db/activity_log_hooks.py
# (کد کامل در بالا)
```

### مرحله 2: تغییر Dependency (یک خط)

```python
# hesabixAPI/app/core/auth_dependency.py
# در get_current_user، بعد از ساخت AuthContext:
ActivityLogContext.set_context(
    session=db,
    user_id=user.id,
    business_id=business_id,
    request=request
)
```

### مرحله 3: Import Events (یک خط)

```python
# hesabixAPI/adapters/db/__init__.py یا app/main.py
import adapters.db.activity_log_hooks  # برای ثبت event handlers
```

**نتیجه:** تمام عملیات CRUD به صورت خودکار لاگ می‌شوند! 🎉

---

## ✅ مزایای این راهکار

1. **حداقل تغییرات**: فقط 2-3 خط تغییر در dependency
2. **پوشش کامل**: تمام عملیات CRUD خودکار
3. **قابل اعتماد**: حتی اگر developer فراموش کند، لاگ می‌شود
4. **عملکرد خوب**: در سطح ORM، بدون overhead اضافی
5. **قابل توسعه**: می‌توان مدل‌های جدید را به راحتی اضافه کرد

---

## ⚠️ نکات مهم

1. **Context باید تنظیم شود**: اگر `get_current_user` فراخوانی نشود، لاگ نمی‌شود
2. **مدل‌های جدید**: باید به `MODEL_CATEGORY_MAP` اضافه شوند
3. **تست**: باید تست شود که context درست تنظیم می‌شود
4. **Performance**: Events در flush اجرا می‌شوند، overhead کمی دارد اما قابل قبول است

---

## 🚀 مراحل پیاده‌سازی

1. ✅ ایجاد مدل `ActivityLog` و migration
2. ✅ ایجاد `activity_log_hooks.py` با SQLAlchemy Events
3. ✅ تغییر `get_current_user` برای تنظیم context
4. ✅ Import hooks در `app/main.py`
5. ✅ تست با یک عملیات ساده (مثلاً ایجاد محصول)
6. ✅ اضافه کردن decorator برای عملیات خاص (اختیاری)
7. ✅ اضافه کردن فراخوانی مستقیم برای موارد خاص (اختیاری)

**تغییرات لازم: فقط 2-3 فایل!** 🎉

