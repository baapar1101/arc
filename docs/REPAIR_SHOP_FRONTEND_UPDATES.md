# ✅ به‌روزرسانی‌های Frontend برای افزونه تعمیرگاه

## تغییرات اعمال شده

### 1️⃣ منوی کناری (Sidebar Menu)

**فایل**: `/hesabixUI/hesabix_ui/lib/pages/business/business_shell.dart`

**تغییرات**:
```dart
_MenuItem(
  label: 'تعمیرگاه',
  icon: Icons.build_circle_outlined,
  selectedIcon: Icons.build_circle,
  path: '/business/${widget.businessId}/repair-shop',
  type: _MenuItemType.simple,
  hasAddButton: true,
),
```

**موقعیت**: بعد از بخش "گارانتی" و قبل از "استعلامات"

**آیکون**: 🔧 `Icons.build_circle_outlined` / `Icons.build_circle`

---

### 2️⃣ صفحه تعمیرگاه (Page)

**فایل**: `/hesabixUI/hesabix_ui/lib/pages/business/repair_shop_page.dart`

**قابلیت‌ها**:
- ✅ بررسی وضعیت افزونه (فعال/غیرفعال)
- ✅ نمایش پیام فعال‌سازی (اگر افزونه غیرفعال باشد)
- ✅ لینک به بازار افزونه‌ها
- ✅ دکمه شروع Trial (14 روز رایگان)
- ✅ نمایش لیست قابلیت‌های افزونه
- ✅ صفحه placeholder برای زمان فعال بودن

**حالت‌های مختلف**:
1. **در حال بارگذاری**: نمایش `CircularProgressIndicator`
2. **خطا**: نمایش پیام خطا + دکمه تلاش مجدد
3. **افزونه غیرفعال**: نمایش پیام فعال‌سازی + دکمه‌های اقدام
4. **افزونه فعال**: نمایش محتوای اصلی (فعلاً placeholder)

---

### 3️⃣ مسیریابی (Routing)

**فایل**: `/hesabixUI/hesabix_ui/lib/main.dart`

**Route اضافه شده**:
```dart
GoRoute(
  path: '/business/:business_id/repair-shop',
  name: 'business_repair_shop',
  pageBuilder: (context, state) {
    final businessId = int.parse(state.pathParameters['business_id']!);
    return NoTransitionPage(
      child: RepairShopPage(
        businessId: businessId,
      ),
    );
  },
),
```

**URL دسترسی**:
```
/business/1/repair-shop
```

---

## نحوه استفاده

### دسترسی از منوی کناری

1. وارد پنل کسب‌وکار شوید
2. در منوی کناری، بخش **"تعمیرگاه"** را مشاهده خواهید کرد
3. با کلیک روی آن، وارد صفحه تعمیرگاه می‌شوید

### اگر افزونه فعال نباشد

صفحه‌ای نمایش داده می‌شود که شامل:
- 📋 توضیحات افزونه
- 📋 لیست قابلیت‌ها
- 💰 قیمت‌گذاری
- 🎁 دکمه "شروع 14 روز رایگان"
- 🛒 دکمه "مشاهده در بازار افزونه‌ها"

### اگر افزونه فعال باشد

صفحه اصلی نمایش داده می‌شود که شامل:
- 📊 لیست سفارشات تعمیر (فعلاً placeholder)
- ➕ دکمه "سفارش جدید"
- ⚙️ دکمه تنظیمات

---

## کارهای باقی‌مانده (TODO در کد)

### در `repair_shop_page.dart`:

```dart
// TODO: فراخوانی API برای بررسی وضعیت افزونه
// final response = await RepairShopService().getPluginStatus(businessId: widget.businessId);

// TODO: API call برای شروع trial
// await MarketplaceService().startTrial(businessId: widget.businessId, pluginId: 3);
```

### صفحات آینده

برای پیاده‌سازی کامل، صفحات زیر نیاز است:

1. **`repair_shop_list_page.dart`** - لیست سفارشات تعمیر
2. **`repair_order_form_page.dart`** - فرم ثبت سفارش جدید
3. **`repair_order_detail_page.dart`** - جزئیات و کارتابل
4. **`repair_technicians_page.dart`** - مدیریت تعمیرکاران
5. **`repair_shop_settings_page.dart`** - تنظیمات تعمیرگاه
6. **`repair_kanban_board_page.dart`** - کارتابل تعمیرات

---

## تست

برای تست:

1. **اجرای برنامه**:
   ```bash
   cd /var/www/ark/hesabixUI/hesabix_ui
   flutter run -d chrome
   ```

2. **ورود به پنل کسب‌وکار**

3. **کلیک روی "تعمیرگاه" در منوی کناری**

4. **مشاهده صفحه فعال‌سازی**

---

## نتیجه

✅ **منوی کناری**: بخش تعمیرگاه اضافه شد  
✅ **Route**: مسیر `/business/:business_id/repair-shop` تعریف شد  
✅ **صفحه پایه**: صفحه با بررسی وضعیت افزونه ایجاد شد  
✅ **UI/UX**: رابط کاربری برای فعال‌سازی طراحی شد  

**وضعیت**: آماده برای تست ✅




