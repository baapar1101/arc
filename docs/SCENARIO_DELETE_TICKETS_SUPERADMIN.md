# سناریو: حذف تیکت‌های پشتیبانی توسط مدیر سیستم

## 📋 خلاصه اجرایی

این سناریو قابلیت حذف تیکت‌های پشتیبانی توسط مدیر سیستم (superadmin) را پیاده‌سازی می‌کند. در این سناریو:
- فقط مدیر سیستم می‌تواند تیکت‌ها را حذف کند
- اپراتورها و کاربران عادی امکان حذف تیکت ندارند
- دکمه حذف فقط در صفحه لیست تیکت‌های اپراتور برای مدیر سیستم نمایش داده می‌شود
- حذف تیکت به صورت Hard Delete انجام می‌شود (تیکت و پیام‌های مرتبط کاملاً حذف می‌شوند)

---

## 🎯 اهداف

1. **امنیت**: فقط مدیر سیستم (superadmin) بتواند تیکت‌ها را حذف کند
2. **UI/UX**: دکمه حذف فقط برای superadmin در لیست تیکت‌های اپراتور نمایش داده شود
3. **تأیید دو مرحله‌ای**: قبل از حذف، از کاربر تأیید گرفته شود
4. **حذف کامل**: تیکت و تمام پیام‌های مرتبط با آن حذف شوند

---

## 🏗️ معماری

```
┌─────────────────────────────────────────────────────────┐
│                  Frontend (Flutter)                      │
│  ┌────────────────────────────────────────────────────┐ │
│  │  OperatorTicketsPage                               │ │
│  │  ┌──────────────────────────────────────────────┐ │ │
│  │  │  if (isSuperAdmin)                           │ │ │
│  │  │    - نمایش دکمه حذف در Bulk Actions        │ │ │
│  │  │    - نمایش آیکون حذف در هر ردیف           │ │ │
│  │  │  else                                         │ │ │
│  │  │    - عدم نمایش دکمه حذف                    │ │ │
│  │  └──────────────────────────────────────────────┘ │ │
│  │                                                    │ │
│  │  SupportService.deleteTicket(ticketId)            │ │
│  │    ↓                                               │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│                  Backend (FastAPI)                       │
│  ┌────────────────────────────────────────────────────┐ │
│  │  DELETE /api/v1/support/operator/tickets/{id}     │ │
│  │  ┌──────────────────────────────────────────────┐ │ │
│  │  │  @require_superadmin                         │ │ │
│  │  │  1. بررسی وجود تیکت                        │ │ │
│  │  │  2. حذف تیکت از دیتابیس                   │ │ │
│  │  │  3. بازگشت پاسخ موفقیت                     │ │ │
│  │  └──────────────────────────────────────────────┘ │ │
│  │                                                    │ │
│  │  TicketRepository.delete_ticket(ticket_id)        │ │
│  │    ↓                                               │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│                    Database                              │
│  ┌────────────────────────────────────────────────────┐ │
│  │  support_tickets                                   │ │
│  │    - حذف رکورد تیکت (CASCADE)                    │ │
│  │  support_messages                                  │ │
│  │    - حذف تمام پیام‌های مرتبط (CASCADE)           │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

---

## 📝 پیاده‌سازی

### 1. Backend - Repository Layer

**فایل:** `hesabixAPI/adapters/db/repositories/support/ticket_repository.py`

در این فایل، متد جدید `delete_ticket` را اضافه می‌کنیم:

```python
def delete_ticket(self, ticket_id: int) -> bool:
    """
    حذف تیکت و تمام پیام‌های مرتبط
    
    Args:
        ticket_id: شناسه تیکت
        
    Returns:
        True اگر تیکت حذف شد، False اگر تیکت یافت نشد
    """
    ticket = self.get_by_id(ticket_id)
    if not ticket:
        return False
    
    # حذف تیکت (پیام‌ها به صورت CASCADE حذف می‌شوند)
    self.db.delete(ticket)
    self.db.commit()
    return True
```

**توضیحات:**
- متد `get_by_id` از `BaseRepository` ارث‌بری شده و تیکت را از دیتابیس می‌گیرد
- با حذف تیکت، به دلیل `ondelete="CASCADE"` در model، تمام پیام‌های مرتبط نیز حذف می‌شوند
- اگر تیکت یافت نشد، `False` برمی‌گرداند

---

### 2. Backend - API Layer

**فایل:** `hesabixAPI/adapters/api/v1/support/operator.py`

در این فایل، endpoint جدید برای حذف تیکت اضافه می‌کنیم:

```python
@router.delete("/tickets/{ticket_id}", response_model=SuccessResponse)
@require_app_permission("superadmin")
async def delete_ticket(
    request: Request,
    ticket_id: int,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """حذف تیکت (فقط برای مدیر سیستم)"""
    ticket_repo = TicketRepository(db)
    
    # حذف تیکت
    deleted = ticket_repo.delete_ticket(ticket_id)
    
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="تیکت یافت نشد یا قبلاً حذف شده است"
        )
    
    return success_response(
        {"message": "تیکت با موفقیت حذف شد", "ticket_id": ticket_id},
        request
    )
```

**توضیحات:**
- دکوراتور `@require_app_permission("superadmin")` تضمین می‌کند فقط superadmin بتواند این endpoint را صدا بزند
- متد HTTP: `DELETE`
- اگر تیکت یافت نشد، خطای `404` برمی‌گرداند
- در صورت موفقیت، پیام موفقیت و ID تیکت حذف شده را برمی‌گرداند

---

### 3. Backend - Permission Decorator (اختیاری)

اگر دکوراتور `@require_app_permission("superadmin")` وجود ندارد، می‌توانیم آن را به فایل permissions اضافه کنیم:

**فایل:** `hesabixAPI/app/core/permissions.py`

```python
from functools import wraps
from fastapi import HTTPException, status
from app.core.auth_dependency import AuthContext

def require_superadmin(func):
    """
    دکوراتور برای محدود کردن دسترسی به superadmin
    """
    @wraps(func)
    async def wrapper(*args, current_user: AuthContext, **kwargs):
        if not current_user.is_superadmin():
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="فقط مدیر سیستم مجاز به انجام این عملیات است"
            )
        return await func(*args, current_user=current_user, **kwargs)
    return wrapper
```

**توضیحات:**
- این دکوراتور می‌تواند به جای `@require_app_permission("superadmin")` استفاده شود
- با استفاده از `current_user.is_superadmin()` چک می‌کند که آیا کاربر superadmin است یا نه

---

### 4. Frontend - Service Layer

**فایل:** `hesabixUI/hesabix_ui/lib/services/support_service.dart`

متد جدید برای حذف تیکت اضافه می‌کنیم:

```dart
/// حذف تیکت (فقط برای مدیر سیستم)
Future<void> deleteTicket(int ticketId) async {
  try {
    await _apiClient.delete(
      '/api/v1/support/operator/tickets/$ticketId',
    );
  } on DioException catch (e) {
    throw _handleError(e);
  }
}

/// حذف چندین تیکت به صورت گروهی (فقط برای مدیر سیستم)
Future<Map<String, dynamic>> deleteTickets(List<int> ticketIds) async {
  try {
    final results = <int, dynamic>{};
    
    for (final ticketId in ticketIds) {
      try {
        await deleteTicket(ticketId);
        results[ticketId] = {'success': true};
      } catch (e) {
        results[ticketId] = {'success': false, 'error': e.toString()};
      }
    }
    
    final successCount = results.values.where((r) => r['success'] == true).length;
    final failCount = results.values.where((r) => r['success'] == false).length;
    
    return {
      'total': ticketIds.length,
      'success': successCount,
      'failed': failCount,
      'results': results,
    };
  } on DioException catch (e) {
    throw _handleError(e);
  }
}
```

**توضیحات:**
- متد `deleteTicket`: حذف یک تیکت
- متد `deleteTickets`: حذف چندین تیکت به صورت گروهی (برای Bulk Delete)
- در صورت خطا، پیام خطا را به صورت Exception برمی‌گرداند

---

### 5. Frontend - UI Layer

**فایل:** `hesabixUI/hesabix_ui/lib/pages/profile/operator/operator_tickets_page.dart`

تغییرات مورد نیاز:

#### 5.1. اضافه کردن State برای چک کردن superadmin

```dart
class _OperatorTicketsPageState extends State<OperatorTicketsPage> {
  Set<int> _selectedRows = <int>{};
  
  // Support data for filters
  final SupportService _supportService = SupportService(ApiClient());
  List<SupportStatus> _statuses = [];
  List<SupportPriority> _priorities = [];
  
  // Refresh counter to force data table refresh
  int _refreshCounter = 0;
  
  // Check if current user is superadmin
  bool _isSuperAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
    _checkUserPermissions();
  }
  
  Future<void> _checkUserPermissions() async {
    try {
      final apiClient = ApiClient();
      final response = await apiClient.get<Map<String, dynamic>>('/api/v1/auth/me');
      final permissions = response.data?['data']?['permissions'] as Map<String, dynamic>?;
      final isSuperAdmin = permissions?['is_superadmin'] as bool? ?? false;
      
      setState(() {
        _isSuperAdmin = isSuperAdmin;
      });
    } catch (e) {
      // Handle error silently
    }
  }
  
  // ... بقیه کد
}
```

#### 5.2. اضافه کردن متدهای حذف

```dart
Future<void> _deleteTicket(int ticketId) async {
  // نمایش دیالوگ تأیید
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.confirmDelete),
      content: Text(t.deleteTicketConfirmMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: Text(t.delete),
        ),
      ],
    ),
  );
  
  if (confirmed != true) return;
  
  try {
    await _supportService.deleteTicket(ticketId);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.ticketDeletedSuccessfully)),
      );
      
      // Refresh the data table
      setState(() {
        _refreshCounter++;
      });
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.errorDeletingTicket(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<void> _deleteSelectedTickets() async {
  if (_selectedRows.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.noTicketsSelected)),
    );
    return;
  }
  
  // نمایش دیالوگ تأیید
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.confirmBulkDelete),
      content: Text(t.deleteBulkTicketsConfirmMessage(_selectedRows.length)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: Text(t.delete),
        ),
      ],
    ),
  );
  
  if (confirmed != true) return;
  
  try {
    // نمایش loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    
    final result = await _supportService.deleteTickets(_selectedRows.toList());
    
    // بستن loading
    if (mounted) Navigator.of(context).pop();
    
    if (mounted) {
      final successCount = result['success'] as int;
      final failCount = result['failed'] as int;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t.bulkDeleteResult(successCount, failCount),
          ),
          backgroundColor: failCount > 0 ? Colors.orange : Colors.green,
        ),
      );
      
      // پاک کردن انتخاب‌ها و refresh
      setState(() {
        _selectedRows.clear();
        _refreshCounter++;
      });
    }
  } catch (e) {
    // بستن loading
    if (mounted) Navigator.of(context).pop();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.errorDeletingTickets(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
```

#### 5.3. اضافه کردن دکمه حذف گروهی و آیکون حذف به DataTable

```dart
@override
Widget build(BuildContext context) {
  final t = AppLocalizations.of(context);
  final theme = Theme.of(context);

  return Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                t.operatorPanel,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // دکمه حذف گروهی (فقط برای superadmin)
              if (_isSuperAdmin && _selectedRows.isNotEmpty) ...[
                ElevatedButton.icon(
                  onPressed: _deleteSelectedTickets,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(t.deleteSelected(_selectedRows.length)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red.shade700,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: DataTableWidget<Map<String, dynamic>>(
              key: ValueKey('data_table_$_refreshCounter'),
              config: DataTableConfig<Map<String, dynamic>>(
                title: 'لیست تیکت‌های پشتیبانی - پنل اپراتور',
                endpoint: '/api/v1/support/operator/tickets/search',
                columns: [
                  // اضافه کردن ستون Actions در ابتدا (فقط برای superadmin)
                  if (_isSuperAdmin)
                    ActionsColumn<Map<String, dynamic>>(
                      'actions',
                      t.actions,
                      width: ColumnWidth.small,
                      actions: [
                        DataTableAction(
                          icon: Icons.delete_outline,
                          label: t.delete,
                          color: Colors.red,
                          onPressed: (ticketData) {
                            final ticketId = ticketData['id'] as int;
                            _deleteTicket(ticketId);
                          },
                        ),
                      ],
                    ),
                  TextColumn(
                    'title',
                    'عنوان',
                    sortable: true,
                    searchable: true,
                    width: ColumnWidth.large,
                  ),
                  // ... بقیه ستون‌ها
                ],
                searchFields: ['title', 'description', 'user.first_name', 'user.last_name', 'user.email'],
                // ... بقیه تنظیمات
              ),
              fromJson: (json) => json,
              calendarController: widget.calendarController,
            ),
          ),
        ],
      ),
    ),
  );
}
```

---

### 6. Frontend - Localization (ترجمه‌ها)

**فایل:** `hesabixUI/hesabix_ui/lib/l10n/app_localizations_fa.dart`

کلیدهای ترجمه جدید که باید اضافه شوند:

```dart
// در کلاس AppLocalizations

String get confirmDelete => 'تأیید حذف';
String get deleteTicketConfirmMessage => 'آیا از حذف این تیکت اطمینان دارید؟ این عملیات قابل برگشت نیست.';
String get ticketDeletedSuccessfully => 'تیکت با موفقیت حذف شد';
String errorDeletingTicket(String error) => 'خطا در حذف تیکت: $error';

String get confirmBulkDelete => 'تأیید حذف گروهی';
String deleteBulkTicketsConfirmMessage(int count) => 'آیا از حذف $count تیکت انتخاب شده اطمینان دارید؟ این عملیات قابل برگشت نیست.';
String get noTicketsSelected => 'هیچ تیکتی انتخاب نشده است';
String deleteSelected(int count) => 'حذف $count مورد انتخابی';
String bulkDeleteResult(int success, int failed) => 
  failed > 0 
    ? 'حذف انجام شد: $success موفق، $failed ناموفق'
    : '$success تیکت با موفقیت حذف شد';
String errorDeletingTickets(String error) => 'خطا در حذف تیکت‌ها: $error';

String get actions => 'عملیات';
String get delete => 'حذف';
String get cancel => 'لغو';
```

---

## 🔒 نکات امنیتی

### 1. بررسی دسترسی در Backend
- استفاده از دکوراتور `@require_app_permission("superadmin")` تضمین می‌کند که فقط superadmin بتواند endpoint را صدا بزند
- حتی اگر کاربر از Postman یا ابزار دیگری استفاده کند، بدون permission مناسب نمی‌تواند تیکت را حذف کند

### 2. عدم نمایش UI برای کاربران غیرمجاز
- با چک کردن `_isSuperAdmin` در frontend، دکمه حذف فقط برای superadmin نمایش داده می‌شود
- این امر از سردرگمی کاربران جلوگیری می‌کند

### 3. تأیید قبل از حذف
- قبل از حذف، از کاربر تأیید گرفته می‌شود تا از حذف تصادفی جلوگیری شود
- پیام تأیید شامل هشدار "عملیات قابل برگشت نیست" است

### 4. Hard Delete vs Soft Delete
- در این پیاده‌سازی، حذف به صورت Hard Delete است (تیکت کاملاً از دیتابیس حذف می‌شود)
- اگر نیاز به Soft Delete دارید (نگهداری تاریخچه)، می‌توانید فیلد `deleted_at` به model اضافه کنید

---

## 🧪 تست سناریو

### تست Backend (Postman/cURL)

#### 1. تست حذف تیکت با SuperAdmin

```bash
# درخواست با API Key مدیر سیستم
curl -X DELETE \
  'http://localhost:8000/api/v1/support/operator/tickets/123' \
  -H 'Authorization: ApiKey YOUR_SUPERADMIN_API_KEY' \
  -H 'Content-Type: application/json'

# پاسخ موفق:
{
  "data": {
    "message": "تیکت با موفقیت حذف شد",
    "ticket_id": 123
  },
  "success": true
}
```

#### 2. تست حذف تیکت با اپراتور عادی (باید خطا بدهد)

```bash
# درخواست با API Key اپراتور عادی
curl -X DELETE \
  'http://localhost:8000/api/v1/support/operator/tickets/123' \
  -H 'Authorization: ApiKey OPERATOR_API_KEY' \
  -H 'Content-Type: application/json'

# پاسخ خطا:
{
  "detail": "فقط مدیر سیستم مجاز به انجام این عملیات است",
  "success": false
}
```

#### 3. تست حذف تیکت غیرموجود

```bash
curl -X DELETE \
  'http://localhost:8000/api/v1/support/operator/tickets/99999' \
  -H 'Authorization: ApiKey YOUR_SUPERADMIN_API_KEY' \
  -H 'Content-Type: application/json'

# پاسخ خطا:
{
  "detail": "تیکت یافت نشد یا قبلاً حذف شده است",
  "success": false
}
```

---

### تست Frontend

#### سناریوی تست 1: مدیر سیستم
1. با حساب superadmin وارد شوید
2. به صفحه "پنل اپراتور" بروید
3. **انتظار:** دکمه حذف و آیکون حذف در هر ردیف نمایش داده شود
4. یک تیکت را انتخاب کنید
5. روی آیکون حذف کلیک کنید
6. **انتظار:** دیالوگ تأیید نمایش داده شود
7. روی "حذف" کلیک کنید
8. **انتظار:** تیکت حذف شود و پیام موفقیت نمایش داده شود
9. **انتظار:** لیست تیکت‌ها refresh شود

#### سناریوی تست 2: اپراتور عادی
1. با حساب اپراتور عادی وارد شوید
2. به صفحه "پنل اپراتور" بروید
3. **انتظار:** دکمه حذف و آیکون حذف نمایش داده نشود
4. **انتظار:** فقط عملیات مجاز (مشاهده، ویرایش وضعیت، پاسخ) نمایش داده شود

#### سناریوی تست 3: حذف گروهی
1. با حساب superadmin وارد شوید
2. چند تیکت را انتخاب کنید
3. **انتظار:** دکمه "حذف X مورد انتخابی" نمایش داده شود
4. روی دکمه کلیک کنید
5. **انتظار:** دیالوگ تأیید با تعداد تیکت‌های انتخابی نمایش داده شود
6. روی "حذف" کلیک کنید
7. **انتظار:** loading نمایش داده شود
8. **انتظار:** تمام تیکت‌های انتخابی حذف شوند
9. **انتظار:** پیام موفقیت با آمار (تعداد موفق/ناموفق) نمایش داده شود

---

## 📊 Database Schema

تغییری در schema نیاز نیست، اما CASCADE relationship را بررسی کنید:

**فایل:** `hesabixAPI/adapters/db/models/support/message.py`

```python
class Message(Base):
    """پیام‌های تیکت"""
    __tablename__ = "support_messages"
    
    # ...
    
    # Foreign Key با CASCADE
    ticket_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("support_tickets.id", ondelete="CASCADE"),  # ✅ این باید CASCADE باشد
        nullable=False, 
        index=True
    )
```

اگر `ondelete="CASCADE"` تنظیم نشده، باید آن را اضافه کنید و migration بزنید.

---

## 🚀 Migration (در صورت نیاز)

اگر `ondelete="CASCADE"` در model موجود نیست:

```bash
# ایجاد migration جدید
cd hesabixAPI
alembic revision --autogenerate -m "Add CASCADE delete for ticket messages"

# اعمال migration
alembic upgrade head
```

---

## 📝 Checklist پیاده‌سازی

### Backend
- [ ] اضافه کردن متد `delete_ticket` به `TicketRepository`
- [ ] اضافه کردن endpoint `DELETE /tickets/{ticket_id}` در `operator.py`
- [ ] تست endpoint با superadmin API key
- [ ] تست endpoint با operator API key (باید خطا بدهد)
- [ ] تست حذف تیکت غیرموجود
- [ ] بررسی CASCADE delete در database schema
- [ ] اجرای migration (در صورت نیاز)

### Frontend
- [ ] اضافه کردن متد `deleteTicket` به `SupportService`
- [ ] اضافه کردن متد `deleteTickets` (bulk delete) به `SupportService`
- [ ] اضافه کردن چک `_isSuperAdmin` در `OperatorTicketsPage`
- [ ] اضافه کردن دکمه حذف گروهی (conditional rendering)
- [ ] اضافه کردن ستون Actions با آیکون حذف
- [ ] پیاده‌سازی متد `_deleteTicket` با دیالوگ تأیید
- [ ] پیاده‌سازی متد `_deleteSelectedTickets` با دیالوگ تأیید
- [ ] اضافه کردن کلیدهای ترجمه به `app_localizations_fa.dart`
- [ ] تست UI با حساب superadmin
- [ ] تست UI با حساب operator
- [ ] تست حذف تک تیکت
- [ ] تست حذف گروهی

### Documentation
- [ ] به‌روزرسانی API documentation
- [ ] به‌روزرسانی User Guide (در صورت نیاز)

---

## 🎨 UI/UX Mockup

### نمایش برای SuperAdmin

```
┌─────────────────────────────────────────────────────────────┐
│  پنل اپراتور                    [حذف 3 مورد انتخابی]       │
├─────────────────────────────────────────────────────────────┤
│  [✓] [🗑️] | عنوان تیکت 1 | کاربر 1 | باز | عادی | ...     │
│  [✓] [🗑️] | عنوان تیکت 2 | کاربر 2 | بسته | فوری | ...    │
│  [✓] [🗑️] | عنوان تیکت 3 | کاربر 3 | باز | عادی | ...     │
│  [ ] [🗑️] | عنوان تیکت 4 | کاربر 4 | باز | کم | ...        │
└─────────────────────────────────────────────────────────────┘
```

### نمایش برای Operator (بدون دکمه حذف)

```
┌─────────────────────────────────────────────────────────────┐
│  پنل اپراتور                                                │
├─────────────────────────────────────────────────────────────┤
│  [✓] | عنوان تیکت 1 | کاربر 1 | باز | عادی | ...           │
│  [✓] | عنوان تیکت 2 | کاربر 2 | بسته | فوری | ...          │
│  [✓] | عنوان تیکت 3 | کاربر 3 | باز | عادی | ...           │
│  [ ] | عنوان تیکت 4 | کاربر 4 | باز | کم | ...             │
└─────────────────────────────────────────────────────────────┘
```

### دیالوگ تأیید حذف

```
┌──────────────────────────────────┐
│  تأیید حذف                       │
├──────────────────────────────────┤
│  آیا از حذف این تیکت اطمینان    │
│  دارید؟ این عملیات قابل برگشت   │
│  نیست.                           │
│                                  │
│         [لغو]    [حذف 🗑️]       │
└──────────────────────────────────┘
```

---

## 🔄 جریان کامل (Flow Diagram)

```
کاربر SuperAdmin
    ↓
ورود به صفحه لیست تیکت‌های اپراتور
    ↓
چک permission → is_superadmin == true
    ↓
نمایش دکمه حذف در UI
    ↓
کلیک روی آیکون حذف یک تیکت
    ↓
نمایش دیالوگ تأیید
    ↓
کاربر تأیید می‌کند
    ↓
Frontend → API Call: DELETE /api/v1/support/operator/tickets/{id}
    ↓
Backend → بررسی permission با @require_app_permission("superadmin")
    ↓
Backend → حذف تیکت از database (CASCADE delete پیام‌ها)
    ↓
Backend → پاسخ موفقیت
    ↓
Frontend → نمایش پیام موفقیت
    ↓
Frontend → Refresh لیست تیکت‌ها
    ↓
پایان
```

---

## 💡 پیشنهادات بهبود (اختیاری)

### 1. Soft Delete به جای Hard Delete
اگر می‌خواهید تاریخچه را نگه دارید:

```python
# در model Ticket
deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
deleted_by: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id"), nullable=True)

# در repository
def soft_delete_ticket(self, ticket_id: int, user_id: int) -> bool:
    ticket = self.get_by_id(ticket_id)
    if not ticket:
        return False
    
    ticket.deleted_at = datetime.utcnow()
    ticket.deleted_by = user_id
    self.db.commit()
    return True
```

### 2. Activity Log
ثبت لاگ حذف تیکت برای audit:

```python
# بعد از حذف تیکت
from app.services.activity_log_service import log_activity

log_activity(
    db=db,
    user_id=current_user.get_user_id(),
    entity_type="ticket",
    entity_id=ticket_id,
    action="delete",
    details={"ticket_title": ticket.title}
)
```

### 3. Undo قابلیت بازگردانی
با استفاده از Soft Delete + Undo API:

```python
@router.post("/tickets/{ticket_id}/restore", response_model=SuccessResponse)
@require_app_permission("superadmin")
async def restore_ticket(ticket_id: int, ...):
    """بازگردانی تیکت حذف شده"""
    # ...
```

### 4. Bulk Delete API Endpoint
بهینه‌سازی حذف گروهی با یک API call:

```python
@router.delete("/tickets/bulk", response_model=SuccessResponse)
@require_app_permission("superadmin")
async def bulk_delete_tickets(
    ticket_ids: List[int],
    ...
):
    """حذف گروهی تیکت‌ها"""
    # ...
```

---

## 📞 پشتیبانی و سوالات

اگر در پیاده‌سازی با مشکل مواجه شدید:
1. لاگ‌های backend را بررسی کنید
2. Network tab مرورگر را برای خطاهای API چک کنید
3. مطمئن شوید permission ها صحیح تنظیم شده‌اند
4. مطمئن شوید CASCADE delete در database تنظیم شده است

---

## 📚 منابع مرتبط

- [سند سیستم دسترسی دو سطحی](PERMISSIONS_SYSTEM.md)
- [سند مدیریت اپراتورها](SUPPORT_OPERATORS_MANAGEMENT_SCENARIO.md)
- [FastAPI Security Best Practices](https://fastapi.tiangolo.com/tutorial/security/)

---

**تاریخ ایجاد:** 2025-12-05  
**نسخه:** 1.0  
**نویسنده:** AI Assistant (Cursor)



