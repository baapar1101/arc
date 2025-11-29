# پیشنهادات بهبود UI و UX بخش Workflow Editor

این سند شامل پیشنهادات جامع برای بهبود بخش افزودن و ویرایش workflow است.

---

## 🔴 مشکلات فعلی

### 1. مشکل هماهنگی نوک سیم با موس
- **مشکل**: هنگام کشیدن سیم، نوک سیم با موقعیت موس هماهنگ نیست
- **علت**: تبدیل مختصات بدون در نظر گیری transformation matrix (zoom/pan)
- **راه‌حل**: استفاده از Listener و تبدیل صحیح مختصات

### 2. عدم Responsive بودن
- UI برای موبایل و تبلت بهینه نشده
- نودها و toolbar در صفحه کوچک مناسب نیستند
- Drawer در موبایل بهتر کار نمی‌کند

### 3. مشکلات UX
- هیچ راهنمایی برای کاربران جدید وجود ندارد
- Snap to grid وجود ندارد
- Connection hints نمایش داده نمی‌شود
- Keyboard shortcuts کامل نیست

---

## ✅ تغییرات انجام شده

### 1. تبدیل مختصات درست ✅
- اضافه کردن متد `_localToCanvasCoordinates` برای تبدیل مختصات با در نظر گیری transformation
- اضافه کردن متد `_globalToCanvasCoordinates` برای تبدیل موقعیت global به canvas coordinates
- غیرفعال کردن pan/scale هنگام اتصال برای جلوگیری از تداخل
- استفاده از `InteractiveViewer` با کنترل pan و scale

### 2. Responsive Design ✅
- ایجاد کلاس `WorkflowResponsive` برای مدیریت اندازه‌های responsive
- تنظیم اندازه نودها: Mobile (140x80), Tablet (160x90), Desktop (180x100)
- تنظیم اندازه drawer: Mobile (85% عرض صفحه), Tablet (350px), Desktop (300px)
- مخفی کردن minimap در موبایل
- تبدیل AppBar به icon-only در موبایل

## ✅ پیشنهادات بهبود بعدی

### 2. Responsive Design

#### برای موبایل:
```dart
// استفاده از MediaQuery برای تشخیص اندازه صفحه
final isMobile = MediaQuery.of(context).size.width < 600;
final isTablet = MediaQuery.of(context).size.width < 1024;

// تنظیمات responsive:
- نودها کوچک‌تر (140x80 به جای 180x100)
- Connection points بزرگ‌تر برای لمس آسان‌تر
- Toolbar به صورت bottom sheet
- Drawer به صورت full screen
- Mini-map کوچک‌تر یا مخفی
```

#### برای تبلت:
```dart
// تنظیمات میانه:
- نودها متوسط (160x90)
- Toolbar قابل تنظیم (قابل مخفی کردن)
- Drawer با عرض بیشتر
```

### 3. Snap to Grid

```dart
// تنظیمات:
- فعال/غیرفعال کردن snap to grid
- اندازه grid قابل تنظیم (10, 20, 50 پیکسل)
- Snap هنگام drag کردن نودها
- Snap هنگام قرار دادن نود جدید
```

### 4. Connection Hints

```dart
// نمایش راهنما هنگام drag:
- Highlight کردن connection points قابل اتصال
- نمایش مسیر پیشنهادی
- جلوگیری از اتصال نامعتبر (مثلاً trigger به trigger)
- نمایش tooltip برای هر connection point
```

### 5. Keyboard Shortcuts

```dart
// اضافه کردن:
- Ctrl/Cmd + A: انتخاب همه نودها
- Ctrl/Cmd + C: کپی
- Ctrl/Cmd + V: چسباندن
- Ctrl/Cmd + X: برش
- Space + Drag: Pan canvas
- Shift + Drag: انتخاب چندگانه
- Arrow Keys: حرکت نود انتخاب شده
- Delete/Backspace: حذف نود/اتصال انتخاب شده
```

### 6. Multi-Select & Grouping

```dart
// انتخاب چندگانه:
- Shift + Click: انتخاب چندگانه
- Drag selection box
- Ctrl/Cmd + Click: toggle selection
- Group کردن نودها برای جابجایی همزمان
```

### 7. Undo/Redo با Visual Feedback

```dart
// بهبود:
- نمایش toast با توضیح عمل undo/redo
- نمایش history list در UI
- محدود کردن history به 50 عمل
```

### 8. Search & Filter

```dart
// در Node Palette:
- جستجوی نودها
- فیلتر بر اساس نوع (trigger/action)
- دسته‌بندی نودها
- نودهای پرکاربرد
```

### 9. Workflow Templates

```dart
// قالب‌های آماده:
- Invoice workflow
- Inventory alert workflow
- Payment reminder workflow
- Custom templates
```

### 10. Visual Improvements

```dart
// بهبودهای بصری:
- Animation برای اضافه/حذف نود
- Hover effects روی نودها
- Drag preview
- Connection animation
- Loading states
```

### 11. Touch Support بهتر

```dart
// برای موبایل و تبلت:
- Pinch to zoom
- Two-finger pan
- Long press برای context menu
- Swipe gestures
```

### 12. Performance Optimizations

```dart
// بهینه‌سازی:
- Virtual scrolling برای workflowهای بزرگ
- Lazy loading نودها
- Debounce برای به‌روزرسانی موقعیت
- استفاده از RepaintBoundary بیشتر
```

---

## 📋 اولویت‌بندی پیاده‌سازی

### فوری (این هفته):
1. ✅ اصلاح تبدیل مختصات
2. ✅ اضافه کردن connection points
3. Responsive برای موبایل
4. Snap to grid

### کوتاه‌مدت (این ماه):
5. Connection hints
6. Keyboard shortcuts کامل
7. Multi-select
8. Search در palette

### میان‌مدت (ماه بعد):
9. Templates
10. Visual improvements
11. Touch support بهتر
12. Performance optimizations

---

## 🔧 جزئیات پیاده‌سازی

### Responsive Design

```dart
class ResponsiveWorkflowEditor extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    final isTablet = screenSize.width < 1024;
    
    final nodeSize = isMobile 
      ? Size(140, 80)
      : isTablet 
        ? Size(160, 90)
        : Size(180, 100);
    
    // ...
  }
}
```

### Snap to Grid

```dart
Offset snapToGrid(Offset position, double gridSize) {
  return Offset(
    (position.dx / gridSize).round() * gridSize,
    (position.dy / gridSize).round() * gridSize,
  );
}
```

### Connection Hints

```dart
// Highlight connection points
Widget buildConnectionHint(Offset position, bool isHighlighted) {
  return Positioned(
    left: position.dx - 12,
    top: position.dy - 12,
    child: AnimatedContainer(
      duration: Duration(milliseconds: 200),
      width: isHighlighted ? 24 : 16,
      height: isHighlighted ? 24 : 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isHighlighted ? Colors.green : Colors.blue,
      ),
    ),
  );
}
```

---

*این سند به صورت مداوم به‌روزرسانی خواهد شد.*

