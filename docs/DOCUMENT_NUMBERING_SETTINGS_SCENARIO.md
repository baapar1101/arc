# سناریو: تنظیمات شماره‌گذاری اسناد

## خلاصه
این سناریو نحوه پیاده‌سازی صفحه تنظیمات شماره‌گذاری اسناد را در بخش تنظیمات کسب و کار توضیح می‌دهد. کاربران با دسترسی مناسب می‌توانند نحوه شماره‌گذاری هر نوع سند را به صورت جداگانه تعیین کنند و در صورت عدم تعیین، از حالت پیش‌فرض استفاده می‌شود.

---

## 1. ساختار دیتابیس (Backend)

### 1.1. ایجاد جدول `business_document_numbering_settings`

```sql
CREATE TABLE business_document_numbering_settings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    business_id INTEGER NOT NULL,
    document_type VARCHAR(50) NOT NULL,  -- نوع سند (invoice_sales, receipt, payment, transfer, ...)
    
    -- تنظیمات شماره‌گذاری
    prefix VARCHAR(20),                  -- پیشوند (مثلاً INV, RC, PY, TR)
    include_date BOOLEAN DEFAULT 1,      -- آیا تاریخ در شماره باشد؟
    calendar_type VARCHAR(10) DEFAULT 'gregorian',  -- نوع تقویم: gregorian (میلادی) یا jalali (شمسی)
    date_format VARCHAR(20),             -- فرمت تاریخ (YYYYMMDD, YYMMDD, YYYY-MM-DD, YYYY/MM/DD, ...)
    separator VARCHAR(5) DEFAULT '-',    -- جداکننده (مثلاً -, _, /)
    start_number INTEGER DEFAULT 1,       -- شماره شروع
    number_padding INTEGER DEFAULT 4,    -- تعداد صفرهای پیش‌رو (4 = 0001, 5 = 00001)
    reset_period VARCHAR(20),            -- دوره ریست: daily, monthly, yearly, never
    
    -- تنظیمات پیشرفته
    custom_format VARCHAR(100),           -- فرمت سفارشی (مثلاً {prefix}-{date}-{number})
    is_active BOOLEAN DEFAULT 1,         -- فعال/غیرفعال
    
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(business_id, document_type),
    FOREIGN KEY (business_id) REFERENCES businesses(id) ON DELETE CASCADE
);
```

### 1.2. انواع اسناد پشتیبانی شده

- **فاکتورها:**
  - `invoice_sales` - فاکتور فروش
  - `invoice_sales_return` - برگشت از فروش
  - `invoice_purchase` - فاکتور خرید
  - `invoice_purchase_return` - برگشت از خرید
  - `invoice_direct_consumption` - مصرف مستقیم
  - `invoice_production` - تولید
  - `invoice_waste` - ضایعات

- **اسناد مالی:**
  - `receipt` - دریافت
  - `payment` - پرداخت
  - `transfer` - انتقال
  - `expense` - هزینه
  - `income` - درآمد
  - `manual` - سند دستی
  - `opening_balance` - تراز افتتاحیه

- **چک:**
  - `check_endorse` - پاسخگویی چک
  - `check_clear` - وصول چک
  - `check_pay` - پرداخت چک
  - `check_return` - برگشت چک
  - `check_bounce` - برگشت خوردن چک
  - `check_deposit` - واریز به حساب
  - `check_delete` - حذف چک

---

## 2. Backend API

### 2.1. مدل SQLAlchemy

**مسیر:** `hesabixAPI/adapters/db/models/document_numbering.py`

```python
from sqlalchemy import String, Integer, Boolean, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from adapters.db.session import Base

class BusinessDocumentNumberingSetting(Base):
    __tablename__ = "business_document_numbering_settings"
    __table_args__ = (
        UniqueConstraint('business_id', 'document_type', 
                        name='uq_doc_numbering_business_type'),
    )
    
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), 
        nullable=False, index=True
    )
    document_type: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    
    prefix: Mapped[str | None] = mapped_column(String(20), nullable=True)
    include_date: Mapped[bool] = mapped_column(Boolean, default=True, server_default="1")
    calendar_type: Mapped[str] = mapped_column(String(10), default="gregorian", server_default="gregorian")
    date_format: Mapped[str | None] = mapped_column(String(20), nullable=True)
    separator: Mapped[str] = mapped_column(String(5), default="-", server_default="-")
    start_number: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    number_padding: Mapped[int] = mapped_column(Integer, default=4, server_default="4")
    reset_period: Mapped[str | None] = mapped_column(String(20), nullable=True)
    
    custom_format: Mapped[str | None] = mapped_column(String(100), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="1")
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )
    
    business = relationship("Business", backref="document_numbering_settings")
```

### 2.2. Schema (Pydantic)

**مسیر:** `hesabixAPI/adapters/api/v1/schemas.py`

```python
class DocumentNumberingSettingRequest(BaseModel):
    document_type: str
    prefix: Optional[str] = None
    include_date: bool = True
    calendar_type: str = "gregorian"  # gregorian (میلادی) یا jalali (شمسی)
    date_format: Optional[str] = None
    separator: str = "-"
    start_number: int = 1
    number_padding: int = 4
    reset_period: Optional[str] = None  # daily, monthly, yearly, never
    custom_format: Optional[str] = None
    is_active: bool = True

class DocumentNumberingSettingResponse(BaseModel):
    id: int
    business_id: int
    document_type: str
    prefix: Optional[str]
    include_date: bool
    calendar_type: str
    date_format: Optional[str]
    separator: str
    start_number: int
    number_padding: int
    reset_period: Optional[str]
    custom_format: Optional[str]
    is_active: bool
    created_at: datetime
    updated_at: datetime
```

### 2.3. API Endpoints

**مسیر:** `hesabixAPI/adapters/api/v1/document_numbering.py`

```python
@router.get("/businesses/{business_id}/document-numbering-settings")
async def get_document_numbering_settings(
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    دریافت تمام تنظیمات شماره‌گذاری اسناد یک کسب و کار
    """
    # بررسی دسترسی: settings.join
    if not ctx.has_business_permission("settings", "join"):
        raise HTTPException(403, "دسترسی غیرمجاز")
    
    settings = db.query(BusinessDocumentNumberingSetting).filter(
        BusinessDocumentNumberingSetting.business_id == business_id
    ).all()
    
    return [DocumentNumberingSettingResponse.from_orm(s) for s in settings]

@router.get("/businesses/{business_id}/document-numbering-settings/{document_type}")
async def get_document_numbering_setting(
    business_id: int,
    document_type: str,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    دریافت تنظیمات شماره‌گذاری برای یک نوع سند خاص
    """
    if not ctx.has_business_permission("settings", "join"):
        raise HTTPException(403, "دسترسی غیرمجاز")
    
    setting = db.query(BusinessDocumentNumberingSetting).filter(
        and_(
            BusinessDocumentNumberingSetting.business_id == business_id,
            BusinessDocumentNumberingSetting.document_type == document_type
        )
    ).first()
    
    if not setting:
        # برگرداندن تنظیمات پیش‌فرض
        return _get_default_setting(document_type)
    
    return DocumentNumberingSettingResponse.from_orm(setting)

@router.post("/businesses/{business_id}/document-numbering-settings")
async def create_document_numbering_setting(
    business_id: int,
    data: DocumentNumberingSettingRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    ایجاد یا به‌روزرسانی تنظیمات شماره‌گذاری
    """
    if not ctx.has_business_permission("settings", "join"):
        raise HTTPException(403, "دسترسی غیرمجاز")
    
    existing = db.query(BusinessDocumentNumberingSetting).filter(
        and_(
            BusinessDocumentNumberingSetting.business_id == business_id,
            BusinessDocumentNumberingSetting.document_type == data.document_type
        )
    ).first()
    
    if existing:
        # به‌روزرسانی
        for key, value in data.dict(exclude_unset=True).items():
            setattr(existing, key, value)
        existing.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(existing)
        return DocumentNumberingSettingResponse.from_orm(existing)
    else:
        # ایجاد جدید
        new_setting = BusinessDocumentNumberingSetting(
            business_id=business_id,
            **data.dict()
        )
        db.add(new_setting)
        db.commit()
        db.refresh(new_setting)
        return DocumentNumberingSettingResponse.from_orm(new_setting)

@router.delete("/businesses/{business_id}/document-numbering-settings/{document_type}")
async def delete_document_numbering_setting(
    business_id: int,
    document_type: str,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    حذف تنظیمات شماره‌گذاری (بازگشت به پیش‌فرض)
    """
    if not ctx.has_business_permission("settings", "join"):
        raise HTTPException(403, "دسترسی غیرمجاز")
    
    setting = db.query(BusinessDocumentNumberingSetting).filter(
        and_(
            BusinessDocumentNumberingSetting.business_id == business_id,
            BusinessDocumentNumberingSetting.document_type == document_type
        )
    ).first()
    
    if setting:
        db.delete(setting)
        db.commit()
    
    return {"message": "تنظیمات حذف شد و به حالت پیش‌فرض بازگشت"}

def _get_default_setting(document_type: str) -> dict:
    """
    برگرداندن تنظیمات پیش‌فرض برای هر نوع سند
    """
    defaults = {
        "invoice_sales": {"prefix": "INV", "include_date": True, "calendar_type": "gregorian", "date_format": "YYYYMMDD"},
        "invoice_sales_return": {"prefix": "INV-RET", "include_date": True, "calendar_type": "gregorian", "date_format": "YYYYMMDD"},
        "receipt": {"prefix": "RC", "include_date": True, "calendar_type": "gregorian", "date_format": "YYYYMMDD"},
        "payment": {"prefix": "PY", "include_date": True, "calendar_type": "gregorian", "date_format": "YYYYMMDD"},
        "transfer": {"prefix": "TR", "include_date": True, "calendar_type": "gregorian", "date_format": "YYYYMMDD"},
        # ... سایر انواع
    }
    
    default = defaults.get(document_type, {
        "prefix": "DOC",
        "include_date": True,
        "calendar_type": "gregorian",
        "date_format": "YYYYMMDD",
        "separator": "-",
        "start_number": 1,
        "number_padding": 4,
        "reset_period": "never"
    })
    
    return default
```

### 2.4. سرویس تولید شماره سند

**مسیر:** `hesabixAPI/app/services/document_numbering_service.py`

```python
from app.core.calendar import CalendarConverter
from datetime import datetime, date

def generate_document_code(
    db: Session,
    business_id: int,
    document_type: str,
    document_date: date
) -> str:
    """
    تولید شماره سند بر اساس تنظیمات کسب و کار یا پیش‌فرض
    """
    # دریافت تنظیمات از دیتابیس
    setting = db.query(BusinessDocumentNumberingSetting).filter(
        and_(
            BusinessDocumentNumberingSetting.business_id == business_id,
            BusinessDocumentNumberingSetting.document_type == document_type,
            BusinessDocumentNumberingSetting.is_active == True
        )
    ).first()
    
    # اگر تنظیمات وجود نداشت، از پیش‌فرض استفاده کن
    if not setting:
        setting = _get_default_setting_for_type(document_type)
    
    # تولید شماره بر اساس تنظیمات
    prefix = setting.prefix or "DOC"
    separator = setting.separator or "-"
    
    # بخش تاریخ
    date_part = ""
    if setting.include_date:
        date_format = setting.date_format or "YYYYMMDD"
        calendar_type = setting.calendar_type or "gregorian"
        date_part = _format_date(document_date, date_format, calendar_type)
    
    # بخش شماره
    number_part = _get_next_number(
        db, business_id, document_type, 
        setting.start_number, setting.number_padding,
        setting.reset_period, document_date,
        setting.calendar_type or "gregorian"
    )
    
    # ترکیب نهایی
    if date_part:
        return f"{prefix}{separator}{date_part}{separator}{number_part}"
    else:
        return f"{prefix}{separator}{number_part}"

def _format_date(document_date: date, date_format: str, calendar_type: str) -> str:
    """
    فرمت‌بندی تاریخ بر اساس نوع تقویم (شمسی یا میلادی)
    
    Args:
        document_date: تاریخ میلادی سند
        date_format: فرمت مورد نظر (مثلاً YYYYMMDD, YYYY/MM/DD)
        calendar_type: نوع تقویم ('gregorian' یا 'jalali')
    
    Returns:
        رشته فرمت‌بندی شده تاریخ
    """
    # تبدیل date به datetime
    dt = datetime.combine(document_date, datetime.min.time())
    
    # تبدیل به تقویم مورد نظر
    if calendar_type == "jalali":
        cal_data = CalendarConverter.to_jalali(dt)
        year = cal_data["year"]
        month = cal_data["month"]
        day = cal_data["day"]
    else:  # gregorian
        cal_data = CalendarConverter.to_gregorian(dt)
        year = cal_data["year"]
        month = cal_data["month"]
        day = cal_data["day"]
    
    # فرمت‌بندی بر اساس الگو
    formatted = date_format
    
    # جایگزینی سال
    formatted = formatted.replace("YYYY", f"{year:04d}")
    formatted = formatted.replace("YY", f"{year % 100:02d}")
    
    # جایگزینی ماه
    formatted = formatted.replace("MM", f"{month:02d}")
    formatted = formatted.replace("M", f"{month}")
    
    # جایگزینی روز
    formatted = formatted.replace("DD", f"{day:02d}")
    formatted = formatted.replace("D", f"{day}")
    
    return formatted

def _get_next_number(
    db: Session,
    business_id: int,
    document_type: str,
    start_number: int,
    padding: int,
    reset_period: str | None,
    document_date: date,
    calendar_type: str = "gregorian"
) -> str:
    """
    دریافت شماره بعدی بر اساس دوره ریست
    
    نکته: اگر calendar_type == "jalali" باشد، باید محدوده را بر اساس تقویم شمسی محاسبه کنیم
    """
    from app.core.calendar import CalendarConverter
    from datetime import datetime
    
    # تعیین محدوده جستجو بر اساس reset_period
    if reset_period == "daily":
        if calendar_type == "jalali":
            # برای شمسی، باید تمام اسنادی که در همان روز شمسی هستند را پیدا کنیم
            # ابتدا تاریخ میلادی را به شمسی تبدیل می‌کنیم
            dt = datetime.combine(document_date, datetime.min.time())
            jalali = CalendarConverter.to_jalali(dt)
            # سپس تمام تاریخ‌های میلادی که در همان روز شمسی هستند را پیدا می‌کنیم
            # این کار پیچیده است، پس بهتر است از query بر اساس document_date استفاده کنیم
            # و در زمان مقایسه، تاریخ شمسی را بررسی کنیم
            date_from = document_date
            date_to = document_date
        else:
            date_from = document_date
            date_to = document_date
    elif reset_period == "monthly":
        if calendar_type == "jalali":
            # برای شمسی، باید تمام اسنادی که در همان ماه شمسی هستند را پیدا کنیم
            dt = datetime.combine(document_date, datetime.min.time())
            jalali = CalendarConverter.to_jalali(dt)
            # محاسبه محدوده بر اساس ماه شمسی
            # این کار نیاز به تبدیل تاریخ‌های ابتدا و انتهای ماه شمسی به میلادی دارد
            # برای سادگی، از همان منطق میلادی استفاده می‌کنیم اما در query فیلتر می‌کنیم
            date_from = document_date.replace(day=1)
            date_to = (date_from + timedelta(days=32)).replace(day=1) - timedelta(days=1)
        else:
            date_from = document_date.replace(day=1)
            date_to = (date_from + timedelta(days=32)).replace(day=1) - timedelta(days=1)
    elif reset_period == "yearly":
        if calendar_type == "jalali":
            # برای شمسی، باید تمام اسنادی که در همان سال شمسی هستند را پیدا کنیم
            dt = datetime.combine(document_date, datetime.min.time())
            jalali = CalendarConverter.to_jalali(dt)
            # محاسبه محدوده بر اساس سال شمسی
            date_from = document_date.replace(month=1, day=1)
            date_to = document_date.replace(month=12, day=31)
        else:
            date_from = document_date.replace(month=1, day=1)
            date_to = document_date.replace(month=12, day=31)
    else:  # never
        date_from = None
        date_to = None
    
    # جستجوی آخرین سند
    query = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == document_type
        )
    )
    
    if date_from and date_to:
        if calendar_type == "jalali" and reset_period in ["daily", "monthly", "yearly"]:
            # برای تقویم شمسی، باید اسناد را بر اساس تاریخ شمسی فیلتر کنیم
            # این کار نیاز به تبدیل تاریخ میلادی هر سند به شمسی دارد
            # برای بهینه‌سازی، می‌توانیم از محدوده میلادی تقریبی استفاده کنیم
            # یا تمام اسناد را بگیریم و در Python فیلتر کنیم
            # راه حل بهتر: استفاده از محدوده میلادی و سپس فیلتر در Python
            query = query.filter(
                and_(
                    Document.document_date >= date_from,
                    Document.document_date <= date_to
                )
            )
            # سپس در Python، اسناد را بر اساس تاریخ شمسی فیلتر می‌کنیم
            docs = query.all()
            dt = datetime.combine(document_date, datetime.min.time())
            target_jalali = CalendarConverter.to_jalali(dt)
            
            filtered_docs = []
            for doc in docs:
                doc_dt = datetime.combine(doc.document_date, datetime.min.time())
                doc_jalali = CalendarConverter.to_jalali(doc_dt)
                
                if reset_period == "daily":
                    if (doc_jalali["year"] == target_jalali["year"] and
                        doc_jalali["month"] == target_jalali["month"] and
                        doc_jalali["day"] == target_jalali["day"]):
                        filtered_docs.append(doc)
                elif reset_period == "monthly":
                    if (doc_jalali["year"] == target_jalali["year"] and
                        doc_jalali["month"] == target_jalali["month"]):
                        filtered_docs.append(doc)
                elif reset_period == "yearly":
                    if doc_jalali["year"] == target_jalali["year"]:
                        filtered_docs.append(doc)
            
            last_doc = max(filtered_docs, key=lambda d: d.code) if filtered_docs else None
        else:
            # برای میلادی یا never، از فیلتر ساده استفاده می‌کنیم
            query = query.filter(
                and_(
                    Document.document_date >= date_from,
                    Document.document_date <= date_to
                )
            )
            last_doc = query.order_by(Document.code.desc()).first()
    else:
        last_doc = query.order_by(Document.code.desc()).first()
    
    if last_doc:
        try:
            # استخراج شماره از کد آخرین سند
            parts = last_doc.code.split(separator)
            last_num = int(parts[-1])
            next_num = last_num + 1
        except:
            next_num = start_number
    else:
        next_num = start_number
    
    return f"{next_num:0{padding}d}"
```

### 2.5. به‌روزرسانی سرویس‌های موجود

**تغییرات در `invoice_service.py`:**
```python
# قبل:
doc_code = _build_invoice_code(db, business_id, invoice_type)

# بعد:
from app.services.document_numbering_service import generate_document_code
doc_code = generate_document_code(db, business_id, invoice_type, document_date)
```

**تغییرات مشابه در:**
- `receipt_payment_service.py`
- `transfer_service.py`
- `expense_income_service.py`
- سایر سرویس‌های ایجاد سند

---

## 3. Frontend (Flutter)

### 3.1. مدل‌ها

**مسیر:** `hesabixUI/hesabix_ui/lib/models/document_numbering_models.dart`

```dart
class DocumentNumberingSetting {
  final int? id;
  final int businessId;
  final String documentType;
  final String? prefix;
  final bool includeDate;
  final String calendarType; // gregorian یا jalali
  final String? dateFormat;
  final String separator;
  final int startNumber;
  final int numberPadding;
  final String? resetPeriod; // daily, monthly, yearly, never
  final String? customFormat;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  DocumentNumberingSetting({
    this.id,
    required this.businessId,
    required this.documentType,
    this.prefix,
    this.includeDate = true,
    this.calendarType = 'gregorian',
    this.dateFormat,
    this.separator = '-',
    this.startNumber = 1,
    this.numberPadding = 4,
    this.resetPeriod,
    this.customFormat,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DocumentNumberingSetting.fromJson(Map<String, dynamic> json) {
    return DocumentNumberingSetting(
      id: json['id'],
      businessId: json['business_id'],
      documentType: json['document_type'],
      prefix: json['prefix'],
      includeDate: json['include_date'] ?? true,
      calendarType: json['calendar_type'] ?? 'gregorian',
      dateFormat: json['date_format'],
      separator: json['separator'] ?? '-',
      startNumber: json['start_number'] ?? 1,
      numberPadding: json['number_padding'] ?? 4,
      resetPeriod: json['reset_period'],
      customFormat: json['custom_format'],
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'business_id': businessId,
      'document_type': documentType,
      'prefix': prefix,
      'include_date': includeDate,
      'calendar_type': calendarType,
      'date_format': dateFormat,
      'separator': separator,
      'start_number': startNumber,
      'number_padding': numberPadding,
      'reset_period': resetPeriod,
      'custom_format': customFormat,
      'is_active': isActive,
    };
  }
}
```

### 3.2. سرویس API

**مسیر:** `hesabixUI/hesabix_ui/lib/services/document_numbering_api_service.dart`

```dart
class DocumentNumberingApiService {
  static final ApiClient _apiClient = ApiClient();

  static Future<List<DocumentNumberingSetting>> getSettings(int businessId) async {
    final response = await _apiClient.get(
      '/businesses/$businessId/document-numbering-settings',
    );
    final List<dynamic> data = response.data;
    return data.map((json) => DocumentNumberingSetting.fromJson(json)).toList();
  }

  static Future<DocumentNumberingSetting> getSetting(
    int businessId,
    String documentType,
  ) async {
    final response = await _apiClient.get(
      '/businesses/$businessId/document-numbering-settings/$documentType',
    );
    return DocumentNumberingSetting.fromJson(response.data);
  }

  static Future<DocumentNumberingSetting> saveSetting(
    int businessId,
    DocumentNumberingSetting setting,
  ) async {
    final response = await _apiClient.post(
      '/businesses/$businessId/document-numbering-settings',
      data: setting.toJson(),
    );
    return DocumentNumberingSetting.fromJson(response.data);
  }

  static Future<void> deleteSetting(int businessId, String documentType) async {
    await _apiClient.delete(
      '/businesses/$businessId/document-numbering-settings/$documentType',
    );
  }
}
```

### 3.3. صفحه تنظیمات

**مسیر:** `hesabixUI/hesabix_ui/lib/pages/business/document_numbering_settings_page.dart`

```dart
class DocumentNumberingSettingsPage extends StatefulWidget {
  final int businessId;
  const DocumentNumberingSettingsPage({super.key, required this.businessId});

  @override
  State<DocumentNumberingSettingsPage> createState() => _DocumentNumberingSettingsPageState();
}

class _DocumentNumberingSettingsPageState extends State<DocumentNumberingSettingsPage> {
  bool _loading = true;
  List<DocumentNumberingSetting> _settings = [];
  Map<String, String> _documentTypeNames = {
    'invoice_sales': 'فاکتور فروش',
    'invoice_sales_return': 'برگشت از فروش',
    'invoice_purchase': 'فاکتور خرید',
    'invoice_purchase_return': 'برگشت از خرید',
    'receipt': 'دریافت',
    'payment': 'پرداخت',
    'transfer': 'انتقال',
    // ... سایر انواع
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await DocumentNumberingApiService.getSettings(widget.businessId);
      setState(() {
        _settings = settings;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا در بارگذاری: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('تنظیمات شماره‌گذاری اسناد'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: _documentTypeNames.length,
              itemBuilder: (context, index) {
                final documentType = _documentTypeNames.keys.elementAt(index);
                final documentName = _documentTypeNames[documentType]!;
                final setting = _settings.firstWhere(
                  (s) => s.documentType == documentType,
                  orElse: () => _getDefaultSetting(documentType),
                );

                return Card(
                  margin: EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(documentName),
                    subtitle: Text(_formatPreview(setting)),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _showEditDialog(documentType, setting),
                  ),
                );
              },
            ),
    );
  }

  DocumentNumberingSetting _getDefaultSetting(String documentType) {
    // برگرداندن تنظیمات پیش‌فرض
    return DocumentNumberingSetting(
      businessId: widget.businessId,
      documentType: documentType,
      prefix: _getDefaultPrefix(documentType),
      includeDate: true,
      calendarType: 'gregorian',
      dateFormat: 'YYYYMMDD',
      separator: '-',
      startNumber: 1,
      numberPadding: 4,
      resetPeriod: 'never',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  String _getDefaultPrefix(String documentType) {
    final prefixes = {
      'invoice_sales': 'INV',
      'receipt': 'RC',
      'payment': 'PY',
      'transfer': 'TR',
      // ...
    };
    return prefixes[documentType] ?? 'DOC';
  }

  String _formatPreview(DocumentNumberingSetting setting) {
    final today = DateTime.now();
    String datePart = '';
    
    if (setting.includeDate) {
      if (setting.calendarType == 'jalali') {
        // تبدیل به شمسی با استفاده از shamsi_date package
        import 'package:shamsi_date/shamsi_date.dart';
        final jalali = Jalali.fromDateTime(today);
        datePart = _formatJalaliDate(jalali, setting.dateFormat ?? 'YYYYMMDD');
      } else {
        // میلادی
        datePart = _formatGregorianDate(today, setting.dateFormat ?? 'YYYYMMDD');
      }
    }
    
    final numberPart = '1'.padLeft(setting.numberPadding, '0');
    
    if (datePart.isNotEmpty) {
      return '${setting.prefix}${setting.separator}$datePart${setting.separator}$numberPart';
    }
    return '${setting.prefix}${setting.separator}$numberPart';
  }

  String _formatGregorianDate(DateTime date, String format) {
    String result = format;
    result = result.replaceAll('YYYY', date.year.toString().padLeft(4, '0'));
    result = result.replaceAll('YY', (date.year % 100).toString().padLeft(2, '0'));
    result = result.replaceAll('MM', date.month.toString().padLeft(2, '0'));
    result = result.replaceAll('M', date.month.toString());
    result = result.replaceAll('DD', date.day.toString().padLeft(2, '0'));
    result = result.replaceAll('D', date.day.toString());
    return result;
  }

  String _formatJalaliDate(Jalali jalali, String format) {
    String result = format;
    result = result.replaceAll('YYYY', jalali.year.toString().padLeft(4, '0'));
    result = result.replaceAll('YY', (jalali.year % 100).toString().padLeft(2, '0'));
    result = result.replaceAll('MM', jalali.month.toString().padLeft(2, '0'));
    result = result.replaceAll('M', jalali.month.toString());
    result = result.replaceAll('DD', jalali.day.toString().padLeft(2, '0'));
    result = result.replaceAll('D', jalali.day.toString());
    return result;
  }

  Future<void> _showEditDialog(
    String documentType,
    DocumentNumberingSetting setting,
  ) async {
    // نمایش دیالوگ ویرایش با فیلدهای:
    // - پیشوند
    // - شامل تاریخ (چک‌باکس)
    // - نوع تقویم (dropdown: میلادی، شمسی)
    // - فرمت تاریخ (dropdown که بر اساس نوع تقویم تغییر می‌کند)
    //   * برای میلادی: YYYYMMDD, YYMMDD, YYYY-MM-DD, YYYY/MM/DD, YY-MM-DD, YY/MM/DD
    //   * برای شمسی: YYYYMMDD, YYMMDD, YYYY/MM/DD, YYYY-MM-DD, YY/MM/DD, YY-MM-DD
    // - جداکننده
    // - شماره شروع
    // - تعداد صفرهای پیش‌رو
    // - دوره ریست
    // - فعال/غیرفعال
    // - پیش‌نمایش زنده (که با تغییر هر فیلد به‌روزرسانی می‌شود)
    // ...
    
    // مثال کد برای تغییر فرمت تاریخ بر اساس نوع تقویم:
    /*
    List<String> getDateFormats(String calendarType) {
      if (calendarType == 'jalali') {
        return [
          'YYYYMMDD',
          'YYMMDD',
          'YYYY/MM/DD',
          'YYYY-MM-DD',
          'YY/MM/DD',
          'YY-MM-DD',
        ];
      } else {
        return [
          'YYYYMMDD',
          'YYMMDD',
          'YYYY-MM-DD',
          'YYYY/MM/DD',
          'YY-MM-DD',
          'YY/MM/DD',
        ];
      }
    }
    */
  }
}
```

### 3.4. اضافه کردن لینک در صفحه تنظیمات

**تغییرات در `settings_page.dart`:**

```dart
_buildSettingItem(
  context,
  title: 'شماره‌گذاری اسناد',
  subtitle: 'تنظیم نحوه شماره‌گذاری انواع اسناد',
  icon: Icons.numbers,
  onTap: () => context.go('/business/${widget.businessId}/settings/document-numbering'),
),
```

### 3.5. Routing

**تغییرات در `main.dart`:**

```dart
GoRoute(
  path: '/business/:business_id/settings/document-numbering',
  name: 'business_settings_document_numbering',
  pageBuilder: (context, state) {
    final businessId = int.parse(state.pathParameters['business_id']!);
    if (!_authStore!.hasBusinessPermission('settings', 'join')) {
      return NoTransitionPage(child: PermissionGuard.buildAccessDeniedPage());
    }
    return NoTransitionPage(
      child: DocumentNumberingSettingsPage(businessId: businessId),
    );
  },
),
```

---

## 4. جریان کار (User Flow)

### 4.1. دسترسی به صفحه
1. کاربر وارد بخش **تنظیمات کسب و کار** می‌شود (`/business/{id}/settings`)
2. در بخش **تنظیمات عمومی**، گزینه **"شماره‌گذاری اسناد"** را می‌بیند
3. با کلیک روی آن، به صفحه تنظیمات شماره‌گذاری منتقل می‌شود

### 4.2. مشاهده تنظیمات
1. صفحه لیست تمام انواع اسناد را نمایش می‌دهد
2. برای هر نوع سند، یک پیش‌نمایش از فرمت شماره‌گذاری نمایش داده می‌شود
3. اگر تنظیمات سفارشی وجود داشته باشد، با آیکون یا رنگ متفاوت نمایش داده می‌شود

### 4.3. ویرایش تنظیمات
1. کاربر روی یک نوع سند کلیک می‌کند
2. دیالوگ ویرایش باز می‌شود با فیلدهای:
   - **پیشوند** (prefix): مثلاً INV, RC, PY
   - **شامل تاریخ**: چک‌باکس
   - **نوع تقویم**: dropdown (میلادی، شمسی)
   - **فرمت تاریخ**: dropdown (بسته به نوع تقویم):
     - **میلادی:** YYYYMMDD, YYMMDD, YYYY-MM-DD, YYYY/MM/DD, YY-MM-DD
     - **شمسی:** YYYYMMDD, YYMMDD, YYYY/MM/DD, YYYY-MM-DD, YY/MM/DD
   - **جداکننده**: input (پیش‌فرض: `-`)
   - **شماره شروع**: عدد (پیش‌فرض: 1)
   - **تعداد صفرهای پیش‌رو**: عدد (پیش‌فرض: 4)
   - **دوره ریست**: dropdown (روزانه، ماهانه، سالانه، هرگز)
   - **فعال/غیرفعال**: چک‌باکس
3. کاربر تغییرات را اعمال می‌کند
4. با کلیک روی "ذخیره"، تنظیمات در دیتابیس ذخیره می‌شود
5. پیش‌نمایش شماره سند به صورت زنده به‌روزرسانی می‌شود

### 4.4. بازگشت به پیش‌فرض
1. کاربر می‌تواند تنظیمات سفارشی را حذف کند
2. با حذف، سیستم به تنظیمات پیش‌فرض بازمی‌گردد

### 4.5. استفاده در ایجاد سند
1. هنگام ایجاد یک سند جدید (مثلاً فاکتور فروش)
2. سیستم تنظیمات مربوط به `invoice_sales` را از دیتابیس می‌خواند
3. اگر تنظیمات وجود نداشت، از پیش‌فرض استفاده می‌کند
4. شماره سند بر اساس تنظیمات تولید می‌شود
5. شماره در فیلد مربوطه نمایش داده می‌شود

---

## 5. تنظیمات پیش‌فرض

### 5.1. فاکتورها
- **پیشوند:** `INV`
- **شامل تاریخ:** بله
- **نوع تقویم:** میلادی (gregorian)
- **فرمت تاریخ:** `YYYYMMDD`
- **جداکننده:** `-`
- **شماره شروع:** 1
- **تعداد صفرها:** 4
- **دوره ریست:** هرگز
- **نمونه میلادی:** `INV-20241120-0001`
- **نمونه شمسی:** `INV-14031001-0001` (با فرمت YYYYMMDD)

### 5.2. دریافت/پرداخت
- **دریافت:**
  - پیشوند: `RC`
  - نوع تقویم: میلادی (پیش‌فرض)
  - نمونه میلادی: `RC-20241120-0001`
  - نمونه شمسی: `RC-14031001-0001`
- **پرداخت:**
  - پیشوند: `PY`
  - نوع تقویم: میلادی (پیش‌فرض)
  - نمونه میلادی: `PY-20241120-0001`
  - نمونه شمسی: `PY-14031001-0001`

### 5.3. انتقال
- **پیشوند:** `TR`
- **نوع تقویم:** میلادی (پیش‌فرض)
- **نمونه میلادی:** `TR-20241120-0001`
- **نمونه شمسی:** `TR-14031001-0001`

### 5.4. فرمت‌های تاریخ پشتیبانی شده

#### تقویم میلادی:
- `YYYYMMDD` → `20241120`
- `YYMMDD` → `241120`
- `YYYY-MM-DD` → `2024-11-20`
- `YYYY/MM/DD` → `2024/11/20`
- `YY-MM-DD` → `24-11-20`
- `YY/MM/DD` → `24/11/20`

#### تقویم شمسی:
- `YYYYMMDD` → `14031001`
- `YYMMDD` → `031001`
- `YYYY/MM/DD` → `1403/10/01`
- `YYYY-MM-DD` → `1403-10-01`
- `YY/MM/DD` → `03/10/01`
- `YY-MM-DD` → `03-10-01`

---

## 6. نکات پیاده‌سازی

### 6.1. استفاده از تقویم شمسی
- برای تبدیل تاریخ میلادی به شمسی از `CalendarConverter.to_jalali()` استفاده می‌شود
- برای تبدیل تاریخ شمسی به میلادی از `CalendarConverter.to_gregorian()` استفاده می‌شود
- تاریخ سند در دیتابیس همیشه به صورت میلادی ذخیره می‌شود
- فقط در زمان نمایش و تولید شماره سند، تبدیل به تقویم مورد نظر انجام می‌شود
- هنگام استفاده از تقویم شمسی برای دوره ریست (reset_period):
  - برای `daily`: شماره‌گذاری هر روز شمسی از 1 شروع می‌شود
  - برای `monthly`: شماره‌گذاری هر ماه شمسی از 1 شروع می‌شود
  - برای `yearly`: شماره‌گذاری هر سال شمسی از 1 شروع می‌شود
  - برای `never`: شماره‌گذاری پیوسته است و ریست نمی‌شود
- در محاسبه reset_period، باید تاریخ میلادی سند را به شمسی تبدیل کرده و سپس محدوده را محاسبه کنیم

### 6.2. سازگاری با داده‌های موجود
- اسناد موجود در دیتابیس تغییر نمی‌کنند
- فقط اسناد جدید از تنظیمات جدید استفاده می‌کنند
- در صورت تغییر فرمت، ممکن است شماره‌های تکراری ایجاد نشود (بسته به reset_period)

### 6.3. اعتبارسنجی
- پیشوند نباید خالی باشد
- تعداد صفرهای پیش‌رو باید بین 1 تا 10 باشد
- شماره شروع باید مثبت باشد
- نوع تقویم باید `gregorian` یا `jalali` باشد
- فرمت تاریخ باید معتبر باشد و با نوع تقویم سازگار باشد
- در فرمت شمسی، استفاده از `/` برای جداکننده تاریخ توصیه می‌شود

### 6.4. دسترسی‌ها
- فقط کاربرانی که دسترسی `settings.join` دارند می‌توانند تنظیمات را تغییر دهند
- سایر کاربران فقط می‌توانند مشاهده کنند (اگر نیاز باشد)

### 6.5. بهینه‌سازی
- تنظیمات را در cache نگه دارید تا در هر بار ایجاد سند، query به دیتابیس نزنید
- از index روی `business_id` و `document_type` استفاده کنید

---

## 7. Migration

```python
def upgrade():
    op.create_table(
        'business_document_numbering_settings',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('document_type', sa.String(50), nullable=False),
        sa.Column('prefix', sa.String(20), nullable=True),
        sa.Column('include_date', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('calendar_type', sa.String(10), nullable=False, server_default='gregorian'),
        sa.Column('date_format', sa.String(20), nullable=True),
        sa.Column('separator', sa.String(5), nullable=False, server_default='-'),
        sa.Column('start_number', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('number_padding', sa.Integer(), nullable=False, server_default='4'),
        sa.Column('reset_period', sa.String(20), nullable=True),
        sa.Column('custom_format', sa.String(100), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'document_type', name='uq_doc_numbering_business_type')
    )
    op.create_index('ix_doc_numbering_business', 'business_document_numbering_settings', ['business_id'])
    op.create_index('ix_doc_numbering_type', 'business_document_numbering_settings', ['document_type'])
```

---

## 8. تست

### 8.1. تست Backend
- تست ایجاد تنظیمات
- تست به‌روزرسانی تنظیمات
- تست حذف تنظیمات
- تست تولید شماره سند با تنظیمات سفارشی
- تست تولید شماره سند با پیش‌فرض
- تست دوره‌های ریست (روزانه، ماهانه، سالانه)

### 8.2. تست Frontend
- تست نمایش لیست تنظیمات
- تست ویرایش تنظیمات
- تست پیش‌نمایش فرمت
- تست اعتبارسنجی فیلدها
- تست دسترسی‌ها

---

## 9. مثال‌های استفاده از تقویم شمسی

### 9.1. مثال 1: فاکتور فروش با تاریخ شمسی
- **نوع سند:** `invoice_sales`
- **پیشوند:** `INV`
- **نوع تقویم:** `jalali` (شمسی)
- **فرمت تاریخ:** `YYYY/MM/DD`
- **جداکننده:** `/`
- **شماره:** `0001`
- **نتیجه:** `INV/1403/10/01/0001`

### 9.2. مثال 2: دریافت با تاریخ شمسی بدون جداکننده
- **نوع سند:** `receipt`
- **پیشوند:** `RC`
- **نوع تقویم:** `jalali` (شمسی)
- **فرمت تاریخ:** `YYYYMMDD`
- **جداکننده:** `-`
- **شماره:** `0001`
- **نتیجه:** `RC-14031001-0001`

### 9.3. مثال 3: پرداخت با تاریخ میلادی
- **نوع سند:** `payment`
- **پیشوند:** `PY`
- **نوع تقویم:** `gregorian` (میلادی)
- **فرمت تاریخ:** `YYYY-MM-DD`
- **جداکننده:** `-`
- **شماره:** `0001`
- **نتیجه:** `PY-2024-11-20-0001`

### 9.4. مثال 4: دوره ریست ماهانه با تقویم شمسی
- **نوع سند:** `invoice_sales`
- **نوع تقویم:** `jalali`
- **دوره ریست:** `monthly`
- **توضیح:** شماره‌گذاری در ابتدای هر ماه شمسی از 1 شروع می‌شود
- **مثال:**
  - `INV-1403/10/01-0001` (اول مهر)
  - `INV-1403/10/15-0002` (پانزدهم مهر)
  - `INV-1403/11/01-0001` (اول آبان - ریست شده)

---

## 10. مستندات کاربری

- راهنمای استفاده از صفحه تنظیمات شماره‌گذاری
- توضیح هر فیلد و تأثیر آن بر شماره سند
- مثال‌های مختلف فرمت‌های شماره‌گذاری برای هر دو تقویم
- نحوه انتخاب تقویم شمسی یا میلادی
- نحوه بازگشت به پیش‌فرض

