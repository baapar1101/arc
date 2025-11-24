# مستندات افزونه سامانه مودیان مالیاتی (نسخه قدیمی)

این مستندات نحوه ارسال اسناد به سامانه امور مالیاتی در نسخه قدیمی برنامه (Vue.js 3 + Symfony 6) را توضیح می‌دهد.

## فهرست مطالب

1. [معماری کلی](#معماری-کلی)
2. [کتابخانه استفاده شده](#کتابخانه-استفاده-شده)
3. [ساختار دیتابیس](#ساختار-دیتابیس)
4. [فرآیند ارسال فاکتور](#فرآیند-ارسال-فاکتور)
5. [API Endpoints](#api-endpoints)
6. [فرانت‌اند (Vue.js)](#فرانتاند-vuejs)
7. [اعتبارسنجی فاکتور](#اعتبارسنجی-فاکتور)
8. [ساخت DTO فاکتور](#ساخت-dto-فاکتور)
9. [وضعیت‌های فاکتور](#وضعیتهای-فاکتور)

---

## معماری کلی

افزونه سامانه مودیان مالیاتی از دو بخش اصلی تشکیل شده است:

### Backend (Symfony 6)
- **کنترلر**: `TaxSettingsController.php`
- **Entity**: `PluginTaxInvoice.php` و `PluginTaxsettingsKey.php`
- **Repository**: `PluginTaxInvoiceRepository.php`

### Frontend (Vue.js 3)
- **صفحه لیست فاکتورهای فروش**: `webUI/src/views/acc/sell/list.vue`
- **صفحه لیست فاکتورهای مالیاتی**: `webUI/src/views/acc/plugins/tax/invoices/list.vue`
- **صفحه تنظیمات مالیاتی**: `webUI/src/views/acc/settings/tax-settings.vue`

---

## کتابخانه استفاده شده

برنامه از کتابخانه **SnappMarketPro/Moadian** استفاده می‌کند:

```json
"snapp-market-pro/moadian": "^1.1"
```

این کتابخانه در `composer.json` تعریف شده و برای ارتباط با سامانه مودیان استفاده می‌شود.

### URL های سامانه

```php
// حالت Sandbox
https://sandboxrc.tax.gov.ir/

// حالت Production
https://tp.tax.gov.ir/
```

حالت Sandbox از تنظیمات سیستم (`tax_system_sandbox_mode`) خوانده می‌شود.

---

## ساختار دیتابیس

### جدول `plugin_tax_invoice`

این جدول فاکتورهای آماده ارسال به سامانه مودیان را نگهداری می‌کند:

| فیلد | نوع | توضیحات |
|------|-----|---------|
| `id` | INT | شناسه یکتا |
| `business_id` | INT | شناسه کسب و کار |
| `user_id` | INT | شناسه کاربر |
| `invoice_id` | INT | شناسه فاکتور اصلی (HesabdariDoc) |
| `invoice_code` | VARCHAR(255) | کد فاکتور |
| `tax_system_invoice_number` | VARCHAR(255) | شماره منحصر به فرد مالیاتی (referenceNumber) |
| `tax_system_reference_number` | VARCHAR(255) | شماره ارجاع یکتا |
| `status` | VARCHAR(255) | وضعیت: `pending`, `sent`, `error`, `accepted` |
| `response_data` | TEXT | پاسخ سامانه (JSON) |
| `error_message` | TEXT | پیام خطا (JSON) |
| `created_at` | DATETIME | تاریخ ایجاد |
| `sent_at` | DATETIME | تاریخ ارسال |
| `confirmed_at` | DATETIME | تاریخ تایید |
| `amount` | DECIMAL | مبلغ فاکتور |
| `customer_name` | VARCHAR(255) | نام مشتری |
| `customer_id` | VARCHAR(255) | کد مشتری |
| `invoice_type` | VARCHAR(50) | نوع فاکتور: `اصلی`, `اصلاحی` |

### جدول `plugin_taxsettings_key`

این جدول تنظیمات اتصال به سامانه مودیان را نگهداری می‌کند:

| فیلد | نوع | توضیحات |
|------|-----|---------|
| `id` | INT | شناسه یکتا |
| `business_id` | INT | شناسه کسب و کار |
| `user_id` | INT | شناسه کاربر |
| `tax_memory_id` | VARCHAR | شناسه حافظه مالیاتی |
| `economic_code` | VARCHAR | کد اقتصادی |
| `private_key` | TEXT | کلید خصوصی RSA |

---

## فرآیند ارسال فاکتور

### مرحله 1: اضافه کردن فاکتور به لیست ارسال

**Endpoint**: `POST /api/plugins/tax/list/send-invoice`

**فرانت‌اند**: از صفحه لیست فاکتورهای فروش (`/acc/sell/list`)

```javascript
// در فایل sell/list.vue
async sendToTaxSystem(code) {
  const response = await axios.post('/api/plugins/tax/list/send-invoice', { 
    codes: [code] 
  });
}
```

**Backend**: 
- بررسی می‌کند که فاکتور قبلاً به لیست اضافه نشده باشد
- یک رکورد جدید در `plugin_tax_invoice` با وضعیت `pending` ایجاد می‌کند
- اطلاعات مشتری را از ردیف‌های فاکتور استخراج می‌کند

**کد Backend**:
```php
private function saveInvoiceToSql($invoice, $taxSettings, $em, $businessId, $userId)
{
    // بررسی تکراری نبودن
    $existingRecord = $taxInvoiceRepo->findByInvoiceCodeAndBusiness(...);
    
    // ایجاد رکورد جدید
    $taxInvoice = new PluginTaxInvoice();
    $taxInvoice->setStatus('pending');
    // ...
}
```

### مرحله 2: ارسال فاکتور به سامانه

**Endpoint**: `POST /api/plugins/tax/invoice/send/{id}`

**فرانت‌اند**: از صفحه لیست فاکتورهای مالیاتی (`/acc/plugins/tax/invoices/list`)

```javascript
// در فایل tax/invoices/list.vue
async performSend(item) {
  // 1. اعتبارسنجی اطلاعات خریدار
  const validateResponse = await axios.post(
    `/api/plugins/tax/invoice/validate-buyer-info/${item.id}`
  );
  
  // 2. ارسال فاکتور
  const response = await axios.post(`/api/plugins/tax/invoice/send/${item.id}`);
}
```

**Backend - مراحل ارسال**:

#### 2.1. دریافت تنظیمات مالیاتی
```php
$taxSettings = $this->getTaxSettings($em, $businessId, $user);
// شامل: taxMemoryId, economicCode, privateKey
```

#### 2.2. اتصال به سامانه مودیان
```php
// ایجاد نمونه اولیه Moadian
$moadian = new \SnappMarketPro\Moadian\Moadian(
    '',              // publicKey (بعداً دریافت می‌شود)
    $privateKey,      // کلید خصوصی
    '',               // keyId (بعداً دریافت می‌شود)
    $username,        // شناسه حافظه مالیاتی
    $baseUrl          // URL سامانه
);

// دریافت اطلاعات سرور (کلید عمومی سازمان مالیاتی)
$serverInfo = $moadian->getServerInformation();
$taxOrgPublicKey = $serverInfo['result']['data']['publicKeys'][0]['key'];
$taxOrgKeyId = $serverInfo['result']['data']['publicKeys'][0]['id'];

// ایجاد نمونه نهایی Moadian با کلید عمومی
$moadian = new \SnappMarketPro\Moadian\Moadian(
    $taxOrgPublicKey,
    $privateKey,
    $taxOrgKeyId,
    $username,
    $baseUrl
);

// لاگین و دریافت Token
$token = $moadian->login();
$moadian->setToken($token);
```

#### 2.3. اعتبارسنجی فاکتور
```php
$validationResult = $this->validateInvoiceForTax($invoice);
// بررسی موارد:
// - وجود اقلام در فاکتور
// - وجود کد مالیاتی برای هر کالا/خدمت
// - وجود واحد مالیاتی برای هر کالا/خدمت
// - عدم وجود اعشار در مبلغ مالیات
// - صفر بودن هزینه حمل
```

#### 2.4. ساخت DTO فاکتور
```php
$invoiceDto = $this->buildInvoiceDto($invoice, $moadian, $taxSettings['economicCode']);
```

#### 2.5. ارسال فاکتور
```php
$response = $moadian->sendInvoices([$invoiceDto]);
```

#### 2.6. بروزرسانی وضعیت
```php
if (isset($response['result'][0]['referenceNumber'])) {
    $taxInvoice->setStatus('sent');
    $taxInvoice->setTaxSystemInvoiceNumber($response['result'][0]['referenceNumber']);
    $taxInvoice->setSentAt(new \DateTimeImmutable());
    $em->persist($taxInvoice);
    $em->flush();
}
```

---

## API Endpoints

### 1. دریافت تنظیمات مالیاتی
```
GET /api/plugins/tax/settings/get
```
**پاسخ**:
```json
{
  "taxMemoryId": "شناسه حافظه مالیاتی",
  "economicCode": "کد اقتصادی",
  "privateKey": "کلید خصوصی"
}
```

### 2. ذخیره تنظیمات مالیاتی
```
POST /api/plugins/tax/settings/save
```
**بدنه درخواست**:
```json
{
  "taxMemoryId": "شناسه حافظه مالیاتی",
  "economicCode": "کد اقتصادی",
  "privateKey": "کلید خصوصی"
}
```

### 3. تولید کلید و CSR
```
POST /api/plugins/tax/settings/generate-csr
```
**بدنه درخواست**:
```json
{
  "personType": "natural|legal",
  "nationalId": "شناسه ملی",
  "nameFa": "نام فارسی (برای اشخاص حقوقی)",
  "nameEn": "نام انگلیسی (برای اشخاص حقوقی)",
  "email": "ایمیل (برای اشخاص حقوقی)"
}
```

### 4. اضافه کردن فاکتور به لیست ارسال
```
POST /api/plugins/tax/list/send-invoice
```
**بدنه درخواست**:
```json
{
  "codes": ["کد فاکتور 1", "کد فاکتور 2"]
}
```

### 5. دریافت لیست فاکتورهای مالیاتی
```
GET /api/plugins/tax/invoices/list
```
**پاسخ**:
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "invoiceNumber": "INV-001",
      "status": "pending|sent|error|accepted",
      "taxSystemInvoiceNumber": "شماره منحصر به فرد",
      ...
    }
  ]
}
```

### 6. ارسال فاکتور به سامانه
```
POST /api/plugins/tax/invoice/send/{id}
```
**پاسخ**:
```json
{
  "success": true,
  "invoiceCode": "INV-001",
  "referenceNumber": "شماره ارجاع",
  "data": { ... }
}
```

### 7. ارسال گروهی فاکتورها
```
POST /api/plugins/tax/invoice/send-bulk
```
**بدنه درخواست**:
```json
{
  "ids": [1, 2, 3]
}
```

### 8. استعلام وضعیت فاکتورها
```
POST /api/plugins/tax/inquire-status
```
**بدنه درخواست**:
```json
{
  "referenceNumbers": ["شماره ارجاع 1", "شماره ارجاع 2"]
}
```

### 9. حذف فاکتور از لیست
```
DELETE /api/plugins/tax/invoice/delete/{id}
```

### 10. اعتبارسنجی اطلاعات خریدار
```
POST /api/plugins/tax/invoice/validate-buyer-info/{id}
```

---

## فرانت‌اند (Vue.js)

### صفحه لیست فاکتورهای فروش

**مسیر**: `/acc/sell/list`

**عملکرد**:
- نمایش لیست فاکتورهای فروش
- امکان انتخاب فاکتورها
- دکمه "ارسال به سامانه مودیان" برای ارسال تکی
- دکمه "ارسال گروهی" برای ارسال چند فاکتور

**کد کلیدی**:
```javascript
// ارسال تکی
async sendToTaxSystem(code) {
  const response = await axios.post('/api/plugins/tax/list/send-invoice', {
    codes: [code]
  });
  // هدایت به صفحه لیست فاکتورهای مالیاتی
  this.$router.push('/acc/plugins/tax/invoices/list');
}

// ارسال گروهی
async sendBulkToTaxSystem() {
  const response = await axios.post('/api/plugins/tax/list/send-invoice', {
    codes: this.itemsSelected
  });
}
```

### صفحه لیست فاکتورهای مالیاتی

**مسیر**: `/acc/plugins/tax/invoices/list`

**عملکرد**:
- نمایش فاکتورهای اضافه شده به لیست ارسال
- نمایش وضعیت هر فاکتور (pending, sent, error, accepted)
- امکان ارسال فاکتورهای pending یا error
- امکان بررسی وضعیت فاکتورهای sent
- امکان مشاهده خطاهای فاکتورهای error
- امکان حذف فاکتورهای pending یا error

**وضعیت‌ها**:
- **pending**: ارسال نشده (خاکستری)
- **sent**: ارسال شده (نارنجی)
- **error**: خطا دار (قرمز)
- **accepted**: تایید شده (سبز)

**کد کلیدی**:
```javascript
// ارسال فاکتور
async performSend(item) {
  // 1. اعتبارسنجی اطلاعات خریدار
  const validateResponse = await axios.post(
    `/api/plugins/tax/invoice/validate-buyer-info/${item.id}`
  );
  
  // 2. ارسال
  const response = await axios.post(`/api/plugins/tax/invoice/send/${item.id}`);
}

// بررسی وضعیت
async checkInvoiceStatus(item) {
  const response = await axios.post('/api/plugins/tax/inquire-status', {
    referenceNumbers: [item.uniqueTaxNumber]
  });
}
```

---

## اعتبارسنجی فاکتور

قبل از ارسال فاکتور، اعتبارسنجی‌های زیر انجام می‌شود:

### 1. بررسی وجود اقلام
```php
if (empty($data['items'])) {
    return ['valid' => false, 'message' => 'فاکتور فاقد اقلام است'];
}
```

### 2. بررسی کد مالیاتی
برای هر کالا/خدمت باید کد مالیاتی تعریف شده باشد:
```php
$taxCode = $commodityObj->getTaxCode();
if (empty($taxCode)) {
    $errors[] = "کالا/خدمت {$rowNumber}: کد مالیاتی تعریف نشده است";
}
```

### 3. بررسی واحد مالیاتی
برای هر کالا/خدمت باید واحد مالیاتی تعریف شده باشد:
```php
$taxUnit = $commodityObj->getTaxUnit();
if (empty($taxUnit)) {
    $errors[] = "کالا/خدمت {$rowNumber}: واحد مالیاتی تعریف نشده است";
}
```

### 4. بررسی اعشار در مالیات
مبلغ مالیات بر ارزش افزوده نباید اعشار داشته باشد:
```php
if (fmod($totalTax, 1) != 0) {
    $errors[] = "مبلغ مالیات بر ارزش افزوده نباید اعشار داشته باشد";
}
```

### 5. بررسی هزینه حمل
هزینه حمل باید صفر باشد:
```php
if ($data['shippingCost'] > 0) {
    $errors[] = "هزینه حمل باید صفر باشد";
}
```

---

## ساخت DTO فاکتور

تابع `buildInvoiceDto` فاکتور را به فرمت مورد نیاز سامانه مودیان تبدیل می‌کند:

### Header (سربرگ فاکتور)

```php
$header = (new \SnappMarketPro\Moadian\Dto\InvoiceHeaderDto())
    ->setTaxid($moadian->generateTaxId($dateTime, $internalId))  // شناسه یکتا مالیاتی
    ->setIndati2m($dateTime->getTimestamp() * 1000)              // تاریخ و زمان
    ->setIndatim($dateTime->getTimestamp() * 1000)               // تاریخ و زمان
    ->setInty($InvoiceType)                                       // نوع فاکتور (1=عادی, 2=ساده)
    ->setInno($moadian->normalizeInvoiceNumber($internalId))     // شماره سریال فاکتور
    ->setTins($taxId)                                             // شماره اقتصادی فروشنده
    ->setTob($personType)                                         // نوع شخص خریدار (1=حقیقی, 2=حقوقی)
    ->setBid($buyerNationalId)                                   // شناسه ملی خریدار
    ->setTinb($buyerEconomicCode)                                 // کد اقتصادی خریدار
    ->setTprdis(array_sum(array_column($data['items'], 'prdis')))  // جمع مبلغ قبل از تخفیف
    ->setTdis($data['totalDiscount'])                             // جمع تخفیف
    ->setTadis($data['totalInvoice'] - $data['totalDiscount'])     // جمع مبلغ بعد از تخفیف
    ->setTvam($totalTax)                                          // جمع مالیات
    ->setTodam($data['shippingCost'])                              // جمع سایر اضافات
    ->setTbill($data['finalTotal'])                                // جمع کل
    ->setSetm($invoicePayType);                                    // نوع پرداخت
```

### Body (بدنه فاکتور - اقلام)

برای هر قلم فاکتور:

```php
$bodyDto = (new \SnappMarketPro\Moadian\Dto\InvoiceBodyDto())
    ->setSstid($taxCode)              // کد مالیاتی کالا/خدمت
    ->setSstt($item['name']['name'])   // نام کالا/خدمت
    ->setAm($item['count'])            // تعداد
    ->setMu($taxUnit)                  // واحد مالیاتی
    ->setFee($item['price'])           // قیمت واحد
    ->setPrdis($prdis)                 // مبلغ قبل از تخفیف
    ->setDis($item['discountAmount'])  // تخفیف
    ->setAdis($adis)                   // مبلغ بعد از تخفیف
    ->setVra($vra)                     // نرخ مالیات (درصد)
    ->setVam($ks)                      // مبلغ مالیات
    ->setTsstam($os);                  // جمع کل
```

### Payment (پرداخت)

```php
$paymentDto = (new \SnappMarketPro\Moadian\Dto\InvoicePaymentDto())
    ->setIinn(null)
    ->setAcn(null)
    ->setTrmn(null)
    ->setTrn(null)
    ->setPcn(null)
    ->setPid(null)
    ->setPdt(null);
```

### ساخت DTO نهایی

```php
$invoiceDto = new \SnappMarketPro\Moadian\Dto\InvoiceDto();
$invoiceDto->setHeader($header);
$invoiceDto->setBody($bodyItems);
$invoiceDto->setPayments([$paymentDto]);
```

---

## وضعیت‌های فاکتور

### وضعیت‌های ممکن

1. **pending**: فاکتور به لیست اضافه شده اما هنوز ارسال نشده
2. **sent**: فاکتور به سامانه ارسال شده و منتظر تایید است
3. **error**: فاکتور دارای خطا است (از سامانه رد شده)
4. **accepted**: فاکتور توسط سامانه تایید شده

### تغییر وضعیت

- **pending → sent**: پس از ارسال موفق به سامانه
- **sent → accepted**: پس از استعلام وضعیت و دریافت تایید
- **sent → error**: پس از استعلام وضعیت و دریافت خطا
- **error → sent**: پس از ارسال مجدد فاکتور خطا دار

### استعلام وضعیت

برای بررسی وضعیت فاکتورهای ارسال شده:

```php
$response = $moadian->inquireByReferenceNumbers($referenceNumbers);

// پاسخ
[
    'result' => [
        'data' => [
            [
                'referenceNumber' => 'شماره ارجاع',
                'status' => 'SUCCESS|FAILED',
                'data' => [
                    'error' => [...],    // در صورت خطا
                    'warning' => [...]   // در صورت هشدار
                ]
            ]
        ]
    ]
]
```

---

## نکات مهم

### 1. تولید شناسه یکتا مالیاتی (Tax ID)

```php
$taxId = $moadian->generateTaxId($dateTime, $internalId);
```

این شناسه بر اساس الگوریتم سامانه مودیان تولید می‌شود.

### 2. نرمال‌سازی شماره فاکتور

```php
$invoiceNumber = $moadian->normalizeInvoiceNumber($internalId);
```

### 3. محاسبه نرخ مالیات (VRA)

```php
private function calculateVra($itemTotal, $itemTax, $invoice): int
{
    if ($itemTotal <= 0 || $itemTax <= 0) {
        return 0;
    }
    
    $vra = round(($itemTax / $itemTotal) * 100, 2);
    $taxPercent = $invoice->getTaxPercent() ?? 9;
    $expectedVra = (int) $taxPercent;
    
    if ($vra > 0 && abs($vra - $expectedVra) <= 1) {
        return $expectedVra;
    }
    
    return (int) $vra;
}
```

### 4. نوع فاکتور

- **نوع 1 (عادی)**: برای فاکتورهایی که خریدار دارای شناسه ملی و کد اقتصادی است
- **نوع 2 (ساده)**: برای سایر فاکتورها

```php
$InvoiceType = 2;  // پیش‌فرض: ساده
if ($buyerNationalId && $buyerEconomicCode) {
    $InvoiceType = 1;  // عادی
}
```

### 5. نوع شخص خریدار

- **1 (حقیقی)**: اگر شناسه ملی 11 رقمی باشد
- **2 (حقوقی)**: در غیر این صورت

```php
$personType = 1;
if (strlen($buyerNationalId) == 11) {
    $personType = 2;  // حقیقی
}
```

---

## خطاهای رایج

### 1. تنظیمات ناقص
```
تنظیمات مالیاتی تکمیل نشده است. لطفاً ابتدا تنظیمات را تکمیل کنید.
```
**راه حل**: تنظیمات مالیاتی (شناسه حافظه، کد اقتصادی، کلید خصوصی) را تکمیل کنید.

### 2. فاکتور تکراری
```
این فاکتور قبلاً به سامانه مودیان ارسال شده است.
```
**راه حل**: فاکتور را از لیست فاکتورهای مالیاتی حذف کنید یا از فاکتور جدید استفاده کنید.

### 3. کد مالیاتی ناقص
```
کالا/خدمت X: کد مالیاتی تعریف نشده است
```
**راه حل**: برای هر کالا/خدمت کد مالیاتی 13 رقمی تعریف کنید.

### 4. واحد مالیاتی ناقص
```
کالا/خدمت X: واحد مالیاتی تعریف نشده است
```
**راه حل**: برای هر کالا/خدمت واحد مالیاتی تعریف کنید.

### 5. خطا در اتصال
```
خطا در اتصال به سامانه مودیان، لطفاً تنظیمات را بررسی کنید.
```
**راه حل**: 
- کلید خصوصی را بررسی کنید
- شناسه حافظه مالیاتی را بررسی کنید
- اتصال اینترنت را بررسی کنید

---

## فایل‌های کلیدی

### Backend
- `hesabixCore/src/Controller/Plugins/TaxSettingsController.php` - کنترلر اصلی
- `hesabixCore/src/Entity/PluginTaxInvoice.php` - Entity فاکتور مالیاتی
- `hesabixCore/src/Entity/PluginTaxsettingsKey.php` - Entity تنظیمات
- `hesabixCore/src/Repository/PluginTaxInvoiceRepository.php` - Repository

### Frontend
- `webUI/src/views/acc/sell/list.vue` - لیست فاکتورهای فروش
- `webUI/src/views/acc/plugins/tax/invoices/list.vue` - لیست فاکتورهای مالیاتی
- `webUI/src/views/acc/settings/tax-settings.vue` - تنظیمات مالیاتی

---

## خلاصه فرآیند

1. **تنظیمات**: کاربر تنظیمات مالیاتی را تکمیل می‌کند (شناسه حافظه، کد اقتصادی، کلید خصوصی)
2. **انتخاب فاکتور**: از لیست فاکتورهای فروش، فاکتورها را انتخاب می‌کند
3. **اضافه به لیست**: فاکتورها به جدول `plugin_tax_invoice` با وضعیت `pending` اضافه می‌شوند
4. **ارسال**: از صفحه لیست فاکتورهای مالیاتی، فاکتورها به سامانه ارسال می‌شوند
5. **بررسی وضعیت**: می‌توان وضعیت فاکتورهای ارسال شده را بررسی کرد
6. **مدیریت خطا**: در صورت خطا، می‌توان فاکتور را اصلاح و مجدداً ارسال کرد

---

**تاریخ ایجاد مستندات**: 2025-01-XX
**نسخه برنامه**: قدیمی (Vue.js 3 + Symfony 6)

