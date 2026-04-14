# سناریوی جامع: محاسبه و نمایش سود فاکتور

## 📋 خلاصه
این سند سناریوی پیاده‌سازی قابلیت محاسبه و نمایش سود فاکتور را به صورت جامع بررسی می‌کند. این قابلیت شامل تنظیمات در بخش کسب و کار، محاسبه سود در بکند، و نمایش آن در لیست فاکتورها و دیالوگ جزئیات فاکتور است.

**ویژگی‌های کلیدی:**
- ✅ پشتیبانی از **8 روش مختلف** محاسبه هزینه (FIFO, LIFO, میانگین، و غیره)
- ✅ محاسبه **سود ناخالص و خالص** با در نظر گیری هزینه‌های سربار
- ✅ پشتیبانی کامل از **فاکتورهای تولیدی** با محاسبه هزینه مواد اولیه و عملیات
- ✅ **قابل استفاده برای انواع کسب و کار**: بازرگانی، تولیدی، خدماتی
- ✅ **گزینه‌های انعطاف‌پذیر** برای شامل/عدم شامل هزینه‌ها

---

## 🎯 اهداف

1. **تنظیمات کسب و کار**: اضافه کردن گزینه‌های تنظیم نحوه محاسبه سود فاکتور
2. **محاسبه سود**: محاسبه خودکار سود برای هر فاکتور بر اساس تنظیمات
3. **نمایش در لیست**: نمایش سود در لیست فاکتورها
4. **نمایش در جزئیات**: نمایش سود در دیالوگ جزئیات فاکتور
5. **پشتیبانی از مراکز تولیدی**: محاسبه سود برای فاکتورهای تولید با در نظر گیری هزینه‌های تولید
6. **مدیریت هزینه‌های سربار**: امکان شامل/عدم شامل هزینه‌های سربار در محاسبه سود

---

## 🏭 کاربرد برای انواع کسب و کار

### 1. کسب و کارهای بازرگانی
**مثال**: فروشگاه، عمده‌فروشی، خرده‌فروشی

**تنظیمات پیشنهادی:**
- مبنای محاسبه: `purchase_price` یا `fifo`
- نوع محاسبه: `gross` (سود ناخالص)
- شامل هزینه سربار: `false` (یا با درصد کم)

**مزایا:**
- محاسبه سریع و ساده سود
- مناسب برای کسب و کارهایی که هزینه سربار کم است
- نمایش سود واقعی از فروش

### 2. مراکز تولیدی
**مثال**: کارخانه، تولیدی، صنعتی

**تنظیمات پیشنهادی:**
- مبنای محاسبه: `fifo` یا `weighted_average`
- نوع محاسبه: `both` (ناخالص و خالص)
- شامل هزینه سربار: `true`
- نوع سربار: `production_overhead` یا `all_overhead`

**مزایا:**
- محاسبه دقیق هزینه تولید (مواد اولیه + عملیات)
- در نظر گیری هزینه‌های سربار تولید
- محاسبه سود واقعی محصولات تولیدی
- پشتیبانی از فاکتور تولید (`invoice_production`)

**نحوه کار:**
1. در فاکتور تولید، هزینه مواد اولیه و عملیات محاسبه می‌شود
2. هزینه کل تولید به محصول نهایی تخصیص می‌یابد
3. هنگام فروش محصول نهایی، سود بر اساس هزینه تولید محاسبه می‌شود

### 3. کسب و کارهای خدماتی
**مثال**: مشاوره، طراحی، نرم‌افزار

**تنظیمات پیشنهادی:**
- مبنای محاسبه: `actual_cost` یا `standard_cost`
- نوع محاسبه: `net` (سود خالص)
- شامل هزینه سربار: `true`
- نوع سربار: `all_overhead` یا `custom_percent`

**مزایا:**
- در نظر گیری هزینه‌های نیروی انسانی و سربار
- محاسبه سود واقعی خدمات

### 4. کسب و کارهای ترکیبی
**مثال**: تولید + فروش، واردات + توزیع

**تنظیمات پیشنهادی:**
- مبنای محاسبه: `fifo` یا `weighted_average`
- نوع محاسبه: `both`
- شامل هزینه سربار: `true`
- نوع سربار: `all_overhead`

**مزایا:**
- پشتیبانی از هر دو نوع فاکتور (تولید و فروش)
- محاسبه دقیق سود در هر مرحله

---

## 💰 هزینه‌های سربار (Overhead Costs)

### انواع هزینه‌های سربار

#### 1. هزینه‌های سربار تولید (Production Overhead)
- هزینه‌های غیرمستقیم تولید
- مثال: برق کارخانه، استهلاک ماشین‌آلات، حقوق کارگران غیرمستقیم
- **منبع**: از فیلد `production_operations_total` در فاکتور تولید

#### 2. هزینه‌های اداری (Administrative Overhead)
- هزینه‌های مدیریت و اداری
- مثال: حقوق مدیران، اجاره دفتر، هزینه‌های اداری
- **منبع**: از جداول هزینه‌ها یا تنظیمات کسب و کار

#### 3. هزینه‌های فروش (Sales Overhead)
- هزینه‌های مرتبط با فروش
- مثال: حقوق فروشندگان، تبلیغات، بازاریابی
- **منبع**: از جداول هزینه‌ها یا تنظیمات کسب و کار

#### 4. هزینه‌های سربار سفارشی (Custom Percent)
- درصد ثابت از هزینه کل
- مثال: 10% از هزینه کل به عنوان سربار
- **منبع**: از تنظیمات کسب و کار (`invoice_profit_overhead_percent`)

### گزینه‌های محاسبه هزینه سربار

1. **بدون سربار (`none`)**: فقط سود ناخالص محاسبه می‌شود
2. **فقط سربار تولید (`production_overhead`)**: فقط هزینه‌های تولید
3. **تمام هزینه‌های سربار (`all_overhead`)**: تولید + اداری + فروش
4. **درصد سفارشی (`custom_percent`)**: درصد ثابت از هزینه کل

### مثال محاسبه با هزینه سربار

```
هزینه کالای فروش رفته: 10,000,000 تومان
مبلغ فروش: 15,000,000 تومان

سود ناخالص: 5,000,000 تومان (33.33%)

هزینه سربار (10%): 1,000,000 تومان
سود خالص: 4,000,000 تومان (26.67%)
```

---

## 🔍 بررسی ساختار فعلی

### 1. ساختار Backend

#### مدل‌های دیتابیس

**Business Model** (`hesabixAPI/adapters/db/models/business.py`):
- جدول `businesses` شامل فیلدهای تنظیمات کسب و کار
- فیلدهای موجود: `default_credit_limit`, `check_credit_enabled_by_default`
- نیاز به اضافه کردن فیلدهای جدید برای تنظیمات محاسبه سود

**Product Model** (`hesabixAPI/adapters/db/models/product.py`):
- محصولات دارای `base_purchase_price` (قیمت خرید) و `base_sales_price` (قیمت فروش)
- این قیمت‌ها برای محاسبه سود استفاده می‌شوند

**Invoice/Document Model**:
- فاکتورها در جدول `documents` ذخیره می‌شوند
- ردیف‌های فاکتور در `document_lines` با `extra_info` (JSON) که می‌تواند `cost_price` را نگه دارد
- در `invoice_service.py` محاسبات `cost_price` برای انبار انجام می‌شود

#### سرویس‌های موجود

**Invoice Service** (`hesabixAPI/app/services/invoice_service.py`):
- تابع `create_invoice`: ایجاد فاکتور جدید
- تابع `update_invoice`: ویرایش فاکتور
- محاسبه `cost_price` از `extra_info` یا قیمت خرید محصول
- محاسبه سود نیاز به اضافه شدن دارد

**Business Service**:
- مدیریت تنظیمات کسب و کار
- نیاز به اضافه کردن endpoint برای تنظیمات محاسبه سود

### 2. ساختار Frontend

#### صفحات موجود

**Business Info Settings Page** (`hesabixUI/hesabix_ui/lib/pages/business/business_info_settings_page.dart`):
- صفحه تنظیمات اطلاعات کسب و کار
- شامل تنظیمات اعتبار مشتریان
- نیاز به اضافه کردن بخش تنظیمات محاسبه سود

**Invoices List Page** (`hesabixUI/hesabix_ui/lib/pages/business/invoices_list_page.dart`):
- صفحه لیست فاکتورها با `DataTableWidget`
- نمایش فیلدهای مختلف فاکتور
- نیاز به اضافه کردن ستون سود

**Document Details Dialog** (`hesabixUI/hesabix_ui/lib/widgets/document/document_details_dialog.dart`):
- دیالوگ نمایش جزئیات کامل سند
- شامل تب‌های: اطلاعات، کالاها، حساب‌ها، تراکنش‌ها، فایل‌ها
- نیاز به نمایش سود در تب اطلاعات یا کالاها

#### مدل‌های موجود

**InvoiceListItem** (`hesabixUI/hesabix_ui/lib/models/invoice_list_item.dart`):
- مدل برای نمایش فاکتور در لیست
- نیاز به اضافه کردن فیلد `profit` و `profitPercent`

**InvoiceLineItem** (`hesabixUI/hesabix_ui/lib/models/invoice_line_item.dart`):
- مدل برای ردیف‌های فاکتور
- دارای `basePurchasePriceMainUnit` و `baseSalesPriceMainUnit`
- نیاز به محاسبه و نمایش سود هر ردیف

---

## 📐 طراحی راه‌حل

### 1. تنظیمات محاسبه سود در کسب و کار

#### فیلدهای جدید در جدول `businesses`:

```sql
ALTER TABLE businesses ADD COLUMN invoice_profit_calculation_method VARCHAR(20) DEFAULT 'automatic';
-- مقادیر: 'automatic' (خودکار), 'manual' (دستی), 'disabled' (غیرفعال)

ALTER TABLE businesses ADD COLUMN invoice_profit_calculation_basis VARCHAR(30) DEFAULT 'purchase_price';
-- مقادیر: 
--   'purchase_price' (قیمت خرید)
--   'cost_price' (قیمت تمام شده)
--   'average_cost' (میانگین قیمت)
--   'fifo' (اول ورود، اول خروج)
--   'lifo' (آخر ورود، اول خروج)
--   'weighted_average' (میانگین وزنی)
--   'standard_cost' (هزینه استاندارد)
--   'actual_cost' (هزینه واقعی)

ALTER TABLE businesses ADD COLUMN invoice_profit_include_overhead BOOLEAN DEFAULT FALSE;
-- آیا هزینه‌های سربار (Overhead) در محاسبه سود لحاظ شود؟

ALTER TABLE businesses ADD COLUMN invoice_profit_overhead_type VARCHAR(30) DEFAULT 'none';
-- نوع هزینه‌های سربار:
--   'none' (بدون سربار)
--   'production_overhead' (فقط سربار تولید)
--   'all_overhead' (تمام هزینه‌های سربار)
--   'custom_percent' (درصد سفارشی)

ALTER TABLE businesses ADD COLUMN invoice_profit_overhead_percent DECIMAL(5,2) DEFAULT 0;
-- درصد هزینه‌های سربار (در صورت انتخاب custom_percent)

ALTER TABLE businesses ADD COLUMN invoice_profit_calculation_type VARCHAR(20) DEFAULT 'gross';
-- نوع محاسبه سود:
--   'gross' (سود ناخالص - بدون هزینه‌ها)
--   'net' (سود خالص - با هزینه‌ها)
--   'both' (هر دو)
```

#### Schema در Backend:

**Business Model** (`hesabixAPI/adapters/db/models/business.py`):
```python
# فیلدهای جدید
invoice_profit_calculation_method: Mapped[str | None] = mapped_column(
    String(20), 
    nullable=True, 
    default="automatic",
    comment="روش محاسبه سود فاکتور: automatic, manual, disabled"
)
invoice_profit_calculation_basis: Mapped[str | None] = mapped_column(
    String(30), 
    nullable=True, 
    default="purchase_price",
    comment="مبنای محاسبه سود: purchase_price, cost_price, average_cost, fifo, lifo, weighted_average, standard_cost, actual_cost"
)
invoice_profit_include_overhead: Mapped[bool] = mapped_column(
    Boolean,
    nullable=False,
    default=False,
    server_default="0",
    comment="آیا هزینه‌های سربار در محاسبه سود لحاظ شود؟"
)
invoice_profit_overhead_type: Mapped[str | None] = mapped_column(
    String(30),
    nullable=True,
    default="none",
    comment="نوع هزینه‌های سربار: none, production_overhead, all_overhead, custom_percent"
)
invoice_profit_overhead_percent: Mapped[Decimal | None] = mapped_column(
    Numeric(5, 2),
    nullable=True,
    default=0,
    comment="درصد هزینه‌های سربار (در صورت انتخاب custom_percent)"
)
invoice_profit_calculation_type: Mapped[str | None] = mapped_column(
    String(20),
    nullable=True,
    default="gross",
    comment="نوع محاسبه سود: gross, net, both"
)
```

**Business Schema** (`hesabixAPI/adapters/api/v1/schemas.py`):
```python
class BusinessUpdateRequest(BaseModel):
    # ... فیلدهای موجود ...
    invoice_profit_calculation_method: Optional[str] = Field(
        default=None,
        description="روش محاسبه سود فاکتور: automatic, manual, disabled"
    )
    invoice_profit_calculation_basis: Optional[str] = Field(
        default=None,
        description="مبنای محاسبه سود: purchase_price, cost_price, average_cost, fifo, lifo, weighted_average, standard_cost, actual_cost"
    )
    invoice_profit_include_overhead: Optional[bool] = Field(
        default=None,
        description="آیا هزینه‌های سربار در محاسبه سود لحاظ شود؟"
    )
    invoice_profit_overhead_type: Optional[str] = Field(
        default=None,
        description="نوع هزینه‌های سربار: none, production_overhead, all_overhead, custom_percent"
    )
    invoice_profit_overhead_percent: Optional[Decimal] = Field(
        default=None,
        ge=0,
        le=100,
        description="درصد هزینه‌های سربار (0-100) - فقط برای custom_percent"
    )
    invoice_profit_calculation_type: Optional[str] = Field(
        default=None,
        description="نوع محاسبه سود: gross (ناخالص), net (خالص), both (هر دو)"
    )

class BusinessResponse(BaseModel):
    # ... فیلدهای موجود ...
    invoice_profit_calculation_method: Optional[str] = Field(
        default=None,
        description="روش محاسبه سود فاکتور"
    )
    invoice_profit_calculation_basis: Optional[str] = Field(
        default=None,
        description="مبنای محاسبه سود"
    )
    invoice_profit_include_overhead: Optional[bool] = Field(
        default=None,
        description="آیا هزینه‌های سربار در محاسبه سود لحاظ می‌شود"
    )
    invoice_profit_overhead_type: Optional[str] = Field(
        default=None,
        description="نوع هزینه‌های سربار"
    )
    invoice_profit_overhead_percent: Optional[Decimal] = Field(
        default=None,
        description="درصد هزینه‌های سربار"
    )
    invoice_profit_calculation_type: Optional[str] = Field(
        default=None,
        description="نوع محاسبه سود"
    )
```

### 2. محاسبه سود در Backend

#### منطق محاسبه سود:

**برای فاکتورهای فروش (`invoice_sales`, `invoice_sales_return`)**:
- سود ناخالص = (قیمت فروش - قیمت خرید/هزینه) × تعداد
- سود خالص = سود ناخالص - هزینه‌های سربار (در صورت فعال بودن)
- سود کل فاکتور = مجموع سود تمام ردیف‌ها

**برای فاکتورهای تولید (`invoice_production`)**:
- هزینه مواد اولیه = مجموع هزینه مواد خروجی (out_lines)
- هزینه عملیات = `production_operations_total` از `extra_info`
- هزینه کل تولید = هزینه مواد اولیه + هزینه عملیات
- سود ناخالص = (قیمت فروش محصول نهایی - هزینه کل تولید) × تعداد
- سود خالص = سود ناخالص - هزینه‌های سربار اضافی

**برای فاکتورهای خرید (`invoice_purchase`)**:
- معمولاً سود محاسبه نمی‌شود (یا می‌تواند منفی باشد)

**مبنای محاسبه هزینه**:
1. **purchase_price**: استفاده از `base_purchase_price` محصول
2. **cost_price**: استفاده از `cost_price` از `extra_info` ردیف یا محاسبه از انبار
3. **average_cost**: استفاده از میانگین قیمت خرید از تاریخچه
4. **fifo** (First In First Out): استفاده از قیمت قدیمی‌ترین موجودی
5. **lifo** (Last In First Out): استفاده از قیمت جدیدترین موجودی
6. **weighted_average**: میانگین وزنی قیمت‌های خرید بر اساس تعداد
7. **standard_cost**: استفاده از هزینه استاندارد محصول (در صورت تعریف)
8. **actual_cost**: استفاده از هزینه واقعی از انبار (cost_price از extra_info)

**هزینه‌های سربار (Overhead)**:
- **none**: بدون هزینه سربار
- **production_overhead**: فقط هزینه‌های سربار تولید (از فاکتور تولید)
- **all_overhead**: تمام هزینه‌های سربار (تولید + اداری + فروش)
- **custom_percent**: درصد سفارشی از هزینه کل

#### توابع کمکی برای محاسبه هزینه:

```python
def _get_cost_per_unit_by_basis(
    db: Session,
    business_id: int,
    product: Product,
    line: DocumentLine,
    calculation_basis: str,
    document_date: date,
    warehouse_id: Optional[int] = None
) -> Decimal:
    """
    محاسبه هزینه هر واحد بر اساس مبنای انتخاب شده
    """
    extra_info = line.extra_info or {}
    
    if calculation_basis == "purchase_price":
        return Decimal(str(product.base_purchase_price or 0))
    
    elif calculation_basis == "cost_price":
        # استفاده از cost_price از extra_info یا قیمت خرید
        if extra_info.get("cost_price") is not None:
            return Decimal(str(extra_info.get("cost_price")))
        return Decimal(str(product.base_purchase_price or 0))
    
    elif calculation_basis == "actual_cost":
        # هزینه واقعی از انبار (اولویت با cost_price از extra_info)
        if extra_info.get("cost_price") is not None:
            return Decimal(str(extra_info.get("cost_price")))
        # یا از cogs_amount محاسبه می‌شود
        if extra_info.get("cogs_amount") is not None and line.quantity > 0:
            return Decimal(str(extra_info.get("cogs_amount"))) / Decimal(str(line.quantity))
        return Decimal(str(product.base_purchase_price or 0))
    
    elif calculation_basis == "average_cost":
        return _calculate_average_purchase_cost(db, business_id, product.id, document_date)
    
    elif calculation_basis == "fifo":
        return _calculate_fifo_cost(db, business_id, product.id, line.quantity, document_date, warehouse_id)
    
    elif calculation_basis == "lifo":
        return _calculate_lifo_cost(db, business_id, product.id, line.quantity, document_date, warehouse_id)
    
    elif calculation_basis == "weighted_average":
        return _calculate_weighted_average_cost(db, business_id, product.id, document_date)
    
    elif calculation_basis == "standard_cost":
        # استفاده از هزینه استاندارد محصول (در صورت تعریف در extra_info یا جدول جداگانه)
        if extra_info.get("standard_cost") is not None:
            return Decimal(str(extra_info.get("standard_cost")))
        # fallback به قیمت خرید
        return Decimal(str(product.base_purchase_price or 0))
    
    else:
        # fallback به قیمت خرید
        return Decimal(str(product.base_purchase_price or 0))


def _calculate_overhead_cost(
    db: Session,
    business_id: int,
    document_id: int,
    total_cost: Decimal,
    overhead_type: str,
    overhead_percent: Optional[Decimal] = None
) -> Decimal:
    """
    محاسبه هزینه‌های سربار
    """
    if overhead_type == "none":
        return Decimal(0)
    
    elif overhead_type == "custom_percent":
        if overhead_percent is None or overhead_percent <= 0:
            return Decimal(0)
        return total_cost * (overhead_percent / 100)
    
    elif overhead_type == "production_overhead":
        # دریافت هزینه عملیات از فاکتور تولید مرتبط
        document = db.query(Document).filter(Document.id == document_id).first()
        if document and document.document_type == "invoice_production":
            extra_info = document.extra_info or {}
            operations_total = Decimal(str(extra_info.get("production_operations_total", 0) or 0))
            return operations_total
        return Decimal(0)
    
    elif overhead_type == "all_overhead":
        # محاسبه تمام هزینه‌های سربار (تولید + اداری + فروش)
        # این می‌تواند از جداول هزینه‌ها یا تنظیمات کسب و کار محاسبه شود
        # برای سادگی، می‌توان از درصد ثابت یا محاسبه از فاکتورهای هزینه استفاده کرد
        # TODO: پیاده‌سازی کامل بر اساس نیاز کسب و کار
        return Decimal(0)
    
    return Decimal(0)
```

#### تابع اصلی محاسبه سود:

```python
def _calculate_invoice_profit(
    db: Session,
    business_id: int,
    document_id: int,
    calculation_method: str = "automatic",
    calculation_basis: str = "purchase_price",
    include_overhead: bool = False,
    overhead_type: str = "none",
    overhead_percent: Optional[Decimal] = None,
    calculation_type: str = "gross"
) -> Dict[str, Any]:
    """
    محاسبه سود فاکتور با پشتیبانی از روش‌های مختلف و هزینه‌های سربار
    
    Returns:
        {
            "gross_profit": Decimal,  # سود ناخالص
            "net_profit": Decimal,  # سود خالص
            "gross_profit_percent": Decimal,  # درصد سود ناخالص
            "net_profit_percent": Decimal,  # درصد سود خالص
            "total_overhead": Decimal,  # هزینه‌های سربار
            "line_profits": List[Dict]  # سود هر ردیف
        }
    """
    # دریافت تنظیمات کسب و کار
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        return _empty_profit_response()
    
    # اگر محاسبه سود غیرفعال است
    if calculation_method == "disabled":
        return _empty_profit_response()
    
    # دریافت فاکتور
    document = db.query(Document).filter(Document.id == document_id).first()
    if not document or not document.document_type.startswith("invoice"):
        return _empty_profit_response()
    
    # دریافت ردیف‌های فاکتور
    lines = db.query(DocumentLine).filter(DocumentLine.document_id == document_id).all()
    
    total_gross_profit = Decimal(0)
    total_net_profit = Decimal(0)
    total_sales = Decimal(0)
    total_cost = Decimal(0)
    line_profits = []
    
    # برای فاکتور تولید
    if document.document_type == "invoice_production":
        return _calculate_production_profit(
            db, business_id, document, lines,
            calculation_basis, include_overhead, overhead_type, overhead_percent, calculation_type
        )
    
    # برای فاکتورهای فروش
    if document.document_type in ["invoice_sales", "invoice_sales_return"]:
        for line in lines:
            if not line.product_id:
                continue
            
            product = db.query(Product).filter(Product.id == line.product_id).first()
            if not product:
                continue
            
            qty = Decimal(str(line.quantity or 0))
            unit_price = Decimal(str(line.unit_price or 0))
            discount_amount = Decimal(str(line.discount_amount or 0))
            
            # محاسبه مبلغ فروش (بعد از تخفیف)
            sales_amount = (qty * unit_price) - discount_amount
            
            # محاسبه هزینه هر واحد بر اساس مبنای انتخاب شده
            cost_per_unit = _get_cost_per_unit_by_basis(
                db, business_id, product, line, calculation_basis,
                document.document_date, line.warehouse_id
            )
            
            total_line_cost = qty * cost_per_unit
            
            # محاسبه سود ناخالص ردیف
            line_gross_profit = sales_amount - total_line_cost
            line_gross_profit_percent = (line_gross_profit / sales_amount * 100) if sales_amount > 0 else Decimal(0)
            
            # محاسبه هزینه سربار برای این ردیف (در صورت فعال بودن)
            line_overhead = Decimal(0)
            if include_overhead:
                line_overhead = _calculate_overhead_cost(
                    db, business_id, document_id, total_line_cost,
                    overhead_type, overhead_percent
                ) / len(lines) if len(lines) > 0 else Decimal(0)
            
            # محاسبه سود خالص ردیف
            line_net_profit = line_gross_profit - line_overhead
            line_net_profit_percent = (line_net_profit / sales_amount * 100) if sales_amount > 0 else Decimal(0)
            
            total_gross_profit += line_gross_profit
            total_net_profit += line_net_profit
            total_sales += sales_amount
            total_cost += total_line_cost
            
            line_profits.append({
                "line_id": line.id,
                "product_id": product.id,
                "product_code": product.code,
                "product_name": product.name,
                "quantity": float(qty),
                "unit_price": float(unit_price),
                "cost_per_unit": float(cost_per_unit),
                "sales_amount": float(sales_amount),
                "total_cost": float(total_line_cost),
                "gross_profit": float(line_gross_profit),
                "net_profit": float(line_net_profit),
                "gross_profit_percent": float(line_gross_profit_percent),
                "net_profit_percent": float(line_net_profit_percent),
                "overhead": float(line_overhead)
            })
    
    # محاسبه هزینه سربار کل
    total_overhead = Decimal(0)
    if include_overhead:
        total_overhead = _calculate_overhead_cost(
            db, business_id, document_id, total_cost,
            overhead_type, overhead_percent
        )
        total_net_profit = total_gross_profit - total_overhead
    
    # محاسبه درصد سود
    gross_profit_percent = (total_gross_profit / total_sales * 100) if total_sales > 0 else Decimal(0)
    net_profit_percent = (total_net_profit / total_sales * 100) if total_sales > 0 else Decimal(0)
    
    # ساخت response بر اساس نوع محاسبه
    result = {
        "total_overhead": float(total_overhead),
        "line_profits": line_profits
    }
    
    if calculation_type in ["gross", "both"]:
        result["gross_profit"] = float(total_gross_profit)
        result["gross_profit_percent"] = float(gross_profit_percent)
    
    if calculation_type in ["net", "both"]:
        result["net_profit"] = float(total_net_profit)
        result["net_profit_percent"] = float(net_profit_percent)
    
    # برای سازگاری با کد قدیم
    if calculation_type == "gross":
        result["total_profit"] = result["gross_profit"]
        result["total_profit_percent"] = result["gross_profit_percent"]
    elif calculation_type == "net":
        result["total_profit"] = result["net_profit"]
        result["total_profit_percent"] = result["net_profit_percent"]
    
    return result


def _calculate_production_profit(
    db: Session,
    business_id: int,
    document: Document,
    lines: List[DocumentLine],
    calculation_basis: str,
    include_overhead: bool,
    overhead_type: str,
    overhead_percent: Optional[Decimal],
    calculation_type: str
) -> Dict[str, Any]:
    """
    محاسبه سود برای فاکتور تولید
    """
    # جداسازی خطوط ورودی (محصول نهایی) و خروجی (مواد اولیه)
    out_lines = [ln for ln in lines if (ln.extra_info or {}).get("movement") == "out"]
    in_lines = [ln for ln in lines if (ln.extra_info or {}).get("movement") == "in"]
    
    # محاسبه هزینه مواد اولیه
    total_materials_cost = Decimal(0)
    for line in out_lines:
        if not line.product_id:
            continue
        product = db.query(Product).filter(Product.id == line.product_id).first()
        if not product:
            continue
        
        qty = Decimal(str(line.quantity or 0))
        cost_per_unit = _get_cost_per_unit_by_basis(
            db, business_id, product, line, calculation_basis,
            document.document_date, line.warehouse_id
        )
        total_materials_cost += qty * cost_per_unit
    
    # دریافت هزینه عملیات از extra_info
    extra_info = document.extra_info or {}
    operations_total = Decimal(str(extra_info.get("production_operations_total", 0) or 0))
    
    # هزینه کل تولید
    total_production_cost = total_materials_cost + operations_total
    
    # محاسبه سود برای محصولات نهایی (در صورت فروش)
    # برای فاکتور تولید، معمولاً محصول نهایی به انبار اضافه می‌شود
    # سود زمانی محاسبه می‌شود که محصول نهایی در فاکتور فروش فروخته شود
    # اما می‌توان سود بر اساس قیمت فروش پایه محصول محاسبه کرد
    
    total_gross_profit = Decimal(0)
    total_sales = Decimal(0)
    line_profits = []
    
    for line in in_lines:
        if not line.product_id:
            continue
        
        product = db.query(Product).filter(Product.id == line.product_id).first()
        if not product:
            continue
        
        qty = Decimal(str(line.quantity or 0))
        
        # استفاده از قیمت فروش پایه محصول (در صورت وجود)
        unit_price = Decimal(str(product.base_sales_price or 0))
        sales_amount = qty * unit_price
        
        # توزیع هزینه تولید بر اساس تعداد
        if len(in_lines) > 0:
            line_cost = (total_production_cost / len(in_lines)) if len(in_lines) > 0 else Decimal(0)
        else:
            line_cost = Decimal(0)
        
        line_gross_profit = sales_amount - line_cost
        line_gross_profit_percent = (line_gross_profit / sales_amount * 100) if sales_amount > 0 else Decimal(0)
        
        total_gross_profit += line_gross_profit
        total_sales += sales_amount
        
        line_profits.append({
            "line_id": line.id,
            "product_id": product.id,
            "product_code": product.code,
            "product_name": product.name,
            "quantity": float(qty),
            "unit_price": float(unit_price),
            "cost_per_unit": float(line_cost / qty) if qty > 0 else 0,
            "sales_amount": float(sales_amount),
            "total_cost": float(line_cost),
            "gross_profit": float(line_gross_profit),
            "gross_profit_percent": float(line_gross_profit_percent),
            "net_profit": float(line_gross_profit),  # در صورت عدم وجود overhead
            "net_profit_percent": float(line_gross_profit_percent),
            "overhead": 0.0
        })
    
    # محاسبه هزینه سربار اضافی
    total_overhead = Decimal(0)
    if include_overhead and overhead_type != "production_overhead":
        # هزینه سربار اضافی (غیر از هزینه عملیات که قبلاً محاسبه شد)
        total_overhead = _calculate_overhead_cost(
            db, business_id, document.id, total_production_cost,
            overhead_type, overhead_percent
        )
    
    total_net_profit = total_gross_profit - total_overhead
    
    gross_profit_percent = (total_gross_profit / total_sales * 100) if total_sales > 0 else Decimal(0)
    net_profit_percent = (total_net_profit / total_sales * 100) if total_sales > 0 else Decimal(0)
    
    result = {
        "total_overhead": float(total_overhead),
        "line_profits": line_profits
    }
    
    if calculation_type in ["gross", "both"]:
        result["gross_profit"] = float(total_gross_profit)
        result["gross_profit_percent"] = float(gross_profit_percent)
    
    if calculation_type in ["net", "both"]:
        result["net_profit"] = float(total_net_profit)
        result["net_profit_percent"] = float(net_profit_percent)
    
    return result


def _empty_profit_response() -> Dict[str, Any]:
    """پاسخ خالی برای سود"""
    return {
        "gross_profit": 0.0,
        "net_profit": 0.0,
        "gross_profit_percent": 0.0,
        "net_profit_percent": 0.0,
        "total_profit": 0.0,
        "total_profit_percent": 0.0,
        "total_overhead": 0.0,
        "line_profits": []
    }
```

#### اضافه کردن سود به Response:

**Invoice Response Schema** (`hesabixAPI/adapters/api/v1/schema_models/invoice.py`):
```python
class InvoiceResponse(BaseModel):
    # ... فیلدهای موجود ...
    # سود ناخالص
    gross_profit: Optional[Decimal] = Field(None, description="سود ناخالص فاکتور")
    gross_profit_percent: Optional[Decimal] = Field(None, description="درصد سود ناخالص")
    # سود خالص
    net_profit: Optional[Decimal] = Field(None, description="سود خالص فاکتور")
    net_profit_percent: Optional[Decimal] = Field(None, description="درصد سود خالص")
    # برای سازگاری با کد قدیم
    total_profit: Optional[Decimal] = Field(None, description="سود کل فاکتور (ناخالص یا خالص بر اساس تنظیمات)")
    total_profit_percent: Optional[Decimal] = Field(None, description="درصد سود کل")
    # هزینه‌های سربار
    total_overhead: Optional[Decimal] = Field(None, description="هزینه‌های سربار")
    # سود هر ردیف
    line_profits: Optional[List[Dict[str, Any]]] = Field(None, description="سود هر ردیف")
```

**در Invoice Service** - هنگام ساخت response:
```python
# محاسبه سود
profit_data = _calculate_invoice_profit(
    db, 
    business_id, 
    document.id,
    business.invoice_profit_calculation_method or "automatic",
    business.invoice_profit_calculation_basis or "purchase_price",
    business.invoice_profit_include_overhead or False,
    business.invoice_profit_overhead_type or "none",
    Decimal(str(business.invoice_profit_overhead_percent or 0)) if business.invoice_profit_overhead_percent else None,
    business.invoice_profit_calculation_type or "gross"
)

# اضافه کردن به response
if "gross_profit" in profit_data:
    response["gross_profit"] = profit_data["gross_profit"]
    response["gross_profit_percent"] = profit_data["gross_profit_percent"]
if "net_profit" in profit_data:
    response["net_profit"] = profit_data["net_profit"]
    response["net_profit_percent"] = profit_data["net_profit_percent"]
if "total_profit" in profit_data:
    response["total_profit"] = profit_data["total_profit"]
    response["total_profit_percent"] = profit_data["total_profit_percent"]
response["total_overhead"] = profit_data.get("total_overhead", 0.0)
response["line_profits"] = profit_data.get("line_profits", [])
```

### 3. UI - تنظیمات کسب و کار

#### اضافه کردن بخش تنظیمات محاسبه سود:

**Business Info Settings Page** (`hesabixUI/hesabix_ui/lib/pages/business/business_info_settings_page.dart`):

```dart
// اضافه کردن state variables
String? _invoiceProfitCalculationMethod; // 'automatic', 'manual', 'disabled'
String? _invoiceProfitCalculationBasis; // 'purchase_price', 'cost_price', 'average_cost', 'fifo', 'lifo', etc.
bool _invoiceProfitIncludeOverhead = false;
String? _invoiceProfitOverheadType; // 'none', 'production_overhead', 'all_overhead', 'custom_percent'
double? _invoiceProfitOverheadPercent;
String? _invoiceProfitCalculationType; // 'gross', 'net', 'both'

// در _loadData:
_invoiceProfitCalculationMethod = resp.invoiceProfitCalculationMethod ?? 'automatic';
_invoiceProfitCalculationBasis = resp.invoiceProfitCalculationBasis ?? 'purchase_price';
_invoiceProfitIncludeOverhead = resp.invoiceProfitIncludeOverhead ?? false;
_invoiceProfitOverheadType = resp.invoiceProfitOverheadType ?? 'none';
_invoiceProfitOverheadPercent = resp.invoiceProfitOverheadPercent?.toDouble();
_invoiceProfitCalculationType = resp.invoiceProfitCalculationType ?? 'gross';

// در _buildUpdatePayload:
if (_invoiceProfitCalculationMethod != null) {
  payload['invoice_profit_calculation_method'] = _invoiceProfitCalculationMethod;
}
if (_invoiceProfitCalculationBasis != null) {
  payload['invoice_profit_calculation_basis'] = _invoiceProfitCalculationBasis;
}
payload['invoice_profit_include_overhead'] = _invoiceProfitIncludeOverhead;
if (_invoiceProfitOverheadType != null) {
  payload['invoice_profit_overhead_type'] = _invoiceProfitOverheadType;
}
if (_invoiceProfitOverheadPercent != null) {
  payload['invoice_profit_overhead_percent'] = _invoiceProfitOverheadPercent;
}
if (_invoiceProfitCalculationType != null) {
  payload['invoice_profit_calculation_type'] = _invoiceProfitCalculationType;
}

// اضافه کردن UI widget
Widget _buildProfitCalculationSettings() {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تنظیمات محاسبه سود فاکتور',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          // روش محاسبه
          DropdownButtonFormField<String>(
            value: _invoiceProfitCalculationMethod,
            decoration: const InputDecoration(
              labelText: 'روش محاسبه سود',
              helperText: 'نحوه محاسبه سود فاکتورها را انتخاب کنید',
            ),
            items: const [
              DropdownMenuItem(value: 'automatic', child: Text('خودکار')),
              DropdownMenuItem(value: 'manual', child: Text('دستی')),
              DropdownMenuItem(value: 'disabled', child: Text('غیرفعال')),
            ],
            onChanged: (value) {
              setState(() {
                _invoiceProfitCalculationMethod = value;
              });
            },
          ),
          const SizedBox(height: 16),
          // مبنای محاسبه (فقط اگر روش automatic باشد)
          if (_invoiceProfitCalculationMethod == 'automatic')
            DropdownButtonFormField<String>(
              value: _invoiceProfitCalculationBasis,
              decoration: const InputDecoration(
                labelText: 'مبنای محاسبه هزینه',
                helperText: 'مبنای محاسبه هزینه برای سود را انتخاب کنید',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'purchase_price',
                  child: Text('قیمت خرید محصول'),
                ),
                DropdownMenuItem(
                  value: 'cost_price',
                  child: Text('قیمت تمام شده (از انبار)'),
                ),
                DropdownMenuItem(
                  value: 'actual_cost',
                  child: Text('هزینه واقعی'),
                ),
                DropdownMenuItem(
                  value: 'average_cost',
                  child: Text('میانگین قیمت خرید'),
                ),
                DropdownMenuItem(
                  value: 'fifo',
                  child: Text('FIFO (اول ورود، اول خروج)'),
                ),
                DropdownMenuItem(
                  value: 'lifo',
                  child: Text('LIFO (آخر ورود، اول خروج)'),
                ),
                DropdownMenuItem(
                  value: 'weighted_average',
                  child: Text('میانگین وزنی'),
                ),
                DropdownMenuItem(
                  value: 'standard_cost',
                  child: Text('هزینه استاندارد'),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _invoiceProfitCalculationBasis = value;
                });
              },
            ),
          const SizedBox(height: 16),
          // نوع محاسبه سود
          if (_invoiceProfitCalculationMethod == 'automatic')
            DropdownButtonFormField<String>(
              value: _invoiceProfitCalculationType,
              decoration: const InputDecoration(
                labelText: 'نوع محاسبه سود',
                helperText: 'نوع سود مورد نظر را انتخاب کنید',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'gross',
                  child: Text('سود ناخالص (بدون هزینه‌ها)'),
                ),
                DropdownMenuItem(
                  value: 'net',
                  child: Text('سود خالص (با هزینه‌ها)'),
                ),
                DropdownMenuItem(
                  value: 'both',
                  child: Text('هر دو (ناخالص و خالص)'),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _invoiceProfitCalculationType = value;
                });
              },
            ),
          const SizedBox(height: 16),
          // شامل کردن هزینه‌های سربار
          if (_invoiceProfitCalculationMethod == 'automatic' && 
              _invoiceProfitCalculationType != 'gross')
            CheckboxListTile(
              title: const Text('شامل کردن هزینه‌های سربار'),
              subtitle: const Text('آیا هزینه‌های سربار در محاسبه سود خالص لحاظ شود؟'),
              value: _invoiceProfitIncludeOverhead,
              onChanged: (value) {
                setState(() {
                  _invoiceProfitIncludeOverhead = value ?? false;
                });
              },
            ),
          // نوع هزینه‌های سربار
          if (_invoiceProfitCalculationMethod == 'automatic' && 
              _invoiceProfitIncludeOverhead)
            ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _invoiceProfitOverheadType,
                decoration: const InputDecoration(
                  labelText: 'نوع هزینه‌های سربار',
                  helperText: 'نوع هزینه‌های سربار را انتخاب کنید',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'none',
                    child: Text('بدون سربار'),
                  ),
                  DropdownMenuItem(
                    value: 'production_overhead',
                    child: Text('فقط سربار تولید'),
                  ),
                  DropdownMenuItem(
                    value: 'all_overhead',
                    child: Text('تمام هزینه‌های سربار'),
                  ),
                  DropdownMenuItem(
                    value: 'custom_percent',
                    child: Text('درصد سفارشی'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _invoiceProfitOverheadType = value;
                  });
                },
              ),
              // درصد سفارشی
              if (_invoiceProfitOverheadType == 'custom_percent')
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: TextFormField(
                    initialValue: _invoiceProfitOverheadPercent?.toString(),
                    decoration: const InputDecoration(
                      labelText: 'درصد هزینه سربار',
                      helperText: 'درصد هزینه سربار از هزینه کل (0-100)',
                      suffixText: '%',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (value) {
                      setState(() {
                        _invoiceProfitOverheadPercent = double.tryParse(value);
                      });
                    },
                    validator: (value) {
                      if (_invoiceProfitOverheadType == 'custom_percent' && 
                          (value == null || value.isEmpty)) {
                        return 'لطفاً درصد را وارد کنید';
                      }
                      final percent = double.tryParse(value ?? '');
                      if (percent != null && (percent < 0 || percent > 100)) {
                        return 'درصد باید بین 0 تا 100 باشد';
                      }
                      return null;
                    },
                  ),
                ),
            ],
        ],
      ),
    ),
  );
}
```

### 4. UI - لیست فاکتورها

#### اضافه کردن ستون سود:

**InvoiceListItem Model** (`hesabixUI/hesabix_ui/lib/models/invoice_list_item.dart`):
```dart
class InvoiceListItem {
  // ... فیلدهای موجود ...
  final double? totalProfit;
  final double? totalProfitPercent;

  const InvoiceListItem({
    // ... پارامترهای موجود ...
    this.totalProfit,
    this.totalProfitPercent,
  });

  factory InvoiceListItem.fromJson(Map<String, dynamic> json) {
    return InvoiceListItem(
      // ... فیلدهای موجود ...
      totalProfit: _toDouble(json['total_profit']),
      totalProfitPercent: _toDouble(json['total_profit_percent']),
    );
  }
}
```

**Invoices List Page** (`hesabixUI/hesabix_ui/lib/pages/business/invoices_list_page.dart`):
```dart
// در _buildTableConfig - اضافه کردن ستون سود
CustomColumn(
  'total_profit',
  'سود',
  sortable: true,
  searchable: false,
  width: ColumnWidth.medium,
  builder: (dynamic item, int index) {
    final invoice = item as InvoiceListItem;
    if (invoice.totalProfit == null) {
      return const Text('-');
    }
    final profit = invoice.totalProfit!;
    final profitPercent = invoice.totalProfitPercent ?? 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatWithThousands(profit),
              style: TextStyle(
                color: profit >= 0 ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (profitPercent != 0)
              Text(
                '${profitPercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  color: profit >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
          ],
        ),
      ],
    );
  },
),
```

### 5. UI - دیالوگ جزئیات فاکتور

#### اضافه کردن نمایش سود:

**Document Details Dialog** (`hesabixUI/hesabix_ui/lib/widgets/document/document_details_dialog.dart`):

```dart
// در _buildInfoTab - اضافه کردن بخش سود
Widget _buildProfitSection(ThemeData theme) {
  if (_document == null || !_document!.documentType.startsWith('invoice_sales')) {
    return const SizedBox.shrink();
  }
  
  final totalProfit = _rawDocumentData?['total_profit'] as num?;
  final totalProfitPercent = _rawDocumentData?['total_profit_percent'] as num?;
  
  if (totalProfit == null) {
    return const SizedBox.shrink();
  }
  
  final profit = totalProfit.toDouble();
  final profitPercent = totalProfitPercent?.toDouble() ?? 0;
  final isPositive = profit >= 0;
  
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isPositive ? Colors.green.shade50 : Colors.red.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: isPositive ? Colors.green.shade200 : Colors.red.shade200,
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'سود فاکتور:',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatWithThousands(profit),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
            if (profitPercent != 0)
              Text(
                '${profitPercent.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 14,
                  color: isPositive ? Colors.green.shade600 : Colors.red.shade600,
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

// در _buildProductsTab - اضافه کردن ستون سود در جدول کالاها
DataColumn(
  label: const Text('سود'),
  numeric: true,
),
// در DataRow:
DataCell(
  Builder(
    builder: (context) {
      final lineProfit = line['profit'] as num?;
      final lineProfitPercent = line['profit_percent'] as num?;
      if (lineProfit == null) {
        return const Text('-');
      }
      final profit = lineProfit.toDouble();
      final profitPercent = lineProfitPercent?.toDouble() ?? 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            formatWithThousands(profit),
            style: TextStyle(
              color: profit >= 0 ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (profitPercent != 0)
            Text(
              '${profitPercent.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 11,
                color: profit >= 0 ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
        ],
      );
    },
  ),
),
```

---

## 📝 مراحل پیاده‌سازی

### مرحله 1: Backend - دیتابیس و مدل‌ها
1. ✅ ایجاد migration برای اضافه کردن فیلدهای جدید به جدول `businesses`
2. ✅ به‌روزرسانی مدل `Business` در SQLAlchemy
3. ✅ به‌روزرسانی Schema های Pydantic (`BusinessUpdateRequest`, `BusinessResponse`)

### مرحله 2: Backend - منطق محاسبه سود
1. ✅ پیاده‌سازی تابع `_calculate_invoice_profit` در `invoice_service.py`
2. ✅ پیاده‌سازی تابع `_calculate_average_purchase_cost` برای محاسبه میانگین قیمت خرید
3. ✅ اضافه کردن محاسبه سود به response فاکتورها در endpoint های:
   - `GET /api/v1/invoices/{invoice_id}`
   - `GET /api/v1/invoices/business/{business_id}/search`
   - `POST /api/v1/invoices` (بعد از ایجاد)
   - `PUT /api/v1/invoices/{invoice_id}` (بعد از ویرایش)

### مرحله 3: Backend - API تنظیمات
1. ✅ به‌روزرسانی endpoint `PUT /api/v1/businesses/{business_id}` برای پذیرش فیلدهای جدید
2. ✅ به‌روزرسانی endpoint `GET /api/v1/businesses/{business_id}` برای برگرداندن فیلدهای جدید

### مرحله 4: Frontend - تنظیمات کسب و کار
1. ✅ به‌روزرسانی مدل `BusinessResponse` در Dart
2. ✅ اضافه کردن UI برای تنظیمات محاسبه سود در `business_info_settings_page.dart`
3. ✅ اضافه کردن state management برای فیلدهای جدید

### مرحله 5: Frontend - لیست فاکتورها
1. ✅ به‌روزرسانی مدل `InvoiceListItem` برای شامل کردن سود
2. ✅ اضافه کردن ستون سود به جدول لیست فاکتورها
3. ✅ فرمت کردن نمایش سود (مبلغ و درصد)

### مرحله 6: Frontend - دیالوگ جزئیات
1. ✅ اضافه کردن نمایش سود کل در تب اطلاعات
2. ✅ اضافه کردن ستون سود در جدول کالاها (تب کالاها)
3. ✅ استایل‌دهی مناسب برای نمایش سود مثبت/منفی

### مرحله 7: تست و اعتبارسنجی
1. ✅ تست محاسبه سود با روش‌های مختلف
2. ✅ تست نمایش در لیست و جزئیات
3. ✅ تست تغییر تنظیمات و تأثیر آن بر محاسبات
4. ✅ تست edge cases (فاکتور بدون محصول، محصول بدون قیمت خرید، و غیره)

---

## 🔄 جریان کار (Workflow)

### 1. تنظیمات اولیه
```
کاربر → تنظیمات کسب و کار → بخش محاسبه سود
  → انتخاب روش محاسبه (خودکار/دستی/غیرفعال)
  → انتخاب مبنای محاسبه (قیمت خرید/قیمت تمام شده/میانگین)
  → ذخیره تنظیمات
```

### 2. محاسبه سود هنگام ایجاد/ویرایش فاکتور
```
کاربر → ایجاد فاکتور فروش → اضافه کردن محصولات
  → Backend: محاسبه سود بر اساس تنظیمات
  → نمایش سود در UI (اگر روش خودکار باشد)
```

### 3. نمایش سود در لیست فاکتورها
```
کاربر → لیست فاکتورها
  → Backend: محاسبه سود برای هر فاکتور
  → نمایش ستون سود (مبلغ و درصد)
  → رنگ‌بندی: سبز برای سود مثبت، قرمز برای منفی
```

### 4. نمایش سود در جزئیات فاکتور
```
کاربر → کلیک روی فاکتور → دیالوگ جزئیات
  → تب اطلاعات: نمایش سود کل فاکتور
  → تب کالاها: نمایش سود هر ردیف
  → نمایش مبلغ و درصد سود
```

---

## ⚠️ نکات مهم

### 1. عملکرد (Performance)
- محاسبه سود برای لیست فاکتورها می‌تواند سنگین باشد
- **راه‌حل**: Cache کردن نتایج یا محاسبه lazy (فقط هنگام نمایش)
- **بهینه‌سازی**: محاسبه سود فقط برای فاکتورهای فروش

### 2. دقت محاسبات
- استفاده از `Decimal` برای محاسبات مالی
- جلوگیری از خطاهای گرد کردن
- مدیریت مقادیر null و صفر

### 3. سازگاری با داده‌های موجود
- فاکتورهای قدیمی که قبل از این قابلیت ایجاد شده‌اند
- **راه‌حل**: محاسبه سود به صورت on-demand یا با default values

### 4. امنیت و دسترسی
- بررسی دسترسی کاربر به تنظیمات کسب و کار
- بررسی دسترسی به مشاهده سود (ممکن است حساس باشد)

### 5. چند ارزی (Multi-currency)
- محاسبه سود باید با ارز فاکتور هماهنگ باشد
- تبدیل ارز در صورت نیاز

---

## 📊 مثال‌های استفاده

### مثال 1: تنظیمات پیش‌فرض (بازرگانی)
```
روش محاسبه: خودکار
مبنای محاسبه: قیمت خرید محصول
نوع محاسبه: سود ناخالص
شامل هزینه سربار: خیر
```

### مثال 2: تنظیمات برای مرکز تولیدی
```
روش محاسبه: خودکار
مبنای محاسبه: FIFO (اول ورود، اول خروج)
نوع محاسبه: هر دو (ناخالص و خالص)
شامل هزینه سربار: بله
نوع سربار: تمام هزینه‌های سربار
```

### مثال 3: فاکتور فروش ساده
```
محصول: لپ‌تاپ
قیمت خرید: 10,000,000 تومان
قیمت فروش: 12,000,000 تومان
تعداد: 2
سود ناخالص هر واحد: 2,000,000 تومان
سود ناخالص کل: 4,000,000 تومان
درصد سود ناخالص: 16.67%
```

### مثال 4: فاکتور فروش با هزینه سربار
```
محصول: موبایل
قیمت خرید: 5,000,000 تومان
قیمت فروش: 6,000,000 تومان
تعداد: 1
هزینه سربار (10%): 500,000 تومان
سود ناخالص: 1,000,000 تومان
سود خالص: 500,000 تومان
درصد سود ناخالص: 16.67%
درصد سود خالص: 8.33%
```

### مثال 5: فاکتور تولید
```
مواد اولیه:
  - ماده A: 2,000,000 تومان
  - ماده B: 1,500,000 تومان
  مجموع مواد: 3,500,000 تومان

هزینه عملیات: 1,000,000 تومان
هزینه کل تولید: 4,500,000 تومان

محصول نهایی:
  - تعداد: 10 عدد
  - قیمت فروش هر واحد: 600,000 تومان
  - مبلغ فروش کل: 6,000,000 تومان

سود ناخالص: 1,500,000 تومان
درصد سود ناخالص: 25%
```

### مثال 6: فاکتور با روش FIFO
```
موجودی انبار:
  - خرید اول: 100 عدد × 10,000 تومان = 1,000,000 تومان
  - خرید دوم: 50 عدد × 12,000 تومان = 600,000 تومان

فروش: 120 عدد
هزینه با FIFO: (100 × 10,000) + (20 × 12,000) = 1,240,000 تومان
قیمت فروش: 120 × 15,000 = 1,800,000 تومان
سود: 560,000 تومان
```

### مثال 7: فاکتور با روش LIFO
```
موجودی انبار (همان مثال قبل):
فروش: 120 عدد
هزینه با LIFO: (50 × 12,000) + (70 × 10,000) = 1,300,000 تومان
قیمت فروش: 1,800,000 تومان
سود: 500,000 تومان
```

---

## 🎨 UI/UX پیشنهادی

### رنگ‌بندی
- **سود مثبت**: سبز (`Colors.green`)
- **سود منفی/زیان**: قرمز (`Colors.red`)
- **بدون سود**: خاکستری (`Colors.grey`)

### نمایش
- **مبلغ سود**: با فرمت هزارگان (مثال: `1,234,567`)
- **درصد سود**: با یک یا دو رقم اعشار (مثال: `12.5%`)
- **نمایش ترکیبی**: مبلغ در خط اول، درصد در خط دوم (کوچکتر)

### آیکون‌ها
- سود مثبت: 📈 یا ✅
- سود منفی: 📉 یا ⚠️

---

## ✅ چک‌لیست پیاده‌سازی

### Backend
- [ ] Migration برای فیلدهای جدید
- [ ] به‌روزرسانی مدل Business
- [ ] به‌روزرسانی Schema ها
- [ ] پیاده‌سازی تابع محاسبه سود
- [ ] اضافه کردن سود به Invoice Response
- [ ] تست واحد (Unit Tests)
- [ ] تست یکپارچگی (Integration Tests)

### Frontend
- [ ] به‌روزرسانی مدل BusinessResponse
- [ ] UI تنظیمات در صفحه کسب و کار
- [ ] به‌روزرسانی مدل InvoiceListItem
- [ ] ستون سود در لیست فاکتورها
- [ ] نمایش سود در دیالوگ جزئیات
- [ ] استایل‌دهی و رنگ‌بندی
- [ ] تست UI

### مستندات
- [ ] به‌روزرسانی API Documentation
- [ ] راهنمای کاربر (User Guide)
- [ ] Changelog

---

## 🔮 قابلیت‌های آینده (Future Enhancements)

1. **گزارش سود و زیان**: گزارش جامع سود فاکتورها
2. **تحلیل سود**: نمودارها و آمار سود
3. **هدف سود**: تنظیم هدف سود و هشدار در صورت عدم دستیابی
4. **مقایسه سود**: مقایسه سود بین دوره‌های مختلف
5. **سود بر اساس دسته‌بندی**: تحلیل سود بر اساس دسته‌بندی محصولات
6. **هزینه استاندارد محصول**: تعریف هزینه استاندارد برای هر محصول
7. **تحلیل انحراف هزینه**: مقایسه هزینه واقعی با هزینه استاندارد
8. **تخصیص هزینه سربار پیشرفته**: تخصیص هزینه‌های سربار بر اساس معیارهای مختلف (ساعت کار، تعداد، وزن، و غیره)
9. **گزارش سودآوری محصول**: گزارش سودآوری هر محصول به صورت جداگانه
10. **مقایسه روش‌های محاسبه**: امکان مقایسه نتایج روش‌های مختلف محاسبه سود

---

## 📚 منابع و مراجع

- فایل‌های مرتبط:
  - `hesabixAPI/adapters/db/models/business.py`
  - `hesabixAPI/adapters/api/v1/schemas.py`
  - `hesabixAPI/app/services/invoice_service.py`
  - `hesabixUI/hesabix_ui/lib/pages/business/business_info_settings_page.dart`
  - `hesabixUI/hesabix_ui/lib/pages/business/invoices_list_page.dart`
  - `hesabixUI/hesabix_ui/lib/widgets/document/document_details_dialog.dart`

---

---

## 📝 خلاصه تغییرات و بهبودها

### تغییرات نسبت به نسخه اولیه:

#### 1. روش‌های محاسبه هزینه (از 3 به 8 روش)
- ✅ اضافه شدن **FIFO** (First In First Out)
- ✅ اضافه شدن **LIFO** (Last In First Out)
- ✅ اضافه شدن **Weighted Average** (میانگین وزنی)
- ✅ اضافه شدن **Standard Cost** (هزینه استاندارد)
- ✅ اضافه شدن **Actual Cost** (هزینه واقعی)

#### 2. پشتیبانی از مراکز تولیدی
- ✅ محاسبه سود برای فاکتورهای تولید (`invoice_production`)
- ✅ در نظر گیری هزینه مواد اولیه
- ✅ در نظر گیری هزینه عملیات (`production_operations_total`)
- ✅ تخصیص هزینه تولید به محصولات نهایی

#### 3. هزینه‌های سربار (Overhead)
- ✅ گزینه شامل/عدم شامل هزینه سربار
- ✅ 4 نوع هزینه سربار: none, production_overhead, all_overhead, custom_percent
- ✅ محاسبه درصد سفارشی برای هزینه سربار
- ✅ محاسبه سود ناخالص و خالص

#### 4. نوع محاسبه سود
- ✅ سود ناخالص (Gross Profit) - بدون هزینه‌ها
- ✅ سود خالص (Net Profit) - با هزینه‌ها
- ✅ هر دو (Both) - نمایش همزمان ناخالص و خالص

#### 5. UI و تنظیمات
- ✅ رابط کاربری کامل برای تمام تنظیمات
- ✅ اعتبارسنجی ورودی‌ها
- ✅ راهنمای کاربری برای هر گزینه

### مزایای نسخه جدید:

1. **انعطاف‌پذیری بیشتر**: پشتیبانی از انواع مختلف کسب و کار
2. **دقت بالاتر**: روش‌های مختلف محاسبه برای دقت بیشتر
3. **تحلیل بهتر**: نمایش سود ناخالص و خالص برای تحلیل بهتر
4. **قابل استفاده برای تولیدی**: پشتیبانی کامل از فاکتورهای تولید
5. **مدیریت هزینه**: کنترل کامل بر هزینه‌های سربار

---

**تاریخ ایجاد**: 2024
**آخرین به‌روزرسانی**: 2024 (نسخه 2.0 - با پشتیبانی از تولیدی و هزینه‌های سربار)
**وضعیت**: در انتظار پیاده‌سازی

