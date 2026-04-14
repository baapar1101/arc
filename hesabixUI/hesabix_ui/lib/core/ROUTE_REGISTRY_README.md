# Route Registry - راهکار خودکار برای Preload صفحات

## مقدمه

Route Registry یک سیستم خودکار برای preload کردن صفحات است که باعث می‌شود تمام صفحات در bundle اصلی قرار گیرند و تاخیر بین navigation ها حذف شود.

## مزایا

- ✅ **خودکار**: صفحات جدید به صورت خودکار register می‌شوند
- ✅ **بدون تاخیر**: تمام صفحات در bundle اصلی قرار می‌گیرند
- ✅ **ساده**: فقط کافی است `registerRoutePage` را در builder function فراخوانی کنید
- ✅ **انعطاف‌پذیر**: با هر نوع route سازگار است

## نحوه استفاده

### روش 1: استفاده مستقیم از `registerRoutePage`

برای صفحات جدید، کافی است `registerRoutePage` را در builder function فراخوانی کنید:

```dart
GoRoute(
  path: '/my-page',
  name: 'my_page',
  builder: (context, state) {
    // ثبت صفحه برای preload خودکار
    registerRoutePage(() => MyPage(
      param1: 'dummy',
      param2: 0,
    ));
    
    // ایجاد و بازگشت صفحه واقعی
    return MyPage(
      param1: state.pathParameters['param1'] ?? '',
      param2: int.parse(state.pathParameters['param2'] ?? '0'),
    );
  },
)
```

### روش 2: استفاده از Helper Functions

می‌توانید از helper functions استفاده کنید:

```dart
GoRoute(
  path: '/my-page',
  name: 'my_page',
  builder: wrapBuilder((context, state) => MyPage(
    param1: state.pathParameters['param1'] ?? '',
  )),
)
```

### روش 3: استفاده در pageBuilder

برای routes با `pageBuilder`:

```dart
GoRoute(
  path: '/my-page',
  name: 'my_page',
  pageBuilder: (context, state) {
    // ثبت صفحه برای preload
    registerRoutePage(() => NoTransitionPage(
      child: MyPage(
        businessId: 0,
      ),
    ));
    
    final businessId = int.parse(state.pathParameters['business_id']!);
    return NoTransitionPage(
      child: MyPage(
        businessId: businessId,
      ),
    );
  },
)
```

## مثال‌های کامل

### مثال 1: صفحه ساده بدون پارامتر

```dart
GoRoute(
  path: '/dashboard',
  name: 'dashboard',
  builder: (context, state) {
    registerRoutePage(() => const DashboardPage());
    return const DashboardPage();
  },
)
```

### مثال 2: صفحه با path parameters

```dart
GoRoute(
  path: '/business/:business_id/dashboard',
  name: 'business_dashboard',
  pageBuilder: (context, state) {
    // ثبت برای preload (با dummy value)
    registerRoutePage(() => NoTransitionPage(
      child: BusinessDashboardPage(
        businessId: 0,
        authStore: _authStore!,
      ),
    ));
    
    // صفحه واقعی
    final businessId = int.parse(state.pathParameters['business_id']!);
    return NoTransitionPage(
      child: BusinessDashboardPage(
        businessId: businessId,
        authStore: _authStore!,
      ),
    );
  },
)
```

### مثال 3: صفحه با query parameters

```dart
GoRoute(
  path: '/reports/kardex',
  name: 'reports_kardex',
  pageBuilder: (context, state) {
    // ثبت برای preload
    registerRoutePage(() => NoTransitionPage(
      child: KardexPage(
        businessId: 0,
        calendarController: _calendarController!,
        initialPersonIds: [],
      ),
    ));
    
    // صفحه واقعی
    final businessId = int.parse(state.pathParameters['business_id']!);
    final personIds = _parsePersonIds(state.uri.queryParameters);
    return NoTransitionPage(
      child: KardexPage(
        businessId: businessId,
        calendarController: _calendarController!,
        initialPersonIds: personIds,
      ),
    );
  },
)
```

## نکات مهم

1. **Dummy Values**: در `registerRoutePage`، از dummy values استفاده کنید که باعث خطا نشوند (مثلاً `0` برای `businessId`)

2. **Timing**: `registerRoutePage` باید **قبل از** return شدن صفحه فراخوانی شود

3. **Error Handling**: خطاهای preload نباید برنامه را متوقف کنند (به صورت خودکار handle می‌شوند)

4. **Performance**: preload فقط یک بار در هنگام لود اولیه انجام می‌شود

## افزودن صفحه جدید

برای افزودن صفحه جدید:

1. Route را در `main.dart` تعریف کنید
2. `registerRoutePage` را در builder function فراخوانی کنید
3. صفحه به صورت خودکار preload می‌شود!

**مثال**:
```dart
// صفحه جدید: MyNewPage
GoRoute(
  path: '/my-new-page',
  name: 'my_new_page',
  builder: (context, state) {
    // فقط این خط را اضافه کنید!
    registerRoutePage(() => MyNewPage(param: 'dummy'));
    return MyNewPage(param: state.queryParameters['param'] ?? '');
  },
)
```

## Troubleshooting

### صفحه preload نمی‌شود

- مطمئن شوید که `registerRoutePage` را فراخوانی کرده‌اید
- مطمئن شوید که `registerRoutePage` **قبل از** return شدن صفحه فراخوانی می‌شود

### خطا در preload

- از dummy values مناسب استفاده کنید
- مطمئن شوید که تمام dependencies موجود هستند

### Bundle خیلی بزرگ شده

- این طبیعی است! تمام صفحات در bundle اصلی قرار می‌گیرند
- اما navigation بسیار سریع‌تر می‌شود

## پشتیبانی

برای سوالات یا مشکلات، به تیم توسعه مراجعه کنید.

