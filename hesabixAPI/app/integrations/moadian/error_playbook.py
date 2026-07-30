"""
کاتالوگ راهنمای خطاهای سامانه مودیان — پیام actionable برای UI.
هر ورودی: title، explanation، action، action_route، severity
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional


# action_route: کلید مسیریابی سمت کلاینت
# invoice | person | product | tax_settings | stuffid | none

_PLAYBOOK: Dict[str, Dict[str, str]] = {
    "0304401": {
        "title": "نرخ مالیات کالا با سامانه مودیان یکی نیست",
        "explanation": (
            "نرخ ارزش‌افزودهٔ ردیف کالا باید دقیقاً مطابق شناسه کالا/خدمت در stuffid.tax.gov.ir باشد. "
            "معمولاً برای کالاهای مشمول سال ۱۴۰۳ به بعد ۱۰٪ است؛ صفر فقط برای شناسه‌های معاف مجاز است."
        ),
        "action": "نرخ مالیات ردیف فاکتور و تعریف کالا را با stuffid یکسان کنید، سپس دوباره ارسال کنید.",
        "action_route": "product",
        "action_label": "ویرایش کالا",
        "severity": "error",
    },
    "0200201": {
        "title": "تاریخ صدور فاکتور خارج از مهلت مجاز است",
        "explanation": (
            "سامانه مودیان فقط در بازهٔ مجاز (معمولاً حدود ۱۲ روز از تاریخ صدور) صورتحساب را می‌پذیرد. "
            "فاکتورهای خیلی قدیمی یا با تاریخ آینده رد می‌شوند."
        ),
        "action": "فاکتور جدید با تاریخ معتبر بسازید یا در صورت تمدید مهلت فصلی طبق اطلاعیه سازمان اقدام کنید.",
        "action_route": "invoice",
        "action_label": "مشاهده فاکتور",
        "severity": "error",
    },
    "02002": {
        "title": "تاریخ صدور فاکتور نامعتبر است",
        "explanation": "تاریخ و زمان صدور از نظر قواعد محاسباتی مودیان پذیرفته نشده است.",
        "action": "تاریخ صدور فاکتور را بررسی و در بازه مجاز تنظیم کنید.",
        "action_route": "invoice",
        "action_label": "ویرایش فاکتور",
        "severity": "error",
    },
    "00012": {
        "title": "شماره اقتصادی خریدار خالی است",
        "explanation": (
            "برای صورتحساب نوع اول، سامانه شماره اقتصادی خریدار (tinb) را الزامی می‌داند. "
            "اگر خریدار مصرف‌کننده نهایی است، صورتحساب باید به‌صورت نوع دوم (ساده) ارسال شود."
        ),
        "action": "کد اقتصادی ۱۱ یا ۱۴ رقمی طرف‌حساب را تکمیل کنید، یا فاکتور بدون هویت کامل خریدار را به‌عنوان نوع ۲ بفرستید.",
        "action_route": "person",
        "action_label": "ویرایش طرف‌حساب",
        "severity": "error",
    },
    "00107": {
        "title": "قاعده ارسال صورتحساب ناقص است",
        "explanation": (
            "این خطا معمولاً همراه با خطاهای دیگر (تاریخ یا هویت خریدار) دیده می‌شود. "
            "پس از رفع خطاهای اصلی، اغلب خودبه‌خود برطرف می‌شود."
        ),
        "action": "ابتدا خطاهای نرخ مالیات و تاریخ را برطرف کنید و دوباره استعلام بگیرید.",
        "action_route": "invoice",
        "action_label": "مشاهده فاکتور",
        "severity": "warning",
    },
    "0103502": {
        "title": "واحد اندازه‌گیری مجاز نیست",
        "explanation": "مقدار واحد اندازه‌گیری باید از فهرست کدهای عددی مودیان باشد، نه نام فارسی مثل «عدد».",
        "action": "واحد مالیاتی کالا را به کد عددی (مثلاً ۱۶۲۷ برای عدد) تغییر دهید.",
        "action_route": "product",
        "action_label": "ویرایش واحد کالا",
        "severity": "error",
    },
    "0103504": {
        "title": "فرمت واحد اندازه‌گیری نادرست است",
        "explanation": "واحد اندازه‌گیری باید فقط رقم باشد (حداکثر ۸ رقم).",
        "action": "کد واحد مالیاتی کالا را به صورت عددی ثبت کنید.",
        "action_route": "product",
        "action_label": "ویرایش کالا",
        "severity": "error",
    },
    "0107305": {
        "title": "ارزش ریالی کالا نامعتبر است",
        "explanation": (
            "فیلد ارزش ریالی (ssrv) نباید صفر ارسال شود مگر مقدار واقعی داشته باشد. "
            "این فیلد پرچم کالا/خدمت نیست."
        ),
        "action": "فاکتور را دوباره ارسال کنید؛ در نسخهٔ فعلی این فیلد فقط در صورت مقدار واقعی ارسال می‌شود.",
        "action_route": "invoice",
        "action_label": "ارسال مجدد",
        "severity": "error",
    },
    "0300101": {
        "title": "شماره مالیاتی صورتحساب با سامانه منطبق نیست",
        "explanation": (
            "taxid باید با شناسه حافظه، تاریخ صدور و سریال داخلی هم‌خوان باشد و تکراری نباشد."
        ),
        "action": "از ارسال مجدد همان فاکتور با taxid تکراری خودداری کنید؛ در صورت نیاز فاکتور اصلاحی بفرستید.",
        "action_route": "invoice",
        "action_label": "مشاهده فاکتور",
        "severity": "error",
    },
    "1301101": {
        "title": "شناسه ملی خریدار با سامانه منطبق نیست",
        "explanation": "کد ملی/شناسه خریدار در پایگاه سازمان مالیاتی یافت نشد یا نادرست است.",
        "action": "کد ملی طرف‌حساب را با مدارک هویتی تطبیق دهید و اصلاح کنید.",
        "action_route": "person",
        "action_label": "ویرایش طرف‌حساب",
        "severity": "warning",
    },
    "1301001": {
        "title": "نوع شخص خریدار نادرست است",
        "explanation": "مقدار tob باید با واقعیت طرف‌حساب یکی باشد: ۱ حقیقی، ۲ حقوقی.",
        "action": "نوع شخص طرف‌حساب (حقیقی/حقوقی) را در اطلاعات طرف‌حساب درست کنید.",
        "action_route": "person",
        "action_label": "ویرایش طرف‌حساب",
        "severity": "warning",
    },
    "4103": {
        "title": "عدم تطابق گواهی و کلید",
        "explanation": (
            "کد ملی گواهی امضا با شناسه کلاینت توکن یکی نیست. "
            "اگر قبلاً فقط با کلید خصوصی کار می‌کردید، گواهی نامرتبط را حذف کنید."
        ),
        "action": "به تنظیمات مودیان بروید و گواهی/کلید را هم‌تراز کنید.",
        "action_route": "tax_settings",
        "action_label": "تنظیمات مودیان",
        "severity": "error",
    },
    "PERSON_ECONOMIC_CODE_INVALID": {
        "title": "کد اقتصادی طرف‌حساب نامعتبر است",
        "explanation": "کد اقتصادی باید ۱۱ یا ۱۴ رقم باشد. مقادیر ۱۳ رقمی یا ناقص رد می‌شوند.",
        "action": "کد اقتصادی طرف‌حساب را اصلاح کنید.",
        "action_route": "person",
        "action_label": "ویرایش طرف‌حساب",
        "severity": "error",
    },
    "PERSON_TAX_ID_MISSING": {
        "title": "طرف‌حساب فاقد شناسه مالیاتی است",
        "explanation": "برای ارسال نوع اول، کد ملی یا کد اقتصادی خریدار لازم است.",
        "action": "اطلاعات هویتی طرف‌حساب را تکمیل کنید یا فاکتور مصرف‌کننده را به‌صورت نوع ۲ بفرستید.",
        "action_route": "person",
        "action_label": "ویرایش طرف‌حساب",
        "severity": "error",
    },
    "PERSON_NATIONAL_ID_INVALID": {
        "title": "کد ملی طرف‌حساب نامعتبر است",
        "explanation": "کد ملی باید ۱۰ رقم (حقیقی) یا شناسه ملی ۱۱ رقم (حقوقی) باشد.",
        "action": "کد ملی طرف‌حساب را اصلاح کنید.",
        "action_route": "person",
        "action_label": "ویرایش طرف‌حساب",
        "severity": "error",
    },
    "PRODUCT_TAX_CODE_MISSING": {
        "title": "کالای فاکتور فاقد کد مالیاتی است",
        "explanation": "هر ردیف باید شناسه ۱۳ رقمی کالا/خدمت مودیان داشته باشد.",
        "action": "از stuffid کد مالیاتی کالا را بگیرید و در تعریف کالا ثبت کنید.",
        "action_route": "product",
        "action_label": "ویرایش کالا",
        "severity": "error",
    },
    "PRODUCT_TAX_UNIT_MISSING": {
        "title": "واحد مالیاتی کالا تعریف نشده",
        "explanation": "برای ارسال به مودیان، واحد اندازه‌گیری مالیاتی کالا الزامی است.",
        "action": "واحد مالیاتی کالا را انتخاب کنید (ترجیحاً کد عددی مودیان).",
        "action_route": "product",
        "action_label": "ویرایش کالا",
        "severity": "error",
    },
    "TAX_SETTINGS_INCOMPLETE": {
        "title": "تنظیمات اتصال مودیان ناقص است",
        "explanation": "شناسه حافظه، کد اقتصادی فروشنده و کلید خصوصی برای ارسال لازم است.",
        "action": "تنظیمات مودیان را تکمیل و اتصال را تست کنید.",
        "action_route": "tax_settings",
        "action_label": "تنظیمات مودیان",
        "severity": "error",
    },
    "TAX_SETTINGS_NOT_CONFIGURED": {
        "title": "تنظیمات مودیان ثبت نشده است",
        "explanation": "هنوز اتصال این کسب‌وکار به سامانه مودیان پیکربندی نشده است.",
        "action": "از صفحه تنظیمات مودیان، اطلاعات حافظه مالیاتی و کلید را وارد کنید.",
        "action_route": "tax_settings",
        "action_label": "رفتن به تنظیمات",
        "severity": "error",
    },
    "TAX_NETWORK_ERROR": {
        "title": "خطا در ارتباط با سامانه مودیان",
        "explanation": "درخواست به سرور مالیاتی نرسیده یا پاسخ نگرفته است.",
        "action": "اتصال اینترنت و وضعیت سامانه را بررسی کنید و چند دقیقه بعد دوباره تلاش کنید.",
        "action_route": "tax_settings",
        "action_label": "تست اتصال",
        "severity": "error",
    },
}


def _normalize_code(code: Any) -> str:
    if code is None:
        return ""
    return str(code).strip().upper()


def get_error_playbook(code: Any, message: Any = None) -> Dict[str, Any]:
    """برگرداندن playbook برای یک کد خطا."""
    raw_code = _normalize_code(code)
    msg = str(message or "").strip()

    entry = _PLAYBOOK.get(raw_code)
    # تطبیق پیشوندی برای کدهای ۷ رقمی مشابه (0200201 vs 02002)
    if not entry and raw_code:
        for key, val in _PLAYBOOK.items():
            if raw_code.startswith(key) or key.startswith(raw_code):
                entry = val
                break

    if entry:
        return {
            "code": raw_code or None,
            "message": msg or entry["title"],
            "title": entry["title"],
            "explanation": entry["explanation"],
            "action": entry["action"],
            "action_route": entry["action_route"],
            "action_label": entry["action_label"],
            "severity": entry["severity"],
        }

    # پیام عمومی ولی ساخت‌یافته
    title = "خطای سامانه مودیان"
    explanation = msg or "جزئیات بیشتری از سامانه دریافت نشده است."
    action = "جزئیات فنی را بررسی کنید؛ در صورت تکرار، تنظیمات اتصال و داده فاکتور را کنترل کنید."
    route = "invoice"
    label = "مشاهده فاکتور"
    severity = "error"

    lower = msg.lower()
    if "نرخ" in msg and "مالیات" in msg:
        route, label = "product", "ویرایش کالا"
    elif "تاریخ" in msg:
        route, label = "invoice", "ویرایش فاکتور"
    elif "خریدار" in msg or "اقتصادی" in msg or "ملی" in msg:
        route, label = "person", "ویرایش طرف‌حساب"
    elif "واحد" in msg:
        route, label = "product", "ویرایش کالا"
    elif "اتصال" in msg or "شبکه" in msg or "token" in lower:
        route, label = "tax_settings", "تنظیمات مودیان"

    return {
        "code": raw_code or None,
        "message": msg or title,
        "title": title,
        "explanation": explanation,
        "action": action,
        "action_route": route,
        "action_label": label,
        "severity": severity,
    }


def enrich_moadian_errors(errors: List[Dict[str, Any]] | None) -> List[Dict[str, Any]]:
    """لیست خطاها را با playbook غنی می‌کند."""
    if not errors:
        return []
    out: List[Dict[str, Any]] = []
    for item in errors:
        if not isinstance(item, dict):
            continue
        playbook = get_error_playbook(item.get("code"), item.get("message"))
        merged = {**playbook, **{k: v for k, v in item.items() if v is not None}}
        # playbook fields win for title/explanation/action if missing in item
        for key in ("title", "explanation", "action", "action_route", "action_label", "severity"):
            if not merged.get(key):
                merged[key] = playbook.get(key)
        out.append(merged)
    return out
