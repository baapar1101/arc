# 📚 مستندات کامل افزونه مدیریت تعمیرگاه

## فهرست مطالب

1. [معرفی](#معرفی)
2. [معماری سیستم](#معماری-سیستم)
3. [دیتابیس](#دیتابیس)
4. [API Documentation](#api-documentation)
5. [یکپارچگی‌ها](#یکپارچگیها)
6. [جریان کاری](#جریان-کاری)
7. [امنیت و دسترسی‌ها](#امنیت-و-دسترسیها)
8. [خطاها و عیب‌یابی](#خطاها-و-عیبیابی)

---

## معرفی

افزونه **مدیریت تعمیرگاه** یک سیستم جامع برای مدیریت فرآیند تعمیرات از دریافت کالا تا تحویل نهایی است.

### ویژگی‌های کلیدی
- ✅ دریافت و ثبت کالای تعمیری
- ✅ مدیریت تعمیرکاران و حق‌الزحمه
- ✅ کارتابل تعمیرات (10 وضعیت)
- ✅ یکپارچگی با سیستم گارانتی
- ✅ حواله خروج خودکار قطعات
- ✅ صدور فاکتور و ثبت حسابداری
- ✅ تاریخچه کامل تعمیرات

---

## معماری سیستم

### لایه‌های سیستم

```
┌─────────────────────────────────┐
│      API Layer (FastAPI)        │
│  /api/v1/repair-shop/*          │
└─────────────────────────────────┘
              ↓
┌─────────────────────────────────┐
│     Service Layer               │
│  - repair_shop_service          │
│  - repair_shop_operations       │
│  - repair_shop_accounting       │
└─────────────────────────────────┘
              ↓
┌─────────────────────────────────┐
│     Repository Layer            │
│  - RepairOrderRepository        │
│  - RepairTechnicianRepository   │
│  - etc.                         │
└─────────────────────────────────┘
              ↓
┌─────────────────────────────────┐
│     Database Layer (MySQL)      │
│  7 جدول اصلی                    │
└─────────────────────────────────┘
```

### یکپارچگی با سیستم‌های دیگر

```
┌──────────────────────────┐
│   Repair Shop System     │
└──────────────────────────┘
         ↓ ↑
    ┌────────────┬─────────────┬─────────────┬──────────────┐
    ↓            ↓             ↓             ↓              ↓
┌────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐  ┌──────────┐
│Products│  │Warehouse │  │Accounting│  │Warranty │  │  Storage │
└────────┘  └──────────┘  └──────────┘  └─────────┘  └──────────┘
```

---

## دیتابیس

### ERD (Entity Relationship Diagram)

```
┌─────────────────────┐
│ repair_shop_settings│
│ - business_id (PK)  │
│ - receipt_format    │
│ - auto_send_sms     │
└─────────────────────┘

┌──────────────────────┐        ┌─────────────────────┐
│ repair_technicians   │        │   repair_orders     │
│ - id (PK)            │◄───────│ - id (PK)           │
│ - business_id        │        │ - code (UNIQUE)     │
│ - person_id (FK)     │        │ - customer_id (FK)  │
│ - commission_type    │        │ - technician_id (FK)│
│ - commission_value   │        │ - status            │
└──────────────────────┘        │ - final_cost        │
                                └─────────────────────┘
                                         ↓ 1:N
                        ┌────────────────┴────────────────┐
                        ↓                                 ↓
            ┌──────────────────────┐      ┌─────────────────────────┐
            │ repair_order_parts   │      │ repair_order_statuses   │
            │ - id (PK)            │      │ - id (PK)               │
            │ - repair_order_id(FK)│      │ - repair_order_id (FK)  │
            │ - product_id (FK)    │      │ - status                │
            │ - quantity           │      │ - created_at            │
            │ - unit_price         │      │ - sms_sent              │
            └──────────────────────┘      └─────────────────────────┘
```

### جدول repair_orders (جدول اصلی)

| ستون | نوع | توضیحات |
|------|-----|---------|
| `id` | INT | شناسه یکتا |
| `code` | VARCHAR(50) | کد یکتا (مثل REC-2025-0001) |
| `business_id` | INT | کسب‌وکار |
| `customer_person_id` | INT | مشتری از جدول persons |
| `product_name` | VARCHAR(255) | نام کالا |
| `warranty_code_id` | INT NULL | کد گارانتی (اختیاری) |
| `status` | VARCHAR(50) | وضعیت فعلی |
| `assigned_technician_id` | INT NULL | تعمیرکار |
| `final_cost` | DECIMAL(18,2) | هزینه نهایی |
| `parts_cost` | DECIMAL(18,2) | هزینه قطعات |
| `labor_cost` | DECIMAL(18,2) | دستمزد |
| `technician_commission` | DECIMAL(18,2) | حق‌الزحمه |
| `received_at` | DATETIME | تاریخ دریافت |
| `completed_at` | DATETIME NULL | تاریخ تکمیل |
| `delivered_at` | DATETIME NULL | تاریخ تحویل |

### وضعیت‌های مجاز (Status)

| وضعیت | توضیح |
|-------|-------|
| `received` | دریافت شده |
| `assigned` | اختصاص داده شده |
| `in_progress` | در حال تعمیر |
| `waiting_parts` | منتظر قطعات |
| `testing` | در حال تست |
| `completed_fixed` | تعمیر موفق |
| `completed_unfixable` | غیرقابل تعمیر |
| `ready_for_pickup` | آماده تحویل |
| `delivered` | تحویل داده شده |
| `cancelled` | لغو شده |

---

## API Documentation

### Authentication

تمام API ها نیاز به Bearer Token دارند:

```
Authorization: Bearer sk_your_api_key
```

### Base URL

```
/api/v1/repair-shop
```

### Endpoints

#### 1. Settings

##### GET `/businesses/{business_id}/settings`
دریافت تنظیمات تعمیرگاه

**Response:**
```json
{
  "id": 1,
  "business_id": 1,
  "receipt_code_format": "sequential",
  "receipt_code_prefix": "REC",
  "auto_send_sms_on_receive": true,
  "sms_templates": {...}
}
```

##### PUT `/businesses/{business_id}/settings`
به‌روزرسانی تنظیمات

**Request Body:**
```json
{
  "auto_send_sms_on_receive": true,
  "receipt_code_prefix": "REC"
}
```

#### 2. Technicians

##### POST `/businesses/{business_id}/technicians`
ایجاد تعمیرکار جدید

**Request Body:**
```json
{
  "person_id": 123,
  "commission_type": "percentage",
  "commission_value": 30,
  "is_active": true
}
```

**Commission Types:**
- `fixed`: مبلغ فیکس (مثلاً 200,000 تومان)
- `percentage`: درصد از دستمزد (مثلاً 30%)
- `case_by_case`: موردی (دستی وارد می‌شود)

#### 3. Repair Orders

##### POST `/businesses/{business_id}/orders`
ایجاد سفارش تعمیر جدید

**Request Body:**
```json
{
  "customer_person_id": 123,
  "product_name": "لپتاپ ایسوس",
  "product_serial": "ABC123",
  "warranty_code_id": 456,
  "problem_description": "روشن نمی‌شود",
  "estimated_cost": 1500000
}
```

**Response:**
```json
{
  "id": 1,
  "code": "REC-2025-0001",
  "status": "received",
  "customer_name": "علی احمدی",
  "product_name": "لپتاپ ایسوس",
  "received_at": "2025-02-05T10:30:00",
  ...
}
```

##### GET `/businesses/{business_id}/orders?status=in_progress`
لیست سفارشات با فیلتر

**Query Parameters:**
- `status`: فیلتر بر اساس وضعیت
- `customer_person_id`: فیلتر بر اساس مشتری
- `assigned_technician_id`: فیلتر بر اساس تعمیرکار
- `search`: جستجو در کد، نام کالا، سریال
- `offset`: شروع از (pagination)
- `limit`: تعداد نتایج

#### 4. Operations

##### POST `/businesses/{business_id}/orders/{order_id}/assign-technician`
اختصاص تعمیرکار

**Request Body:**
```json
{
  "technician_id": 1
}
```

##### POST `/businesses/{business_id}/orders/{order_id}/update-status`
تغییر وضعیت

**Request Body:**
```json
{
  "status": "in_progress",
  "notes": "شروع تعمیر",
  "send_notification": true
}
```

##### POST `/businesses/{business_id}/orders/{order_id}/add-parts`
افزودن قطعات

**Request Body:**
```json
{
  "parts": [
    {
      "product_id": 10,
      "quantity": 1,
      "unit_price": 500000,
      "warehouse_id": 1
    },
    {
      "product_id": 11,
      "quantity": 2,
      "warehouse_id": 1
    }
  ]
}
```

**نکته**: سیستم به صورت خودکار:
1. موجودی را بررسی می‌کند
2. حواله خروج پیش‌نویس ایجاد می‌کند
3. هزینه قطعات را محاسبه می‌کند

##### POST `/businesses/{business_id}/orders/{order_id}/calculate-costs`
محاسبه هزینه‌ها

**Request Body:**
```json
{
  "labor_cost": 1000000
}
```

**Response:**
```json
{
  "parts_cost": 500000,
  "labor_cost": 1000000,
  "technician_commission": 300000,
  "final_cost": 1500000
}
```

##### POST `/businesses/{business_id}/orders/{order_id}/complete`
اتمام تعمیر

**Request Body:**
```json
{
  "is_fixed": true,
  "notes": "تعمیر با موفقیت انجام شد"
}
```

**نکته**: در این مرحله:
1. حواله خروج پست می‌شود
2. وضعیت به `completed_fixed` یا `completed_unfixable` تغییر می‌کند
3. موجودی از انبار کسر می‌شود

##### POST `/businesses/{business_id}/orders/{order_id}/deliver`
تحویل کالا

**Request Body:**
```json
{
  "notes": "تحویل به مشتری"
}
```

#### 5. Accounting

##### POST `/businesses/{business_id}/orders/{order_id}/create-invoice`
صدور فاکتور تعمیر

**Response:**
```json
{
  "document": {
    "id": 123,
    "code": "INV-2025-001",
    "document_type": "invoice_sales",
    ...
  },
  "accounting_summary": {
    "labor_cost": 1000000,
    "parts_cost": 500000,
    "final_cost": 1500000
  }
}
```

**اسناد حسابداری ثبت شده:**
```
حساب دریافتنی (10401)   بدهکار: 1,500,000
درآمد فروش (50001)        بستانکار: 1,000,000 (خدمات)
درآمد فروش (50001)        بستانکار: 500,000 (قطعات)
بهای تمام شده (40001)    بدهکار: 300,000
موجودی کالا (10102)       بستانکار: 300,000
```

---

## یکپارچگی‌ها

### 1. Marketplace Plugin System

```python
# بررسی فعال بودن
from app.core.repair_shop_plugin_dependency import check_repair_shop_plugin_active

is_active = check_repair_shop_plugin_active(db, business_id)
```

### 2. Permission System

دسترسی‌های مورد نیاز:
- `repair_shop.read`: مشاهده
- `repair_shop.write`: ثبت و ویرایش
- `repair_shop.delete`: حذف
- `repair_shop.manage`: مدیریت تنظیمات

### 3. Warehouse Integration

```python
# هنگام افزودن قطعات
from app.services.warehouse_service import get_product_stock

stock = get_product_stock(db, business_id, product_id, warehouse_id)
if stock < quantity:
    raise ApiError("INSUFFICIENT_STOCK", ...)
```

### 4. Accounting Integration

```python
from app.services.invoice_service import create_invoice

# صدور فاکتور
invoice = create_invoice(db, business_id, user_id, invoice_payload)
```

---

## جریان کاری

### سناریوی کامل: تعمیر لپتاپ

```
1️⃣ دریافت کالا
   POST /orders
   {
     "customer_person_id": 1,
     "product_name": "لپتاپ",
     "problem_description": "روشن نمی‌شود"
   }
   
2️⃣ اختصاص تعمیرکار
   POST /orders/1/assign-technician
   {"technician_id": 1}
   
3️⃣ شروع تعمیر
   POST /orders/1/update-status
   {"status": "in_progress"}
   
4️⃣ افزودن قطعات
   POST /orders/1/add-parts
   {
     "parts": [{"product_id": 10, "quantity": 1, "warehouse_id": 1}]
   }
   → حواله خروج پیش‌نویس ایجاد می‌شود
   
5️⃣ محاسبه هزینه
   POST /orders/1/calculate-costs
   {"labor_cost": 1000000}
   → حق‌الزحمه تعمیرکار محاسبه می‌شود
   
6️⃣ اتمام تعمیر
   POST /orders/1/complete
   {"is_fixed": true}
   → حواله خروج پست می‌شود
   → موجودی کسر می‌شود
   
7️⃣ صدور فاکتور
   POST /orders/1/create-invoice
   → فاکتور فروش ایجاد می‌شود
   → اسناد حسابداری ثبت می‌شوند
   
8️⃣ تحویل
   POST /orders/1/deliver
```

---

## امنیت و دسترسی‌ها

### نقش‌های پیشنهادی

#### 1. مدیر تعمیرگاه
```json
{
  "repair_shop": {
    "read": true,
    "write": true,
    "delete": true,
    "manage": true
  }
}
```

#### 2. تعمیرکار
```json
{
  "repair_shop": {
    "read": true,
    "write": true
  }
}
```

#### 3. کارشناس پذیرش
```json
{
  "repair_shop": {
    "read": true,
    "write": true
  },
  "people": {
    "read": true,
    "write": true
  }
}
```

---

## خطاها و عیب‌یابی

### خطاهای رایج

#### 1. `PLUGIN_NOT_ACTIVE`
```json
{
  "error_code": "PLUGIN_NOT_ACTIVE",
  "message": "افزونه مدیریت تعمیرگاه فعال نیست"
}
```

**حل**: افزونه را از marketplace خریداری یا trial کنید.

#### 2. `INSUFFICIENT_STOCK`
```json
{
  "error_code": "INSUFFICIENT_STOCK",
  "message": "موجودی کافی نیست",
  "extra_data": {
    "product_id": 10,
    "current_stock": 5,
    "requested": 10
  }
}
```

**حل**: موجودی را افزایش دهید یا تعداد را کاهش دهید.

#### 3. `INVOICE_ALREADY_EXISTS`
```json
{
  "error_code": "INVOICE_ALREADY_EXISTS",
  "message": "فاکتور قبلاً ایجاد شده است"
}
```

**حل**: هر سفارش فقط یک فاکتور دارد.

#### 4. `NO_ACTIVE_STORAGE_PLAN`
```json
{
  "error_code": "NO_ACTIVE_STORAGE_PLAN",
  "message": "پکیج ذخیره‌سازی فعالی وجود ندارد"
}
```

**حل**: برای آپلود تصاویر، پلن ذخیره‌سازی فعال کنید.

### Logging

تمام عملیات مهم لاگ می‌شوند:

```python
import logging
logger = logging.getLogger(__name__)

logger.info(f"سفارش تعمیر {order.code} ایجاد شد")
logger.warning(f"موجودی کافی نیست: {product_id}")
logger.error(f"خطا در ایجاد فاکتور: {e}")
```

---

## نکات عملیاتی

### 1. Performance

- استفاده از Index ها برای جستجوی سریع
- Pagination برای لیست‌ها
- Lazy Loading برای relationships

### 2. Scalability

- جداسازی concerns (Service, Repository, API)
- استفاده از Queue برای پیامک/ایمیل
- Cache برای تنظیمات

### 3. Best Practices

- Validation در Pydantic models
- Transaction management در service layer
- Error handling مناسب
- Logging جامع

---

## مثال‌های کاربردی

### مثال 1: دریافت آمار تعمیرات

```python
from sqlalchemy import func

# تعداد تعمیرات موفق
successful_repairs = db.query(func.count(RepairOrder.id)).filter(
    RepairOrder.business_id == business_id,
    RepairOrder.status == "completed_fixed"
).scalar()

# میانگین زمان تعمیر
avg_duration = db.query(
    func.avg(
        func.timestampdiff(
            sa.text('HOUR'),
            RepairOrder.received_at,
            RepairOrder.completed_at
        )
    )
).filter(
    RepairOrder.business_id == business_id,
    RepairOrder.completed_at.isnot(None)
).scalar()
```

### مثال 2: گزارش عملکرد تعمیرکار

```python
from sqlalchemy import func, case

technician_report = db.query(
    RepairTechnician.id,
    Person.name,
    func.count(RepairOrder.id).label('total_repairs'),
    func.sum(
        case(
            (RepairOrder.status == 'completed_fixed', 1),
            else_=0
        )
    ).label('successful_repairs'),
    func.sum(RepairOrder.technician_commission).label('total_commission')
).join(
    Person, RepairTechnician.person_id == Person.id
).outerjoin(
    RepairOrder, RepairOrder.assigned_technician_id == RepairTechnician.id
).filter(
    RepairTechnician.business_id == business_id
).group_by(
    RepairTechnician.id, Person.name
).all()
```

---

**تاریخ**: 2025-02-05  
**نسخه**: 1.0.0  
**نویسنده**: AI Assistant

