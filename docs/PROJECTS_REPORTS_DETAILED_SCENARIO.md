# 📊 سناریوی جامع یکپارچه‌سازی فیلتر پروژه در گزارشات

## 🎯 خلاصه اجرایی

افزودن فیلتر پروژه به **18 گزارش** موجود در سیستم برای امکان تحلیل و ردیابی مالی هر پروژه به صورت جداگانه.

---

## 📋 فهرست کامل گزارشات و اولویت‌بندی

### دسته 1: گزارشات حسابداری محوری (اولویت 1 - بحرانی) 🔴

| ردیف | نام گزارش | فایل Backend | فایل Frontend | اولویت |
|------|-----------|--------------|---------------|--------|
| 1 | دفتر کل | `general_ledger_service.py` | `general_ledger_report_page.dart` | ⭐⭐⭐⭐⭐ |
| 2 | دفتر روزنامه | `journal_ledger_service.py` | `journal_ledger_report_page.dart` | ⭐⭐⭐⭐⭐ |
| 3 | تراز آزمایشی | `trial_balance_service.py` | `trial_balance_report_page.dart` | ⭐⭐⭐⭐ |
| 4 | سود و زیان دوره‌ای | `pnl_service.py` | `pnl_period_report_page.dart` | ⭐⭐⭐⭐⭐ |
| 5 | سود و زیان تجمعی | `pnl_service.py` | `pnl_cumulative_report_page.dart` | ⭐⭐⭐⭐⭐ |

### دسته 2: گزارشات اشخاص (اولویت 2 - بالا) 🟠

| ردیف | نام گزارش | اولویت |
|------|-----------|--------|
| 6 | تراکنش‌های اشخاص | ⭐⭐⭐⭐ |
| 7 | بدهکاران | ⭐⭐⭐⭐ |
| 8 | بستانکاران | ⭐⭐⭐⭐ |
| 9 | برترین مشتریان | ⭐⭐⭐ |
| 10 | برترین تامین‌کنندگان | ⭐⭐⭐ |

### دسته 3: گزارشات فروش و خرید (اولویت 3 - متوسط) 🟡

| ردیف | نام گزارش | اولویت |
|------|-----------|--------|
| 11 | فروش روزانه | ⭐⭐⭐⭐ |
| 12 | خرید روزانه | ⭐⭐⭐⭐ |
| 13 | فروش ماهانه | ⭐⭐⭐ |
| 14 | فروش بر اساس محصول | ⭐⭐⭐ |

### دسته 4: گزارشات بانکی و نقدی (اولویت 4 - متوسط) 🟡

| ردیف | نام گزارش | اولویت |
|------|-----------|--------|
| 15 | گردش بانک | ⭐⭐⭐⭐ |
| 16 | گردش صندوق و تنخواه | ⭐⭐⭐⭐ |

### دسته 5: گزارشات انبار (اولویت 5 - پایین) 🟢

| ردیف | نام گزارش | اولویت |
|------|-----------|--------|
| 17 | کاردکس موجودی | ⭐⭐⭐ |
| 18 | تحرکات محصول | ⭐⭐ |

---

## 🔧 راهنمای پیاده‌سازی گام به گام

### گام 1: Backend - به‌روزرسانی سرویس‌های گزارش

#### 📄 فایل: `general_ledger_service.py`

**قبل از تغییر:**
```python
def get_general_ledger_report(
    db: Session,
    business_id: int,
    account_ids: List[int],
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    person_id: Optional[int] = None,
    include_proforma: bool = False,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
```

**بعد از تغییر:**
```python
def get_general_ledger_report(
    db: Session,
    business_id: int,
    account_ids: List[int],
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    person_id: Optional[int] = None,
    project_id: Optional[int] = None,  # 🆕 اضافه شد
    include_proforma: bool = False,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش دفتر کل با فیلتر پروژه
    
    Args:
        project_id: شناسه پروژه برای فیلتر (اختیاری)
    """
```

**در بدنه تابع، اضافه کنید:**
```python
# در قسمت query building
query = db.query(DocumentLine).join(Document).filter(
    Document.business_id == business_id,
    # ... سایر شرط‌ها
)

# 🆕 فیلتر پروژه
if project_id:
    query = query.filter(Document.project_id == project_id)
```

**همین تغییرات را برای این سرویس‌ها تکرار کنید:**
- ✅ `journal_ledger_service.py` → تابع `get_journal_ledger_report`
- ✅ `trial_balance_service.py` → تابع `get_trial_balance_report`
- ✅ `pnl_service.py` → توابع `get_pnl_period_report` و `get_pnl_cumulative_report`

---

### گام 2: Backend - به‌روزرسانی API Endpoints

#### 📄 فایل: `adapters/api/v1/documents.py`

**مثال: endpoint دفتر کل**

**قبل از تغییر:**
```python
@router.post("/businesses/{business_id}/reports/general-ledger")
async def general_ledger_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # ...
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    currency_id = body.get('currency_id')
    person_id = body.get('person_id')
    include_proforma = body.get('include_proforma', False)
```

**بعد از تغییر:**
```python
@router.post("/businesses/{business_id}/reports/general-ledger")
async def general_ledger_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # ...
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    currency_id = body.get('currency_id')
    person_id = body.get('person_id')
    project_id = body.get('project_id')  # 🆕 اضافه شد
    include_proforma = body.get('include_proforma', False)
    
    # 🆕 اعتبارسنجی پروژه
    if project_id is not None:
        try:
            project_id = int(project_id)
        except (ValueError, TypeError):
            project_id = None
    
    result = get_general_ledger_report(
        db=db,
        business_id=business_id,
        account_ids=account_ids,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        person_id=person_id,
        project_id=project_id,  # 🆕 پاس دادن به سرویس
        include_proforma=include_proforma,
        skip=skip,
        take=take,
    )
```

**این تغییرات را برای این endpoint ها اعمال کنید:**
- ✅ `/reports/general-ledger` (خط 2230)
- ✅ `/reports/pnl-period` (خط 2335)
- ✅ `/reports/pnl-cumulative` (خط 2414)
- ✅ `/reports/journal-ledger` (اگر وجود دارد)
- ✅ `/reports/trial-balance` (خط 2125)

---

### گام 3: Frontend - ایجاد Widget فیلتر یکپارچه

#### 📄 فایل: `lib/widgets/reports/common_report_filters.dart`

```dart
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';

/// فیلترهای مشترک گزارشات مالی
class CommonReportFilters extends StatelessWidget {
  final int businessId;
  final ApiClient apiClient;
  final CalendarController calendarController;
  
  // فیلترهای تاریخ
  final DateTime? fromDate;
  final DateTime? toDate;
  final VoidCallback? onClearDates;
  final Function(DateTime?) onFromDateChanged;
  final Function(DateTime?) onToDateChanged;
  
  // فیلتر سال مالی
  final int? selectedFiscalYearId;
  final List<Map<String, dynamic>>? fiscalYears;
  final Function(int?)? onFiscalYearChanged;
  
  // فیلتر پروژه 🆕
  final int? selectedProjectId;
  final Function(int?) onProjectChanged;
  
  // نمایش/عدم نمایش فیلترها
  final bool showDateFilters;
  final bool showFiscalYearFilter;
  final bool showProjectFilter;

  const CommonReportFilters({
    Key? key,
    required this.businessId,
    required this.apiClient,
    required this.calendarController,
    this.fromDate,
    this.toDate,
    this.onClearDates,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    this.selectedFiscalYearId,
    this.fiscalYears,
    this.onFiscalYearChanged,
    required this.selectedProjectId,
    required this.onProjectChanged,
    this.showDateFilters = true,
    this.showFiscalYearFilter = true,
    this.showProjectFilter = true,
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
        spacing: 12,
        runSpacing: 12,
        children: [
          // فیلترهای تاریخ
          if (showDateFilters) ...[
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
            if (onClearDates != null)
              IconButton(
                onPressed: onClearDates,
                icon: const Icon(Icons.clear),
                tooltip: 'پاک کردن فیلتر تاریخ',
              ),
          ],
          
          // فیلتر سال مالی
          if (showFiscalYearFilter && fiscalYears != null && fiscalYears!.isNotEmpty)
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                value: selectedFiscalYearId,
                decoration: const InputDecoration(
                  labelText: 'سال مالی',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
                items: fiscalYears!.map((fy) {
                  final id = fy['id'] as int;
                  final title = fy['title'] as String? ?? 'FY $id';
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(title, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: onFiscalYearChanged,
              ),
            ),
          
          // 🆕 فیلتر پروژه
          if (showProjectFilter)
            SizedBox(
              width: 280,
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

---

### گام 4: Frontend - به‌روزرسانی صفحه دفتر کل

#### 📄 فایل: `general_ledger_report_page.dart`

**تغییرات مورد نیاز:**

##### 1. اضافه کردن Import
```dart
import 'package:hesabix_ui/widgets/reports/common_report_filters.dart';
```

##### 2. اضافه کردن State
```dart
class _GeneralLedgerReportPageState extends State<GeneralLedgerReportPage> {
  // ... سایر state ها
  int? _selectedProjectId;  // 🆕 اضافه کنید
```

##### 3. جایگزینی بخش فیلترها
**قبل:**
```dart
// فیلترهای دستی موجود
Row(
  children: [
    DateInputField(...),
    DateInputField(...),
    // ...
  ],
)
```

**بعد:**
```dart
// 🆕 استفاده از widget مشترک
CommonReportFilters(
  businessId: widget.businessId,
  apiClient: ApiClient(),
  calendarController: widget.calendarController,
  fromDate: _fromDate,
  toDate: _toDate,
  onFromDateChanged: (date) {
    setState(() => _fromDate = date);
    _refreshData();
  },
  onToDateChanged: (date) {
    setState(() => _toDate = date);
    _refreshData();
  },
  onClearDates: () {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _refreshData();
  },
  selectedFiscalYearId: _selectedFiscalYearId,
  fiscalYears: _fiscalYears,
  onFiscalYearChanged: (fyId) {
    setState(() => _selectedFiscalYearId = fyId);
    _refreshData();
  },
  selectedProjectId: _selectedProjectId,  // 🆕
  onProjectChanged: (projectId) {         // 🆕
    setState(() => _selectedProjectId = projectId);
    _refreshData();
  },
),
```

##### 4. اضافه کردن به DataTableConfig
```dart
DataTableConfig(
  endpoint: '/api/v1/businesses/${widget.businessId}/reports/general-ledger',
  method: 'POST',
  requestBody: () {
    final body = <String, dynamic>{
      'account_ids': _selectedAccounts.map((a) => a.id).toList(),
    };
    
    if (_fromDate != null) body['date_from'] = _fromDate!.toIso8601String();
    if (_toDate != null) body['date_to'] = _toDate!.toIso8601String();
    if (_selectedFiscalYearId != null) body['fiscal_year_id'] = _selectedFiscalYearId;
    if (_selectedCurrencyId != null) body['currency_id'] = _selectedCurrencyId;
    if (_selectedPerson != null) body['person_id'] = _selectedPerson!.id;
    if (_selectedProjectId != null) body['project_id'] = _selectedProjectId;  // 🆕
    body['include_proforma'] = _includeProforma;
    
    return body;
  },
  // ...
)
```

---

### گام 5: نمونه کامل برای یک گزارش

#### 🎯 مثال عملی: گزارش سود و زیان

##### Backend

**1. به‌روزرسانی Service:**
```python
# hesabixAPI/app/services/pnl_service.py

def get_pnl_period_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    project_id: Optional[int] = None,  # 🆕 خط 51
    skip: int = 0,
    take: int = 100,
) -> Dict[str, Any]:
    """
    گزارش سود و زیان دوره‌ای با فیلتر پروژه
    """
    # ... کد موجود ...
    
    # 🆕 اضافه کردن فیلتر پروژه در query های درآمد و هزینه
    turnover_query = db.query(
        DocumentLine.account_id,
        func.sum(DocumentLine.debit).label('total_debit'),
        func.sum(DocumentLine.credit).label('total_credit')
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        and_(
            Document.business_id == business_id,
            Document.is_proforma == False,
            DocumentLine.account_id.isnot(None),
            DocumentLine.account_id.in_(account_ids),
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    # 🆕 فیلتر پروژه
    if project_id:
        turnover_query = turnover_query.filter(Document.project_id == project_id)
    
    turnover_query = turnover_query.group_by(DocumentLine.account_id)
    
    # ادامه کد...
```

**2. به‌روزرسانی Endpoint:**
```python
# hesabixAPI/adapters/api/v1/documents.py (خط 2335)

@router.post("/businesses/{business_id}/reports/pnl-period")
async def pnl_period_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # استخراج پارامترها
    fiscal_year_id = body.get('fiscal_year_id')
    currency_id = body.get('currency_id')
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    project_id = body.get('project_id')  # 🆕
    
    # تبدیل نوع
    if project_id is not None:
        try:
            project_id = int(project_id)
        except (ValueError, TypeError):
            project_id = None
    
    # فراخوانی سرویس
    result = get_pnl_period_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        project_id=project_id,  # 🆕
        skip=skip,
        take=take,
    )
    
    return success_response(data=result, message="گزارش سود و زیان دریافت شد")
```

##### Frontend

**به‌روزرسانی صفحه:**
```dart
// lib/pages/business/pnl_period_report_page.dart

class _PnlPeriodReportPageState extends State<PnlPeriodReportPage> {
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedProjectId;  // 🆕
  
  List<Map<String, dynamic>> _fiscalYears = [];
  Map<String, dynamic>? _reportData;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('گزارش سود و زیان دوره‌ای'),
            // 🆕 نمایش نام پروژه در عنوان
            if (_selectedProjectId != null && _projectName != null)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_special, size: 16),
                    const SizedBox(width: 4),
                    Text('پروژه: $_projectName', style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _exportToPdf,
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'خروجی PDF',
          ),
          IconButton(
            onPressed: _exportToExcel,
            icon: const Icon(Icons.table_chart),
            tooltip: 'خروجی Excel',
          ),
        ],
      ),
      body: Column(
        children: [
          // 🆕 فیلترهای یکپارچه
          CommonReportFilters(
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
            onClearDates: () {
              setState(() {
                _fromDate = null;
                _toDate = null;
              });
              _loadReport();
            },
            selectedFiscalYearId: _selectedFiscalYearId,
            fiscalYears: _fiscalYears,
            onFiscalYearChanged: (fyId) {
              setState(() => _selectedFiscalYearId = fyId);
              _loadReport();
            },
            selectedProjectId: _selectedProjectId,
            onProjectChanged: (projectId) {
              setState(() => _selectedProjectId = projectId);
              _loadReport();
            },
          ),
          
          const SizedBox(height: 16),
          
          // محتوای گزارش
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildReportContent(),
          ),
        ],
      ),
    );
  }
  
  Future<void> _loadReport() async {
    if (_loading) return;
    
    setState(() => _loading = true);
    
    try {
      final body = <String, dynamic>{};
      
      if (_fromDate != null) body['date_from'] = _fromDate!.toIso8601String();
      if (_toDate != null) body['date_to'] = _toDate!.toIso8601String();
      if (_selectedFiscalYearId != null) body['fiscal_year_id'] = _selectedFiscalYearId;
      if (_selectedProjectId != null) body['project_id'] = _selectedProjectId;  // 🆕
      
      final response = await widget.apiClient.post(
        '/api/v1/businesses/${widget.businessId}/reports/pnl-period',
        data: body,
      );
      
      if (response['success'] == true) {
        setState(() {
          _reportData = response['data'] as Map<String, dynamic>;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
      // نمایش خطا
    }
  }
  
  Widget _buildReportContent() {
    if (_reportData == null) {
      return const Center(child: Text('فیلترها را انتخاب کنید'));
    }
    
    final summary = _reportData!['summary'] as Map<String, dynamic>;
    final revenue = summary['total_revenue'] as num? ?? 0;
    final expense = summary['total_expense'] as num? ?? 0;
    final netProfit = summary['net_profit_loss'] as num? ?? 0;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 🆕 Card خلاصه با نمایش نام پروژه
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_selectedProjectId != null)
                    Row(
                      children: [
                        const Icon(Icons.folder_special, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'گزارش پروژه: $_projectName',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem('درآمد', revenue, Colors.green),
                      _buildSummaryItem('هزینه', expense, Colors.red),
                      _buildSummaryItem(
                        netProfit >= 0 ? 'سود' : 'زیان',
                        netProfit.abs(),
                        netProfit >= 0 ? Colors.green : Colors.red,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // جداول درآمد و هزینه
          _buildRevenueTable(),
          const SizedBox(height: 16),
          _buildExpenseTable(),
        ],
      ),
    );
  }
}
```

---

## 📊 نمایش بصری تغییرات

### قبل از یکپارچه‌سازی:
```
┌─────────────────────────────────────────────────────┐
│  گزارش سود و زیان                                  │
├─────────────────────────────────────────────────────┤
│  از تاریخ: [1404/01/01]  تا تاریخ: [1404/03/31]  │
│  سال مالی: [1404        ▼]                         │
├─────────────────────────────────────────────────────┤
│  درآمد: 500,000,000  |  هزینه: 350,000,000        │
│  سود خالص: 150,000,000                             │
├─────────────────────────────────────────────────────┤
│  [جدول تفصیلی درآمدها و هزینه‌ها]                 │
└─────────────────────────────────────────────────────┘
```

### بعد از یکپارچه‌سازی:
```
┌─────────────────────────────────────────────────────┐
│  گزارش سود و زیان  📁 پروژه: ساخت ساختمان A      │
├─────────────────────────────────────────────────────┤
│  از تاریخ: [1404/01/01]  تا تاریخ: [1404/03/31]  │
│  سال مالی: [1404        ▼]                         │
│  🆕 پروژه: [ساخت ساختمان A  ▼]                   │
├─────────────────────────────────────────────────────┤
│  📊 عملکرد پروژه در دوره انتخابی:                │
│  درآمد: 200,000,000  |  هزینه: 150,000,000        │
│  سود خالص: 50,000,000  |  حاشیه سود: 25%          │
├─────────────────────────────────────────────────────┤
│  [جدول تفصیلی - فقط تراکنش‌های این پروژه]         │
└─────────────────────────────────────────────────────┘
```

---

## 🎯 ویژگی‌های خاص هر گزارش

### 1. گزارش دفتر کل
**کاربرد پروژه:**
- مشاهده تراکنش‌های یک حساب در پروژه خاص
- مانده حساب دریافتنی/پرداختنی در پروژه

**مثال query:**
```python
if project_id:
    query = query.filter(Document.project_id == project_id)
```

### 2. گزارش سود و زیان
**کاربرد پروژه:**
- محاسبه سودآوری هر پروژه
- مقایسه عملکرد پروژه‌ها
- تحلیل حاشیه سود

**امکان جدید: مقایسه چند پروژه**
```dart
// انتخاب چند پروژه برای مقایسه
List<int> _selectedProjects = [];

// نمایش نمودار مقایسه‌ای
BarChart(
  data: _selectedProjects.map((projectId) {
    return {
      'project': getProjectName(projectId),
      'profit': getProjectProfit(projectId),
    };
  }),
)
```

### 3. گزارش روزنامه
**کاربرد پروژه:**
- مشاهده همه اسناد ثبت شده در پروژه
- ممیزی تراکنش‌های پروژه

### 4. گزارش تراز
**کاربرد پروژه:**
- تراز حساب‌ها محدود به پروژه خاص
- بررسی صحت ثبت‌های پروژه

### 5. گزارش‌های فروش
**کاربرد پروژه:**
- فروش روزانه/ماهانه هر پروژه
- محصولات پرفروش در پروژه
- مشتریان کلیدی پروژه

---

## 🎨 UI/UX پیشرفته

### 1. نمایش Badge پروژه
```dart
// در هدر گزارش
if (_selectedProjectId != null)
  Container(
    padding: EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.blue.shade100,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.folder_special, size: 16, color: Colors.blue),
        SizedBox(width: 4),
        Text('پروژه: $_projectName'),
        IconButton(
          icon: Icon(Icons.close, size: 16),
          onPressed: () {
            setState(() => _selectedProjectId = null);
            _loadReport();
          },
        ),
      ],
    ),
  ),
```

### 2. Export با نام پروژه
```dart
Future<void> _exportToExcel() async {
  String filename = 'گزارش_سود_و_زیان';
  
  // 🆕 اضافه کردن نام پروژه به نام فایل
  if (_selectedProjectId != null && _projectName != null) {
    filename += '_${_projectName.replaceAll(' ', '_')}';
  }
  
  filename += '_${_fromDate}_${_toDate}.xlsx';
  
  // ادامه export...
}
```

### 3. ذخیره فیلترهای پیش‌فرض
```dart
// ذخیره آخرین فیلتر انتخابی
SharedPreferences prefs = await SharedPreferences.getInstance();
await prefs.setInt('last_selected_project_id', _selectedProjectId ?? 0);

// بازیابی در بارگذاری
_selectedProjectId = prefs.getInt('last_selected_project_id');
```

---

## 🔍 کیس‌های خاص

### کیس 1: گزارش بدون پروژه
```dart
// اضافه کردن گزینه "فقط اسناد بدون پروژه"
DropdownMenuItem(
  value: -1,  // مقدار خاص
  child: Text('اسناد بدون پروژه'),
)

// در API
if project_id == -1:
    query = query.filter(Document.project_id == None)
```

### کیس 2: مقایسه با/بدون پروژه
```dart
// Toggle برای نمایش همزمان
bool _showComparison = false;

if (_showComparison) {
  // نمایش 2 ستون: با پروژه / بدون پروژه
  Row(
    children: [
      Expanded(child: _buildProjectReport()),
      Expanded(child: _buildNonProjectReport()),
    ],
  )
}
```

### کیس 3: گزارش چند پروژه
```dart
// انتخاب چندتایی برای مقایسه
List<int> _selectedProjects = [];

MultiProjectSelector(
  selectedProjects: _selectedProjects,
  onChanged: (projects) {
    setState(() => _selectedProjects = projects);
    _loadComparativeReport();
  },
)
```

---

## 🚀 نقشه راه پیاده‌سازی (Roadmap)

### Week 1: گزارشات حسابداری اصلی
- [ ] دفتر کل (2 ساعت)
- [ ] دفتر روزنامه (2 ساعت)
- [ ] تراز آزمایشی (1.5 ساعت)
- [ ] سود و زیان دوره‌ای (2 ساعت)
- [ ] سود و زیان تجمعی (2 ساعت)
- [ ] تست و اصلاح باگ (2 ساعت)

**جمع: 11.5 ساعت**

### Week 2: گزارشات اشخاص و فروش
- [ ] تراکنش‌های اشخاص (1.5 ساعت)
- [ ] بدهکاران/بستانکاران (2 ساعت)
- [ ] فروش روزانه (1.5 ساعت)
- [ ] خرید روزانه (1.5 ساعت)
- [ ] فروش ماهانه (1 ساعت)
- [ ] تست کلی (2 ساعت)

**جمع: 9.5 ساعت**

### Week 3: گزارشات بانکی و انبار
- [ ] گردش بانک (2 ساعت)
- [ ] گردش صندوق (1.5 ساعت)
- [ ] کاردکس (1.5 ساعت)
- [ ] سایر گزارشات (2 ساعت)
- [ ] تست نهایی (2 ساعت)

**جمع: 9 ساعت**

**⏱️ زمان کل تخمینی: 30 ساعت (حدود 4 روز کاری)**

---

## 📝 الگوی کد برای کپی-پیست

### الگوی Backend (Service)
```python
def get_YOUR_report(
    db: Session,
    business_id: int,
    # ... پارامترهای موجود
    project_id: Optional[int] = None,  # 🆕 همیشه اضافه کنید
    skip: int = 0,
    take: int = 100,
) -> Dict[str, Any]:
    """گزارش با فیلتر پروژه"""
    
    # Query پایه
    query = db.query(...).join(Document).filter(
        Document.business_id == business_id,
        # ... سایر فیلترها
    )
    
    # 🆕 فیلتر پروژه - همیشه همین ساختار
    if project_id:
        query = query.filter(Document.project_id == project_id)
    
    # ادامه query...
```

### الگوی Backend (API Endpoint)
```python
@router.post("/businesses/{business_id}/reports/YOUR-REPORT")
async def your_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    # ...
):
    # استخراج پارامترها
    project_id = body.get('project_id')  # 🆕 اضافه کنید
    
    # تبدیل نوع
    if project_id is not None:
        try:
            project_id = int(project_id)
        except (ValueError, TypeError):
            project_id = None
    
    # فراخوانی سرویس
    result = get_YOUR_report(
        # ... سایر پارامترها
        project_id=project_id,  # 🆕 پاس دهید
    )
```

### الگوی Frontend (Page State)
```dart
class _YourReportPageState extends State<YourReportPage> {
  // ... سایر state ها
  int? _selectedProjectId;  // 🆕 همیشه اضافه کنید
  String? _projectName;      // 🆕 برای نمایش
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text('عنوان گزارش'),
            // 🆕 نمایش badge پروژه
            if (_selectedProjectId != null)
              _buildProjectBadge(),
          ],
        ),
      ),
      body: Column(
        children: [
          // 🆕 فیلترهای یکپارچه
          CommonReportFilters(
            businessId: widget.businessId,
            apiClient: widget.apiClient,
            calendarController: widget.calendarController,
            // ... سایر فیلترها
            selectedProjectId: _selectedProjectId,
            onProjectChanged: _onProjectChanged,
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }
  
  void _onProjectChanged(int? projectId) {
    setState(() => _selectedProjectId = projectId);
    if (projectId != null) {
      _loadProjectName(projectId);
    } else {
      _projectName = null;
    }
    _loadReport();
  }
}
```

---

## 🧪 نمونه‌های تست

### تست Backend
```python
# test_project_filter_in_reports.py

def test_general_ledger_with_project():
    """تست فیلتر پروژه در دفتر کل"""
    # ایجاد 2 پروژه
    project1 = create_project(db, business_id=1, data={'code': 'P1', 'name': 'پروژه 1'})
    project2 = create_project(db, business_id=1, data={'code': 'P2', 'name': 'پروژه 2'})
    
    # ایجاد 4 فاکتور: 2 برای پروژه 1، 2 برای پروژه 2
    invoice1 = create_invoice(db, business_id=1, data={'project_id': project1.id, ...})
    invoice2 = create_invoice(db, business_id=1, data={'project_id': project1.id, ...})
    invoice3 = create_invoice(db, business_id=1, data={'project_id': project2.id, ...})
    invoice4 = create_invoice(db, business_id=1, data={'project_id': project2.id, ...})
    
    # گزارش بدون فیلتر پروژه - باید 4 سند نمایش دهد
    report_all = get_general_ledger_report(db, business_id=1, account_ids=[...])
    assert report_all['pagination']['total'] == 4
    
    # گزارش با فیلتر پروژه 1 - باید 2 سند نمایش دهد
    report_p1 = get_general_ledger_report(db, business_id=1, account_ids=[...], project_id=project1.id)
    assert report_p1['pagination']['total'] == 2
    
    # گزارش با فیلتر پروژه 2 - باید 2 سند نمایش دهد
    report_p2 = get_general_ledger_report(db, business_id=1, account_ids=[...], project_id=project2.id)
    assert report_p2['pagination']['total'] == 2
```

### تست Frontend
```dart
// test/reports/general_ledger_project_filter_test.dart

testWidgets('General Ledger with project filter', (tester) async {
  await tester.pumpWidget(MyApp());
  
  // رفتن به صفحه گزارش
  await tester.tap(find.text('گزارش دفتر کل'));
  await tester.pumpAndSettle();
  
  // انتخاب پروژه
  await tester.tap(find.byType(ProjectSelectorWidget));
  await tester.pumpAndSettle();
  await tester.tap(find.text('پروژه A'));
  await tester.pumpAndSettle();
  
  // بررسی نمایش badge
  expect(find.text('پروژه: پروژه A'), findsOneWidget);
  
  // بررسی فیلتر شدن داده‌ها
  // ...
});
```

---

## 📈 KPIs و متریک‌ها

### متریک‌های قابل اندازه‌گیری برای هر پروژه:

1. **مالی**:
   - درآمد کل
   - هزینه کل
   - سود/زیان خالص
   - حاشیه سود (Profit Margin)
   - بازگشت سرمایه (ROI)

2. **عملیاتی**:
   - تعداد اسناد
   - تعداد فاکتورها
   - تعداد تراکنش‌ها
   - میانگین ارزش فاکتور

3. **زمانی**:
   - مدت زمان پروژه
   - درصد پیشرفت زمانی
   - پیش‌بینی تاریخ اتمام

4. **بودجه**:
   - بودجه تخصیصی
   - هزینه واقعی
   - انحراف از بودجه (Budget Variance)
   - درصد مصرف بودجه

### Dashboard پروژه (پیشنهاد آینده)
```dart
ProjectDashboard(
  projectId: _selectedProjectId,
  widgets: [
    // KPI Cards
    KPICard(title: 'درآمد', value: revenue, icon: Icons.trending_up),
    KPICard(title: 'هزینه', value: expense, icon: Icons.trending_down),
    KPICard(title: 'سود', value: profit, icon: Icons.monetization_on),
    
    // نمودارها
    ProfitTrendChart(projectId: _selectedProjectId),
    ExpenseBreakdownPieChart(projectId: _selectedProjectId),
    BudgetVsActualChart(projectId: _selectedProjectId),
  ],
)
```

---

## ✅ چک‌لیست تکمیل

### Backend (11 فایل)
- [ ] `general_ledger_service.py` + endpoint
- [ ] `journal_ledger_service.py` + endpoint
- [ ] `trial_balance_service.py` + endpoint
- [ ] `pnl_service.py` (2 تابع) + endpoints
- [ ] گزارشات فروش (3 سرویس)
- [ ] گزارشات بانک (2 سرویس)
- [ ] تست‌های واحد

### Frontend (11 فایل)
- [ ] `common_report_filters.dart` (widget جدید)
- [ ] `general_ledger_report_page.dart`
- [ ] `journal_ledger_report_page.dart`
- [ ] `trial_balance_report_page.dart`
- [ ] `pnl_period_report_page.dart`
- [ ] `pnl_cumulative_report_page.dart`
- [ ] `people_transactions_report_page.dart`
- [ ] `daily_sales_report_page.dart`
- [ ] `bank_accounts_turnover_report_page.dart`
- [ ] تست‌های UI

### Documentation
- [x] سناریوی کلی
- [x] راهنمای یکپارچه‌سازی
- [ ] نمونه‌های API (Swagger)
- [ ] راهنمای کاربری

---

## 💰 تخمین هزینه/زمان

| مرحله | تخمین زمان | توسعه‌دهنده |
|-------|-------------|--------------|
| Backend Services | 12 ساعت | Backend Dev |
| Backend Endpoints | 6 ساعت | Backend Dev |
| Frontend Widgets | 4 ساعت | Frontend Dev |
| Frontend Pages | 12 ساعت | Frontend Dev |
| Testing | 8 ساعت | QA Team |
| Documentation | 4 ساعت | Tech Writer |
| **جمع** | **46 ساعت** | **~6 روز کاری** |

---

## 🎁 ارزش افزوده برای کاربران

### قبل از پیاده‌سازی:
❌ گزارش‌ها کلی و نامشخص  
❌ عدم امکان تحلیل عملکرد پروژه  
❌ سختی در پیگیری هزینه‌های پروژه  
❌ نیاز به Export و تحلیل دستی در Excel  

### بعد از پیاده‌سازی:
✅ گزارش دقیق هر پروژه  
✅ تحلیل سودآوری لحظه‌ای  
✅ کنترل بودجه پروژه  
✅ تصمیم‌گیری مبتنی بر داده  
✅ صرفه‌جویی ساعت‌ها زمان  

---

## 🏆 Best Practices

1. **Performance**: Cache کردن لیست پروژه‌ها (TTL: 5 دقیقه)
2. **UX**: نمایش واضح "بدون فیلتر" vs "همه پروژه‌ها"
3. **Export**: اضافه کردن نام پروژه به فایل‌های خروجی
4. **Validation**: بررسی تعلق پروژه به همان کسب‌وکار
5. **Logging**: ثبت log برای تحلیل استفاده از فیلتر پروژه

---

**نسخه**: 1.0.0  
**تاریخ**: دسامبر 2025  
**وضعیت**: ✅ آماده شروع پیاده‌سازی

