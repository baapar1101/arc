"""User-facing error messages for legacy import validation failures."""

from __future__ import annotations

from typing import Any

from pydantic import ValidationError

# نام فارسی فیلدهای رایج در انتقال کسب‌وکار / اشخاص
_FIELD_LABELS_FA: dict[str, str] = {
    "name": "نام کسب‌وکار",
    "business_type": "نوع کسب‌وکار",
    "business_field": "زمینه فعالیت",
    "address": "آدرس",
    "phone": "تلفن ثابت",
    "mobile": "موبایل",
    "national_id": "کد ملی / شناسه ملی",
    "registration_number": "شماره ثبت",
    "economic_id": "شناسه اقتصادی",
    "country": "کشور",
    "province": "استان",
    "city": "شهر",
    "postal_code": "کد پستی",
    "default_currency_id": "ارز پیش‌فرض",
    "first_name": "نام",
    "last_name": "نام خانوادگی",
    "company_name": "نام شرکت",
    "email": "ایمیل",
}


def _field_label(field: str | None) -> str:
    if not field:
        return "یکی از فیلدها"
    return _FIELD_LABELS_FA.get(field, field)


def _short_preview(value: Any, *, limit: int = 80) -> str:
    text = str(value).replace("\n", " ").strip()
    if len(text) <= limit:
        return text
    return f"{text[: limit - 1]}…"


def _describe_error(err: dict[str, Any]) -> str:
    loc = err.get("loc") or ()
    field = None
    for part in loc:
        if isinstance(part, str) and part not in ("body", "query", "path"):
            field = part
            break
    label = _field_label(field)
    type_ = err.get("type") or ""
    ctx = err.get("ctx") or {}
    input_value = err.get("input")

    if type_ == "string_too_long":
        max_len = ctx.get("max_length")
        length = len(str(input_value)) if input_value is not None else None
        parts = [
            f"فیلد «{label}» در داده‌های نسخه قدیم بیش از حد مجاز طولانی است"
        ]
        if max_len is not None and length is not None:
            parts.append(f"(حداکثر {max_len} کاراکتر؛ طول فعلی {length})")
        elif max_len is not None:
            parts.append(f"(حداکثر {max_len} کاراکتر)")
        if input_value is not None:
            parts.append(f"مقدار: «{_short_preview(input_value)}»")
        if field == "economic_id":
            parts.append(
                "این مقدار شبیه متن توضیحی است، نه شناسه اقتصادی. "
                "لطفاً در حسابیکس قبلی فیلد «کد اقتصادی» را اصلاح کنید و دوباره تلاش کنید."
            )
        else:
            parts.append(
                "لطفاً این فیلد را در حسابیکس قبلی کوتاه یا اصلاح کنید و دوباره تلاش کنید."
            )
        return " ".join(parts)

    if type_ == "string_too_short":
        min_len = ctx.get("min_length")
        detail = f" (حداقل {min_len} کاراکتر)" if min_len is not None else ""
        return (
            f"فیلد «{label}» در داده‌های نسخه قدیم کوتاه‌تر از حد مجاز است{detail}. "
            "لطفاً آن را در حسابیکس قبلی تکمیل کنید و دوباره تلاش کنید."
        )

    if type_ in {"missing", "value_error.missing"}:
        return (
            f"فیلد الزامی «{label}» در داده‌های نسخه قدیم موجود نیست. "
            "لطفاً اطلاعات کسب‌وکار را در حسابیکس قبلی تکمیل کنید و دوباره تلاش کنید."
        )

    msg = str(err.get("msg") or "مقدار نامعتبر")
    preview = f" مقدار: «{_short_preview(input_value)}»." if input_value is not None else ""
    return (
        f"فیلد «{label}» در داده‌های نسخه قدیم نامعتبر است ({msg}).{preview} "
        "لطفاً آن را در حسابیکس قبلی اصلاح کنید و دوباره تلاش کنید."
    )


def format_legacy_validation_error(
    exc: ValidationError,
    *,
    stage: str = "ایجاد کسب‌وکار",
) -> str:
    """پیام فارسی واضح برای خطای اعتبارسنجی هنگام انتقال از نسخه قدیم."""
    errors = list(exc.errors())
    if not errors:
        return (
            f"خطا در {stage} از داده‌های نسخه قدیم: داده‌ها نامعتبر هستند. "
            "لطفاً اطلاعات را در حسابیکس قبلی بررسی کنید."
        )
    details = [_describe_error(e) for e in errors[:5]]
    header = f"خطا در {stage} از داده‌های نسخه قدیم:"
    if len(details) == 1:
        return f"{header} {details[0]}"
    numbered = "\n".join(f"{i}. {d}" for i, d in enumerate(details, 1))
    return f"{header}\n{numbered}"


def format_legacy_import_exception(exc: BaseException) -> str:
    """استخراج پیام قابل‌نمایش برای کاربر از هر خطای انتقال."""
    from app.core.responses import ApiError

    if isinstance(exc, ValidationError):
        return format_legacy_validation_error(exc)

    if isinstance(exc, ApiError) and isinstance(exc.detail, dict):
        err = exc.detail.get("error", exc.detail)
        if isinstance(err, dict):
            message = err.get("message")
            if isinstance(message, str) and message.strip():
                return message.strip()

    text = str(exc).strip()
    if text:
        return text
    return "انتقال از نسخه قدیم با خطای ناشناخته متوقف شد."
