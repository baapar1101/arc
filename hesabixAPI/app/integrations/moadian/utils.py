"""
توابع کمکی برای کار با سامانه مودیان مالیاتی
"""
from __future__ import annotations

import hashlib
import re
from datetime import date, datetime
from typing import Optional, Union

DateLike = Union[datetime, date, str, None]


def coerce_to_datetime(value: DateLike) -> datetime:
    """تبدیل date/datetime/رشته ISO به datetime برای توابعی که به timestamp نیاز دارند."""
    if value is None:
        return datetime.utcnow()
    if isinstance(value, datetime):
        return value
    if isinstance(value, date):
        return datetime.combine(value, datetime.min.time())
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if isinstance(parsed, datetime):
                return parsed
            return datetime.combine(parsed, datetime.min.time())
        except (TypeError, ValueError):
            return datetime.utcnow()
    return datetime.utcnow()


def generate_tax_id(client_id: str, timestamp: DateLike, internal_id: int) -> str:
    """
    تولید شناسه یکتای مالیاتی (TAXID)
    مطابق الگوریتم InvoiceIdService در کتابخانه PHP:
    - clientId (tax_memory_id) + hexDaysPastEpoch (5 hex) + hexInternalInvoiceId (10 hex) + checksum
    
    Args:
        client_id: شناسه حافظه مالیاتی (tax_memory_id)
        timestamp: زمان صدور فاکتور
        internal_id: شناسه داخلی فاکتور
    
    Returns:
        شناسه یکتای مالیاتی (مثلا: A1B2C3000010000000001)
    """
    timestamp = coerce_to_datetime(timestamp)
    from app.integrations.moadian.verhoeff import verhoeff_checksum
    
    # تبدیل clientId به عدد (مطابق clientIdToNumber در PHP)
    def client_id_to_number(client_id: str) -> str:
        """تبدیل clientId به عدد - حروف به ASCII code"""
        CHARACTER_TO_NUMBER_CODING = {
            'A': 65, 'B': 66, 'C': 67, 'D': 68, 'E': 69, 'F': 70,
            'G': 71, 'H': 72, 'I': 73, 'J': 74, 'K': 75, 'L': 76,
            'M': 77, 'N': 78, 'O': 79, 'P': 80, 'Q': 81, 'R': 82,
            'S': 83, 'T': 84, 'U': 85, 'V': 86, 'W': 87, 'X': 88,
            'Y': 89, 'Z': 90,
        }
        result = ""
        for char in client_id:
            if char.isdigit():
                result += char
            elif char.upper() in CHARACTER_TO_NUMBER_CODING:
                result += str(CHARACTER_TO_NUMBER_CODING[char.upper()])
        return result
    
    # محاسبه days past epoch
    days_past_epoch = int(timestamp.timestamp() / (3600 * 24))
    days_past_epoch_padded = str(days_past_epoch).zfill(6)
    hex_days_past_epoch = hex(days_past_epoch)[2:].zfill(5).upper()
    
    # تبدیل clientId به عدد
    numeric_client_id = client_id_to_number(client_id)
    
    # internal invoice ID
    internal_id_padded = str(internal_id).zfill(12)
    hex_internal_id = hex(internal_id)[2:].zfill(10).upper()
    
    # ساخت decimal invoice ID برای checksum
    decimal_invoice_id = numeric_client_id + days_past_epoch_padded + internal_id_padded
    
    # محاسبه checksum با Verhoeff algorithm
    checksum = verhoeff_checksum(decimal_invoice_id)
    
    # ساخت شناسه نهایی: clientId + hexDays + hexInternalId + checksum
    tax_id = client_id.upper() + hex_days_past_epoch + hex_internal_id + str(checksum)
    
    return tax_id


def normalize_invoice_number(invoice_number: str | int, max_length: int = 20) -> str:
    """
    نرمالایز کردن شماره فاکتور برای ارسال به سامانه
    مطابق کتابخانه PHP: str_pad(dechex($internalInvoiceId), 10, 0, STR_PAD_LEFT)
    
    Args:
        invoice_number: شماره فاکتور (باید عدد باشد)
        max_length: حداکثر طول مجاز (پیش‌فرض 10 برای hex)
    
    Returns:
        شماره نرمال شده به hex با padding
    """
    # تبدیل به عدد صحیح
    try:
        if isinstance(invoice_number, str):
            # حذف کاراکترهای غیرعددی
            num_str = re.sub(r'[^0-9]', '', invoice_number)
            if not num_str:
                num_str = "0"
            internal_id = int(num_str)
        else:
            internal_id = int(invoice_number)
    except (ValueError, TypeError):
        internal_id = 0
    
    # تبدیل به hex و padding به 10 کاراکتر (مطابق کتابخانه PHP)
    hex_value = hex(internal_id)[2:]  # حذف '0x'
    normalized = hex_value.zfill(10).upper()  # padding به 10 کاراکتر و uppercase
    
    return normalized


def timestamp_to_unix_ms(dt: DateLike) -> int:
    """
    تبدیل datetime به Unix timestamp به milliseconds
    
    Args:
        dt: تاریخ و زمان
    
    Returns:
        Unix timestamp (milliseconds)
    """
    return int(coerce_to_datetime(dt).timestamp() * 1000)


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
    تبدیل درصد مالیات به فرمت سامانه مودیان (درصد × ۱۰۰، مثلاً ۹٪ → ۹۰۰).

    ورودی می‌تواند به‌صورت «۹» (۹٪) یا «۰.۰۹» (کسر اعشاری نمایندهٔ ۹٪) باشد.
    """
    try:
        tf = float(tax_percentage)
    except (TypeError, ValueError):
        return 0
    if tf <= 0:
        return 0
    # فقط اعداد کسر واقعی (مثلاً ۰.۰۹ برای ۹٪)؛ مقدار ۱ به‌عنوان ۱٪ حفظ می‌شود
    if 0 < tf < 1.0:
        tf = tf * 100.0
    return int(round(tf * 100.0))


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
    روش تسویه (setm) در هدر صورت‌حساب مودیان.

    مطابق الگوی رایج SDKها و moadian-full:
    - 1: نقدی
    - 2: نسیه
    - 3: نقد و نسیه
    """
    if is_cash and is_credit:
        return 3
    elif is_credit:
        return 2
    else:
        return 1


def map_invoice_pattern(
    is_return: bool = False,
    is_cancel: bool = False,
    is_corrective: bool = False,
) -> int:
    """
    الگوی صورت‌حساب (inp): فروش / برگشت / ابطال / اصلاح.

    - 1: فروش
    - 2: برگشت از فروش
    - 3: ابطال
    - 4: اصلاحی
    """
    if is_corrective:
        return 4
    if is_cancel:
        return 3
    if is_return:
        return 2
    return 1


def map_invoice_subject_for_inp(inp: int, document_type: str = "") -> int:
    """موضوع صورتحساب (ins) هم‌راستا با الگوی inp."""
    if inp == 3:
        return 3
    if inp == 4:
        return 4
    if inp == 2:
        return 5
    return map_invoice_subject(document_type)


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
    
    # نقشه کدهای خطا به پیام فارسی (بر اساس مستندات سامانه مودیان)
    error_map = {
        # خطاهای احراز هویت و تنظیمات
        'TAX-101': 'شناسه حافظه مالیاتی نامعتبر است',
        'TAX-102': 'کد اقتصادی نامعتبر است',
        'TAX-103': 'کلید خصوصی نامعتبر است',
        'TAX-104': 'امضای دیجیتال نامعتبر است',
        'AUTH-001': 'خطا در احراز هویت',
        'AUTH-002': 'توکن منقضی شده است',
        'AUTH-003': 'دسترسی غیرمجاز',
        'AUTH-004': 'شناسه حافظه مالیاتی یافت نشد',
        '4103': 'کد ملی گواهی امضا با شناسه کلاینت توکن مطابقت ندارد',
        
        # خطاهای اعتبارسنجی فاکتور
        'TAX-201': 'فاکتور تکراری است',
        'TAX-202': 'شماره فاکتور نامعتبر است',
        'TAX-203': 'تاریخ فاکتور نامعتبر است',
        'TAX-204': 'نوع فاکتور نامعتبر است',
        'TAX-205': 'الگوی پرداخت نامعتبر است',
        'TAX-206': 'موضوع فاکتور نامعتبر است',
        
        # خطاهای اقلام فاکتور
        'TAX-301': 'کد مالیاتی کالا نامعتبر است',
        'TAX-302': 'کد ملی خریدار نامعتبر است',
        'TAX-303': 'مبلغ فاکتور نامعتبر است',
        'TAX-304': 'واحد اندازه‌گیری نامعتبر است',
        'TAX-305': 'تعداد/مقدار کالا نامعتبر است',
        'TAX-306': 'نرخ مالیات نامعتبر است',
        'TAX-307': 'مبلغ مالیات نامعتبر است',
        
        # خطاهای شبکه و ارتباط
        'TAX-401': 'خطا در اتصال به سرور',
        'TAX-402': 'زمان انتظار پاسخ تمام شد',
        'TAX-403': 'سرور در دسترس نیست',
        'TAX-404': 'مسیر درخواست یافت نشد',
        
        # خطاهای پردازش
        'TAX-501': 'خطا در پردازش درخواست',
        'TAX-502': 'داده‌های ارسالی ناقص است',
        'TAX-503': 'سرویس موقتاً در دسترس نیست',
        
        # خطاهای عمومی
        'TAX-999': 'خطای نامشخص از سامانه مودیان',
    }
    
    # استخراج error_code و error_message از error_data
    error_code = ''
    error_message = ''
    
    if isinstance(error_data, dict):
        error_code = error_data.get('code', '') or error_data.get('errorCode', '')
        error_message = error_data.get('message', '') or error_data.get('errorMessage', '') or error_data.get('detail', '')
    elif isinstance(error_data, str):
        error_message = error_data
    
    # نرمالایز کردن error_code
    if error_code:
        error_code = str(error_code).strip().upper()
    
    # اگر کد خطا در نقشه بود
    if error_code and error_code in error_map:
        mapped_message = error_map[error_code]
        if error_message and error_message != mapped_message:
            return f"{mapped_message}: {error_message} ({error_code})"
        return f"{mapped_message} ({error_code})"
    
    # اگر پیام خطا موجود بود
    if error_message:
        error_message_str = str(error_message).strip()
        if error_code:
            return f"{error_message_str} ({error_code})"
        return error_message_str
    
    # در غیر این صورت کد خطا را نمایش می‌دهیم
    if error_code:
        return f"خطا: {error_code}"
    
    return "خطای نامشخص از سامانه مودیان"




