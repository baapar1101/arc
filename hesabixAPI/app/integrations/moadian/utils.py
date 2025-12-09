"""
توابع کمکی برای کار با سامانه مودیان مالیاتی
"""
from __future__ import annotations

import hashlib
import re
from datetime import datetime
from typing import Optional


def generate_tax_id(economic_code: str, timestamp: datetime, internal_id: int) -> str:
    """
    تولید شناسه یکتای مالیاتی (TAXID)
    الگوریتم: کد اقتصادی + timestamp + شماره داخلی را hash می‌کنیم
    
    Args:
        economic_code: کد اقتصادی فروشنده
        timestamp: زمان صدور فاکتور
        internal_id: شناسه داخلی فاکتور
    
    Returns:
        شناسه یکتای 32 کاراکتری hexadecimal
    """
    # فرمت: کد_اقتصادی + timestamp + شماره_فاکتور
    ts_unix = int(timestamp.timestamp() * 1000)  # milliseconds
    raw_string = f"{economic_code}{ts_unix}{internal_id}"
    
    # SHA256 hash و برداشتن 32 کاراکتر اول
    hash_object = hashlib.sha256(raw_string.encode('utf-8'))
    return hash_object.hexdigest()[:32].upper()


def normalize_invoice_number(invoice_number: str | int, max_length: int = 20) -> str:
    """
    نرمالایز کردن شماره فاکتور برای ارسال به سامانه
    - حذف کاراکترهای غیرمجاز
    - محدود کردن طول
    - اضافه کردن صفر در ابتدا در صورت نیاز
    
    Args:
        invoice_number: شماره فاکتور
        max_length: حداکثر طول مجاز
    
    Returns:
        شماره نرمال شده
    """
    # تبدیل به string
    num_str = str(invoice_number)
    
    # حذف کاراکترهای غیرعددی و غیرحرفی
    normalized = re.sub(r'[^A-Za-z0-9]', '', num_str)
    
    # محدود کردن طول
    if len(normalized) > max_length:
        normalized = normalized[-max_length:]
    
    # اگر کوتاه‌تر از حد مطلوب بود، صفر اضافه می‌کنیم
    if len(normalized) < max_length and normalized.isdigit():
        normalized = normalized.zfill(max_length)
    
    return normalized.upper()


def timestamp_to_unix_ms(dt: datetime) -> int:
    """
    تبدیل datetime به Unix timestamp به milliseconds
    
    Args:
        dt: تاریخ و زمان
    
    Returns:
        Unix timestamp (milliseconds)
    """
    return int(dt.timestamp() * 1000)


def datetime_to_moadian_format(dt: datetime) -> int:
    """
    تبدیل datetime به فرمت عددی سامانه مودیان (yyyyMMdd)
    
    Args:
        dt: تاریخ و زمان
    
    Returns:
        عدد 8 رقمی (مثلا 20250105)
    """
    return int(dt.strftime('%Y%m%d'))


def calculate_vat_rate(tax_percentage: float) -> int:
    """
    تبدیل درصد مالیات به فرمت سامانه مودیان
    سامانه نرخ را × 100 می‌خواهد (مثلا 9% = 900)
    
    Args:
        tax_percentage: درصد مالیات (مثلا 9.0)
    
    Returns:
        نرخ × 100 (مثلا 900)
    """
    return int(tax_percentage * 100)


def validate_economic_code(code: Optional[str]) -> bool:
    """
    اعتبارسنجی کد اقتصادی
    باید 11 یا 14 رقم باشد
    
    Args:
        code: کد اقتصادی
    
    Returns:
        True اگر معتبر باشد
    """
    if not code:
        return False
    
    # حذف فاصله و خط تیره
    clean = re.sub(r'[\s\-]', '', code)
    
    # باید فقط عدد باشد
    if not clean.isdigit():
        return False
    
    # طول باید 11 یا 14 رقم باشد
    return len(clean) in (11, 14)


def validate_national_id(national_id: Optional[str]) -> tuple[bool, Optional[str]]:
    """
    اعتبارسنجی کد ملی / شناسه ملی
    - کد ملی اشخاص حقیقی: 10 رقم
    - شناسه ملی اشخاص حقوقی: 11 رقم
    
    Args:
        national_id: کد/شناسه ملی
    
    Returns:
        (معتبر است؟, نوع شخص: 'natural' یا 'legal')
    """
    if not national_id:
        return False, None
    
    # حذف فاصله و خط تیره
    clean = re.sub(r'[\s\-]', '', national_id)
    
    # باید فقط عدد باشد
    if not clean.isdigit():
        return False, None
    
    length = len(clean)
    
    if length == 10:
        return True, 'natural'  # اشخاص حقیقی
    elif length == 11:
        return True, 'legal'  # اشخاص حقوقی
    else:
        return False, None


def validate_tax_code(tax_code: Optional[str]) -> bool:
    """
    اعتبارسنجی کد مالیاتی کالا
    باید 13 رقم باشد
    
    Args:
        tax_code: کد مالیاتی
    
    Returns:
        True اگر معتبر باشد
    """
    if not tax_code:
        return False
    
    # حذف فاصله و خط تیره
    clean = re.sub(r'[\s\-]', '', tax_code)
    
    # باید فقط عدد باشد
    if not clean.isdigit():
        return False
    
    # باید دقیقا 13 رقم باشد
    return len(clean) == 13


def round_to_int(value: float | int | None) -> int:
    """
    گرد کردن و تبدیل به عدد صحیح (سامانه اعشار قبول نمی‌کند)
    
    Args:
        value: مقدار
    
    Returns:
        عدد صحیح گرد شده
    """
    if value is None:
        return 0
    
    try:
        return int(round(float(value)))
    except (ValueError, TypeError):
        return 0


def map_invoice_type_to_moadian(document_type: str, is_return: bool = False) -> int:
    """
    تبدیل نوع فاکتور داخلی به کد سامانه مودیان
    
    Args:
        document_type: نوع سند داخلی
        is_return: آیا فاکتور برگشتی است؟
    
    Returns:
        کد نوع فاکتور:
        - 1: فاکتور عادی
        - 2: فاکتور ساده
        - 3: فاکتور ابطالی
    """
    # اگر برگشتی باشد، نوع ابطالی
    if is_return:
        return 3
    
    # اگر خریدار دارای کد ملی و اقتصادی باشد، نوع عادی
    # این منطق باید در service بررسی شود
    # پیش‌فرض: ساده
    return 2


def map_payment_pattern(is_cash: bool = True, is_credit: bool = False) -> int:
    """
    تبدیل الگوی پرداخت به کد سامانه
    
    Args:
        is_cash: آیا نقدی است؟
        is_credit: آیا نسیه است؟
    
    Returns:
        کد الگوی پرداخت:
        - 1: نقدی
        - 2: نسیه
        - 3: نقدی/نسیه
    """
    if is_cash and is_credit:
        return 3
    elif is_credit:
        return 2
    else:
        return 1


def map_invoice_subject(document_type: str) -> int:
    """
    تبدیل نوع سند به موضوع فاکتور
    
    Args:
        document_type: نوع سند
    
    Returns:
        کد موضوع:
        - 1: فروش
        - 2: فروش ارزی
        - 3: خرید
        - 4: خرید ارزی
        - 5: برگشت از فروش
        - 6: برگشت از خرید
    """
    type_lower = document_type.lower()
    
    if 'sales' in type_lower or 'invoice_sales' in type_lower:
        return 1  # فروش
    elif 'return' in type_lower or 'sales_return' in type_lower:
        return 5  # برگشت از فروش
    elif 'purchase' in type_lower:
        return 3  # خرید
    else:
        return 1  # پیش‌فرض: فروش


def extract_moadian_error_message(error_data: dict) -> str:
    """
    استخراج پیام خطا از پاسخ سامانه مودیان
    
    Args:
        error_data: داده خطا از API
    
    Returns:
        پیام خطای فارسی
    """
    if not error_data:
        return "خطای نامشخص"
    
    # نقشه کدهای خطا به پیام فارسی
    error_map = {
        'TAX-101': 'شناسه حافظه مالیاتی نامعتبر است',
        'TAX-102': 'کد اقتصادی نامعتبر است',
        'TAX-103': 'کلید خصوصی نامعتبر است',
        'TAX-104': 'امضای دیجیتال نامعتبر است',
        'TAX-201': 'فاکتور تکراری است',
        'TAX-202': 'شماره فاکتور نامعتبر است',
        'TAX-203': 'تاریخ فاکتور نامعتبر است',
        'TAX-301': 'کد مالیاتی کالا نامعتبر است',
        'TAX-302': 'کد ملی خریدار نامعتبر است',
        'TAX-303': 'مبلغ فاکتور نامعتبر است',
        'TAX-401': 'خطا در اتصال به سرور',
        'TAX-402': 'زمان انتظار پاسخ تمام شد',
        'AUTH-001': 'خطا در احراز هویت',
        'AUTH-002': 'توکن منقضی شده است',
    }
    
    error_code = error_data.get('code', '')
    error_message = error_data.get('message', '')
    
    # اگر کد خطا در نقشه بود
    if error_code in error_map:
        return f"{error_map[error_code]} ({error_code})"
    
    # اگر پیام خطا موجود بود
    if error_message:
        return error_message
    
    # در غیر این صورت کد خطا را نمایش می‌دهیم
    return f"خطا: {error_code}" if error_code else "خطای نامشخص"




