# سناریو مانیتورینگ سیستم (System Monitoring Scenario)

## 📋 فهرست مطالب
1. [مقدمه](#مقدمه)
2. [اهداف و نیازمندی‌ها](#اهداف-و-نیازمندی‌ها)
3. [معماری سیستم مانیتورینگ](#معماری-سیستم-مانیتورینگ)
4. [بخش‌های مانیتورینگ](#بخش‌های-مانیتورینگ)
5. [رابط کاربری (UI)](#رابط-کاربری-ui)
6. [به‌روزرسانی لحظه‌ای](#به‌روزرسانی-لحظه‌ای)
7. [نمودارها و چارت‌ها](#نمودارها-و-چارت‌ها)
8. [گزارشات](#گزارشات)
9. [هشدارها و آلارم‌ها](#هشدارها-و-آلارم‌ها)
10. [API Endpoints](#api-endpoints)
11. [پیاده‌سازی Backend](#پیاده‌سازی-backend)
12. [پیاده‌سازی Frontend](#پیاده‌سازی-frontend)

---

## مقدمه

سیستم مانیتورینگ برای مدیران سیستم طراحی شده است تا بتوانند وضعیت کلی سیستم، منابع سخت‌افزاری، سرویس‌ها و عملکرد اجزای مختلف را به صورت لحظه‌ای و در قالب نمودارها و گزارشات مشاهده کنند.

---

## اهداف و نیازمندی‌ها

### اهداف اصلی:
1. **مانیتورینگ منابع سخت‌افزاری**: CPU، RAM، Disk، Network
2. **مانیتورینگ سرویس‌ها**: API Server، Database، Redis Cache، Background Workers
3. **مانیتورینگ عملکرد**: Response Time، Request Rate، Error Rate
4. **گزارشات قابل دانلود**: PDF، Excel، CSV
5. **هشدارهای خودکار**: در صورت بروز مشکل
6. **تاریخچه و تحلیل روند**: برای بررسی الگوهای استفاده

### نیازمندی‌های عملکردی:
- **به‌روزرسانی لحظه‌ای**: بروزرسانی هر 1-5 ثانیه برای metrics حساس
- **ذخیره‌سازی داده‌ها**: نگهداری تاریخچه حداقل 30 روز
- **دسترسی محدود**: فقط مدیران سیستم (superadmin یا permission خاص)
- **عملکرد بالا**: استفاده از cache برای کاهش بار دیتابیس

---

## معماری سیستم مانیتورینگ

```
┌─────────────────┐
│   Frontend UI   │  (Flutter - Real-time Dashboard)
│                 │
│  - WebSocket    │
│  - Charts       │
│  - Alerts       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Backend API    │  (FastAPI)
│                 │
│  - /monitoring  │
│  - /metrics     │
│  - WebSocket    │
└────────┬────────┘
         │
         ├──────────────────┬──────────────────┐
         ▼                  ▼                  ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│   Database   │   │  Redis Cache │   │  System APIs │
│              │   │              │   │              │
│ - Metrics    │   │ - Real-time  │   │ - psutil     │
│ - History    │   │ - Aggregated │   │ - systemctl  │
│ - Alerts     │   │              │   │              │
└──────────────┘   └──────────────┘   └──────────────┘
```

---

## بخش‌های مانیتورینگ

### 1. مانیتورینگ منابع سخت‌افزاری (Hardware Resources)

#### 1.1 CPU (پردازنده)
- **استفاده CPU (%)**: درصد استفاده از CPU
- **Core Count**: تعداد هسته‌ها
- **Load Average**: میانگین بار سیستم (1min, 5min, 15min)
- **Process Top Consumers**: پردازه‌های پرمصرف CPU
- **نمودار**: Line Chart با زمان واقعی (Real-time)
- **بازه زمانی**: 1 دقیقه، 5 دقیقه، 1 ساعت، 24 ساعت

#### 1.2 Memory (حافظه)
- **RAM استفاده شده / کل (GB/MB)**: درصد و مقدار استفاده
- **Swap استفاده شده / کل**: استفاده از Swap
- **Memory Breakdown**: تفکیک استفاده (System, Cache, Buffers, Applications)
- **Memory Top Consumers**: پردازه‌های پرمصرف حافظه
- **نمودار**: Stacked Area Chart
- **هشدار**: در صورت استفاده بیش از 85% از RAM

#### 1.3 Disk (دیسک)
- **فضای استفاده شده / کل (GB/TB)**: برای هر پارتیشن
- **I/O Rate**: خواندن/نوشتن در ثانیه (IOPS)
- **I/O Wait**: زمان انتظار I/O
- **Disk Usage by Directory**: استفاده فضای هر دایرکتوری
- **نمودار**: Pie Chart برای فضا، Line Chart برای I/O
- **هشدار**: در صورت پر شدن بیش از 90% از فضا

#### 1.4 Network (شبکه)
- **Bandwidth استفاده شده (Mbps/Gbps)**: Upload/Download
- **Packets**: تعداد بسته‌های ارسالی/دریافتی
- **Connections**: تعداد اتصالات فعال
- **Network Interface Stats**: آمار هر رابط شبکه
- **نمودار**: Dual-axis Line Chart (Upload/Download)
- **بازه زمانی**: Real-time و تاریخی

---

### 2. مانیتورینگ سرویس‌ها (Services Monitoring)

#### 2.1 API Server
- **Status**: آنلاین/آفلاین
- **Uptime**: مدت زمان فعالیت
- **Version**: نسخه API
- **Workers**: تعداد worker های فعال
- **Active Connections**: اتصالات فعال
- **Response Time**: میانگین زمان پاسخ
- **Request Rate**: درخواست در ثانیه (RPS)
- **Error Rate**: درصد خطا (4xx, 5xx)
- **Health Check**: آخرین وضعیت health endpoint

#### 2.2 Database (PostgreSQL/SQLite)
- **Status**: متصل/قطع شده
- **Connection Pool**: تعداد اتصالات فعال/حداکثر
- **Query Performance**: تعداد query های کند
- **Slow Queries**: لیست query های کند (بیش از 1 ثانیه)
- **Database Size**: حجم دیتابیس
- **Table Sizes**: حجم هر جدول
- **Cache Hit Rate**: نرخ موفقیت cache
- **Lock Statistics**: آمار قفل‌ها

#### 2.3 Redis Cache
- **Status**: فعال/غیرفعال
- **Memory Usage**: استفاده حافظه
- **Keys Count**: تعداد کلیدها
- **Hit/Miss Rate**: نرخ موفقیت cache
- **Commands per Second**: تعداد دستورات در ثانیه
- **Connected Clients**: کلاینت‌های متصل
- **Eviction Policy**: سیاست حذف

#### 2.4 Background Workers (RQ Workers)
- **Status**: فعال/غیرفعال
- **Queue Length**: تعداد کارهای در صف
- **Processing Rate**: نرخ پردازش
- **Failed Jobs**: تعداد کارهای ناموفق
- **Worker Status**: وضعیت هر worker
- **Job History**: تاریخچه کارها

#### 2.5 External Services
- **Email Service**: وضعیت سرویس ایمیل
- **SMS Service**: وضعیت سرویس پیامک
- **Telegram Bot**: وضعیت ربات تلگرام
- **Payment Gateways**: وضعیت درگاه‌های پرداخت

---

### 3. مانیتورینگ عملکرد (Performance Monitoring)

#### 3.1 API Endpoints
- **Endpoint Performance**: آمار عملکرد هر endpoint
  - تعداد درخواست‌ها
  - میانگین زمان پاسخ
  - حداکثر زمان پاسخ
  - نرخ خطا
- **Slow Endpoints**: endpoint های کند (بیش از 1 ثانیه)
- **Error Endpoints**: endpoint هایی با بیشترین خطا
- **Top Endpoints**: پرکاربردترین endpoint ها
- **نمودار**: Heatmap برای زمان پاسخ، Bar Chart برای تعداد درخواست‌ها

#### 3.2 Request Statistics
- **Total Requests**: کل درخواست‌ها
- **Requests per Second**: RPS
- **Response Time Distribution**: توزیع زمان پاسخ
- **Status Code Distribution**: توزیع کدهای وضعیت
- **User Activity**: فعالیت کاربران
- **Peak Hours**: ساعات پیک

#### 3.3 Application Metrics
- **Active Users**: کاربران فعال
- **Concurrent Sessions**: جلسات همزمان
- **API Usage by User**: استفاده API توسط کاربر
- **Business Activity**: فعالیت کسب‌وکارها
- **File Upload/Download**: آپلود/دانلود فایل

---

## رابط کاربری (UI)

### 4.1 صفحه اصلی Dashboard

```
┌─────────────────────────────────────────────────────────────┐
│  System Monitoring Dashboard                    [⚙️ Settings]│
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌─────────┐│
│  │ CPU        │  │ Memory     │  │ Disk       │  │ Network ││
│  │ 45%        │  │ 6.2/16 GB  │  │ 120/500 GB │  │ 15 Mbps ││
│  │ 🟢 Normal  │  │ 🟢 Normal  │  │ 🟢 Normal  │  │ 🟢 OK   ││
│  └────────────┘  └────────────┘  └────────────┘  └─────────┘│
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  System Resources (Last 1 Hour)                          ││
│  │                                                           ││
│  │  [CPU Usage Chart - Line Chart]                          ││
│  │  [Memory Usage Chart - Area Chart]                       ││
│  │                                                           ││
│  └─────────────────────────────────────────────────────────┘│
│                                                               │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌─────────┐│
│  │ API Server │  │ Database   │  │ Redis      │  │ Workers ││
│  │ 🟢 Online  │  │ 🟢 OK      │  │ 🟢 Active  │  │ 4 Active││
│  │ Uptime: 7d │  │ 25/100 Conn│  │ 95% Hit    │  │ 0 Queue ││
│  └────────────┘  └────────────┘  └────────────┘  └─────────┘│
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  API Performance (Last 1 Hour)                           ││
│  │                                                           ││
│  │  [Request Rate Chart - Bar Chart]                        ││
│  │  [Response Time Chart - Line Chart]                      ││
│  │                                                           ││
│  └─────────────────────────────────────────────────────────┘│
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 تب‌های مختلف

1. **Overview (نمای کلی)**: خلاصه وضعیت سیستم
2. **Hardware (سخت‌افزار)**: منابع سخت‌افزاری
3. **Services (سرویس‌ها)**: وضعیت سرویس‌ها
4. **Performance (عملکرد)**: آمار عملکرد API
5. **Logs (لاگ‌ها)**: لاگ‌های سیستم
6. **Alerts (هشدارها)**: هشدارها و آلارم‌ها
7. **Reports (گزارشات)**: گزارشات قابل دانلود

### 4.3 فیلترها و تنظیمات

- **بازه زمانی**: 1 دقیقه، 5 دقیقه، 1 ساعت، 6 ساعت، 24 ساعت، 7 روز، 30 روز
- **Auto-refresh**: فعال/غیرفعال کردن بروزرسانی خودکار
- **Refresh Interval**: تنظیم فاصله بروزرسانی (1s, 5s, 10s, 30s, 1m)
- **Export**: خروجی گرفتن از داده‌ها

---

## به‌روزرسانی لحظه‌ای

### 5.1 WebSocket Connection

برای بروزرسانی لحظه‌ای از **WebSocket** استفاده می‌شود:

```javascript
// Frontend (Flutter)
WebSocket connection → Backend
  ↓
Subscribe to channels:
  - hardware:metrics
  - services:status
  - api:performance
  - alerts:new
```

**Backend Endpoints:**
- `WS /api/v1/admin/monitoring/stream` - WebSocket endpoint برای دریافت داده‌های لحظه‌ای

**Data Format:**
```json
{
  "channel": "hardware:metrics",
  "timestamp": "2024-01-01T12:00:00Z",
  "data": {
    "cpu_percent": 45.2,
    "memory_percent": 62.5,
    "disk_usage": 120.5,
    "network_in": 15.2,
    "network_out": 8.7
  }
}
```

### 5.2 Polling Fallback

در صورت عدم دسترسی به WebSocket، از **HTTP Polling** استفاده می‌شود:
- فاصله پیش‌فرض: 5 ثانیه
- قابل تنظیم: 1-60 ثانیه

### 5.3 Cache Strategy

- **Real-time Data**: در Redis با TTL 10 ثانیه
- **Historical Data**: در دیتابیس هر 1 دقیقه
- **Aggregated Data**: هر 5 دقیقه برای بهینه‌سازی

---

## نمودارها و چارت‌ها

### 6.1 کتابخانه‌های پیشنهادی

**Flutter:**
- `fl_chart` - برای نمودارهای تعاملی
- `syncfusion_flutter_charts` - کتابخانه کامل و قدرتمند
- `charts_flutter` - از Google

### 6.2 انواع نمودارها

#### 6.2.1 Line Chart (نمودار خطی)
- **موارد استفاده**: CPU Usage، Memory Usage، Response Time، Request Rate
- **ویژگی‌ها**: چند خطی (Multi-line)، زوم (Zoom)، Tooltip
- **رنگ‌بندی**: رنگ‌های مختلف برای هر metric

#### 6.2.2 Area Chart (نمودار ناحیه‌ای)
- **موارد استفاده**: Memory Breakdown، Disk Usage over time
- **ویژگی‌ها**: Stacked Area، Gradient Fill
- **شفافیت**: نمایش چند metric همزمان

#### 6.2.3 Bar Chart (نمودار میله‌ای)
- **موارد استفاده**: Request Count by Endpoint، Error Count، Top Users
- **ویژگی‌ها**: Horizontal/Vertical، Grouped Bar
- **تعاملی**: قابلیت کلیک برای جزئیات بیشتر

#### 6.2.4 Pie Chart (نمودار دایره‌ای)
- **موارد استفاده**: Disk Usage by Partition، Status Code Distribution
- **ویژگی‌ها**: Legend، Percentage Labels
- **انیمیشن**: انیمیشن هنگام بارگذاری

#### 6.2.5 Heatmap (نقشه حرارتی)
- **موارد استفاده**: API Response Time by Endpoint and Time
- **ویژگی‌ها**: رنگ‌بندی بر اساس شدت
- **تعاملی**: Tooltip با جزئیات

#### 6.2.6 Gauge Chart (نمودار عقربه‌ای)
- **موارد استفاده**: CPU Usage، Memory Usage، Disk Usage
- **ویژگی‌ها**: نشان دادن درصد استفاده
- **هشدار**: تغییر رنگ در آستانه خطر

#### 6.2.7 Real-time Sparklines (نمودارهای کوچک)
- **موارد استفاده**: نمایش سریع در کارت‌ها
- **ویژگی‌ها**: ساده و سریع
- **بهینه‌سازی**: فقط آخرین 50 نقطه

### 6.3 ویژگی‌های مشترک

- **Zoom & Pan**: زوم و جابجایی در نمودارها
- **Tooltip**: نمایش مقدار دقیق هنگام hover/tap
- **Legend**: راهنمای نمودار
- **Responsive**: سازگار با اندازه‌های مختلف صفحه
- **Dark Mode**: پشتیبانی از حالت تاریک
- **Export**: خروجی تصویر (PNG, SVG)

---

## گزارشات

### 7.1 انواع گزارشات

#### 7.1.1 گزارش روزانه (Daily Report)
- **محتوا**: خلاصه عملکرد در 24 ساعت گذشته
- **شامل**: 
  - استفاده منابع (CPU, RAM, Disk, Network)
  - آمار API (Requests, Errors, Response Time)
  - وضعیت سرویس‌ها
  - هشدارها و خطاها
- **فرمت**: PDF, Excel, CSV

#### 7.1.2 گزارش هفتگی (Weekly Report)
- **محتوا**: تحلیل روند در 7 روز گذشته
- **شامل**: 
  - نمودارهای روند
  - مقایسه با هفته قبل
  - Peak Hours
  - توصیه‌های بهینه‌سازی
- **فرمت**: PDF

#### 7.1.3 گزارش ماهانه (Monthly Report)
- **محتوا**: بررسی جامع در 30 روز گذشته
- **شامل**: 
  - تحلیل کامل عملکرد
  - الگوهای استفاده
  - پیش‌بینی روند
  - توصیه‌های استراتژیک
- **فرمت**: PDF با نمودارهای کامل

#### 7.1.4 گزارش سفارشی (Custom Report)
- **انتخاب بازه زمانی**: از تاریخ تا تاریخ
- **انتخاب Metrics**: انتخاب metrics مورد نظر
- **انتخاب فرمت**: PDF, Excel, CSV, JSON
- **فیلترها**: فیلتر بر اساس سرویس، endpoint، و غیره

### 7.2 قالب گزارشات

#### 7.2.1 PDF Report
- **Header**: لوگو و عنوان گزارش
- **Executive Summary**: خلاصه اجرایی
- **Detailed Charts**: نمودارهای تفصیلی
- **Tables**: جداول داده‌ها
- **Footer**: تاریخ و زمان تولید

#### 7.2.2 Excel Report
- **Multiple Sheets**: 
  - Summary
  - Hardware Metrics
  - Service Status
  - API Performance
  - Alerts
- **Charts**: نمودارهای Excel
- **Pivot Tables**: جداول محوری

#### 7.2.3 CSV Report
- **Raw Data**: داده‌های خام
- **CSV Format**: قابل استفاده در Excel و Google Sheets
- **Multiple Files**: فایل جداگانه برای هر metric

### 7.3 برنامه‌ریزی گزارشات

- **Scheduled Reports**: گزارشات زمان‌بندی شده
  - روزانه: هر روز ساعت 8 صبح
  - هفتگی: هر دوشنبه ساعت 8 صبح
  - ماهانه: اول هر ماه ساعت 8 صبح
- **Email Delivery**: ارسال خودکار به ایمیل مدیر
- **Storage**: ذخیره گزارشات در سیستم (حداقل 1 سال)

---

## هشدارها و آلارم‌ها

### 8.1 انواع هشدارها

#### 8.1.1 هشدارهای منابع سخت‌افزاری
- **CPU**: استفاده بیش از 90% برای بیش از 5 دقیقه
- **Memory**: استفاده بیش از 85% برای بیش از 5 دقیقه
- **Disk**: استفاده بیش از 90% یا کمتر از 10% فضای خالی
- **Network**: استفاده بیش از 80% از bandwidth

#### 8.1.2 هشدارهای سرویس‌ها
- **API Server**: قطع سرویس یا عدم پاسخ
- **Database**: قطع اتصال یا خطای query
- **Redis**: قطع اتصال یا خطای cache
- **Workers**: توقف worker یا صف بیش از 1000 کار

#### 8.1.3 هشدارهای عملکرد
- **Response Time**: میانگین زمان پاسخ بیش از 2 ثانیه
- **Error Rate**: نرخ خطا بیش از 5%
- **Slow Queries**: query های کند بیش از 10 در دقیقه
- **Failed Jobs**: کارهای ناموفق بیش از 10 در ساعت

### 8.2 سطوح هشدار

1. **Info (اطلاعات)**: فقط اطلاع‌رسانی
2. **Warning (هشدار)**: نیاز به توجه
3. **Critical (بحرانی)**: نیاز به اقدام فوری

### 8.3 کانال‌های ارسال هشدار

- **درون برنامه (In-app)**: نمایش در Dashboard
- **ایمیل**: ارسال به مدیر سیستم
- **تلگرام**: ارسال به گروه/کانال تلگرام (اختیاری)
- **SMS**: برای هشدارهای بحرانی (اختیاری)

### 8.4 تنظیمات هشدار

- **Thresholds**: تنظیم آستانه‌ها
- **Notification Channels**: انتخاب کانال‌های اطلاع‌رسانی
- **Cooldown Period**: فاصله بین هشدارهای مشابه (برای جلوگیری از spam)
- **Alert Rules**: قوانین سفارشی برای هشدارها

---

## API Endpoints

### 9.1 Hardware Monitoring

```
GET /api/v1/admin/monitoring/hardware/current
  - دریافت وضعیت فعلی منابع سخت‌افزاری

GET /api/v1/admin/monitoring/hardware/history
  - دریافت تاریخچه منابع سخت‌افزاری
  - Query params: start_time, end_time, interval

GET /api/v1/admin/monitoring/hardware/top-processes
  - دریافت پردازه‌های پرمصرف
```

### 9.2 Services Monitoring

```
GET /api/v1/admin/monitoring/services/status
  - دریافت وضعیت همه سرویس‌ها

GET /api/v1/admin/monitoring/services/{service_name}/status
  - دریافت وضعیت یک سرویس خاص

GET /api/v1/admin/monitoring/services/{service_name}/metrics
  - دریافت metrics یک سرویس خاص
```

### 9.3 Performance Monitoring

```
GET /api/v1/admin/monitoring/performance/overview
  - دریافت خلاصه عملکرد

GET /api/v1/admin/monitoring/performance/endpoints
  - دریافت آمار endpoint ها

GET /api/v1/admin/monitoring/performance/slow-endpoints
  - دریافت endpoint های کند

GET /api/v1/admin/monitoring/performance/error-endpoints
  - دریافت endpoint هایی با بیشترین خطا
```

### 9.4 WebSocket

```
WS /api/v1/admin/monitoring/stream
  - WebSocket endpoint برای دریافت داده‌های لحظه‌ای
  - Subscribe to channels:
    - hardware:metrics
    - services:status
    - api:performance
    - alerts:new
```

### 9.5 Reports

```
GET /api/v1/admin/monitoring/reports
  - دریافت لیست گزارشات

POST /api/v1/admin/monitoring/reports/generate
  - تولید گزارش سفارشی
  - Body: { start_time, end_time, metrics, format }

GET /api/v1/admin/monitoring/reports/{report_id}/download
  - دانلود گزارش
```

### 9.6 Alerts

```
GET /api/v1/admin/monitoring/alerts
  - دریافت لیست هشدارها

GET /api/v1/admin/monitoring/alerts/active
  - دریافت هشدارهای فعال

POST /api/v1/admin/monitoring/alerts/{alert_id}/acknowledge
  - تایید هشدار

GET /api/v1/admin/monitoring/alerts/settings
  - دریافت تنظیمات هشدارها

PUT /api/v1/admin/monitoring/alerts/settings
  - به‌روزرسانی تنظیمات هشدارها
```

---

## پیاده‌سازی Backend

### 10.1 ساختار دیتابیس

#### جدول monitoring_metrics
```sql
CREATE TABLE monitoring_metrics (
    id SERIAL PRIMARY KEY,
    metric_type VARCHAR(50) NOT NULL,  -- cpu, memory, disk, network, api
    metric_name VARCHAR(100) NOT NULL, -- cpu_percent, memory_used, etc.
    value DECIMAL(15, 2) NOT NULL,
    unit VARCHAR(20),                   -- percent, bytes, seconds
    timestamp TIMESTAMP NOT NULL,
    metadata JSONB,                     -- اطلاعات اضافی
    INDEX idx_metric_timestamp (metric_type, timestamp)
);
```

#### جدول monitoring_service_status
```sql
CREATE TABLE monitoring_service_status (
    id SERIAL PRIMARY KEY,
    service_name VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL,       -- online, offline, degraded
    uptime_seconds INTEGER,
    version VARCHAR(50),
    metadata JSONB,
    last_check TIMESTAMP NOT NULL,
    INDEX idx_service_status (service_name, last_check)
);
```

#### جدول monitoring_alerts
```sql
CREATE TABLE monitoring_alerts (
    id SERIAL PRIMARY KEY,
    alert_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL,     -- info, warning, critical
    title VARCHAR(200) NOT NULL,
    message TEXT,
    metric_name VARCHAR(100),
    threshold_value DECIMAL(15, 2),
    current_value DECIMAL(15, 2),
    status VARCHAR(20) DEFAULT 'active', -- active, acknowledged, resolved
    created_at TIMESTAMP NOT NULL,
    acknowledged_at TIMESTAMP,
    acknowledged_by INTEGER,
    resolved_at TIMESTAMP,
    INDEX idx_alert_status (status, created_at)
);
```

### 10.2 Backend Services

#### 10.2.1 Hardware Monitoring Service
```python
class HardwareMonitoringService:
    def get_current_metrics(self) -> dict:
        """دریافت metrics فعلی سخت‌افزار"""
        # استفاده از psutil برای جمع‌آوری اطلاعات
        
    def get_historical_metrics(self, start_time, end_time, interval='1m') -> list:
        """دریافت تاریخچه metrics"""
        # خواندن از دیتابیس یا cache
        
    def collect_metrics(self):
        """جمع‌آوری و ذخیره metrics (Background Task)"""
        # اجرا هر 10 ثانیه
```

#### 10.2.2 Service Monitoring Service
```python
class ServiceMonitoringService:
    def check_service_status(self, service_name: str) -> dict:
        """بررسی وضعیت یک سرویس"""
        
    def check_all_services(self) -> dict:
        """بررسی وضعیت همه سرویس‌ها"""
        
    def get_service_metrics(self, service_name: str) -> dict:
        """دریافت metrics یک سرویس"""
```

#### 10.2.3 Alert Service
```python
class AlertService:
    def check_thresholds(self, metrics: dict):
        """بررسی آستانه‌ها و ایجاد هشدار"""
        
    def send_alert(self, alert: dict):
        """ارسال هشدار از طریق کانال‌های مختلف"""
        
    def acknowledge_alert(self, alert_id: int, user_id: int):
        """تایید هشدار"""
```

### 10.3 Background Tasks

#### Task: Collect Hardware Metrics
- **فرکانس**: هر 10 ثانیه
- **وظیفه**: جمع‌آوری metrics از psutil و ذخیره در Redis + Database

#### Task: Check Service Status
- **فرکانس**: هر 30 ثانیه
- **وظیفه**: بررسی وضعیت سرویس‌ها

#### Task: Aggregate Metrics
- **فرکانس**: هر 5 دقیقه
- **وظیفه**: تجمیع داده‌های دقیقه‌ای به داده‌های 5 دقیقه‌ای

#### Task: Check Alerts
- **فرکانس**: هر 30 ثانیه
- **وظیفه**: بررسی آستانه‌ها و ایجاد هشدار

---

## پیاده‌سازی Frontend

### 11.1 ساختار صفحات

```
lib/pages/admin/system_monitoring/
  ├── system_monitoring_page.dart          # صفحه اصلی
  ├── widgets/
  │   ├── hardware_metrics_card.dart       # کارت منابع سخت‌افزاری
  │   ├── service_status_card.dart         # کارت وضعیت سرویس
  │   ├── performance_chart.dart           # نمودار عملکرد
  │   ├── alert_list.dart                  # لیست هشدارها
  │   └── metric_gauge.dart                # گیج metric
  ├── tabs/
  │   ├── overview_tab.dart                # تب نمای کلی
  │   ├── hardware_tab.dart                # تب سخت‌افزار
  │   ├── services_tab.dart                # تب سرویس‌ها
  │   ├── performance_tab.dart             # تب عملکرد
  │   ├── alerts_tab.dart                  # تب هشدارها
  │   └── reports_tab.dart                 # تب گزارشات
  └── services/
      ├── monitoring_service.dart          # سرویس ارتباط با API
      └── websocket_service.dart           # سرویس WebSocket
```

### 11.2 State Management

استفاده از **Provider** یا **Riverpod** برای مدیریت state:
- Real-time metrics state
- Historical data cache
- Alert state
- UI preferences (refresh interval, time range)

### 11.3 WebSocket Integration

```dart
class MonitoringWebSocketService {
  WebSocketChannel? _channel;
  
  Stream<Map<String, dynamic>> connect() {
    // اتصال به WebSocket
    // Subscribe to channels
    // Return stream
  }
  
  void disconnect() {
    // قطع اتصال
  }
}
```

### 11.4 Chart Implementation

استفاده از `fl_chart` برای نمودارها:
- تنظیمات رنگ مطابق theme
- انیمیشن‌های smooth
- Tooltip با اطلاعات دقیق
- قابلیت zoom و pan

---

## اولویت‌بندی پیاده‌سازی

### فاز 1: MVP (حداقل محصول قابل استفاده)
1. ✅ مانیتورینگ منابع سخت‌افزاری (CPU, RAM, Disk, Network)
2. ✅ مانیتورینگ وضعیت سرویس‌ها (API, Database, Redis)
3. ✅ Dashboard ساده با نمودارهای اولیه
4. ✅ بروزرسانی با HTTP Polling (هر 5 ثانیه)

### فاز 2: بهبود عملکرد
1. ✅ WebSocket برای بروزرسانی لحظه‌ای
2. ✅ نمودارهای پیشرفته و تعاملی
3. ✅ سیستم هشدارها
4. ✅ گزارشات پایه (PDF)

### فاز 3: ویژگی‌های پیشرفته
1. ✅ گزارشات کامل و سفارشی (Excel, CSV)
2. ✅ تحلیل روند و پیش‌بینی
3. ✅ تنظیمات پیشرفته هشدارها
4. ✅ ارسال هشدار از طریق کانال‌های مختلف

---

## نکات مهم

1. **امنیت**: تمام endpoint ها نیاز به مجوز admin دارند
2. **عملکرد**: استفاده از cache برای کاهش بار دیتابیس
3. **مقیاس‌پذیری**: طراحی برای مقیاس‌پذیری در آینده
4. **قابلیت اطمینان**: مدیریت خطا و fallback mechanisms
5. **تجربه کاربری**: UI/UX ساده و واضح
6. **مستندات**: مستندسازی کامل API و کد

---

## کتابخانه‌های پیشنهادی

### Backend (Python)
- `psutil`: جمع‌آوری اطلاعات سیستم
- `fastapi-websocket`: WebSocket support
- `redis`: برای cache و real-time data
- `celery` یا `rq`: برای background tasks
- `reportlab` یا `weasyprint`: برای تولید PDF
- `openpyxl`: برای تولید Excel

### Frontend (Flutter)
- `fl_chart`: برای نمودارها
- `web_socket_channel`: برای WebSocket
- `provider` یا `riverpod`: برای state management
- `intl`: برای فرمت تاریخ و زمان
- `syncfusion_flutter_pdf`: برای نمایش PDF (اختیاری)

---

**نویسنده**: AI Assistant  
**تاریخ**: 2024  
**نسخه**: 1.0

