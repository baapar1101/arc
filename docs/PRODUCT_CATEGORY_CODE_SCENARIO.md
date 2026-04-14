# سناریو پیاده‌سازی: تولید خودکار کد کالا بر اساس دسته‌بندی

## 📋 خلاصه نیازمندی

زمانی که اولین کالا در یک دسته‌بندی تعریف می‌شود و یک کد به آن اختصاص داده می‌شود، کالاهای بعدی که در همان دسته‌بندی تعریف می‌شوند باید به صورت خودکار کد بعدی را دریافت کنند.

### مثال:
- **دسته‌بندی 1:** ابزار آشپزخانه
  - اولین کالا: کاربر کد `500001` را دستی وارد می‌کند
  - کالاهای بعدی: سیستم به صورت خودکار `500002`، `500003` و ... را تولید می‌کند

- **دسته‌بندی 2:** حوله
  - اولین کالا: کاربر کد `520001` را دستی وارد می‌کند
  - کالاهای بعدی: سیستم به صورت خودکار `520002`، `520003` و ... را تولید می‌کند

---

## ⚠️ نکات مهم

### 🔒 جلوگیری از تکراری بودن کد

**مشکل Race Condition:**
- در صورت درخواست‌های همزمان، ممکن است دو کالا کد یکسان دریافت کنند
- برای حل این مشکل، از **Row Locking (`with_for_update`)** و **Retry Logic** استفاده می‌شود
- جزئیات کامل در بخش [جلوگیری از تکراری بودن کد](#۴-جلوگیری-از-تکراری-بودن-کد-و-race-condition) آمده است

### ✅ محافظت‌های موجود:
1. **UniqueConstraint** در سطح دیتابیس: `(business_id, code)`
2. **Row Locking** برای جلوگیری از Race Condition
3. **Retry Logic** برای مدیریت خطاهای نادر

---

## 🎯 سناریوهای پیاده‌سازی

### سناریو ۱: پیشنهاد کد در فیلد (UI-Based Auto-Suggestion)

#### نحوه کار:
1. کاربر در فرم ایجاد کالا، دسته‌بندی را انتخاب می‌کند
2. اگر فیلد کد خالی است، UI به صورت خودکار یک درخواست API ارسال می‌کند
3. Backend آخرین کد آن دسته را پیدا می‌کند و یکی به آن اضافه می‌کند
4. کد پیشنهادی در فیلد کد نمایش داده می‌شود (قابل ویرایش)
5. کاربر می‌تواند پیشنهاد را بپذیرد یا تغییر دهد

#### پیاده‌سازی Backend:

**Endpoint جدید:**
```python
GET /api/v1/products/business/{business_id}/suggest-code?category_id={category_id}
```

**تابع جدید در `product_service.py`:**
```python
def suggest_next_code_by_category(
    db: Session, 
    business_id: int, 
    category_id: int | None
) -> str | None:
    """
    پیشنهاد کد بعدی برای یک دسته‌بندی
    
    Args:
        db: Session دیتابیس
        business_id: شناسه کسب‌وکار
        category_id: شناسه دسته‌بندی (اگر None باشد، None برمی‌گرداند)
    
    Returns:
        کد پیشنهادی یا None اگر category_id مشخص نشده باشد
    """
    if category_id is None:
        return None
    
    # پیدا کردن آخرین کد عددی در این دسته‌بندی
    products = db.query(Product).filter(
        and_(
            Product.business_id == business_id,
            Product.category_id == category_id,
            Product.code.isnot(None)
        )
    ).order_by(Product.id.desc()).all()
    
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
        return None
    
    # پیشنهاد کد بعدی
    return str(max_code + 1)
```

**Endpoint در `products.py`:**
```python
@router.get("/business/{business_id}/suggest-code")
@require_business_access("business_id")
def suggest_product_code_endpoint(
    request: Request,
    business_id: int,
    category_id: int | None = None,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    
    suggested_code = suggest_next_code_by_category(db, business_id, category_id)
    
    return success_response(
        data={"suggested_code": suggested_code},
        request=request
    )
```

#### پیاده‌سازی Frontend:

**تغییرات در `product_basic_info_section.dart`:**

```dart
// اضافه کردن State variable
String? _suggestedCode;
bool _loadingSuggestedCode = false;

// تابع برای دریافت پیشنهاد کد
Future<void> _fetchSuggestedCode(int? categoryId) async {
  if (categoryId == null) {
    setState(() {
      _suggestedCode = null;
    });
    return;
  }

  // اگر فیلد کد قبلاً پر شده، پیشنهاد نده
  if (widget.formData.code != null && widget.formData.code!.isNotEmpty) {
    return;
  }

  setState(() {
    _loadingSuggestedCode = true;
  });

  try {
    final api = ApiClient();
    final response = await api.get<Map<String, dynamic>>(
      '/api/v1/products/business/${widget.businessId}/suggest-code',
      queryParameters: {'category_id': categoryId.toString()},
    );

    final data = response.data?['data'] as Map<String, dynamic>?;
    final suggestedCode = data?['suggested_code'] as String?;

    if (suggestedCode != null && mounted) {
      setState(() {
        _suggestedCode = suggestedCode;
      });
      // به‌روزرسانی فرم با کد پیشنهادی
      _updateFormData(widget.formData.copyWith(code: suggestedCode));
    }
  } catch (e) {
    // در صورت خطا، فقط لاگ کن (نباید کاربر را نگران کنیم)
    debugPrint('خطا در دریافت پیشنهاد کد: $e');
  } finally {
    if (mounted) {
      setState(() {
        _loadingSuggestedCode = false;
      });
    }
  }
}

// تغییر در CategoryPickerField
CategoryPickerField(
  businessId: widget.businessId,
  categoriesTree: widget.categories,
  initialValue: widget.formData.categoryId,
  label: t.categories,
  onChanged: (value) {
    _updateFormData(widget.formData.copyWith(categoryId: value));
    // دریافت پیشنهاد کد
    _fetchSuggestedCode(value);
  },
),

// تغییر در TextFormField کد
TextFormField(
  initialValue: widget.formData.code,
  decoration: InputDecoration(
    labelText: '${t.code} (اختیاری)',
    suffixIcon: _loadingSuggestedCode
        ? const SizedBox(
            width: 20,
            height: 20,
            child: Padding(
              padding: EdgeInsets.all(12.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : null,
    hintText: _suggestedCode != null 
        ? 'پیشنهاد: $_suggestedCode' 
        : null,
  ),
  validator: ProductFormValidator.validateCode,
  onChanged: (value) {
    _updateFormData(widget.formData.copyWith(
      code: value.trim().isEmpty ? null : value.trim()
    ));
  },
),
```

#### مزایا:
- ✅ کاربر کد پیشنهادی را می‌بیند و می‌تواند تغییر دهد
- ✅ تجربه کاربری بهتر
- ✅ بدون تغییر در منطق فعلی `create_product`

#### معایب:
- ❌ نیاز به API اضافی
- ❌ درخواست‌های اضافی به سرور
- ❌ پیچیدگی بیشتر در Frontend

---

### سناریو ۲: تولید خودکار کد در سمت سرور (Server-Side Auto-Generation)

#### نحوه کار:
1. کاربر در فرم ایجاد کالا، دسته‌بندی را انتخاب می‌کند
2. کاربر می‌تواند فیلد کد را خالی بگذارد
3. در سمت سرور، اگر `code` خالی باشد و `category_id` مشخص باشد:
   - آخرین کد عددی آن دسته را پیدا می‌کند
   - یکی به آن اضافه می‌کند
   - کد را ذخیره می‌کند
4. اگر `category_id` مشخص نباشد یا کدی در دسته وجود نداشته باشد، از منطق فعلی استفاده می‌شود

#### پیاده‌سازی Backend:

**تغییر در `product_service.py`:**

```python
def _generate_auto_code_by_category(
    db: Session, 
    business_id: int, 
    category_id: int | None
) -> str | None:
    """
    تولید کد خودکار بر اساس دسته‌بندی
    
    Args:
        db: Session دیتابیس
        business_id: شناسه کسب‌وکار
        category_id: شناسه دسته‌بندی
    
    Returns:
        کد پیشنهادی یا None اگر نتوان کد تولید کرد
    """
    if category_id is None:
        return None
    
    # پیدا کردن آخرین کد عددی در این دسته‌بندی
    products = db.query(Product).filter(
        and_(
            Product.business_id == business_id,
            Product.category_id == category_id,
            Product.code.isnot(None)
        )
    ).order_by(Product.id.desc()).limit(100).all()  # محدود کردن برای کارایی
    
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
        return None
    
    # تولید کد بعدی
    return str(max_code + 1)


def _generate_auto_code(db: Session, business_id: int, category_id: int | None = None) -> str:
    """
    تولید کد خودکار (با پشتیبانی از دسته‌بندی)
    
    اول سعی می‌کند بر اساس دسته‌بندی کد تولید کند،
    اگر موفق نشد از منطق قبلی استفاده می‌کند.
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
    
    max_id = db.execute(select(func.max(Product.id))).scalar() or 0
    return f"P{max_id + 1:06d}"


def create_product(db: Session, business_id: int, payload: ProductCreateRequest) -> Dict[str, Any]:
    # ... کدهای قبلی ...
    
    # پردازش کد: اگر خالی، None یا برابر نام کالا باشد، کد خودکار تولید می‌شود
    code = None
    if payload.code:
        code_str = payload.code.strip() if isinstance(payload.code, str) else str(payload.code).strip()
        if code_str and code_str != payload.name.strip():
            code = code_str
            dup = db.query(Product).filter(and_(Product.business_id == business_id, Product.code == code)).first()
            if dup:
                raise ApiError("DUPLICATE_PRODUCT_CODE", "کد کالا/خدمت تکراری است", http_status=400)
    
    # اگر کد خالی است یا برابر نام کالا است، کد خودکار تولید کن
    if not code:
        # استفاده از category_id برای تولید کد خودکار
        code = _generate_auto_code(db, business_id, payload.category_id)
    
    # ... ادامه کدهای قبلی ...
```

#### پیاده‌سازی Frontend:
- بدون تغییر! فیلد کد همچنان اختیاری است و کاربر می‌تواند آن را خالی بگذارد.

#### مزایا:
- ✅ بدون نیاز به API اضافی
- ✅ پیاده‌سازی ساده‌تر
- ✅ بدون تغییر در Frontend
- ✅ منطق در یک مکان (Backend)

#### معایب:
- ❌ کاربر کد را قبل از ذخیره نمی‌بیند
- ❌ اگر بخواهد کد خاصی داشته باشد، باید آن را دستی وارد کند

---

### سناریو ۳: سناریو ترکیبی (Recommended)

ترکیب هر دو سناریو:
1. **پیشنهاد کد در UI** وقتی دسته‌بندی انتخاب می‌شود (سناریو ۱)
2. **تولید خودکار در سمت سرور** اگر کاربر فیلد را خالی بگذارد (سناریو ۲)

#### مزایا:
- ✅ بهترین تجربه کاربری (کاربر کد را می‌بیند)
- ✅ انعطاف‌پذیری (اگر خالی بگذارد، خودکار تولید می‌شود)
- ✅ پشتیبانی از هر دو حالت

#### پیاده‌سازی:
- ترکیبی از سناریو ۱ و ۲

---

## 🔍 نکات مهم پیاده‌سازی

### ۱. الگوریتم پیدا کردن آخرین کد

**روش فعلی (پیشنهادی):**
- بررسی تمام کدهای یک دسته‌بندی
- استخراج کدهای عددی
- پیدا کردن بزرگ‌ترین عدد
- اضافه کردن یک واحد

**بهینه‌سازی:**
- می‌توان از Query مستقیم SQL استفاده کرد:
```sql
SELECT MAX(CAST(code AS INTEGER))
FROM products
WHERE business_id = ? AND category_id = ? AND code ~ '^[0-9]+$'
```

**توجه:** باید از Regex برای بررسی اینکه کد فقط عدد است استفاده کرد.

### ۲. حالت‌های خاص

#### الف) اگر هیچ کالایی در دسته وجود نداشته باشد:
- در **سناریو ۱**: `None` برگردانده می‌شود (کاربر باید خودش کد اول را وارد کند)
- در **سناریو ۲**: از منطق فعلی استفاده می‌شود

#### ب) اگر کدهای غیر عددی وجود داشته باشد:
- فقط کدهای عددی در نظر گرفته می‌شوند
- کدهای متنی (مثل `P1001`) نادیده گرفته می‌شوند

#### ج) اگر کالاهایی حذف شده باشند:
- آخرین کد موجود در دیتابیس در نظر گرفته می‌شود
- **مهم:** باید بر اساس `id` یا `created_at` مرتب‌سازی شود، نه فقط کد

### ۳. عملکرد (Performance)

**بهینه‌سازی‌های پیشنهادی:**

1. **Index روی `(business_id, category_id, code)`:**
```python
# در migration
Index('ix_products_business_category_code', 'business_id', 'category_id', 'code')
```

2. **محدود کردن Query:**
```python
.limit(100)  # فقط 100 تا آخرین کد را بررسی کن
```

3. **Cache (اختیاری):**
- می‌توان آخرین کد هر دسته را در Cache نگه داشت
- اما باید در هر ایجاد کالا Cache را invalidate کرد

### ۴. جلوگیری از تکراری بودن کد و Race Condition

#### 🔒 محافظت در سطح دیتابیس

**UniqueConstraint موجود:**
```python
# در models/product.py
__table_args__ = (
    UniqueConstraint("business_id", "code", name="uq_products_business_code"),
)
```

این constraint در سطح دیتابیس از تکراری بودن کد جلوگیری می‌کند.

#### ⚠️ مشکل Race Condition

**سناریوی مشکل:**
1. دو درخواست همزمان برای ایجاد کالا در یک دسته می‌آیند
2. هر دو `_generate_auto_code_by_category` را صدا می‌زنند
3. هر دو آخرین کد را می‌خوانند (مثلاً `500002`)
4. هر دو کد `500003` را تولید می‌کنند
5. هر دو سعی می‌کنند با همان کد ذخیره کنند
6. یکی موفق می‌شود، دیگری خطای `IntegrityError` می‌گیرد

#### ✅ راه حل ۱: استفاده از Row Locking (`with_for_update`)

**تغییر در `_generate_auto_code_by_category`:**

```python
def _generate_auto_code_by_category(
    db: Session, 
    business_id: int, 
    category_id: int | None
) -> str | None:
    """
    تولید کد خودکار بر اساس دسته‌بندی (با Row Locking)
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
        return None
    
    return str(max_code + 1)
```

**مزایا:**
- ✅ جلوگیری از Race Condition
- ✅ اطمینان از یکتا بودن کد
- ✅ استفاده از قابلیت‌های دیتابیس

**معایب:**
- ❌ ممکن است باعث Block شدن درخواست‌های دیگر شود (در صورت ترافیک بالا)

#### ✅ راه حل ۲: Retry Logic با Exception Handling

**تغییر در `create_product`:**

```python
from sqlalchemy.exc import IntegrityError

def create_product(db: Session, business_id: int, payload: ProductCreateRequest) -> Dict[str, Any]:
    repo = ProductRepository(db)
    _validate_tax(payload)
    _validate_item_type_inventory(payload)
    # ... سایر اعتبارسنجی‌ها ...
    
    # پردازش کد با Retry Logic
    max_retries = 3
    retry_count = 0
    
    while retry_count < max_retries:
        try:
            code = None
            if payload.code:
                code_str = payload.code.strip() if isinstance(payload.code, str) else str(payload.code).strip()
                if code_str and code_str != payload.name.strip():
                    code = code_str
                    dup = db.query(Product).filter(
                        and_(Product.business_id == business_id, Product.code == code)
                    ).first()
                    if dup:
                        raise ApiError("DUPLICATE_PRODUCT_CODE", "کد کالا/خدمت تکراری است", http_status=400)
            
            # اگر کد خالی است، کد خودکار تولید کن
            if not code:
                code = _generate_auto_code(db, business_id, payload.category_id)
            
            # ایجاد کالا
            obj = repo.create(
                business_id=business_id,
                item_type=payload.item_type,
                code=code,
                # ... سایر فیلدها ...
            )
            
            _upsert_attributes(db, obj.id, business_id, payload.attribute_ids)
            db.commit()  # Commit موفق
            
            data = _to_dict(obj)
            return {"message": "PRODUCT_CREATED", "data": data}
            
        except IntegrityError as e:
            # خطای تکراری بودن کد
            db.rollback()
            retry_count += 1
            
            if retry_count >= max_retries:
                # اگر بعد از 3 بار تلاش باز هم خطا داد، خطا را برمی‌گردانیم
                raise ApiError(
                    "DUPLICATE_PRODUCT_CODE", 
                    "کد کالا/خدمت تکراری است. لطفاً دوباره تلاش کنید.", 
                    http_status=400
                )
            
            # اگر کد خودکار بود، دوباره تولید کن
            if not payload.code or (payload.code and payload.code.strip() == payload.name.strip()):
                # کد خودکار بود، دوباره تولید کن
                continue
            else:
                # کد دستی بود و تکراری است
                raise ApiError("DUPLICATE_PRODUCT_CODE", "کد کالا/خدمت تکراری است", http_status=400)
        
        except Exception as e:
            db.rollback()
            raise
```

**مزایا:**
- ✅ ساده‌تر از Row Locking
- ✅ خودکار Retry می‌کند
- ✅ در صورت خطا، دوباره تلاش می‌کند

**معایب:**
- ❌ ممکن است چند بار تلاش کند (کمی کندتر)
- ❌ در ترافیک بالا ممکن است چند بار Retry شود

#### ✅ راه حل ۳: ترکیب هر دو (Recommended)

**بهترین راه حل: ترکیب Row Locking + Retry Logic**

```python
def _generate_auto_code_by_category(
    db: Session, 
    business_id: int, 
    category_id: int | None
) -> str | None:
    """تولید کد خودکار با Row Locking"""
    if category_id is None:
        return None
    
    # استفاده از Row Locking
    products = db.query(Product).filter(
        and_(
            Product.business_id == business_id,
            Product.category_id == category_id,
            Product.code.isnot(None)
        )
    ).with_for_update().order_by(Product.id.desc()).limit(100).all()
    
    # ... بقیه کد ...
    
    return str(max_code + 1)


def create_product(db: Session, business_id: int, payload: ProductCreateRequest) -> Dict[str, Any]:
    # ... اعتبارسنجی‌ها ...
    
    max_retries = 2  # کمتر از قبل چون Row Locking داریم
    retry_count = 0
    
    while retry_count < max_retries:
        try:
            # ... تولید کد و ایجاد کالا ...
            db.commit()
            return {"message": "PRODUCT_CREATED", "data": data}
            
        except IntegrityError as e:
            db.rollback()
            retry_count += 1
            if retry_count >= max_retries:
                raise ApiError("DUPLICATE_PRODUCT_CODE", "کد تکراری است", http_status=400)
            # Retry
            continue
```

**مزایا:**
- ✅ بهترین محافظت در برابر Race Condition
- ✅ Retry برای حالت‌های نادر
- ✅ تعادل بین کارایی و اطمینان

#### 📊 مقایسه راه حل‌ها

| راه حل | کارایی | اطمینان | پیچیدگی | توصیه |
|--------|--------|---------|---------|-------|
| Row Locking | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ✅ |
| Retry Logic | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | ⚠️ |
| ترکیبی | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐ **بهترین** |

### ۵. امنیت و اعتبارسنجی

- بررسی تکراری بودن کد (از قبل وجود دارد)
- بررسی دسترسی کاربر به `business_id` و `category_id`
- بررسی معتبر بودن `category_id` (مربوط به همان `business_id` باشد)

### ۶. تست‌ها

**Test Cases:**

#### تست‌های عملکردی:

1. ✅ ایجاد اولین کالا در یک دسته (کد دستی: `500001`)
2. ✅ ایجاد دومین کالا در همان دسته (کد خودکار: `500002`)
3. ✅ ایجاد کالا در دسته دیگر (کد دستی: `520001`)
4. ✅ ایجاد کالای بعدی در دسته دوم (کد خودکار: `520002`)
5. ✅ ایجاد کالا بدون دسته‌بندی (کد خودکار با منطق قبلی)
6. ✅ ایجاد کالا با کد غیر عددی موجود در دسته (نادیده گرفته شود)
7. ✅ ایجاد کالا با کد دستی که تکراری است (خطا)
8. ✅ ایجاد کالا با کد دستی که بزرگ‌تر از آخرین کد است (مجاز است)

#### تست‌های Race Condition:

9. ✅ **تست همزمانی (Concurrent Requests):**
   - ارسال 10 درخواست همزمان برای ایجاد کالا در یک دسته
   - همه باید با کدهای یکتا ذخیره شوند (`500002`, `500003`, ..., `500011`)
   - هیچ کد تکراری نباید ایجاد شود

10. ✅ **تست Retry Logic:**
    - شبیه‌سازی خطای `IntegrityError`
    - بررسی اینکه Retry انجام می‌شود
    - بررسی اینکه بعد از Retry موفق می‌شود

11. ✅ **تست Row Locking:**
    - بررسی اینکه `with_for_update()` درست کار می‌کند
    - بررسی اینکه درخواست‌های همزمان به ترتیب پردازش می‌شوند

#### تست‌های Edge Cases:

12. ✅ ایجاد کالا با کد عددی منفی (باید نادیده گرفته شود)
13. ✅ ایجاد کالا با کد خیلی بزرگ (مثلاً `999999999`)
14. ✅ ایجاد کالا در دسته‌ای که همه کدهایش غیر عددی هستند
15. ✅ ایجاد کالا در دسته‌ای که کدهایش مخلوط هستند (عددی و غیر عددی)

---

## 📊 مقایسه سناریوها

| ویژگی | سناریو ۱ (UI) | سناریو ۲ (Server) | سناریو ۳ (ترکیبی) |
|-------|---------------|-------------------|-------------------|
| تجربه کاربری | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| پیچیدگی Backend | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| پیچیدگی Frontend | ⭐⭐⭐ | ⭐ | ⭐⭐⭐ |
| تعداد API Calls | بیشتر | بدون تغییر | بیشتر |
| انعطاف‌پذیری | متوسط | بالا | بالا |
| **توصیه** | ❌ | ✅ | ⭐ **بهترین** |

---

## ✅ تصمیم نهایی

**توصیه: سناریو ۲ (Server-Side Auto-Generation)**

### دلایل:
1. ✅ پیاده‌سازی ساده‌تر
2. ✅ بدون نیاز به تغییر Frontend
3. ✅ منطق در یک مکان (Backend)
4. ✅ بدون API اضافی
5. ✅ کاربر می‌تواند کد را دستی وارد کند یا خالی بگذارد

### در صورت نیاز به تجربه کاربری بهتر:
- بعداً می‌توان سناریو ۱ را هم اضافه کرد (سناریو ۳)

---

## 📝 مراحل پیاده‌سازی (سناریو ۲)

### مرحله ۱: پیاده‌سازی توابع اصلی

1. ✅ ایجاد تابع `_generate_auto_code_by_category` در `product_service.py`
   - با استفاده از `with_for_update()` برای Row Locking
   - استخراج آخرین کد عددی از دسته‌بندی
   - تولید کد بعدی

2. ✅ تغییر تابع `_generate_auto_code` برای پشتیبانی از `category_id`
   - اضافه کردن پارامتر `category_id`
   - اول سعی کند بر اساس دسته کد تولید کند
   - در صورت عدم موفقیت، از منطق قبلی استفاده کند

3. ✅ تغییر تابع `create_product` برای استفاده از `category_id` در تولید کد خودکار
   - اضافه کردن Retry Logic برای مدیریت `IntegrityError`
   - استفاده از `category_id` در `_generate_auto_code`

### مرحله ۲: بهینه‌سازی و امنیت

4. ✅ Migration برای Index (برای بهینه‌سازی Query):
   ```python
   # در migration
   op.create_index(
       'ix_products_business_category_code',
       'products',
       ['business_id', 'category_id', 'code'],
       unique=False
   )
   ```

5. ✅ اضافه کردن Exception Handling برای `IntegrityError`
   - Import کردن `sqlalchemy.exc.IntegrityError`
   - اضافه کردن Retry Logic با حداکثر 2-3 بار تلاش

### مرحله ۳: تست‌ها

6. ✅ تست‌های واحد برای توابع جدید
   - تست `_generate_auto_code_by_category`
   - تست `_generate_auto_code` با `category_id`
   - تست حالت‌های خاص (بدون کد، کد غیر عددی، و غیره)

7. ✅ تست‌های یکپارچه‌سازی
   - تست ایجاد کالا با دسته‌بندی
   - تست ایجاد کالا بدون دسته‌بندی
   - تست Race Condition (درخواست‌های همزمان)

8. ✅ تست‌های عملکردی
   - تست با تعداد زیاد کالا در یک دسته
   - تست با ترافیک بالا (Load Testing)

### مرحله ۴: مستندسازی

9. ✅ به‌روزرسانی مستندات API
10. ✅ اضافه کردن کامنت‌های توضیحی در کد
11. ✅ به‌روزرسانی Changelog

---

**تاریخ:** 2025-01-27  
**وضعیت:** در انتظار تأیید

