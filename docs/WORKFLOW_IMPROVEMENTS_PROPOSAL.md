# پیشنهادات بهبود سیستم اتوماسیون و Workflow

این سند شامل پیشنهادات جامع برای بهبود عملکرد و افزایش تنظیمات هر نود در سیستم workflow است.

---

## 📋 فهرست محتوا

1. [Triggers (محرک‌ها)](#triggers)
2. [Actions (عمل‌ها)](#actions)
3. [Conditions (شرط‌ها)](#conditions)
4. [Loops (حلقه‌ها)](#loops)
5. [بهبودهای کلی موتور Workflow](#بهبودهای-کلی)

---

## 🔷 Triggers

### 1. DocumentCreatedTrigger (ایجاد سند)

#### پیشنهادات بهبود عملکرد:
- **Caching**: کش کردن metadata نوع سند برای کاهش query به دیتابیس
- **Batch Processing**: پردازش دسته‌ای برای چندین سند ایجاد شده همزمان
- **Validation**: اعتبارسنجی داده‌های سند قبل از trigger
- **Retry Mechanism**: مکانیزم retry برای triggerهای ناموفق

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  document_type:
    type: "string"
    description: "نوع سند (اختیاری)"
    required: false
  min_amount:
    type: "number"
    description: "حداقل مبلغ سند"
    required: false
  max_amount:
    type: "number"
    description: "حداکثر مبلغ سند"
    required: false
  fiscal_year_filter:
    type: "integer"
    description: "فیلتر بر اساس سال مالی خاص"
    required: false
  user_id_filter:
    type: "integer"
    description: "فیلتر بر اساس کاربر ایجادکننده"
    required: false
  description_contains:
    type: "string"
    description: "فیلتر بر اساس کلمات کلیدی در شرح"
    required: false
  enabled:
    type: "boolean"
    description: "فعال/غیرفعال کردن trigger"
    default: true
  cooldown_seconds:
    type: "integer"
    description: "مدت زمان انتظار بین triggerهای متوالی (ثانیه)"
    default: 0
  timeout_seconds:
    type: "integer"
    description: "حداکثر زمان انتظار برای اجرای workflow (ثانیه)"
    default: 300
```

---

### 2. InvoiceCreatedTrigger (ایجاد فاکتور)

#### پیشنهادات بهبود عملکرد:
- **Async Processing**: پردازش ناهمزمان برای فاکتورهای بزرگ
- **Invoice Status Filtering**: فیلتر بر اساس وضعیت فاکتور (پیش‌نویس، تایید شده، لغو شده)
- **Payment Status Tracking**: ردیابی وضعیت پرداخت
- **Tax Calculation**: محاسبه خودکار مالیات و اضافه کردن به trigger data

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  invoice_type:
    type: "string"
    description: "نوع فاکتور (sales/purchase)"
    required: false
  min_amount:
    type: "number"
    description: "حداقل مبلغ فاکتور"
    required: false
  max_amount:
    type: "number"
    description: "حداکثر مبلغ فاکتور"
    required: false
  status_filter:
    type: "array"
    description: "فیلتر بر اساس وضعیت فاکتور (draft/confirmed/cancelled)"
    items:
      type: "string"
    required: false
  person_type_filter:
    type: "string"
    description: "فیلتر بر اساس نوع شخص (customer/supplier)"
    required: false
  currency_id:
    type: "integer"
    description: "فیلتر بر اساس ارز"
    required: false
  include_tax_details:
    type: "boolean"
    description: "شامل جزئیات مالیات در trigger data"
    default: false
  include_payment_status:
    type: "boolean"
    description: "شامل وضعیت پرداخت در trigger data"
    default: false
  batch_mode:
    type: "boolean"
    description: "پردازش دسته‌ای برای فاکتورهای متعدد"
    default: false
```

---

### 3. ReceiptPaymentCreatedTrigger (ایجاد دریافت/پرداخت)

#### پیشنهادات بهبود عملکرد:
- **Payment Method Filtering**: فیلتر بر اساس روش پرداخت
- **Account Filtering**: فیلتر بر اساس حساب بانکی
- **Balance Tracking**: ردیابی موجودی حساب بعد از تراکنش
- **Duplicate Detection**: تشخیص تراکنش‌های تکراری

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  type:
    type: "string"
    description: "نوع (receipt/payment)"
    required: false
  min_amount:
    type: "number"
    description: "حداقل مبلغ"
    required: false
  max_amount:
    type: "number"
    description: "حداکثر مبلغ"
    required: false
  payment_method_filter:
    type: "array"
    description: "فیلتر بر اساس روش پرداخت"
    items:
      type: "string"
    required: false
  account_id_filter:
    type: "integer"
    description: "فیلتر بر اساس حساب بانکی"
    required: false
  include_balance:
    type: "boolean"
    description: "شامل موجودی حساب در trigger data"
    default: false
  check_duplicate:
    type: "boolean"
    description: "بررسی تراکنش تکراری"
    default: false
  duplicate_window_hours:
    type: "integer"
    description: "بازه زمانی بررسی تکراری (ساعت)"
    default: 24
```

---

### 4. CheckDueDateTrigger (سررسید چک)

#### پیشنهادات بهبود عملکرد:
- **Time Zone Support**: پشتیبانی از timezone برای تعیین دقیق سررسید
- **Multiple Reminders**: ارسال چندین یادآوری در بازه‌های زمانی مختلف
- **Check Status Tracking**: ردیابی وضعیت چک (وصول شده، برگشت خورده، و...)
- **Priority Levels**: سطح‌بندی اولویت بر اساس مبلغ

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  check_type:
    type: "string"
    description: "نوع چک (received/paid)"
    required: false
  days_before:
    type: "number"
    description: "تعداد روز قبل از سررسید"
    required: false
  days_after:
    type: "number"
    description: "تعداد روز بعد از سررسید"
    required: false
  reminder_schedule:
    type: "array"
    description: "زمان‌بندی یادآوری‌ها (روزهای قبل از سررسید)"
    items:
      type: "integer"
    required: false
  min_amount:
    type: "number"
    description: "حداقل مبلغ چک"
    required: false
  status_filter:
    type: "array"
    description: "فیلتر بر اساس وضعیت چک"
    items:
      type: "string"
    required: false
  timezone:
    type: "string"
    description: "Timezone برای محاسبه سررسید"
    default: "Asia/Tehran"
  include_grace_period:
    type: "boolean"
    description: "شامل دوره مهلت (grace period)"
    default: false
  grace_period_days:
    type: "integer"
    description: "تعداد روز مهلت"
    default: 0
```

---

### 5. InventoryLowTrigger (موجودی کم)

#### پیشنهادات بهبود عملکرد:
- **Multi-warehouse Support**: پشتیبانی از چند انبار
- **Dynamic Thresholds**: آستانه‌های پویا بر اساس تاریخچه فروش
- **Forecasting**: پیش‌بینی زمان اتمام موجودی
- **Category-based Filtering**: فیلتر بر اساس دسته‌بندی محصولات

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  product_id:
    type: "integer"
    description: "شناسه محصول (اختیاری)"
    required: false
  warehouse_id:
    type: "integer"
    description: "شناسه انبار (اختیاری)"
    required: false
  threshold_type:
    type: "string"
    description: "نوع آستانه (fixed/percentage/dynamic)"
    enum: ["fixed", "percentage", "dynamic"]
    default: "fixed"
  threshold_value:
    type: "number"
    description: "مقدار آستانه"
    required: false
  threshold_percentage:
    type: "number"
    description: "درصد آستانه (برای threshold_type=percentage)"
    required: false
  category_id:
    type: "integer"
    description: "فیلتر بر اساس دسته‌بندی"
    required: false
  include_forecast:
    type: "boolean"
    description: "شامل پیش‌بینی زمان اتمام"
    default: false
  forecast_days:
    type: "integer"
    description: "تعداد روز برای پیش‌بینی"
    default: 30
  check_frequency:
    type: "string"
    description: "فرکانس بررسی (realtime/hourly/daily)"
    enum: ["realtime", "hourly", "daily"]
    default: "realtime"
```

---

### 6. PersonCreatedTrigger (ایجاد شخص)

#### پیشنهادات بهبود عملکرد:
- **Person Type Validation**: اعتبارسنجی نوع شخص
- **Duplicate Person Detection**: تشخیص شخص تکراری
- **Data Enrichment**: غنی‌سازی داده‌ها با اطلاعات اضافی
- **Welcome Message**: ارسال پیام خوش‌آمدگویی

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  person_type:
    type: "string"
    description: "نوع شخص (customer/supplier/etc)"
    required: false
  person_types:
    type: "array"
    description: "چند نوع شخص"
    items:
      type: "string"
    required: false
  check_duplicate:
    type: "boolean"
    description: "بررسی شخص تکراری"
    default: false
  duplicate_fields:
    type: "array"
    description: "فیلدهای بررسی تکراری (mobile/email/national_id)"
    items:
      type: "string"
    required: false
  include_credit_limit:
    type: "boolean"
    description: "شامل اعتبار در trigger data"
    default: false
  auto_assign_group:
    type: "boolean"
    description: "اختصاص خودکار به گروه"
    default: false
  send_welcome_message:
    type: "boolean"
    description: "ارسال پیام خوش‌آمدگویی"
    default: false
```

---

### 7. ScheduledTrigger (زمان‌بندی شده)

#### پیشنهادات بهبود عملکرد:
- **Time Zone Support**: پشتیبانی کامل از timezone
- **Holiday Calendar**: تقویم تعطیلات
- **Business Hours Only**: اجرا فقط در ساعات کاری
- **Retry on Failure**: تلاش مجدد در صورت خطا

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  schedule:
    type: "string"
    description: "زمان‌بندی cron"
    required: true
  timezone:
    type: "string"
    description: "Timezone"
    default: "Asia/Tehran"
  business_hours_only:
    type: "boolean"
    description: "اجرا فقط در ساعات کاری"
    default: false
  business_hours_start:
    type: "string"
    description: "شروع ساعت کاری (HH:mm)"
    default: "09:00"
  business_hours_end:
    type: "string"
    description: "پایان ساعت کاری (HH:mm)"
    default: "17:00"
  exclude_holidays:
    type: "boolean"
    description: "حذف تعطیلات"
    default: false
  holiday_calendar_id:
    type: "integer"
    description: "شناسه تقویم تعطیلات"
    required: false
  max_execution_time:
    type: "integer"
    description: "حداکثر زمان اجرا (ثانیه)"
    default: 300
  retry_on_failure:
    type: "boolean"
    description: "تلاش مجدد در صورت خطا"
    default: false
  retry_attempts:
    type: "integer"
    description: "تعداد تلاش‌های مجدد"
    default: 3
  retry_delay_seconds:
    type: "integer"
    description: "تاخیر بین تلاش‌ها (ثانیه)"
    default: 60
```

---

### 8. WebhookTrigger (Webhook)

#### پیشنهادات بهبود عملکرد:
- **Authentication**: مکانیزم‌های احراز هویت (API Key, OAuth, Signature)
- **Rate Limiting**: محدود کردن تعداد درخواست
- **Payload Validation**: اعتبارسنجی payload
- **Response Customization**: سفارشی‌سازی پاسخ

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  webhook_path:
    type: "string"
    description: "مسیر webhook"
    required: false
  method:
    type: "string"
    description: "روش HTTP"
    default: "POST"
    required: false
  authentication_type:
    type: "string"
    description: "نوع احراز هویت (none/api_key/bearer/signature)"
    enum: ["none", "api_key", "bearer", "signature"]
    default: "none"
  api_key:
    type: "string"
    description: "کلید API"
    required: false
  api_key_header:
    type: "string"
    description: "نام header برای API key"
    default: "X-API-Key"
  bearer_token:
    type: "string"
    description: "توکن Bearer"
    required: false
  signature_secret:
    type: "string"
    description: "رمز امضا"
    required: false
  signature_header:
    type: "string"
    description: "نام header برای امضا"
    default: "X-Signature"
  rate_limit:
    type: "integer"
    description: "حداکثر درخواست در دقیقه"
    required: false
  validate_payload:
    type: "boolean"
    description: "اعتبارسنجی payload"
    default: false
  payload_schema:
    type: "object"
    description: "Schema برای اعتبارسنجی (JSON Schema)"
    required: false
  custom_response:
    type: "boolean"
    description: "استفاده از پاسخ سفارشی"
    default: false
  response_status_code:
    type: "integer"
    description: "کد وضعیت پاسخ"
    default: 200
  response_body:
    type: "string"
    description: "بدنه پاسخ"
    required: false
  timeout_seconds:
    type: "integer"
    description: "Timeout برای پردازش (ثانیه)"
    default: 30
```

---

## 🔷 Actions

### 1. SendEmailAction (ارسال ایمیل)

#### پیشنهادات بهبود عملکرد:
- **Template Engine**: موتور قالب برای ایمیل‌ها
- **Attachment Support**: پشتیبانی از پیوست
- **Priority Levels**: سطح اولویت ایمیل
- **Delivery Tracking**: ردیابی تحویل
- **Retry Mechanism**: تلاش مجدد در صورت خطا

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  to:
    type: "string"
    description: "آدرس ایمیل گیرنده"
    required: true
  cc:
    type: "array"
    description: "CC"
    items:
      type: "string"
    required: false
  bcc:
    type: "array"
    description: "BCC"
    items:
      type: "string"
    required: false
  subject:
    type: "string"
    description: "موضوع"
    required: true
  body:
    type: "string"
    description: "متن ایمیل"
    required: true
  html_body:
    type: "string"
    description: "متن HTML"
    required: false
  template_id:
    type: "integer"
    description: "شناسه قالب ایمیل"
    required: false
  template_variables:
    type: "object"
    description: "متغیرهای قالب"
    required: false
  attachments:
    type: "array"
    description: "پیوست‌ها"
    items:
      type: "object"
      properties:
        filename:
          type: "string"
        content:
          type: "string"
        content_type:
          type: "string"
    required: false
  priority:
    type: "string"
    description: "اولویت (low/normal/high)"
    enum: ["low", "normal", "high"]
    default: "normal"
  send_at:
    type: "string"
    description: "ارسال در زمان مشخص (ISO format)"
    required: false
  track_opens:
    type: "boolean"
    description: "ردیابی باز شدن ایمیل"
    default: false
  track_clicks:
    type: "boolean"
    description: "ردیابی کلیک‌ها"
    default: false
  retry_on_failure:
    type: "boolean"
    description: "تلاش مجدد در صورت خطا"
    default: true
  retry_attempts:
    type: "integer"
    description: "تعداد تلاش‌های مجدد"
    default: 3
  retry_delay_seconds:
    type: "integer"
    description: "تاخیر بین تلاش‌ها"
    default: 60
```

---

### 2. SendTelegramAction (ارسال تلگرام)

#### پیشنهادات بهبود عملکرد:
- **Rich Media Support**: پشتیبانی از تصویر، ویدیو، فایل
- **Keyboard Buttons**: دکمه‌های کیبورد
- **Inline Buttons**: دکمه‌های inline
- **Parse Mode**: حالت‌های مختلف پارس (HTML, Markdown)
- **Message Scheduling**: زمان‌بندی پیام

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  user_id:
    type: "integer"
    description: "شناسه کاربر"
    required: false
  chat_id:
    type: "string"
    description: "شناسه چت (جایگزین user_id)"
    required: false
  message:
    type: "string"
    description: "متن پیام"
    required: true
  parse_mode:
    type: "string"
    description: "حالت پارس (HTML/Markdown/None)"
    enum: ["HTML", "Markdown", "None"]
    default: "None"
  disable_web_page_preview:
    type: "boolean"
    description: "غیرفعال کردن پیش‌نمایش لینک"
    default: false
  disable_notification:
    type: "boolean"
    description: "ارسال بی‌صدا"
    default: false
  photo:
    type: "string"
    description: "URL یا path تصویر"
    required: false
  document:
    type: "string"
    description: "URL یا path فایل"
    required: false
  keyboard:
    type: "array"
    description: "کیبورد (دکمه‌ها)"
    items:
      type: "object"
    required: false
  inline_keyboard:
    type: "array"
    description: "کیبورد inline"
    items:
      type: "object"
    required: false
  reply_to_message_id:
    type: "integer"
    description: "پاسخ به پیام خاص"
    required: false
  send_at:
    type: "string"
    description: "ارسال در زمان مشخص"
    required: false
```

---

### 3. CreateNotificationAction (ایجاد Notification)

#### پیشنهادات بهبود عملکرد:
- **Multiple Channels**: ارسال به چند کانال (in-app, email, SMS, Push)
- **Priority Levels**: سطح اولویت
- **Expiration**: تاریخ انقضا
- **Action Buttons**: دکمه‌های عملیاتی
- **Rich Content**: محتوای غنی (HTML, images)

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  user_id:
    type: "integer"
    description: "شناسه کاربر"
    required: false
  event_key:
    type: "string"
    description: "کلید رویداد"
    required: true
  title:
    type: "string"
    description: "عنوان"
    required: true
  message:
    type: "string"
    description: "پیام"
    required: true
  channels:
    type: "array"
    description: "کانال‌های ارسال"
    items:
      type: "string"
      enum: ["inapp", "email", "sms", "push"]
    default: ["inapp"]
  priority:
    type: "string"
    description: "اولویت (low/normal/high/urgent)"
    enum: ["low", "normal", "high", "urgent"]
    default: "normal"
  category:
    type: "string"
    description: "دسته‌بندی"
    required: false
  icon:
    type: "string"
    description: "آیکون"
    required: false
  image_url:
    type: "string"
    description: "URL تصویر"
    required: false
  action_buttons:
    type: "array"
    description: "دکمه‌های عملیاتی"
    items:
      type: "object"
      properties:
        label:
          type: "string"
        action:
          type: "string"
        url:
          type: "string"
    required: false
  expires_at:
    type: "string"
    description: "تاریخ انقضا (ISO format)"
    required: false
  read_after_action:
    type: "boolean"
    description: "خوانده شده تلقی کردن بعد از کلیک روی دکمه"
    default: true
```

---

### 4. CreateDocumentAction (ایجاد سند)

#### پیشنهادات بهبود عملکرد:
- **Template Support**: پشتیبانی از قالب‌های سند
- **Auto Numbering**: شماره‌گذاری خودکار
- **Validation**: اعتبارسنجی قبل از ایجاد
- **Draft Mode**: حالت پیش‌نویس
- **Approval Workflow**: گردش کار تایید

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  document_type:
    type: "string"
    description: "نوع سند"
    required: true
  date:
    type: "string"
    description: "تاریخ سند"
    required: true
  description:
    type: "string"
    description: "شرح"
    required: false
  lines:
    type: "array"
    description: "خطوط سند"
    required: true
  template_id:
    type: "integer"
    description: "شناسه قالب"
    required: false
  auto_numbering:
    type: "boolean"
    description: "شماره‌گذاری خودکار"
    default: true
  numbering_sequence:
    type: "string"
    description: "سری شماره‌گذاری"
    required: false
  fiscal_year_id:
    type: "integer"
    description: "سال مالی (در صورت عدم مشخص، سال جاری استفاده می‌شود)"
    required: false
  status:
    type: "string"
    description: "وضعیت (draft/confirmed)"
    enum: ["draft", "confirmed"]
    default: "draft"
  require_approval:
    type: "boolean"
    description: "نیاز به تایید"
    default: false
  approver_user_id:
    type: "integer"
    description: "شناسه کاربر تاییدکننده"
    required: false
  validate_before_create:
    type: "boolean"
    description: "اعتبارسنجی قبل از ایجاد"
    default: true
  on_error:
    type: "string"
    description: "رفتار در صورت خطا (fail/skip/log)"
    enum: ["fail", "skip", "log"]
    default: "fail"
```

---

### 5. CreateInvoiceAction (ایجاد فاکتور)

#### پیشنهادات بهبود عملکرد:
- **Discount Support**: پشتیبانی از تخفیف
- **Tax Calculation**: محاسبه خودکار مالیات
- **Payment Terms**: شرایط پرداخت
- **Template System**: سیستم قالب
- **Auto Posting**: ثبت خودکار در دفاتر

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  invoice_type:
    type: "string"
    description: "نوع فاکتور"
    required: true
  person_id:
    type: "integer"
    description: "شناسه شخص"
    required: true
  items:
    type: "array"
    description: "آیتم‌های فاکتور"
    required: true
  currency_id:
    type: "integer"
    description: "شناسه ارز"
    required: false
  date:
    type: "string"
    description: "تاریخ فاکتور (ISO format)"
    required: false
  due_date:
    type: "string"
    description: "تاریخ سررسید"
    required: false
  payment_terms:
    type: "string"
    description: "شرایط پرداخت"
    required: false
  discount_type:
    type: "string"
    description: "نوع تخفیف (percentage/amount)"
    enum: ["percentage", "amount"]
    required: false
  discount_value:
    type: "number"
    description: "مقدار تخفیف"
    required: false
  auto_calculate_tax:
    type: "boolean"
    description: "محاسبه خودکار مالیات"
    default: true
  tax_rate:
    type: "number"
    description: "نرخ مالیات (در صورت عدم خودکار)"
    required: false
  template_id:
    type: "integer"
    description: "شناسه قالب"
    required: false
  status:
    type: "string"
    description: "وضعیت (draft/confirmed)"
    enum: ["draft", "confirmed"]
    default: "draft"
  auto_post:
    type: "boolean"
    description: "ثبت خودکار در دفاتر"
    default: false
  reference_number:
    type: "string"
    description: "شماره مرجع"
    required: false
  notes:
    type: "string"
    description: "یادداشت‌ها"
    required: false
```

---

### 6. UpdateInventoryAction (به‌روزرسانی موجودی)

#### پیشنهادات بهبود عملکرد:
- **Batch Updates**: به‌روزرسانی دسته‌ای
- **Transaction Logging**: ثبت لاگ تراکنش
- **Cost Calculation**: محاسبه هزینه
- **Lot/Serial Tracking**: ردیابی سریال/لوت
- **Reservation Support**: پشتیبانی از رزرو

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  product_id:
    type: "integer"
    description: "شناسه محصول"
    required: true
  warehouse_id:
    type: "integer"
    description: "شناسه انبار"
    required: true
  quantity:
    type: "number"
    description: "تغییر مقدار"
    required: true
  adjustment_type:
    type: "string"
    description: "نوع تنظیم (increase/decrease/set)"
    enum: ["increase", "decrease", "set"]
    default: "increase"
  reason:
    type: "string"
    description: "دلیل تنظیم"
    required: false
  reference_document_id:
    type: "integer"
    description: "شناسه سند مرجع"
    required: false
  reference_document_type:
    type: "string"
    description: "نوع سند مرجع"
    required: false
  cost_per_unit:
    type: "number"
    description: "هزینه هر واحد"
    required: false
  lot_number:
    type: "string"
    description: "شماره لوت"
    required: false
  serial_numbers:
    type: "array"
    description: "شماره‌های سریال"
    items:
      type: "string"
    required: false
  reservation_id:
    type: "integer"
    description: "شناسه رزرو (برای آزاد کردن رزرو)"
    required: false
  validate_stock:
    type: "boolean"
    description: "اعتبارسنجی موجودی قبل از کاهش"
    default: true
  allow_negative:
    type: "boolean"
    description: "اجازه موجودی منفی"
    default: false
  auto_post:
    type: "boolean"
    description: "ثبت خودکار"
    default: true
```

---

### 7. SetVariableAction (تنظیم متغیر)

#### پیشنهادات بهبود عملکرد:
- **Type Casting**: تبدیل نوع خودکار
- **Computed Values**: مقادیر محاسبه‌شده
- **Scoping**: محدوده متغیر (workflow/global)
- **Encryption**: رمزنگاری برای داده‌های حساس

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  variable_name:
    type: "string"
    description: "نام متغیر"
    required: true
  value:
    type: "any"
    description: "مقدار متغیر"
    required: true
  value_type:
    type: "string"
    description: "نوع مقدار (auto/string/number/boolean/object/array)"
    enum: ["auto", "string", "number", "boolean", "object", "array"]
    default: "auto"
  scope:
    type: "string"
    description: "محدوده (workflow/global)"
    enum: ["workflow", "global"]
    default: "workflow"
  encrypt:
    type: "boolean"
    description: "رمزنگاری مقدار"
    default: false
  expiration_seconds:
    type: "integer"
    description: "زمان انقضا (ثانیه)"
    required: false
  computed:
    type: "boolean"
    description: "مقدار محاسبه‌شده"
    default: false
  expression:
    type: "string"
    description: "عبارت محاسبه (برای computed=true)"
    required: false
  default_value:
    type: "any"
    description: "مقدار پیش‌فرض در صورت خطا"
    required: false
```

---

### 8. LogAction (ثبت لاگ)

#### پیشنهادات بهبود عملکرد:
- **Structured Logging**: لاگ ساختاریافته (JSON)
- **Log Aggregation**: تجمیع لاگ‌ها
- **Log Rotation**: چرخش لاگ‌ها
- **Alert Integration**: یکپارچه‌سازی با سیستم هشدار

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  level:
    type: "string"
    description: "سطح لاگ"
    enum: ["debug", "info", "warning", "error", "critical"]
    default: "info"
  message:
    type: "string"
    description: "پیام لاگ"
    required: true
  data:
    type: "object"
    description: "داده‌های اضافی"
    required: false
  structured:
    type: "boolean"
    description: "لاگ ساختاریافته (JSON)"
    default: false
  include_context:
    type: "boolean"
    description: "شامل context workflow"
    default: true
  include_node_results:
    type: "boolean"
    description: "شامل نتایج nodeها"
    default: false
  tags:
    type: "array"
    description: "برچسب‌ها"
    items:
      type: "string"
    required: false
  send_alert:
    type: "boolean"
    description: "ارسال هشدار برای سطح error/critical"
    default: false
  alert_channels:
    type: "array"
    description: "کانال‌های هشدار"
    items:
      type: "string"
    required: false
  retention_days:
    type: "integer"
    description: "مدت نگهداری لاگ (روز)"
    default: 30
```

---

### 9. HttpRequestAction (ارسال HTTP Request)

#### پیشنهادات بهبود عملکرد:
- **Advanced Auth**: احراز هویت پیشرفته (OAuth, JWT)
- **Request/Response Transformation**: تبدیل درخواست/پاسخ
- **Circuit Breaker**: قطع کننده مدار برای جلوگیری از overload
- **Retry with Exponential Backoff**: تلاش مجدد با تاخیر نمایی
- **Response Caching**: کش کردن پاسخ‌ها

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  url:
    type: "string"
    description: "URL مقصد"
    required: true
  method:
    type: "string"
    description: "روش HTTP"
    enum: ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
    default: "POST"
  headers:
    type: "object"
    description: "هدرهای HTTP"
    required: false
  query_params:
    type: "object"
    description: "پارامترهای query string"
    required: false
  body:
    type: "any"
    description: "بدنه درخواست"
    required: false
  body_type:
    type: "string"
    description: "نوع بدنه (json/form/raw)"
    enum: ["json", "form", "raw"]
    default: "json"
  auth_type:
    type: "string"
    description: "نوع احراز هویت (none/basic/bearer/oauth/jwt)"
    enum: ["none", "basic", "bearer", "oauth", "jwt"]
    default: "none"
  auth_config:
    type: "object"
    description: "تنظیمات احراز هویت"
    required: false
  timeout_seconds:
    type: "integer"
    description: "Timeout (ثانیه)"
    default: 30
  retry_on_failure:
    type: "boolean"
    description: "تلاش مجدد در صورت خطا"
    default: true
  retry_attempts:
    type: "integer"
    description: "تعداد تلاش‌های مجدد"
    default: 3
  retry_delay_seconds:
    type: "integer"
    description: "تاخیر پایه (ثانیه)"
    default: 1
  exponential_backoff:
    type: "boolean"
    description: "استفاده از تاخیر نمایی"
    default: true
  retryable_status_codes:
    type: "array"
    description: "کدهای وضعیت قابل retry"
    items:
      type: "integer"
    default: [500, 502, 503, 504]
  circuit_breaker_enabled:
    type: "boolean"
    description: "فعال کردن circuit breaker"
    default: false
  circuit_breaker_threshold:
    type: "integer"
    description: "آستانه خطا برای باز کردن مدار"
    default: 5
  cache_response:
    type: "boolean"
    description: "کش کردن پاسخ"
    default: false
  cache_ttl_seconds:
    type: "integer"
    description: "زمان زندگی کش (ثانیه)"
    default: 300
  cache_key:
    type: "string"
    description: "کلید کش (در صورت عدم مشخص، از URL و params استفاده می‌شود)"
    required: false
  transform_request:
    type: "boolean"
    description: "تبدیل درخواست"
    default: false
  request_script:
    type: "string"
    description: "اسکریپت تبدیل درخواست (JavaScript/Python)"
    required: false
  transform_response:
    type: "boolean"
    description: "تبدیل پاسخ"
    default: false
  response_script:
    type: "string"
    description: "اسکریپت تبدیل پاسخ"
    required: false
  validate_response:
    type: "boolean"
    description: "اعتبارسنجی پاسخ"
    default: false
  response_schema:
    type: "object"
    description: "Schema برای اعتبارسنجی (JSON Schema)"
    required: false
```

---

## 🔷 Conditions

### پیشنهادات بهبود Condition Node

#### پیشنهادات بهبود عملکرد:
- **Complex Conditions**: پشتیبانی از شرط‌های پیچیده (AND, OR, NOT)
- **Multiple Comparisons**: چندین مقایسه همزمان
- **Array Operations**: عملیات روی آرایه (contains, in, not in)
- **String Operations**: عملیات رشته (starts with, ends with, contains, regex)
- **Date/Time Comparisons**: مقایسه تاریخ/زمان
- **Nested Conditions**: شرط‌های تو در تو

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  condition_type:
    type: "string"
    description: "نوع شرط (simple/complex/expression)"
    enum: ["simple", "complex", "expression"]
    default: "simple"
  # برای condition_type=simple
  left_value:
    type: "any"
    description: "مقدار چپ"
    required: false
  operator:
    type: "string"
    description: "عملگر"
    enum: ["==", "!=", ">", "<", ">=", "<=", "contains", "not_contains", "starts_with", "ends_with", "in", "not_in", "regex", "is_null", "is_not_null"]
    default: "=="
  right_value:
    type: "any"
    description: "مقدار راست"
    required: false
  # برای condition_type=complex
  logical_operator:
    type: "string"
    description: "عملگر منطقی (AND/OR)"
    enum: ["AND", "OR"]
    default: "AND"
  conditions:
    type: "array"
    description: "لیست شرط‌ها"
    items:
      type: "object"
    required: false
  # برای condition_type=expression
  expression:
    type: "string"
    description: "عبارت شرط (JavaScript/Python)"
    required: false
  case_sensitive:
    type: "boolean"
    description: "حساس به حروف بزرگ/کوچک"
    default: true
  date_format:
    type: "string"
    description: "فرمت تاریخ برای مقایسه"
    default: "ISO"
  timezone:
    type: "string"
    description: "Timezone برای مقایسه تاریخ/زمان"
    default: "Asia/Tehran"
  on_error:
    type: "string"
    description: "رفتار در صورت خطا (fail/false/true)"
    enum: ["fail", "false", "true"]
    default: "fail"
```

---

## 🔷 Loops

### پیشنهادات بهبود Loop Node

**توجه**: حلقه‌ها در حال حاضر پیاده‌سازی نشده‌اند. پیشنهادات برای پیاده‌سازی:

#### پیشنهادات بهبود عملکرد:
- **For Each Loop**: حلقه روی آرایه/لیست
- **For Range Loop**: حلقه روی بازه عددی
- **While Loop**: حلقه شرطی
- **Break/Continue**: کنترل جریان
- **Parallel Execution**: اجرای موازی
- **Batch Processing**: پردازش دسته‌ای

#### تنظیمات پیشنهادی جدید:
```yaml
config_schema:
  loop_type:
    type: "string"
    description: "نوع حلقه (for_each/for_range/while)"
    enum: ["for_each", "for_range", "while"]
    required: true
  # برای loop_type=for_each
  items_source:
    type: "string"
    description: "منبع آیتم‌ها (reference به node یا variable)"
    required: false
  item_variable:
    type: "string"
    description: "نام متغیر برای هر آیتم"
    default: "item"
  index_variable:
    type: "string"
    description: "نام متغیر برای ایندکس"
    default: "index"
  # برای loop_type=for_range
  start:
    type: "integer"
    description: "شروع"
    required: false
  end:
    type: "integer"
    description: "پایان"
    required: false
  step:
    type: "integer"
    description: "گام"
    default: 1
  # برای loop_type=while
  condition:
    type: "object"
    description: "شرط تداوم حلقه"
    required: false
  max_iterations:
    type: "integer"
    description: "حداکثر تعداد تکرار (برای جلوگیری از infinite loop)"
    default: 1000
  parallel_execution:
    type: "boolean"
    description: "اجرای موازی"
    default: false
  max_parallel:
    type: "integer"
    description: "حداکثر تعداد اجرای موازی"
    default: 5
  batch_size:
    type: "integer"
    description: "اندازه دسته برای پردازش دسته‌ای"
    required: false
  break_on_error:
    type: "boolean"
    description: "توقف در صورت خطا"
    default: false
  continue_on_error:
    type: "boolean"
    description: "ادامه در صورت خطا"
    default: false
```

---

## 🔷 بهبودهای کلی موتور Workflow

### 1. Performance Optimizations

#### پیشنهادات:
- **Connection Pooling**: Pool اتصالات دیتابیس
- **Async Execution**: اجرای ناهمزمان برای actionهای مستقل
- **Caching**: کش کردن نتایج nodeها برای استفاده مجدد
- **Lazy Loading**: بارگذاری تنبل برای nodeهای بزرگ
- **Batch Processing**: پردازش دسته‌ای workflowهای متعدد

#### پیاده‌سازی:
```python
# مثال: Caching برای node results
class WorkflowEngine:
    def __init__(self, ...):
        self.result_cache = {}
        self.cache_ttl = 300  # 5 minutes
    
    def _execute_node(self, node, context, node_results):
        cache_key = self._get_cache_key(node, context)
        if cache_key in self.result_cache:
            cached_result, timestamp = self.result_cache[cache_key]
            if time.time() - timestamp < self.cache_ttl:
                return cached_result
        # ... execute node ...
        self.result_cache[cache_key] = (result, time.time())
        return result
```

---

### 2. Error Handling & Resilience

#### پیشنهادات:
- **Retry Policies**: سیاست‌های retry قابل تنظیم
- **Circuit Breaker**: قطع کننده مدار برای جلوگیری از overload
- **Fallback Actions**: actionهای جایگزین در صورت خطا
- **Error Recovery**: بازیابی از خطا
- **Dead Letter Queue**: صف برای workflowهای ناموفق

#### تنظیمات پیشنهادی:
```yaml
workflow_config:
  error_handling:
    strategy: "fail_fast"  # fail_fast, continue, retry
    retry_policy:
      max_attempts: 3
      initial_delay: 1
      max_delay: 60
      exponential_backoff: true
    circuit_breaker:
      enabled: true
      failure_threshold: 5
      timeout_seconds: 60
    fallback_action:
      enabled: false
      action_type: "log"
      action_config: {}
    dead_letter_queue:
      enabled: true
      max_retries: 3
```

---

### 3. Monitoring & Observability

#### پیشنهادات:
- **Metrics Collection**: جمع‌آوری معیارها
- **Performance Tracking**: ردیابی عملکرد
- **Slow Query Detection**: تشخیص queryهای کند
- **Resource Usage Monitoring**: نظارت بر استفاده از منابع
- **Alerting**: سیستم هشدار

#### معیارهای پیشنهادی:
- زمان اجرای هر node
- تعداد اجراهای موفق/ناموفق
- میزان خطا (error rate)
- استفاده از حافظه
- استفاده از CPU
- تعداد workflowهای در حال اجرا

---

### 4. Security Enhancements

#### پیشنهادات:
- **Input Validation**: اعتبارسنجی ورودی‌ها
- **Output Sanitization**: پاکسازی خروجی‌ها
- **Access Control**: کنترل دسترسی بر اساس نقش
- **Audit Logging**: ثبت لاگ audit
- **Encryption**: رمزنگاری داده‌های حساس
- **Rate Limiting**: محدود کردن نرخ

---

### 5. Developer Experience

#### پیشنهادات:
- **Template Library**: کتابخانه قالب‌های workflow
- **Workflow Testing**: تست workflow قبل از اجرا
- **Dry Run Mode**: حالت اجرای آزمایشی
- **Visual Debugging**: دیباگ بصری
- **Step-by-step Execution**: اجرای گام به گام
- **Variable Inspector**: بازرسی متغیرها

---

### 6. Scalability

#### پیشنهادات:
- **Horizontal Scaling**: مقیاس‌پذیری افقی
- **Queue System**: سیستم صف برای workflowهای زیاد
- **Distributed Execution**: اجرای توزیع‌شده
- **Load Balancing**: توزیع بار
- **Resource Isolation**: جداسازی منابع

---

## 📊 خلاصه اولویت‌ها

### اولویت بالا (Quick Wins):
1. اضافه کردن retry mechanism به همه actionها
2. اضافه کردن timeout به همه operationها
3. بهبود error handling
4. اضافه کردن logging بهتر

### اولویت متوسط:
1. اضافه کردن فیلترهای بیشتر به triggerها
2. اضافه کردن template system
3. بهبود condition node با شرط‌های پیچیده
4. اضافه کردن monitoring

### اولویت پایین (Long-term):
1. پیاده‌سازی loop node
2. Distributed execution
3. Advanced caching
4. Circuit breaker

---

## 📝 یادداشت‌های پیاده‌سازی

### نکات مهم:
1. همه تنظیمات جدید باید **backward compatible** باشند
2. باید **default values** مناسب برای همه تنظیمات تعریف شود
3. باید **validation** برای همه تنظیمات اضافه شود
4. باید **documentation** کامل برای هر تنظیمات نوشته شود
5. باید **unit tests** برای همه بهبودها نوشته شود

### مراحل پیاده‌سازی:
1. فاز 1: بهبود triggerها (2-3 هفته)
2. فاز 2: بهبود actionها (3-4 هفته)
3. فاز 3: بهبود condition و loop (2-3 هفته)
4. فاز 4: بهبودهای کلی موتور (2-3 هفته)

---

*این سند به صورت مداوم به‌روزرسانی خواهد شد.*

