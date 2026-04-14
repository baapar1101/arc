# 📊 سناریوی یکپارچه‌سازی فیلتر پروژه در گزارشات

## 🎯 هدف
افزودن فیلتر پروژه به تمام گزارشات مالی و عملیاتی سیستم برای امکان تحلیل داده‌ها بر اساس پروژه

---

## 📋 فهرست گزارشات نیازمند به‌روزرسانی

### 1️⃣ **گزارشات مالی (اولویت بالا)** 🔴

#### الف) گزارش دفتر کل (General Ledger)
- **فایل**: `general_ledger_report_page.dart`
- **API**: `/api/v1/reports/general-ledger`
- **اهمیت**: ⭐⭐⭐⭐⭐
- **دلیل**: نمایش تراکنش‌های هر حساب با تفکیک پروژه

#### ب) گزارش روزنامه (Journal Ledger)
- **فایل**: `journal_ledger_report_page.dart`
- **API**: `/api/v1/reports/journal-ledger`
- **اهمیت**: ⭐⭐⭐⭐⭐
- **دلیل**: نمایش کلیه اسناد روزانه با فیلتر پروژه

#### ج) گزارش تراز آزمایشی (Trial Balance)
- **فایل**: `trial_balance_report_page.dart`
- **API**: `/api/v1/reports/trial-balance`
- **اهمیت**: ⭐⭐⭐⭐
- **دلیل**: تراز حساب‌ها با محدود کردن به پروژه خاص

#### د) گزارش سود و زیان (P&L)
- **فایل‌ها**: 
  - `pnl_period_report_page.dart` (دوره‌ای)
  - `pnl_cumulative_report_page.dart` (تجمعی)
- **API**: `/api/v1/reports/pnl`
- **اهمیت**: ⭐⭐⭐⭐⭐
- **دلیل**: تحلیل سودآوری هر پروژه

#### ه) گزارش تراکنش‌های اشخاص
- **فایل**: `people_transactions_report_page.dart`
- **API**: `/api/v1/reports/people-transactions`
- **اهمیت**: ⭐⭐⭐⭐
- **دلیل**: مشاهده تراکنش‌های مشتری/تامین‌کننده در پروژه خاص

#### و) گزارش بدهکاران
- **فایل**: `debtors_report_page.dart`
- **API**: `/api/v1/reports/debtors`
- **اهمیت**: ⭐⭐⭐⭐
- **دلیل**: مانده بدهکاری مشتریان در پروژه خاص

#### ز) گزارش بستانکاران
- **فایل**: `creditors_report_page.dart`
- **API**: `/api/v1/reports/creditors`
- **اهمیت**: ⭐⭐⭐⭐
- **دلیل**: مانده بستانکاری تامین‌کنندگان در پروژه خاص

### 2️⃣ **گزارشات فروش و خرید (اولویت متوسط)** 🟡

#### الف) گزارش فروش روزانه
- **فایل**: `daily_sales_report_page.dart`
- **API**: `/api/v1/reports/daily-sales`
- **اهمیت**: ⭐⭐⭐⭐
- **دلیل**: تحلیل فروش روزانه هر پروژه

#### ب) گزارش خرید روزانه
- **فایل**: `daily_purchases_report_page.dart`
- **API**: `/api/v1/reports/daily-purchases`
- **اهمیت**: ⭐⭐⭐⭐
- **دلیل**: تحلیل خرید روزانه هر پروژه

#### ج) گزارش فروش ماهانه
- **فایل**: `monthly_sales_report_page.dart`
- **API**: `/api/v1/reports/monthly-sales`
- **اهمیت**: ⭐⭐⭐
- **دلیل**: روند فروش ماهانه به تفکیک پروژه

#### د) فروش بر اساس محصول
- **فایل**: `sales_by_product_report_page.dart`
- **API**: `/api/v1/reports/sales-by-product`
- **اهمیت**: ⭐⭐⭐
- **دلیل**: محصولات پرفروش در هر پروژه

#### ه) برترین مشتریان
- **فایل**: `top_customers_report_page.dart`
- **API**: `/api/v1/reports/top-customers`
- **اهمیت**: ⭐⭐⭐
- **دلیل**: مشتریان VIP هر پروژه

#### و) برترین تامین‌کنندگان
- **فایل**: `top_suppliers_report_page.dart`
- **API**: `/api/v1/reports/top-suppliers`
- **اهمیت**: ⭐⭐⭐
- **دلیل**: تامین‌کنندگان اصلی هر پروژه

### 3️⃣ **گزارشات انبار و موجودی (اولویت پایین)** 🟢

#### الف) گزارش کاردکس
- **فایل**: `inventory_kardex_report_page.dart`
- **API**: `/api/v1/reports/kardex`
- **اهمیت**: ⭐⭐⭐
- **دلیل**: ردیابی موجودی محصولات در پروژه

#### ب) گزارش موجودی انبار
- **فایل**: `inventory_stock_report_page.dart`
- **API**: `/api/v1/reports/inventory-stock`
- **اهمیت**: ⭐⭐
- **دلیل**: موجودی فعلی با تفکیک پروژه

#### ج) گزارش تحرکات محصول
- **فایل**: `product_movement_history_report_page.dart`
- **API**: `/api/v1/reports/product-movements`
- **اهمیت**: ⭐⭐⭐
- **دلیل**: تحرکات محصول در پروژه خاص

#### د) گزارش انتقالات بین انبار
- **فایل**: `inter_warehouse_transfers_report_page.dart`
- **API**: `/api/v1/reports/warehouse-transfers`
- **اهمیت**: ⭐⭐
- **دلیل**: انتقالات مربوط به پروژه

### 4️⃣ **گزارشات بانکی و صندوق (اولویت متوسط)** 🟡

#### الف) گزارش گردش حساب بانکی
- **فایل**: `bank_accounts_turnover_report_page.dart`
- **API**: `/api/v1/reports/bank-turnover`
- **اهمیت**: ⭐⭐⭐⭐
- **دلیل**: گردش بانکی مرتبط با پروژه

#### ب) گزارش صندوق و تنخواه
- **فایل**: `cash_petty_turnover_report_page.dart`
- **API**: `/api/v1/reports/cash-turnover`
- **اهمیت**: ⭐⭐⭐⭐
- **دلیل**: تراکنش‌های نقدی پروژه

### 5️⃣ **گزارشات اقساط و چک (اولویت پایین)** 🟢

#### الف) گزارش اقساط
- **فایل**: `installments_report_page.dart`
- **API**: `/api/v1/reports/installments`
- **اهمیت**: ⭐⭐⭐
- **دلیل**: اقساط دریافتی/پرداختی پروژه

#### ب) گزارش اسناد در انتظار
- **فایل**: `pending_documents_report_page.dart`
- **API**: `/api/v1/reports/pending-documents`
- **اهمیت**: ⭐⭐
- **دلیل**: اسناد تایید نشده پروژه

---

## 🏗️ معماری یکپارچه‌سازی

### Backend Architecture

```
hesabixAPI/
├── app/
│   └── services/
│       └── reports/
│           ├── general_ledger_service.py
│           ├── journal_ledger_service.py
│           ├── trial_balance_service.py
│           ├── pnl_service.py
│           ├── people_transactions_service.py
│           ├── sales_reports_service.py
│           ├── inventory_reports_service.py
│           └── ... (سایر سرویس‌های گزارش)
│
└── adapters/
    └── api/
        └── v1/
            └── reports/
                ├── financial_reports.py
                ├── sales_reports.py
                ├── inventory_reports.py
                └── ... (سایر endpoint های گزارش)
```

### Frontend Architecture

```
hesabixUI/lib/
├── pages/
│   └── business/
│       ├── general_ledger_report_page.dart
│       ├── pnl_period_report_page.dart
│       └── ... (سایر صفحات گزارش)
│
└── widgets/
    └── reports/
        └── report_filters_widget.dart (جدید)
```

---

## 📝 سناریوی پیاده‌سازی گام به گام

### مرحله 1️⃣: Backend - به‌روزرسانی Query Services

#### الف) اضافه کردن پارامتر project_id به توابع

**مثال: سرویس دفتر کل**

```python
# hesabixAPI/app/services/general_ledger_service.py

def get_general_ledger(
    db: Session,
    business_id: int,
    account_id: Optional[int] = None,
    from_date: Optional[date] = None,
    to_date: Optional[date] = None,
    fiscal_year_id: Optional[int] = None,
    project_id: Optional[int] = None,  # 🆕 اضافه شده
    skip: int = 0,
    limit: int = 100
) -> Dict[str, Any]:
    """
    دریافت گزارش دفتر کل با فیلتر پروژه
    """
    query = db.query(DocumentLine).join(Document)
    
    # فیلتر کسب‌وکار
    query = query.filter(Document.business_id == business_id)
    
    # فیلتر حساب
    if account_id:
        query = query.filter(DocumentLine.account_id == account_id)
    
    # فیلتر تاریخ
    if from_date:
        query = query.filter(Document.document_date >= from_date)
    if to_date:
        query = query.filter(Document.document_date <= to_date)
    
    # فیلتر سال مالی
    if fiscal_year_id:
        query = query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    # 🆕 فیلتر پروژه
    if project_id:
        query = query.filter(Document.project_id == project_id)
    
    # اجرای query و برگرداندن نتایج
    # ...
```

**مثال: سرویس سود و زیان**

```python
# hesabixAPI/app/services/pnl_service.py

def calculate_pnl(
    db: Session,
    business_id: int,
    from_date: date,
    to_date: date,
    project_id: Optional[int] = None,  # 🆕 اضافه شده
    cumulative: bool = False
) -> Dict[str, Any]:
    """
    محاسبه سود و زیان با فیلتر پروژه
    """
    # Query پایه برای درآمدها
    revenue_query = db.query(
        func.sum(DocumentLine.credit - DocumentLine.debit)
    ).join(Document).join(Account).filter(
        Document.business_id == business_id,
        Document.document_date.between(from_date, to_date),
        Account.code.like('4%')  # حساب‌های درآمد
    )
    
    # 🆕 فیلتر پروژه برای درآمد
    if project_id:
        revenue_query = revenue_query.filter(Document.project_id == project_id)
    
    total_revenue = revenue_query.scalar() or 0
    
    # Query پایه برای هزینه‌ها
    expense_query = db.query(
        func.sum(DocumentLine.debit - DocumentLine.credit)
    ).join(Document).join(Account).filter(
        Document.business_id == business_id,
        Document.document_date.between(from_date, to_date),
        Account.code.like('5%')  # حساب‌های هزینه
    )
    
    # 🆕 فیلتر پروژه برای هزینه
    if project_id:
        expense_query = expense_query.filter(Document.project_id == project_id)
    
    total_expense = expense_query.scalar() or 0
    
    # محاسبه سود خالص
    net_profit = total_revenue - total_expense
    
    return {
        'revenue': float(total_revenue),
        'expense': float(total_expense),
        'net_profit': float(net_profit),
        'profit_margin': (net_profit / total_revenue * 100) if total_revenue > 0 else 0,
        'project_id': project_id,
        'from_date': from_date.isoformat(),
        'to_date': to_date.isoformat(),
    }
```

#### ب) به‌روزرسانی API Endpoints

```python
# hesabixAPI/adapters/api/v1/reports/financial_reports.py

@router.get("/businesses/{business_id}/reports/general-ledger")
async def general_ledger_report(
    business_id: int = Path(...),
    account_id: Optional[int] = Query(None),
    from_date: Optional[date] = Query(None),
    to_date: Optional[date] = Query(None),
    fiscal_year_id: Optional[int] = Query(None),
    project_id: Optional[int] = Query(None),  # 🆕 اضافه شده
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user)
):
    """
    گزارش دفتر کل با فیلتر پروژه
    """
    result = get_general_ledger(
        db=db,
        business_id=business_id,
        account_id=account_id,
        from_date=from_date,
        to_date=to_date,
        fiscal_year_id=fiscal_year_id,
        project_id=project_id,  # 🆕 پاس دادن به سرویس
        skip=skip,
        limit=limit
    )
    
    return success_response(data=result, message="GENERAL_LEDGER_FETCHED")
```

### مرحله 2️⃣: Frontend - ایجاد Widget فیلتر مشترک

```dart
// lib/widgets/reports/report_filters_widget.dart

import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';

/// ویجت فیلترهای مشترک گزارشات
class ReportFiltersWidget extends StatelessWidget {
  final int businessId;
  final ApiClient apiClient;
  final CalendarController calendarController;
  
  // فیلترهای تاریخ
  final DateTime? fromDate;
  final DateTime? toDate;
  final Function(DateTime?) onFromDateChanged;
  final Function(DateTime?) onToDateChanged;
  
  // فیلتر پروژه
  final int? selectedProjectId;
  final Function(int?) onProjectChanged;
  
  // فیلترهای اختیاری
  final int? selectedFiscalYearId;
  final Function(int?)? onFiscalYearChanged;
  final List<Map<String, dynamic>>? fiscalYears;
  
  final bool showProjectFilter;
  final bool showDateFilters;
  final bool showFiscalYearFilter;

  const ReportFiltersWidget({
    Key? key,
    required this.businessId,
    required this.apiClient,
    required this.calendarController,
    required this.fromDate,
    required this.toDate,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    required this.selectedProjectId,
    required this.onProjectChanged,
    this.selectedFiscalYearId,
    this.onFiscalYearChanged,
    this.fiscalYears,
    this.showProjectFilter = true,
    this.showDateFilters = true,
    this.showFiscalYearFilter = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          // فیلتر تاریخ از
          if (showDateFilters)
            SizedBox(
              width: 200,
              child: DateInputField(
                value: fromDate,
                calendarController: calendarController,
                onChanged: onFromDateChanged,
                labelText: 'از تاریخ',
                hintText: 'انتخاب تاریخ',
              ),
            ),
          
          // فیلتر تاریخ تا
          if (showDateFilters)
            SizedBox(
              width: 200,
              child: DateInputField(
                value: toDate,
                calendarController: calendarController,
                onChanged: onToDateChanged,
                labelText: 'تا تاریخ',
                hintText: 'انتخاب تاریخ',
              ),
            ),
          
          // فیلتر سال مالی
          if (showFiscalYearFilter && fiscalYears != null && fiscalYears!.isNotEmpty)
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<int>(
                value: selectedFiscalYearId,
                decoration: const InputDecoration(
                  labelText: 'سال مالی',
                  border: OutlineInputBorder(),
                ),
                items: fiscalYears!.map((fy) {
                  return DropdownMenuItem<int>(
                    value: fy['id'] as int,
                    child: Text(fy['title'] as String),
                  );
                }).toList(),
                onChanged: onFiscalYearChanged,
              ),
            ),
          
          // 🆕 فیلتر پروژه
          if (showProjectFilter)
            SizedBox(
              width: 250,
              child: ProjectSelectorWidget(
                businessId: businessId,
                apiClient: apiClient,
                selectedProjectId: selectedProjectId,
                onChanged: onProjectChanged,
                allowNull: true,
                labelText: 'پروژه (همه)',
              ),
            ),
        ],
      ),
    );
  }
}
```

### مرحله 3️⃣: Frontend - به‌روزرسانی صفحات گزارش

**مثال: گزارش دفتر کل**

```dart
// lib/pages/business/general_ledger_report_page.dart

class _GeneralLedgerReportPageState extends State<GeneralLedgerReportPage> {
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedAccountId;
  int? _selectedFiscalYearId;
  int? _selectedProjectId;  // 🆕 اضافه شده
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش دفتر کل')),
      body: Column(
        children: [
          // 🆕 استفاده از ویجت فیلتر مشترک
          ReportFiltersWidget(
            businessId: widget.businessId,
            apiClient: widget.apiClient,
            calendarController: widget.calendarController,
            fromDate: _fromDate,
            toDate: _toDate,
            onFromDateChanged: (date) {
              setState(() => _fromDate = date);
              _loadReport();
            },
            onToDateChanged: (date) {
              setState(() => _toDate = date);
              _loadReport();
            },
            selectedProjectId: _selectedProjectId,
            onProjectChanged: (projectId) {
              setState(() => _selectedProjectId = projectId);
              _loadReport();
            },
            selectedFiscalYearId: _selectedFiscalYearId,
            onFiscalYearChanged: (fyId) {
              setState(() => _selectedFiscalYearId = fyId);
              _loadReport();
            },
            fiscalYears: _fiscalYears,
          ),
          
          // نمایش گزارش
          Expanded(
            child: _buildReportContent(),
          ),
        ],
      ),
    );
  }
  
  Future<void> _loadReport() async {
    final queryParams = <String, dynamic>{
      'from_date': _fromDate?.toIso8601String(),
      'to_date': _toDate?.toIso8601String(),
      'fiscal_year_id': _selectedFiscalYearId,
      'project_id': _selectedProjectId,  // 🆕 پاس دادن به API
    };
    
    // فراخوانی API
    final response = await widget.apiClient.get(
      '/api/v1/businesses/${widget.businessId}/reports/general-ledger',
      queryParameters: queryParams,
    );
    
    // پردازش و نمایش نتایج
    // ...
  }
}
```

---

## 🎨 نمایش بصری فیلتر پروژه در گزارشات

### قبل از پیاده‌سازی:
```
┌─────────────────────────────────────────┐
│  گزارش دفتر کل                         │
├─────────────────────────────────────────┤
│  از تاریخ: [____]  تا تاریخ: [____]   │
│  سال مالی: [__________▼]               │
├─────────────────────────────────────────┤
│  [جدول داده‌ها]                        │
└─────────────────────────────────────────┘
```

### بعد از پیاده‌سازی:
```
┌─────────────────────────────────────────┐
│  گزارش دفتر کل                         │
├─────────────────────────────────────────┤
│  از تاریخ: [____]  تا تاریخ: [____]   │
│  سال مالی: [__________▼]               │
│  🆕 پروژه: [همه پروژه‌ها____▼]        │
├─────────────────────────────────────────┤
│  [جدول داده‌ها - فیلتر شده با پروژه]  │
└─────────────────────────────────────────┘
```

---

## 📊 مثال‌های کاربردی

### مثال 1: گزارش سود و زیان یک پروژه

**سناریو**: مدیر می‌خواهد سودآوری پروژه "ساخت ساختمان A" را ببیند

**درخواست**:
```http
GET /api/v1/businesses/1/reports/pnl?
    from_date=2025-01-01&
    to_date=2025-03-31&
    project_id=5
```

**پاسخ**:
```json
{
  "success": true,
  "data": {
    "project": {
      "id": 5,
      "code": "PRJ-001",
      "name": "ساخت ساختمان A"
    },
    "period": {
      "from": "2025-01-01",
      "to": "2025-03-31"
    },
    "revenue": {
      "total": 500000000,
      "breakdown": {
        "sales": 450000000,
        "other_income": 50000000
      }
    },
    "expenses": {
      "total": 350000000,
      "breakdown": {
        "materials": 200000000,
        "labor": 100000000,
        "overhead": 50000000
      }
    },
    "net_profit": 150000000,
    "profit_margin": 30.0
  }
}
```

### مثال 2: مقایسه عملکرد چند پروژه

**UI**: نمودار مقایسه‌ای

```
سودآوری پروژه‌ها (فروردین 1404)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

پروژه A  ████████████░░ 80%  سود: 150M
پروژه B  ███████░░░░░░ 45%  سود: 90M
پروژه C  ██████████████ 95%  سود: 200M
همه      ████████████░░ 73%  سود: 440M
```

---

## 🔄 فلوچارت تصمیم‌گیری

```
شروع گزارش
    ↓
آیا فیلتر پروژه انتخاب شده؟
    ├─ بله → Query با شرط project_id
    │          ↓
    │      داده‌های فیلتر شده
    │          ↓
    │      نمایش عنوان "گزارش پروژه: [نام]"
    │
    └─ خیر → Query بدون شرط پروژه
               ↓
           همه داده‌ها
               ↓
           نمایش عنوان "گزارش کلی"
    ↓
نمایش نتایج
    ↓
پایان
```

---

## ⚡ بهینه‌سازی عملکرد

### 1. Caching نتایج گزارش
```python
from app.core.cache import get_cache

def get_pnl_report_cached(business_id, from_date, to_date, project_id):
    cache = get_cache()
    cache_key = f"pnl:{business_id}:{from_date}:{to_date}:{project_id or 'all'}"
    
    # بررسی cache
    cached_data = cache.get(cache_key)
    if cached_data:
        return cached_data
    
    # محاسبه گزارش
    report_data = calculate_pnl(...)
    
    # ذخیره در cache (1 ساعت)
    cache.set(cache_key, report_data, ttl=3600)
    
    return report_data
```

### 2. Index بر روی project_id
```sql
-- بهینه‌سازی query های گزارش
CREATE INDEX idx_documents_project_date 
ON documents(project_id, document_date);

CREATE INDEX idx_documents_project_fiscal 
ON documents(project_id, fiscal_year_id);
```

### 3. Materialized Views برای گزارشات پرکاربرد
```sql
-- View گزارش سود و زیان به تفکیک پروژه
CREATE MATERIALIZED VIEW mv_pnl_by_project AS
SELECT 
    d.project_id,
    p.name as project_name,
    DATE_FORMAT(d.document_date, '%Y-%m') as month,
    SUM(CASE WHEN a.code LIKE '4%' THEN dl.credit - dl.debit ELSE 0 END) as revenue,
    SUM(CASE WHEN a.code LIKE '5%' THEN dl.debit - dl.credit ELSE 0 END) as expense
FROM documents d
JOIN document_lines dl ON d.id = dl.document_id
JOIN accounts a ON dl.account_id = a.id
LEFT JOIN projects p ON d.project_id = p.id
GROUP BY d.project_id, p.name, DATE_FORMAT(d.document_date, '%Y-%m');

-- Refresh هر شب
REFRESH MATERIALIZED VIEW mv_pnl_by_project;
```

---

## 📱 نمونه UI/UX

### Card گزارش با فیلتر پروژه

```dart
Card(
  child: Column(
    children: [
      // هدر با نام پروژه
      if (_selectedProjectId != null)
        Container(
          padding: EdgeInsets.all(12),
          color: Colors.blue.shade50,
          child: Row(
            children: [
              Icon(Icons.folder_special, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'گزارش پروژه: $_selectedProjectName',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      
      // محتوای گزارش
      Padding(
        padding: EdgeInsets.all(16),
        child: _buildReportContent(),
      ),
    ],
  ),
)
```

---

## ✅ چک‌لیست پیاده‌سازی

### Backend
- [ ] به‌روزرسانی سرویس دفتر کل
- [ ] به‌روزرسانی سرویس روزنامه
- [ ] به‌روزرسانی سرویس تراز
- [ ] به‌روزرسانی سرویس سود و زیان
- [ ] به‌روزرسانی سرویس تراکنش‌های اشخاص
- [ ] به‌روزرسانی سرویس فروش
- [ ] به‌روزرسانی API endpoints گزارشات
- [ ] افزودن Index های بهینه‌ساز
- [ ] تست performance با داده‌های زیاد

### Frontend
- [ ] ایجاد `ReportFiltersWidget`
- [ ] به‌روزرسانی صفحه دفتر کل
- [ ] به‌روزرسانی صفحه سود و زیان
- [ ] به‌روزرسانی صفحه تراز
- [ ] به‌روزرسانی سایر گزارشات مالی
- [ ] به‌روزرسانی گزارشات فروش
- [ ] تست UX در موبایل و دسکتاپ

### Documentation
- [ ] به‌روزرسانی Swagger با پارامتر project_id
- [ ] راهنمای کاربری فیلتر پروژه در گزارشات
- [ ] نمونه‌های API در مستندات

---

## 🎯 اولویت‌بندی پیاده‌سازی

### فاز 1 (فوری - 1 هفته)
1. گزارش دفتر کل ⭐⭐⭐⭐⭐
2. گزارش روزنامه ⭐⭐⭐⭐⭐
3. گزارش سود و زیان ⭐⭐⭐⭐⭐
4. گزارش تراکنش‌های اشخاص ⭐⭐⭐⭐

### فاز 2 (مهم - 1 هفته)
5. گزارش تراز آزمایشی ⭐⭐⭐⭐
6. گزارش فروش روزانه ⭐⭐⭐⭐
7. گزارش گردش بانک ⭐⭐⭐⭐
8. گزارش بدهکاران/بستانکاران ⭐⭐⭐⭐

### فاز 3 (عادی - 1 هفته)
9. سایر گزارشات فروش ⭐⭐⭐
10. گزارشات انبار ⭐⭐⭐
11. گزارشات اقساط ⭐⭐

---

## 💡 نکات کلیدی

1. **سازگاری با گذشته**: فیلتر پروژه اختیاری است و عدم انتخاب آن به معنی "همه پروژه‌ها" است
2. **عملکرد**: استفاده از Index و Cache برای گزارشات پرکاربرد
3. **UI/UX**: نمایش واضح نام پروژه در هدر گزارش
4. **Export**: فایل‌های Excel/PDF خروجی باید نام پروژه را داشته باشند
5. **مقایسه**: امکان مشاهده همزمان چند پروژه در یک گزارش

---

**تاریخ**: دسامبر 2025  
**نسخه**: 1.0  
**وضعیت**: آماده پیاده‌سازی 🚀

