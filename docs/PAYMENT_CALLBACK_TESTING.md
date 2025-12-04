# 🧪 راهنمای تست صفحات بازگشت پرداخت

## ✅ تغییرات اعمال شده

### 1. Backend (API)
- ✅ تابع `get_db()` اصلاح شد - اضافه شدن `commit()`
- ✅ HTML Templates زیبا ساخته شد:
  - `templates/payment/base.html` - قالب پایه
  - `templates/payment/success.html` - صفحه موفقیت
  - `templates/payment/failed.html` - صفحه خطا
- ✅ ماژول `payment_response.py` برای تشخیص هوشمند
- ✅ Callback endpoints اصلاح شد (zarinpal, parsian, bitpay)
- ✅ پارامتر `source` به API اضافه شد

### 2. Frontend (Flutter)
- ✅ Deep Link تنظیم شد برای Android
- ✅ Deep Link تنظیم شد برای iOS
- ✅ سرویس `DeepLinkHandler` ساخته شد
- ✅ صفحه `PaymentResultPage` برای نمایش نتیجه
- ✅ مستندات کامل `DEEP_LINK_INTEGRATION.md`

---

## 🧪 سناریوهای تست

### تست 1: پرداخت موفق از اپ موبایل

**مراحل:**
1. اپ را در گوشی/شبیه‌ساز باز کنید
2. به بخش "افزایش اعتبار" بروید
3. مبلغ را وارد کنید (حداقل 5000 ریال)
4. روی "پرداخت" کلیک کنید
5. به درگاه BitPay هدایت می‌شوید
6. پرداخت کنید (sandbox mode)
7. **نتیجه مورد انتظار:**
   - ✅ صفحه HTML زیبا با پیام موفقیت
   - ✅ بعد از 2 ثانیه اپ باز می‌شود
   - ✅ صفحه نتیجه با جزئیات تراکنش نمایش داده می‌شود
   - ✅ تراکنش در دیتابیس commit شده

**تست دستی URL:**
```
https://hsxn.hesabix.ir/api/v1/wallet/payments/callback/bitpay?tx_id=XX&trans_id=YYY&id_get=ZZZ&source=app
```

---

### تست 2: پرداخت موفق از مرورگر موبایل

**مراحل:**
1. از مرورگر موبایل به سایت بروید
2. همان مراحل تست 1
3. **نتیجه مورد انتظار:**
   - ✅ صفحه HTML موبایل-فرندلی
   - ✅ دکمه‌های "بازگشت به داشبورد" و "باز کردن در اپ"
   - ✅ در صورت کلیک "باز کردن در اپ"، اپ باز می‌شود

**تست دستی URL:**
```
https://hsxn.hesabix.ir/api/v1/wallet/payments/callback/bitpay?tx_id=XX&trans_id=YYY&id_get=ZZZ&source=mobile_web
```

---

### تست 3: پرداخت موفق از دسکتاپ

**مراحل:**
1. از مرورگر دسکتاپ به سایت بروید
2. همان مراحل تست 1
3. **نتیجه مورد انتظار:**
   - ✅ صفحه HTML کامل با تمام جزئیات
   - ✅ دکمه "بازگشت به داشبورد"
   - ✅ طراحی responsive و زیبا

**تست دستی URL:**
```
https://hsxn.hesabix.ir/api/v1/wallet/payments/callback/bitpay?tx_id=XX&trans_id=YYY&id_get=ZZZ&source=desktop
```

یا بدون source (تشخیص خودکار):
```
https://hsxn.hesabix.ir/api/v1/wallet/payments/callback/bitpay?tx_id=XX&trans_id=YYY&id_get=ZZZ
```

---

### تست 4: پرداخت ناموفق

**مراحل:**
1. پرداخت را کنسل کنید یا اطلاعات اشتباه وارد کنید
2. **نتیجه مورد انتظار:**
   - ✅ صفحه HTML قرمز با آیکون ضربدر
   - ✅ پیام خطا و دلیل شکست
   - ✅ دکمه "تلاش مجدد"
   - ✅ راهنمایی برای کاربر

---

### تست 5: درخواست JSON (برای API Clients)

**مراحل:**
```bash
curl -H "Accept: application/json" \
  "https://hsxn.hesabix.ir/api/v1/wallet/payments/callback/bitpay?tx_id=XX&trans_id=YYY&id_get=ZZZ"
```

**نتیجه مورد انتظار:**
```json
{
  "success": true,
  "data": {
    "transaction_id": 28,
    "success": true,
    "external_ref": "33204507",
    "amount": 100000
  },
  "message": "TOPUP_CONFIRMED"
}
```

یا با پارامتر `format=json`:
```
https://hsxn.hesabix.ir/api/v1/wallet/payments/callback/bitpay?tx_id=XX&trans_id=YYY&id_get=ZZZ&format=json
```

---

### تست 6: Deep Link در اپ

**Android (ADB):**
```bash
# موفق
adb shell am start -W -a android.intent.action.VIEW \
  -d "hesabix://payment/callback?tx_id=28&status=success&amount=100000&ref=123456"

# ناموفق
adb shell am start -W -a android.intent.action.VIEW \
  -d "hesabix://payment/callback?tx_id=29&status=failed&ref=123457"
```

**iOS (Simulator):**
```bash
# موفق
xcrun simctl openurl booted \
  "hesabix://payment/callback?tx_id=28&status=success&amount=100000&ref=123456"

# ناموفق
xcrun simctl openurl booted \
  "hesabix://payment/callback?tx_id=29&status=failed&ref=123457"
```

---

## 🔍 بررسی لاگ‌ها

### لاگ‌های API:
```bash
# مشاهده لاگ‌های real-time
journalctl -u hesabix-api -f

# جستجوی تراکنش خاص
journalctl -u hesabix-api | grep "tx_id.*28"

# بررسی commit های موفق
journalctl -u hesabix-api | grep "create_top_up_request_completed"
```

### بررسی تراکنش در دیتابیس:
```bash
cd /var/www/ark/hesabixAPI && source .venv/bin/activate
python3 << 'EOF'
from sqlalchemy import create_engine, text
engine = create_engine("mysql+pymysql://root:your_password@localhost:3306/hesabixpy")
with engine.connect() as conn:
    result = conn.execute(text("SELECT * FROM wallet_transactions ORDER BY id DESC LIMIT 5"))
    for row in result:
        print(f"ID: {row.id}, Type: {row.type}, Amount: {row.amount}, Status: {row.status}")
EOF
```

---

## ✅ Checklist تست

- [ ] پرداخت موفق از اپ Android
- [ ] پرداخت موفق از اپ iOS
- [ ] پرداخت موفق از Chrome موبایل
- [ ] پرداخت موفق از Safari موبایل
- [ ] پرداخت موفق از دسکتاپ
- [ ] پرداخت ناموفق از اپ
- [ ] پرداخت ناموفق از مرورگر
- [ ] Deep Link باز کردن اپ در Android
- [ ] Deep Link باز کردن اپ در iOS
- [ ] درخواست JSON با Accept header
- [ ] درخواست JSON با format parameter
- [ ] تراکنش commit شدن در دیتابیس
- [ ] نمایش صحیح اطلاعات در HTML
- [ ] Responsive بودن در سایزهای مختلف

---

## 🐛 عیب‌یابی

### مشکل 1: تراکنش commit نمی‌شود
**علت:** تابع `get_db()` بدون commit
**راه حل:** ✅ قبلاً برطرف شد

### مشکل 2: اپ باز نمی‌شود
**علایم:**
- کلیک روی لینک اثری ندارد
- دیالوگ انتخاب اپ نمایش داده نمی‌شود

**بررسی:**
1. AndroidManifest.xml تنظیمات را چک کنید
2. Info.plist تنظیمات را چک کنید
3. اپ را uninstall و مجدداً install کنید
4. با ADB/Simulator تست کنید

### مشکل 3: صفحه HTML نمایش داده نمی‌شود
**علایم:**
- JSON خام نمایش داده می‌شود
- خطای 500

**بررسی:**
1. Template ها موجود باشند در `templates/payment/`
2. Jinja2 نصب باشد
3. لاگ‌های API را بررسی کنید

### مشکل 4: source تشخیص داده نمی‌شود
**بررسی:**
1. پارامتر `source` به API ارسال می‌شود؟
2. در extra_info تراکنش ذخیره شده؟
3. User-Agent header صحیح است؟

---

## 📊 معیارهای موفقیت

✅ **عملکرد:**
- زمان بارگذاری صفحه HTML < 1 ثانیه
- تراکنش commit شود در کمتر از 2 ثانیه
- Deep Link اپ را باز کند در کمتر از 3 ثانیه

✅ **تجربه کاربری:**
- کاربر پیام واضح و دوستانه ببیند
- دکمه‌ها قابل کلیک و واضح باشند
- انیمیشن‌ها نرم و زیبا باشند

✅ **قابلیت اطمینان:**
- 100% تراکنش‌ها در دیتابیس ذخیره شوند
- صفحه fallback همیشه کار کند
- لاگ‌های کامل برای debugging

---

## 🎉 تبریک!

اگر تمام تست‌ها موفق بودند، سیستم پرداخت شما آماده است! 🚀

برای سوالات یا مشکلات، به مستندات زیر مراجعه کنید:
- `/var/www/ark/hesabixUI/DEEP_LINK_INTEGRATION.md`
- `/var/www/ark/hesabixAPI/templates/payment/`
- `/var/www/ark/hesabixAPI/app/core/payment_response.py`


