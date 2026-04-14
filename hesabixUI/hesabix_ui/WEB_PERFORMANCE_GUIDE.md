# راهنمای بهینه‌سازی عملکرد وب برای Flutter Web

## مشکل

در Flutter Web، صفحات به صورت تدریجی لود می‌شوند که باعث ایجاد تأخیر در جابجایی بین صفحات می‌شود.

## راهکارهای پیاده‌سازی شده

### 1. بهینه‌سازی HTML (`web/index.html`)

- ✅ اضافه شدن `preload` برای منابع مهم
- ✅ اضافه شدن `preconnect` و `dns-prefetch` برای بهبود اتصال
- ✅ بهینه‌سازی configuration برای eager loading

### 2. Route Prefetching (`lib/utils/route_prefetcher.dart`)

یک utility class برای پیش‌بارگذاری صفحات مهم:
- پیش‌بارگذاری صفحات اصلی پس از load شدن اپلیکیشن
- پیش‌بارگذاری صفحات در پس‌زمینه بدون block کردن UI

### 3. Eager Loading در Main.dart

- تمام صفحات به صورت eager load می‌شوند (همه import شده‌اند)
- RoutePrefetcher برای prefetch کردن routes مهم

## دستورالعمل Build

برای بهینه‌سازی بیشتر عملکرد در production، از دستورات زیر استفاده کنید:

### Build برای Production با بهینه‌سازی کامل:

```bash
flutter build web --release --web-renderer canvaskit --base-href /
```

### توضیحات فلگ‌ها:

- `--release`: کامپایل با بهینه‌سازی کامل
- `--web-renderer canvaskit`: استفاده از CanvasKit renderer (عملکرد بهتر)
- `--base-href /`: تنظیم base href (در صورت نیاز تغییر دهید)

### Build با Tree Shaking (کوچک‌تر کردن bundle):

```bash
flutter build web --release --web-renderer canvaskit --dart-define=FLUTTER_WEB_USE_SKIA=false
```

### Build برای Development (برای تست):

```bash
flutter run -d chrome --web-renderer canvaskit
```

## نکات مهم

### 1. Code Splitting

Flutter Web به صورت پیش‌فرض تمام کد را در یک bundle اصلی (`main.dart.js`) کامپایل می‌کند. اگر از **deferred imports** استفاده نکنید، تمام صفحات در همان bundle اولیه خواهند بود که باعث می‌شود:

- ✅ تأخیر در جابجایی بین صفحات از بین برود
- ⚠️ حجم bundle اولیه بزرگ‌تر می‌شود

**توصیه:** برای وب، eager loading بهتر از lazy loading است چون:
- کاربران معمولاً چند صفحه را بازدید می‌کنند
- سرعت اینترنت امروزی معمولاً خوب است
- تأخیر کمتر = تجربه کاربری بهتر

### 2. Deferred Imports

اگر می‌خواهید از deferred imports استفاده کنید (برای کاهش حجم bundle اولیه):

```dart
// Import کردن با defer
import 'pages/business/products_page.dart' deferred as products_page;

// استفاده در route
GoRoute(
  path: '/business/:business_id/products',
  builder: (context, state) async {
    await products_page.loadLibrary();
    return products_page.ProductsPage(...);
  },
)
```

**اما توجه کنید:** این باعث می‌شود که هنگام جابجایی به صفحه، تأخیر ایجاد شود.

### 3. Service Worker (اختیاری)

برای cache کردن صفحات در مرورگر، می‌توانید از service worker استفاده کنید:

```bash
flutter build web --pwa-strategy offline-first
```

### 4. CDN و Caching

- از CDN برای serving فایل‌های static استفاده کنید
- تنظیمات cache مناسب برای فایل‌های Flutter Web:
  - `main.dart.js`: Cache for 1 year (با versioning)
  - `canvaskit/`: Cache for 1 year
  - `assets/`: Cache for 1 year

## بررسی عملکرد

### Chrome DevTools

1. باز کردن DevTools (F12)
2. رفتن به تب Network
3. بررسی زمان بارگذاری صفحات
4. بررسی اینکه آیا صفحات از cache لود می‌شوند یا خیر

### Performance Tab

1. باز کردن Performance tab در DevTools
2. Start recording
3. جابجایی بین صفحات
4. بررسی زمان navigation

## راهکارهای پیشنهادی برای بهبود بیشتر

### 1. Lazy Loading برای صفحات کم‌استفاده

صفحاتی که کمتر استفاده می‌شوند را می‌توانید lazy load کنید:

```dart
// فقط برای صفحات خاص که خیلی کم استفاده می‌شوند
import 'pages/admin/system_logs_page.dart' deferred as logs_page;
```

### 2. Prefetch Strategy

RoutePrefetcher به صورت خودکار صفحات مهم را prefetch می‌کند. اگر می‌خواهید صفحات خاصی را prefetch کنید:

```dart
// در جایی که router آماده است
RoutePrefetcher.setRouter(router);
RoutePrefetcher.prefetchRoute('business_products');
```

### 3. Image Optimization

- استفاده از WebP format
- Lazy loading برای تصاویر
- Responsive images

## خلاصه

✅ **تغییرات انجام شده:**
- بهینه‌سازی `index.html` برای preload
- اضافه شدن RoutePrefetcher
- اطمینان از eager loading تمام صفحات

📝 **مراحل بعدی:**
1. Build کردن با دستورات بالا
2. تست کردن در production
3. بررسی عملکرد با DevTools
4. تنظیم CDN و caching (اختیاری)

## سوالات متداول

**Q: چرا همه صفحات eager load می‌شوند؟**  
A: برای حذف تأخیر در جابجایی بین صفحات. حجم bundle بزرگ‌تر می‌شود اما تجربه کاربری بهتر است.

**Q: آیا می‌توانم برخی صفحات را lazy load کنم؟**  
A: بله، با استفاده از deferred imports. اما باید تعادل بین حجم bundle و تأخیر را در نظر بگیرید.

**Q: آیا prefetch باعث کند شدن اولیه می‌شود؟**  
A: خیر، prefetch در پس‌زمینه و بعد از load شدن اولیه انجام می‌شود.

