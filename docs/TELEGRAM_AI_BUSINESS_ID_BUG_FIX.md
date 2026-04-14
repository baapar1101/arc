# رفع باگ بحرانی: دور زدن چک اعتبار در تلگرام

## 🐛 خلاصه باگ

کاربران می‌توانستند از طریق تلگرام بدون چک درست اعتبار کسب‌وکار، از هوش مصنوعی استفاده کنند. این باگ امکان سوءاستفاده مالی و دور زدن سیستم اشتراک را فراهم می‌کرد.

---

## 🔍 تحلیل مشکل

### **باگ ۱: `business_id` می‌تواند `None` باشد**

**محل باگ**: `TelegramAIChatService.process_message()`

**مشکل**:
```python
# خط 255 (قبل از Fix)
ai_service = AIService(self.db, user_context, active_session.business_id)
```

**اگر `active_session.business_id = None`:**
1. `AIService` با `business_id=None` ساخته می‌شود
2. `_get_active_subscription(business_id=None)` اشتراک **global** را چک می‌کند
3. از کیف پول **global** استفاده می‌شود (که وجود ندارد!)
4. یا اگر کاربر اشتراک global داشت، از آن استفاده می‌کرد (نه از business)

**چرا `business_id` می‌تواند `None` باشد؟**

از schema `TelegramAISession`:
```python
business_id: Mapped[int | None] = mapped_column(..., nullable=True, ...)
```

**نتیجه**: کاربر می‌توانست:
- بدون اشتراک از AI استفاده کند
- از اعتبار user استفاده کند (نه business)
- کیف پول business را دور بزند

---

### **باگ ۲: Exception Handling نادرست**

**محل باگ**: `TelegramAIChatService.process_message()`

```python
# خطوط 253-262 (قبل از Fix)
try:
    ai_service = AIService(...)
    availability = ai_service.check_availability(...)
    if not availability["can_use"]:
        return self._send_availability_error(availability)
except Exception as e:
    logger.error(f"Error checking availability: {e}", exc_info=True)
    # در صورت خطا، اجازه ادامه بده  ⚠️ خطرناک!
```

**مشکل**: 
- هر خطایی که رخ دهد، catch می‌شود و کاربر می‌تواند ادامه دهد
- حتی اگر `check_availability()` exception بزند
- حتی اگر `AIService` نتواند ساخته شود

**نتیجه**: دور زدن کامل سیستم چک اعتبار!

---

### **باگ ۳: عدم validation در `check_quota_and_charge`**

**محل باگ**: `AIService.check_quota_and_charge()`

```python
# قبل از Fix
elif plan.plan_type == "pay_as_go":
    cost = self._calculate_cost(plan, input_tokens, output_tokens)
    return self._charge_from_wallet(cost, input_tokens, output_tokens)
    # اگر business_id=None باشد، wallet_service خطا می‌دهد
    # اما پاسخ AI از قبل تولید شده! (هدر رفت منابع)
```

**مشکل**:
- چک اعتبار **بعد از** تولید پاسخ AI انجام می‌شد
- اگر `business_id=None` بود، `charge_wallet_for_service` خطا می‌داد
- اما AI response از قبل تولید شده بود (هزینه API)

---

## ✅ راه‌حل‌های پیاده‌سازی شده

### **Fix ۱: اجباری کردن `business_id` در تلگرام**

**فایل**: `hesabixAPI/app/services/telegram_ai_chat_service.py`

**قبل**:
```python
async def process_message(self, text: str, user_context: AuthContext) -> bool:
    active_session = self.session_repo.get_active_session(self.user_id, self.chat_id)
    if not active_session or not active_session.session_id:
        return self.telegram_provider.send_text(...)
    
    # مستقیم استفاده می‌کرد - حتی اگر None بود!
    try:
        ai_service = AIService(self.db, user_context, active_session.business_id)
        # ...
    except Exception as e:
        # خطا رو می‌خورد!
```

**بعد**:
```python
async def process_message(self, text: str, user_context: AuthContext) -> bool:
    active_session = self.session_repo.get_active_session(self.user_id, self.chat_id)
    if not active_session or not active_session.session_id:
        return self.telegram_provider.send_text(...)
    
    # ✅ چک اجباری business_id
    if not active_session.business_id:
        logger.warning(f"Session without business_id for user {self.user_id}")
        return self.telegram_provider.send_text(
            chat_id=self.chat_id,
            text="❌ کسب‌وکار انتخاب شده نامعتبر است. لطفاً دوباره کسب‌وکار را انتخاب کنید.",
            reply_markup=self._build_inline_keyboard([
                [{"text": "🏢 انتخاب کسب‌وکار", "callback_data": "menu:chat"}]
            ])
        )
    
    # ✅ حذف try-except (خطاها باید نمایش داده شوند)
    ai_service = AIService(self.db, user_context, active_session.business_id)
    availability = ai_service.check_availability(estimated_tokens=len(text) * 2)
    
    if not availability["can_use"]:
        return self._send_availability_error(availability)
```

**تغییرات**:
1. ✅ چک اجباری `business_id` قبل از هر کاری
2. ✅ حذف `try-except` گسترده
3. ✅ پیام خطای واضح برای کاربر

---

### **Fix ۲: validation در `check_availability`**

**فایل**: `hesabixAPI/app/services/ai/ai_service.py`

**اضافه شده در خط 222**:
```python
elif plan.plan_type in ["pay_as_go", "hybrid"]:
    # ✅ بررسی الزامی بودن business_id
    if not self.business_id:
        return {
            "can_use": False,
            "reason": "BUSINESS_REQUIRED",
            "details": {
                "message": "برای استفاده از پلن پرداختی، انتخاب کسب‌وکار الزامی است",
                "suggestions": [
                    "لطفاً ابتدا یک کسب‌وکار را انتخاب کنید",
                    "کیف پول‌ها مختص به هر کسب‌وکار هستند"
                ]
            }
        }
    
    # ادامه محاسبات...
```

---

### **Fix ۳: validation در `check_quota_and_charge`**

**فایل**: `hesabixAPI/app/services/ai/ai_service.py`

**اضافه شده در خط 449**:
```python
elif plan.plan_type == "pay_as_go":
    # ✅ بررسی الزامی بودن business_id
    if not self.business_id:
        raise ApiError(
            "BUSINESS_REQUIRED",
            "برای استفاده از پلن پرداخت به ازای مصرف، انتخاب کسب‌وکار الزامی است",
            http_status=400
        )
    
    cost = self._calculate_cost(plan, input_tokens, output_tokens)
    return self._charge_from_wallet(cost, input_tokens, output_tokens)
```

**همچنین در خط 454 برای hybrid**:
```python
elif plan.plan_type == "hybrid":
    # ✅ بررسی الزامی بودن business_id
    if not self.business_id:
        raise ApiError(
            "BUSINESS_REQUIRED",
            "برای استفاده از پلن ترکیبی، انتخاب کسب‌وکار الزامی است",
            http_status=400
        )
    
    # ادامه logic...
```

---

### **Fix ۴: بهبود warning در `_get_active_subscription`**

**فایل**: `hesabixAPI/app/services/ai/ai_service.py`

**قبل**:
```python
def _get_active_subscription(self) -> Optional[UserAISubscription]:
    if not self.business_id:
        return None  # ساکت بود!
```

**بعد**:
```python
def _get_active_subscription(self) -> Optional[UserAISubscription]:
    if not self.business_id:
        # ✅ warning برای کاربران عادی
        if not (self.ctx.can_access_support_operator() or self.ctx.is_superadmin()):
            logger.warning(
                f"AIService initialized without business_id for regular user {self.ctx.get_user_id()}. "
                f"This may cause issues with wallet charging."
            )
        return None
```

---

## 📊 تأثیر Fix ها

### **قبل از Fix**:

| سناریو | نتیجه | شدت |
|--------|-------|-----|
| کاربر session با `business_id=None` دارد | ✅ می‌تواند استفاده کند | 🔴 بحرانی |
| `check_availability` exception می‌زند | ✅ می‌تواند استفاده کند | 🔴 بحرانی |
| پلن pay_as_go بدون business_id | ✅ می‌تواند استفاده کند (تا موقع charge) | 🔴 بحرانی |

### **بعد از Fix**:

| سناریو | نتیجه | شدت |
|--------|-------|-----|
| کاربر session با `business_id=None` دارد | ❌ خطا: "کسب‌وکار نامعتبر" | ✅ امن |
| `check_availability` exception می‌زند | ❌ خطا به کاربر نمایش داده می‌شود | ✅ امن |
| پلن pay_as_go بدون business_id | ❌ خطا: "BUSINESS_REQUIRED" | ✅ امن |

---

## 🧪 تست‌های پیشنهادی

### **۱. تست سناریوی باگ اصلی**:

```python
# Setup
user = create_test_user()
business = create_test_business(owner=user)
telegram_session = TelegramAISession(
    user_id=user.id,
    chat_id=12345,
    business_id=None,  # ⚠️ None!
    is_active=True
)

# قبل از Fix: می‌گذشت ✅
# بعد از Fix: خطا می‌دهد ❌
result = await telegram_service.process_message("سلام", user_context)
assert "کسب‌وکار نامعتبر" in result.text
```

### **۲. تست چک اعتبار**:

```python
# Setup
ai_service = AIService(db, user_context, business_id=None)
plan = create_pay_as_go_plan()
subscription = create_subscription(user, plan, business_id=None)

# قبل از Fix: می‌گذشت تا charge
# بعد از Fix: در check_availability خطا می‌دهد
availability = ai_service.check_availability(estimated_tokens=1000)
assert availability["can_use"] == False
assert availability["reason"] == "BUSINESS_REQUIRED"
```

### **۳. تست پلن hybrid**:

```python
# Setup
ai_service = AIService(db, user_context, business_id=None)
plan = create_hybrid_plan()

# بعد از Fix: خطا می‌دهد
with pytest.raises(ApiError) as exc:
    ai_service.check_quota_and_charge(100, 200)
assert exc.value.error_code == "BUSINESS_REQUIRED"
```

---

## 🎯 نکات مهم

### **۱. کیف پول‌ها Business-Specific هستند**

این Fix با این فرض طراحی شده که:
- ✅ همه کیف پول‌ها مربوط به business هستند
- ✅ کیف پول global وجود ندارد
- ✅ برای هر استفاده‌ای از AI که نیاز به wallet داره، `business_id` الزامی است

### **۲. استثناها**

فقط این دسترسی‌ها بدون `business_id` کار می‌کنند:
- ✅ `ctx.can_access_support_operator()` → اپراتورهای پشتیبانی
- ✅ `ctx.is_superadmin()` → ادمین‌ها

برای این کاربران، `payment_method = "free"` است.

### **۳. بهبود امنیت**

با این Fix:
1. ✅ دور زدن سیستم اشتراک غیرممکن شد
2. ✅ هزینه‌ها به درستی از کیف پول business کسر می‌شود
3. ✅ لاگ‌های دقیق‌تر (warning برای موارد مشکوک)
4. ✅ پیام‌های خطای واضح برای کاربر

---

## 📝 فایل‌های تغییر یافته

1. ✅ `hesabixAPI/app/services/telegram_ai_chat_service.py`
   - اضافه شدن چک `business_id` در `process_message`
   - حذف `try-except` گسترده
   - بهبود پیام‌های خطا

2. ✅ `hesabixAPI/app/services/ai/ai_service.py`
   - اضافه شدن validation در `check_availability` برای پلن‌های پرداختی
   - اضافه شدن validation در `check_quota_and_charge`
   - بهبود `_get_active_subscription` با warning

---

## 🔮 پیشنهادات آینده

1. **Migration برای cleanup**: حذف session های با `business_id=None`
2. **Monitoring**: alert برای موارد مشکوک
3. **Unit Tests**: اضافه کردن تست‌های خودکار برای این سناریوها
4. **Schema Change**: غیرقابل nullable کردن `business_id` در future

---

**تاریخ Fix**: ۵ دسامبر ۲۰۲۵  
**شدت باگ**: 🔴 بحرانی  
**تأثیر**: امنیت و مالی  
**وضعیت**: ✅ Fixed


