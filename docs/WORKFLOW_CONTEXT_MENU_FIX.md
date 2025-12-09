# رفع مشکل صفحه سفید در Context Menu نودهای Workflow

## 🐛 مشکل

زمانی که کاربر در صفحه ویرایش workflow روی یکی از گزینه‌های context menu نودها (ویرایش، کپی، حذف، یادداشت) کلیک می‌کرد، صفحه سفید می‌شد و اپلیکیشن crash می‌کرد.

## 🔍 علت مشکل

مشکل از **دوبار صدا زدن `Navigator.pop(context)`** بود:

1. یک بار در `workflow_node_context_menu.dart` در متد `onTap` هر گزینه
2. یک بار دیگر در `workflow_visual_editor_page.dart` در callback هایی که به context menu پاس داده می‌شدند

این باعث می‌شد که:
- Context menu بسته شود (اولین pop)
- سپس صفحه اصلی editor هم بسته شود (دومین pop)
- و در نتیجه صفحه سفید نمایش داده شود

## ✅ راه حل

### 1. تغییرات در `workflow_node_context_menu.dart`:

**قبل:**
```dart
PopupMenuItem<String>(
  value: 'edit',
  child: ListTile(...),
  onTap: () => onEdit?.call(),  // ❌ فقط callback صدا زده می‌شد
),
```

**بعد:**
```dart
PopupMenuItem<String>(
  value: 'edit',
  child: ListTile(...),
  onTap: () {
    Navigator.pop(context);  // ✅ اول context menu را می‌بندیم
    Future.delayed(const Duration(milliseconds: 100), () {
      onEdit?.call();  // ✅ سپس callback را صدا می‌زنیم
    });
  },
),
```

### 2. تغییرات در `workflow_visual_editor_page.dart`:

**قبل:**
```dart
onEdit: () async {
  Navigator.pop(context); // ❌ دوبار pop می‌شد
  await Future.delayed(const Duration(milliseconds: 100));
  final result = await showDialog<Map<String, dynamic>>(...);
  // ...
},
```

**بعد:**
```dart
onEdit: () async {
  await Future.delayed(const Duration(milliseconds: 100));  // ✅ فقط منتظر می‌مانیم
  if (!mounted) return;
  final result = await showDialog<Map<String, dynamic>>(...);
  // ...
},
```

## 📝 تغییرات کامل

### فایل `workflow_node_context_menu.dart`:

✅ تمام 4 گزینه منو به این شکل تغییر کردند:
1. **ویرایش (Edit)**: Navigator.pop + Future.delayed + callback
2. **یادداشت (Comment)**: Navigator.pop + Future.delayed + callback
3. **کپی (Duplicate)**: Navigator.pop + Future.delayed + callback
4. **حذف (Delete)**: Navigator.pop + Future.delayed + callback

### فایل `workflow_visual_editor_page.dart`:

✅ تمام callback ها ساده‌سازی شدند:
- حذف `Navigator.pop(context)` از همه callback ها
- حذف `Future.delayed` غیرضروری از بیشتر callback ها
- اضافه کردن check `mounted` قبل از هر عملیات

## 🎯 نتیجه

✅ Context menu به درستی بسته می‌شود  
✅ صفحه editor باز می‌ماند  
✅ دیالوگ‌های ویرایش به درستی باز می‌شوند  
✅ عملیات کپی، حذف، و ویرایش یادداشت کار می‌کنند  
✅ هیچ crash یا صفحه سفیدی رخ نمی‌دهد  

## 🧪 تست

برای تست این تغییرات:

1. وارد صفحه ویرایش workflow شوید
2. روی یک نود راست کلیک کنید (یا لانگ پرس در موبایل)
3. هر کدام از گزینه‌های زیر را امتحان کنید:
   - ✅ ویرایش → دیالوگ تنظیمات باز می‌شود
   - ✅ افزودن/ویرایش یادداشت → دیالوگ یادداشت باز می‌شود
   - ✅ کپی → نود کپی می‌شود
   - ✅ حذف → نود حذف می‌شود با امکان Undo

## 🔑 نکات کلیدی

1. **Single Responsibility**: Context menu خودش مسئول بستن خودش است
2. **Future.delayed**: برای اطمینان از بسته شدن context menu قبل از باز شدن دیالوگ جدید
3. **Mounted Check**: همیشه قبل از استفاده از context بررسی کنید که widget هنوز mounted است
4. **Avoid Double Pop**: هرگز Navigator.pop را در دو جای مختلف برای یک عملیات صدا نزنید

## 📁 فایل‌های تغییر یافته

- `hesabixUI/hesabix_ui/lib/widgets/workflow/workflow_node_context_menu.dart`
- `hesabixUI/hesabix_ui/lib/pages/business/workflow_visual_editor_page.dart`

---

**تاریخ رفع مشکل اولیه**: دسامبر 2025  
**وضعیت**: ✅ حل شده

## 🔄 به‌روزرسانی (رفع مشکل دوم)

### 🐛 مشکل جدید

با وجود رفع اولیه، هنوز زمانی که کاربر روی گزینه‌های context menu کلیک می‌کرد، صفحه سفید می‌شد.

### 🔍 علت مشکل جدید

مشکل از استفاده نادرست از `Navigator.pop(context)` در `onTap` بود. context در onTap ممکن است context صفحه اصلی باشد نه context menu، و این باعث بسته شدن صفحه اصلی می‌شد.

### ✅ راه‌حل نهایی

به جای استفاده از `onTap` و `Navigator.pop` دستی، از مکانیزم built-in `showMenu` استفاده کردیم:

**تغییرات در `workflow_node_context_menu.dart`:**

```dart
static Future<String?> show(...) async {
  final result = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(...),
    items: [
      PopupMenuItem<String>(
        value: 'edit',
        child: ListTile(...),
        // ❌ حذف شد: onTap با Navigator.pop
      ),
      // ... سایر items
    ],
  );

  // ✅ callback ها بعد از بسته شدن menu اجرا می‌شوند
  if (result != null) {
    await Future.delayed(const Duration(milliseconds: 100));
    switch (result) {
      case 'edit':
        onEdit?.call();
        break;
      case 'comment':
        onEditComment?.call();
        break;
      case 'duplicate':
        onDuplicate?.call();
        break;
      case 'delete':
        onDelete?.call();
        break;
    }
  }
  
  return result;
}
```

**تغییرات در `workflow_canvas.dart`:**

```dart
// تغییر نوع onNodeLongPress به async
final Future<void> Function(WorkflowNodeModel, Offset)? onNodeLongPress;

// استفاده از await در onLongPress
onLongPress: () async {
  widget.state.selectNode(node.id);
  if (widget.onNodeLongPress != null) {
    try {
      final position = WorkflowConstants.getNodeCenter(validPosition);
      await widget.onNodeLongPress!.call(node, position);
    } catch (e) {
      debugPrint('خطا در onLongPress: $e');
    }
  }
},
```

**تغییرات در `workflow_visual_editor_page.dart`:**

```dart
onNodeLongPress: (node, position) async {
  await WorkflowNodeContextMenu.show(
    context,
    position,
    node: node,
    onEditComment: () {
      if (mounted) _editNodeComment(node);
    },
    onEdit: () async {
      if (!mounted) return;
      final result = await showDialog<Map<String, dynamic>>(...);
      if (result != null && mounted) {
        _editorState.updateNodeConfig(node.id, result);
      }
    },
    onDuplicate: () {
      if (mounted) _duplicateNode(node);
    },
    onDelete: () {
      if (mounted) _deleteNode(node);
    },
  );
},
```

### 🎯 نتیجه نهایی

✅ Context menu به صورت خودکار بسته می‌شود (توسط showMenu)  
✅ صفحه editor باز می‌ماند  
✅ callback ها بعد از بسته شدن menu اجرا می‌شوند  
✅ دیگر هیچ pop دستی وجود ندارد که باعث بسته شدن صفحه شود  
✅ async/await به درستی مدیریت می‌شود  

### 🔑 نکات کلیدی نهایی

1. **از مکانیزم Built-in استفاده کنید**: showMenu خودش menu را می‌بندد، نیازی به Navigator.pop نیست
2. **Return Value**: از مقدار برگشتی showMenu برای تشخیص انتخاب کاربر استفاده کنید
3. **Async/Await**: onNodeLongPress باید async باشد و منتظر بسته شدن menu بماند
4. **Type Safety**: نوع callback را صریحاً به `Future<void> Function(...)` تغییر دهید

---

**تاریخ به‌روزرسانی**: دسامبر 2025  
**وضعیت**: ✅✅ کاملاً حل شده


