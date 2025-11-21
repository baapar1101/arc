# مشکلات شناسایی شده در بخش چت با هوش مصنوعی

این سند مشکلات شناسایی شده در سیستم چت AI را فهرست می‌کند.

## 🔴 مشکلات بحرانی (Critical Issues)

### 1. Blocking Operations در Async Context

**موقعیت:** 
- `hesabixAPI/app/services/ai/ai_service.py`
- `hesabixAPI/app/services/ai/ai_provider.py`
- `hesabixAPI/adapters/api/v1/ai/chat.py`

**مشکل:**
- درخواست‌های AI در حالی که endpoint ها async هستند، از sync blocking operations استفاده می‌کنند
- متد `chat_completion()` در `ai_service.py` خط 290 sync است و از OpenAI client که blocking است استفاده می‌کند
- متد `handle_function_calls()` در خط 580 نیز sync است و عملیات blocking انجام می‌دهد
- تمام عملیات دیتابیس blocking هستند (SQLAlchemy sync sessions)

**تأثیر:**
- وقتی یک کاربر درخواست AI ارسال می‌کند، thread اصلی FastAPI block می‌شود
- در سیستم چندکاربره، این باعث می‌شود سایر کاربران نتوانند درخواست‌هایشان را پردازش کنند
- کل backend تا زمان دریافت پاسخ از AI به خواب می‌رود

**راه حل پیشنهادی:**
- استفاده از `asyncio.to_thread()` یا `run_in_executor()` برای اجرای عملیات blocking در thread pool
- استفاده از async database drivers (مثل asyncpg) یا اجرای sync operations در executor
- استفاده از async HTTP client برای OpenAI API

---

### 2. Function Calling باعث Timeout می‌شود

**موقعیت:**
- `hesabixAPI/app/services/ai/ai_service.py` خطوط 365-400 و 494-557

**مشکل:**
- وقتی AI تصمیم می‌گیرد function call انجام دهد، یک درخواست جدید به AI ارسال می‌شود
- این درخواست دوم blocking است و می‌تواند زمان زیادی طول بکشد
- در streaming mode (خط 519-557)، وقتی function calls وجود دارد، یک درخواست non-streaming ارسال می‌شود که blocking است
- این باعث می‌شود کل فرآیند طولانی شود و timeout رخ دهد

**تأثیر:**
- کاربران خطای timeout دریافت می‌کنند
- درخواست‌های AI که function calling دارند شکست می‌خورند
- تجربه کاربری ضعیف

**راه حل پیشنهادی:**
- افزایش timeout در frontend برای درخواست‌های AI
- استفاده از async/await برای تمام عملیات
- پیاده‌سازی timeout بهتر در backend
- بهینه‌سازی function calls (parallel execution اگر ممکن باشد)

---

### 3. Streaming در Frontend به درستی کار نمی‌کند

**موقعیت:**
- `hesabixUI/hesabix_ui/lib/services/ai_service.dart` خطوط 180-264
- `hesabixUI/hesabix_ui/lib/widgets/ai/ai_chat_dialog.dart` خطوط 191-228

**مشکل:**
- کد frontend سعی می‌کند streaming را handle کند
- اما در `api_client.dart` خط 18، `receiveTimeout` فقط 20 ثانیه است
- اگر پاسخ AI طولانی باشد یا function calling داشته باشد، timeout رخ می‌دهد
- ممکن است SSE stream به درستی parse نشود

**تأثیر:**
- کاربران پاسخ AI را به صورت یکجا (نه به صورت streaming) دریافت می‌کنند
- تجربه کاربری ضعیف
- اگر پاسخ طولانی باشد، timeout رخ می‌دهد

**راه حل پیشنهادی:**
- افزایش `receiveTimeout` برای streaming requests
- بهبود parsing SSE stream در frontend
- اضافه کردن timeout مخصوص برای AI requests

---

### 4. Database Session Blocking

**موقعیت:**
- `hesabixAPI/adapters/db/session.py` خط 26
- تمام استفاده‌ها از `get_db()` در AI endpoints

**مشکل:**
- `get_db()` یک sync generator است که SQLAlchemy Session برمی‌گرداند
- تمام عملیات دیتابیس blocking هستند
- وقتی درخواست AI در حال پردازش است و عملیات دیتابیس انجام می‌شود، thread block می‌شود

**تأثیر:**
- در سیستم چندکاربره، وقتی یک کاربر درخواست AI دارد و دیتابیس query اجرا می‌شود، سایر کاربران باید منتظر بمانند
- عملکرد کلی سیستم کاهش می‌یابد

**راه حل پیشنهادی:**
- استفاده از async database sessions
- یا اجرای sync database operations در thread pool با `run_in_executor()`

---

## 🟡 مشکلات متوسط (Medium Issues)

### 5. Timeout در Frontend بسیار کوتاه است

**موقعیت:**
- `hesabixUI/hesabix_ui/lib/core/api_client.dart` خطوط 17-18

**مشکل:**
- `connectTimeout`: 10 ثانیه
- `receiveTimeout`: 20 ثانیه
- برای درخواست‌های AI که می‌توانند طولانی باشند، این زمان‌ها کافی نیست

**راه حل پیشنهادی:**
- افزایش timeout برای AI endpoints
- یا استفاده از timeout جداگانه برای AI requests

---

### 6. مدیریت خطا در Streaming

**موقعیت:**
- `hesabixAPI/adapters/api/v1/ai/chat.py` خطوط 280-417

**مشکل:**
- در تابع `_stream_message_response`، مدیریت خطا وجود دارد اما ممکن است کافی نباشد
- اگر خطایی در وسط streaming رخ دهد، ممکن است client از وضعیت درست مطلع نشود

**راه حل پیشنهادی:**
- بهبود مدیریت خطا در streaming
- اطمینان از اینکه client همیشه از وضعیت مطلع می‌شود

---

### 7. Function Calls به صورت Sequential اجرا می‌شوند

**موقعیت:**
- `hesabixAPI/app/services/ai/ai_service.py` خطوط 596-605

**مشکل:**
- در `handle_function_calls`، تمام function calls به صورت sequential اجرا می‌شوند
- اگر چند function call وجود داشته باشد، زمان کل افزایش می‌یابد

**راه حل پیشنهادی:**
- اجرای function calls به صورت parallel اگر ممکن باشد
- استفاده از `asyncio.gather()` برای async execution

---

## 🔵 مشکلات جزئی (Minor Issues)

### 8. عدم وجود Progress Indicator

**موقعیت:**
- `hesabixUI/hesabix_ui/lib/widgets/ai/ai_chat_dialog.dart`

**مشکل:**
- وقتی function calling در حال اجرا است، کاربر هیچ نشانه‌ای از پیشرفت نمی‌بیند
- فقط یک spinner نمایش داده می‌شود

**راه حل پیشنهادی:**
- نمایش progress indicator برای function calls
- نمایش پیام‌های مناسب به کاربر

---

### 9. عدم Retry Mechanism

**موقعیت:**
- تمام AI service calls

**مشکل:**
- اگر خطای موقت رخ دهد (مثل network error)، هیچ retry mechanism وجود ندارد
- کاربر باید دوباره درخواست را ارسال کند

**راه حل پیشنهادی:**
- پیاده‌سازی retry mechanism برای درخواست‌های AI
- با exponential backoff

---

### 10. Database Session در Streaming Response

**موقعیت:**
- `hesabixAPI/adapters/api/v1/ai/chat.py` خطوط 280-417

**مشکل:**
- در تابع `_stream_message_response`، یک database session برای کل مدت streaming نگه داشته می‌شود
- اگر streaming طولانی شود، session مدت زیادی باز می‌ماند

**راه حل پیشنهادی:**
- استفاده از session جداگانه برای commit
- یا استفاده از async database operations

---

## 📊 خلاصه مشکلات

### مشکلات بحرانی:
1. ✅ Blocking operations در async context
2. ✅ Function calling باعث timeout می‌شود
3. ✅ Streaming در frontend به درستی کار نمی‌کند
4. ✅ Database session blocking

### مشکلات متوسط:
5. ✅ Timeout در frontend بسیار کوتاه است
6. ✅ مدیریت خطا در streaming
7. ✅ Function calls به صورت sequential اجرا می‌شوند

### مشکلات جزئی:
8. ✅ عدم وجود progress indicator
9. ✅ عدم retry mechanism
10. ✅ Database session در streaming response

---

## 🎯 اولویت‌بندی

### فوری (P0):
1. Blocking operations در async context - باید فوراً حل شود چون کل سیستم را مختل می‌کند
2. Function calling باعث timeout می‌شود - کاربران نمی‌توانند از AI استفاده کنند

### مهم (P1):
3. Streaming در frontend به درستی کار نمی‌کند - تجربه کاربری ضعیف
4. Database session blocking - عملکرد کلی سیستم را کاهش می‌دهد

### متوسط (P2):
5. Timeout در frontend بسیار کوتاه است
6. مدیریت خطا در streaming
7. Function calls به صورت sequential اجرا می‌شوند

### کم‌اهمیت (P3):
8. عدم وجود progress indicator
9. عدم retry mechanism
10. Database session در streaming response

