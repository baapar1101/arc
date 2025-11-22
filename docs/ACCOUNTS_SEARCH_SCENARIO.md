# سناریو افزودن قابلیت جستجو به جدول حساب‌ها

## وضعیت فعلی

### بکند (Backend)
- ✅ **Endpoint جستجو موجود است**: `/api/v1/accounts/business/{business_id}` (POST)
- ✅ **پارامترهای جستجو**: 
  - `search`: عبارت جستجو (جستجو در `code` و `name`)
  - `take`: تعداد رکوردها
  - `skip`: تعداد رکوردهای رد شده
  - `sort_by`: فیلد مرتب‌سازی (`code` یا `name`)
  - `sort_desc`: جهت مرتب‌سازی
- ✅ **نوع پاسخ**: لیست مسطح (بدون ساختار درختی)

### فرانت (Frontend)
- ❌ **صفحه فعلی**: `accounts_page.dart` فقط از درخت حساب‌ها استفاده می‌کند
- ❌ **جستجو**: قابلیت جستجو وجود ندارد
- ✅ **سرویس**: `AccountService.searchAccounts()` موجود است اما استفاده نمی‌شود

## سناریو پیشنهادی

### گزینه 1: افزودن جستجو به صفحه درختی فعلی (پیشنهادی)

**مزایا:**
- حفظ ساختار درختی برای نمایش
- جستجو سریع و ساده
- تغییرات کم در UI

**معایب:**
- نتایج جستجو در ساختار درختی نمایش داده می‌شود (ممکن است گیج‌کننده باشد)

**پیاده‌سازی:**
1. افزودن یک `TextField` برای جستجو در بالای جدول
2. هنگام تایپ، فراخوانی endpoint جستجو
3. نمایش نتایج جستجو در همان ساختار درختی (یا لیست مسطح)
4. با پاک کردن جستجو، بازگشت به نمایش درختی کامل

### گزینه 2: تبدیل به DataTableWidget (پیشنهادی برای آینده)

**مزایا:**
- استفاده از کامپوننت استاندارد با قابلیت‌های کامل
- جستجو، فیلتر، مرتب‌سازی و صفحه‌بندی یکپارچه
- سازگاری با سایر صفحات

**معایب:**
- از دست رفتن نمایش درختی
- نیاز به تغییرات بیشتر در UI

**پیاده‌سازی:**
1. تبدیل `accounts_page.dart` به استفاده از `DataTableWidget`
2. تنظیم `endpoint` به `/api/v1/accounts/business/{business_id}`
3. تنظیم `searchFields` به `['code', 'name']`
4. تعریف ستون‌ها: `code`, `name`, `account_type`
5. نیاز به تغییر endpoint بکند برای پشتیبانی از `QueryInfo` (یا استفاده از endpoint موجود)

### گزینه 3: حالت ترکیبی (پیشنهادی برای تجربه کاربری بهتر)

**مزایا:**
- حفظ نمایش درختی
- جستجو سریع و کارآمد
- امکان نمایش نتایج جستجو به صورت لیست مسطح

**معایب:**
- پیچیدگی بیشتر در UI

**پیاده‌سازی:**
1. افزودن یک `SearchBar` در بالای صفحه
2. دو حالت نمایش:
   - **حالت عادی**: نمایش درختی کامل (endpoint `/tree`)
   - **حالت جستجو**: نمایش لیست مسطح نتایج (endpoint `/business/{business_id}`)
3. نمایش نتایج جستجو در یک `ListView` یا `DataTable` ساده
4. دکمه "پاک کردن جستجو" برای بازگشت به حالت درختی

## توصیه: گزینه 3 (حالت ترکیبی)

### جزئیات پیاده‌سازی گزینه 3

#### 1. تغییرات در فرانت (Frontend)

**فایل: `accounts_page.dart`**

```dart
// افزودن state برای جستجو
String? _searchQuery;
bool _isSearchMode = false;
List<AccountNode> _searchResults = [];

// افزودن SearchBar در AppBar یا بالای body
TextField(
  controller: _searchController,
  decoration: InputDecoration(
    hintText: 'جستجو در کد و نام حساب...',
    prefixIcon: Icon(Icons.search),
    suffixIcon: _searchQuery != null && _searchQuery!.isNotEmpty
        ? IconButton(
            icon: Icon(Icons.clear),
            onPressed: () {
              setState(() {
                _searchQuery = null;
                _isSearchMode = false;
                _searchResults = [];
              });
              _fetch(); // بازگشت به درخت کامل
            },
          )
        : null,
  ),
  onChanged: (value) {
    _debounceSearch(value);
  },
)

// تابع جستجو با debounce
Timer? _searchDebounce;
void _debounceSearch(String query) {
  _searchDebounce?.cancel();
  _searchDebounce = Timer(Duration(milliseconds: 500), () {
    if (query.trim().isEmpty) {
      setState(() {
        _searchQuery = null;
        _isSearchMode = false;
        _searchResults = [];
      });
      _fetch();
    } else {
      _performSearch(query.trim());
    }
  });
}

// تابع جستجو
Future<void> _performSearch(String query) async {
  setState(() {
    _loading = true;
    _searchQuery = query;
    _isSearchMode = true;
  });
  
  try {
    final service = AccountService();
    final result = await service.searchAccounts(
      businessId: widget.businessId,
      searchQuery: query,
      limit: 100,
    );
    
    final items = (result['items'] as List?) ?? [];
    final parsed = items
        .map((n) => AccountNode.fromJson(Map<String, dynamic>.from(n as Map)))
        .toList();
    
    setState(() {
      _searchResults = parsed;
      _loading = false;
    });
  } catch (e) {
    setState(() {
      _error = e.toString();
      _loading = false;
    });
  }
}

// تغییر build method برای نمایش نتایج جستجو
@override
Widget build(BuildContext context) {
  final t = AppLocalizations.of(context);
  if (_loading) return const Center(child: CircularProgressIndicator());
  if (_error != null) return Center(child: Text(_error!));
  
  // اگر در حالت جستجو هستیم، نتایج جستجو را نمایش بده
  final itemsToShow = _isSearchMode ? _searchResults : _buildVisibleNodes();
  
  return Scaffold(
    appBar: AppBar(
      title: Text(t.chartOfAccounts),
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(60),
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: TextField(
            // ... کد SearchBar
          ),
        ),
      ),
    ),
    body: _isSearchMode
        ? _buildSearchResultsList(itemsToShow)
        : _buildTreeView(itemsToShow),
  );
}
```

#### 2. تغییرات در بکند (Backend) - اختیاری

**اگر بخواهیم از QueryInfo استفاده کنیم:**

```python
# تغییر endpoint برای پشتیبانی از QueryInfo
@router.post("/business/{business_id}",
    summary="جستجو و فیلتر حساب‌ها",
    description="جستجو در حساب‌ها با قابلیت فیلتر، مرتب‌سازی و صفحه‌بندی",
)
@require_business_access("business_id")
def search_accounts(
    request: Request,
    business_id: int,
    query_info: QueryInfo,  # استفاده از QueryInfo به جای SearchAccountsRequest
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """جستجوی حساب‌ها با QueryInfo"""
    query = db.query(Account).filter(
        (Account.business_id == None) | (Account.business_id == business_id)
    )
    
    # اعمال جستجو
    if query_info.search:
        search_term = f"%{query_info.search}%"
        if query_info.search_fields:
            # جستجو در فیلدهای مشخص شده
            conditions = []
            for field in query_info.search_fields:
                if field == 'code':
                    conditions.append(Account.code.ilike(search_term))
                elif field == 'name':
                    conditions.append(Account.name.ilike(search_term))
            if conditions:
                from sqlalchemy import or_
                query = query.filter(or_(*conditions))
        else:
            # جستجو در code و name به صورت پیش‌فرض
            query = query.filter(
                (Account.code.ilike(search_term)) | (Account.name.ilike(search_term))
            )
    
    # ... ادامه کد
```

**یا می‌توانیم endpoint فعلی را نگه داریم** و فقط از `SearchAccountsRequest` استفاده کنیم.

#### 3. بهبود سرویس فرانت

**فایل: `account_service.dart`**

```dart
/// جستجوی حساب‌ها
Future<Map<String, dynamic>> searchAccounts({
  required int businessId,
  String? searchQuery,
  int limit = 50,
  int skip = 0,
  String? sortBy,
  bool sortDesc = false,
}) async {
  try {
    final requestData = <String, dynamic>{
      'take': limit,
      'skip': skip,
      'sort_by': sortBy ?? 'code',
      'sort_desc': sortDesc,
    };

    if (searchQuery != null && searchQuery.isNotEmpty) {
      requestData['search'] = searchQuery;
    }

    final res = await _client.post<Map<String, dynamic>>(
      '/api/v1/accounts/business/$businessId',
      data: requestData,
    );
    
    final responseData = res.data?['data'] as Map<String, dynamic>?;
    return responseData ?? <String, dynamic>{
      'items': <dynamic>[],
      'total': 0,
      'skip': skip,
      'take': limit,
    };
  } catch (e) {
    rethrow;
  }
}
```

## مراحل پیاده‌سازی

### مرحله 1: بهبود سرویس (Frontend)
- [ ] تکمیل متد `searchAccounts` در `AccountService`
- [ ] اضافه کردن پارامترهای `skip`, `sortBy`, `sortDesc`

### مرحله 2: افزودن UI جستجو (Frontend)
- [ ] افزودن `TextField` برای جستجو در `AppBar` یا بالای `body`
- [ ] پیاده‌سازی debounce برای جستجو
- [ ] افزودن state برای حالت جستجو

### مرحله 3: نمایش نتایج جستجو (Frontend)
- [ ] ایجاد متد `_buildSearchResultsList` برای نمایش لیست مسطح
- [ ] تغییر `build` method برای تشخیص حالت جستجو
- [ ] افزودن دکمه پاک کردن جستجو

### مرحله 4: تست و بهبود (اختیاری)
- [ ] تست جستجو با عبارات مختلف
- [ ] بهبود UX (loading state، empty state)
- [ ] اضافه کردن highlight نتایج جستجو

### مرحله 5: بهبود بکند (اختیاری)
- [ ] تبدیل endpoint به استفاده از `QueryInfo` برای سازگاری بیشتر
- [ ] اضافه کردن فیلتر بر اساس `account_type`
- [ ] بهبود عملکرد جستجو با index

## نکات مهم

1. **Debounce**: برای جلوگیری از درخواست‌های زیاد، از debounce استفاده شود (500ms پیشنهادی)
2. **Loading State**: هنگام جستجو، نمایش loading indicator
3. **Empty State**: اگر نتیجه‌ای یافت نشد، پیام مناسب نمایش داده شود
4. **Backward Compatibility**: تغییرات نباید عملکرد فعلی را خراب کند
5. **Performance**: برای دیتابیس‌های بزرگ، استفاده از index روی `code` و `name` توصیه می‌شود

## سوالات برای بررسی

1. آیا می‌خواهید نتایج جستجو در ساختار درختی نمایش داده شود یا لیست مسطح؟
2. آیا نیاز به فیلتر بر اساس `account_type` دارید؟
3. آیا می‌خواهید endpoint بکند را به `QueryInfo` تبدیل کنیم یا همان `SearchAccountsRequest` را نگه داریم؟
4. آیا نیاز به highlight کردن نتایج جستجو دارید؟

