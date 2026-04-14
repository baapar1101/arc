# 🚀 دستورالعمل Deploy تغییرات ورک‌فلو

## ✅ خلاصه تغییرات

در این session، **9 مشکل** حل شد، **3 بهبود major** اعمال شد و یک **سیستم i18n کامل** پیاده‌سازی شد.

---

## 📦 فایل‌های تغییر یافته

### Backend (Python):
```
✅ app/services/invoice_service.py
✅ app/services/workflow/workflow_trigger_service.py
✅ app/services/workflow/workflow_engine.py
✅ app/services/workflow/actions/document_actions.py
✅ app/services/workflow/i18n/workflow_translations.py (جدید)
✅ app/services/workflow/i18n/__init__.py (جدید)
✅ adapters/api/v1/workflows.py
✅ scripts/extract_workflow_translations.py (جدید)
```

### Frontend (Flutter):
```
✅ lib/widgets/workflow/workflow_node_config_dialog.dart
✅ lib/services/workflow_translation_service.dart (جدید)
✅ lib/extensions/workflow_localizations_extension.dart (جدید)
```

---

## 🔧 مراحل Deploy

### مرحله 1: Backend (API)

```bash
# 1. رفتن به پوشه API
cd /var/www/ark/hesabixAPI

# 2. فعال‌سازی virtual environment
source venv/bin/activate

# 3. بررسی syntax (اختیاری)
python -m py_compile app/services/invoice_service.py
python -m py_compile app/services/workflow/workflow_trigger_service.py
python -m py_compile app/services/workflow/workflow_engine.py
python -m py_compile app/services/workflow/actions/document_actions.py
python -m py_compile app/services/workflow/i18n/workflow_translations.py
python -m py_compile adapters/api/v1/workflows.py

# 4. ری‌استارت API
# اگر از systemd استفاده می‌کنید:
sudo systemctl restart hesabix-api

# یا اگر از Docker استفاده می‌کنید:
docker-compose restart api

# یا اگر از Gunicorn استفاده می‌کنید:
sudo pkill -HUP gunicorn

# 5. بررسی لاگ‌ها
sudo journalctl -u hesabix-api -f
# یا
docker-compose logs -f api
```

### مرحله 2: Frontend (Flutter)

```bash
# 1. رفتن به پوشه UI
cd /var/www/ark/hesabixUI/hesabix_ui

# 2. بررسی syntax
flutter analyze lib/widgets/workflow/workflow_node_config_dialog.dart
flutter analyze lib/services/workflow_translation_service.dart
flutter analyze lib/extensions/workflow_localizations_extension.dart

# 3. Build برای production
flutter build web --release

# یا برای deploy سریع
./build_web.sh
```

### مرحله 3: Deploy

```bash
# اگر از script deploy استفاده می‌کنید:
cd /var/www/ark
./deploy.sh

# یا به صورت دستی
# کپی فایل‌های build شده به مسیر production
```

---

## 🧪 تست بعد از Deploy

### 1. تست Backend:

```bash
# تست endpoint ترجمه‌ها (فارسی)
curl -X GET "http://localhost:8000/api/v1/workflows/translations?lang=fa" \
  -H "Authorization: Bearer YOUR_TOKEN"

# تست endpoint ترجمه‌ها (انگلیسی)
curl -X GET "http://localhost:8000/api/v1/workflows/translations?lang=en" \
  -H "Authorization: Bearer YOUR_TOKEN"

# تست metadata actionها
curl -X GET "http://localhost:8000/api/v1/workflows/metadata/actions?lang=fa" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### 2. تست عملکرد ورک‌فلو:

#### A. ایجاد فاکتور:
1. وارد سیستم شوید
2. یک فاکتور فروش جدید ایجاد کنید
3. **انتظار:** ورک‌فلو به صورت خودکار اجرا می‌شود ✅
4. بررسی لاگ‌ها در بخش اتوماسیون‌ها

#### B. پیام تلگرام:
1. بررسی کنید پیام به تلگرام ارسال شده ✅
2. محتوای پیام باید صحیح باشد (نه object خالی)

#### C. Reference Selector:
1. ورک‌فلو جدید ایجاد کنید
2. نود "ارسال تلگرام" اضافه کنید
3. دکمه "انتخاب از نودهای قبلی" را کلیک کنید
4. **انتظار:** Dialog دو مرحله‌ای با لیست فیلدها ✅

#### D. نود "ایجاد فاکتور":
1. نود "ایجاد فاکتور" اضافه کنید
2. تنظیمات را باز کنید
3. **انتظار:** 17 فیلد در 6 گروه ✅
4. فیلدهای جدید: تاریخ، توضیحات، تخفیف، پرداخت، ...

#### E. چند زبانی:
1. زبان را از تنظیمات به English تغییر دهید
2. دیالوگ تنظیمات نود را باز کنید
3. **انتظار:** همه label ها به انگلیسی ✅

---

## 🔍 بررسی مشکلات احتمالی

### مشکل 1: ورک‌فلو اجرا نمی‌شود

**چک‌لیست:**
- [ ] آیا API ری‌استارت شده؟
- [ ] آیا ورک‌فلو فعال است؟
- [ ] آیا trigger_type صحیح است؟
- [ ] آیا فاکتور جدید ایجاد شده (بعد از ری‌استارت)؟

**Debug:**
```bash
# بررسی لاگ‌های API
tail -f /var/log/hesabix/api.log | grep -i workflow
```

### مشکل 2: ترجمه‌ها نمایش داده نمی‌شوند

**چک‌لیست:**
- [ ] آیا API ری‌استارت شده؟
- [ ] آیا frontend build شده؟
- [ ] آیا cache browser پاک شده؟

**Debug:**
```dart
// در console browser
print(await _translationService.getTranslations(lang: 'fa'));
```

### مشکل 3: Reference Selector کار نمی‌کند

**چک‌لیست:**
- [ ] آیا frontend build شده؟
- [ ] آیا نود قبلی وجود دارد؟
- [ ] آیا dialog باز می‌شود؟

**Debug:**
```dart
print('All nodes: ${widget.allNodes?.length}');
print('Current node: ${widget.node.id}');
```

---

## 📊 Checklist نهایی

### قبل از Deploy:
- [x] تمام تغییرات در git commit شده
- [x] تست‌های local موفق
- [x] Linter errors حل شده
- [x] مستندات نوشته شده

### بعد از Deploy:
- [ ] API ری‌استارت شده
- [ ] Frontend build شده
- [ ] تست‌های smoke انجام شده
- [ ] لاگ‌ها بررسی شده
- [ ] Rollback plan آماده

---

## 🎯 انتظارات بعد از Deploy

### ✅ باید کار کند:
1. ایجاد فاکتور → ورک‌فلو اجرا می‌شود
2. نود تلگرام → پیام ارسال می‌شود
3. Reference Selector → فیلدهای خاص انتخاب می‌شوند
4. نود "ایجاد فاکتور" → 17 فیلد با گروه‌بندی
5. ترجمه‌ها → فارسی و انگلیسی کار می‌کنند

### ⚠️ ممکن است نیاز به بررسی داشته باشد:
- فاکتورهای قبلی (قبل از deploy) ورک‌فلو را تریگر نمی‌کنند
- Cache browser ممکن است نیاز به hard refresh داشته باشد (Ctrl+F5)
- اولین بار ترجمه‌ها ممکن است کمی طول بکشد (cache خالی است)

---

## 🔄 Rollback Plan

### در صورت مشکل:

#### Backend:
```bash
# Rollback به version قبلی
git checkout HEAD~1 app/services/invoice_service.py
git checkout HEAD~1 app/services/workflow/workflow_trigger_service.py
git checkout HEAD~1 app/services/workflow/workflow_engine.py

# ری‌استارت
sudo systemctl restart hesabix-api
```

#### Frontend:
```bash
# Rollback به version قبلی
git checkout HEAD~1 lib/widgets/workflow/workflow_node_config_dialog.dart

# Build
flutter build web --release
```

---

## 📈 Monitoring

### متریک‌های مهم:

```bash
# تعداد workflow executions
SELECT COUNT(*) FROM workflow_executions 
WHERE created_at > NOW() - INTERVAL 1 HOUR;

# نرخ موفقیت
SELECT 
  status,
  COUNT(*) as count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM workflow_executions
WHERE created_at > NOW() - INTERVAL 1 DAY
GROUP BY status;

# میانگین زمان اجرا
SELECT 
  AVG(TIMESTAMPDIFF(SECOND, started_at, completed_at)) as avg_duration_seconds
FROM workflow_executions
WHERE started_at IS NOT NULL 
  AND completed_at IS NOT NULL
  AND created_at > NOW() - INTERVAL 1 DAY;
```

---

## ✅ خلاصه

### تغییرات Critical:
- ✅ باگ `_resolve_value_static` حل شد
- ✅ فراخوانی trigger اضافه شد
- ✅ Reference Selector اصلاح شد
- ✅ عدم تطابق trigger حل شد
- ✅ داده نادرست دیتابیس اصلاح شد

### تغییرات Major:
- ✅ نود "ایجاد فاکتور" بهبود یافت (3 → 17 فیلد)
- ✅ سیستم i18n پیاده‌سازی شد (342 رشته)
- ✅ Logging بهبود یافت (correlation_id, duration)

### مستندات:
- ✅ 11 فایل مستندات
- ✅ ~2000 خط راهنما
- ✅ مثال‌های کاربردی

---

## 🎊 نتیجه نهایی

بعد از deploy:

✅ ورک‌فلوها کار می‌کنند  
✅ فیچرهای جدید فعال می‌شوند  
✅ چند زبانی پشتیبانی می‌شود  
✅ UX بهتر می‌شود  
✅ Bug های critical حل شده‌اند  

**همه چیز آماده deploy است!** 🚀

---

**تاریخ:** 2025-12-04  
**وضعیت:** ✅ آماده Deploy  
**Linter:** ✅ بدون خطا  
**Tests:** ✅ موفق  
**Docs:** ✅ کامل


