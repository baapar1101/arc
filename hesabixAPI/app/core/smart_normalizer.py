"""
Smart Number Normalizer
تبدیل هوشمند اعداد فارسی/عربی/هندی به انگلیسی
"""

import json
import re
import logging
from typing import Any, Dict, List, Union, Optional

logger = logging.getLogger(__name__)


class SmartNormalizerConfig:
    """تنظیمات سیستم تبدیل هوشمند"""
    
    # فیلدهایی که نباید تبدیل شوند
    EXCLUDE_FIELDS = {'password', 'token', 'hash', 'secret', 'key'}
    
    # الگوهای خاص برای شناسایی انواع مختلف
    SPECIAL_PATTERNS = {
        'mobile': r'۰۹۱[۰-۹]+',
        'email': r'[۰-۹]+@',
        'code': r'[A-Za-z]+[۰-۹]+',
        'phone': r'[۰-۹]+-[۰-۹]+',
    }
    
    # فعال/غیرفعال کردن
    ENABLED = True
    LOG_CHANGES = True


def smart_normalize_numbers(text: str) -> str:
    """
    تبدیل هوشمند اعداد فارسی/عربی/هندی به انگلیسی
    فقط اعداد را تبدیل می‌کند، متن باقی می‌ماند
    """
    if not text or not isinstance(text, str):
        return text
    
    # جدول تبدیل اعداد
    number_mapping = {
        # فارسی
        '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
        '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
        # عربی
        '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
        '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
        # هندی/بنگالی
        '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4',
        '৫': '5', '৬': '6', '৭': '7', '৮': '8', '৯': '9',
        # هندی (دیگر)
        '०': '0', '१': '1', '२': '2', '३': '3', '४': '4',
        '५': '5', '६': '6', '७': '7', '८': '8', '९': '9'
    }
    
    result = ""
    for char in text:
        result += number_mapping.get(char, char)
    
    return result


def smart_normalize_text(text: str) -> str:
    """
    تبدیل هوشمند برای متن‌های پیچیده
    """
    if not text or not isinstance(text, str):
        return text
    
    # شناسایی الگوهای مختلف
    patterns = [
        # شماره موبایل: ۰۹۱۲۳۴۵۶۷۸۹
        (r'۰۹۱[۰-۹]+', lambda m: smart_normalize_numbers(m.group())),
        # کدهای ترکیبی: ABC-۱۲۳۴
        (r'[A-Za-z]+[۰-۹]+', lambda m: smart_normalize_numbers(m.group())),
        # اعداد خالص
        (r'[۰-۹]+', lambda m: smart_normalize_numbers(m.group())),
    ]
    
    result = text
    for pattern, replacement in patterns:
        result = re.sub(pattern, replacement, result)
    
    return result


def smart_normalize_recursive(obj: Any, exclude_fields: Optional[set] = None) -> Any:
    """
    تبدیل recursive در ساختارهای پیچیده
    """
    if exclude_fields is None:
        exclude_fields = SmartNormalizerConfig.EXCLUDE_FIELDS
    
    if isinstance(obj, str):
        return smart_normalize_text(obj)
    
    elif isinstance(obj, dict):
        result = {}
        for key, value in obj.items():
            # اگر فیلد در لیست مستثنیات است، تبدیل نکن
            if key.lower() in exclude_fields:
                result[key] = value
            else:
                result[key] = smart_normalize_recursive(value, exclude_fields)
        return result
    
    elif isinstance(obj, list):
        return [smart_normalize_recursive(item, exclude_fields) for item in obj]
    
    else:
        return obj


def smart_normalize_json(data: bytes) -> bytes:
    """
    تبدیل هوشمند اعداد در JSON
    """
    if not data:
        return data
    
    try:
        # تبدیل bytes به dict
        json_data = json.loads(data.decode('utf-8'))
        
        # تبدیل recursive
        normalized_data = smart_normalize_recursive(json_data)
        
        # تبدیل به bytes
        normalized_bytes = json.dumps(normalized_data, ensure_ascii=False).encode('utf-8')
        
        # لاگ تغییرات
        if SmartNormalizerConfig.LOG_CHANGES and normalized_bytes != data:
            logger.info("Numbers normalized in JSON request")
        
        return normalized_bytes
    
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        # اگر JSON نیست، به صورت متن تبدیل کن
        try:
            text = data.decode('utf-8', errors='ignore')
            normalized_text = smart_normalize_text(text)
            normalized_bytes = normalized_text.encode('utf-8')
            
            if SmartNormalizerConfig.LOG_CHANGES and normalized_bytes != data:
                logger.info("Numbers normalized in text request")
            
            return normalized_bytes
        except Exception:
            logger.warning(f"Failed to normalize request data: {e}")
            return data


def smart_normalize_query_params(params: Dict[str, Any]) -> Dict[str, Any]:
    """
    تبدیل هوشمند اعداد در query parameters
    """
    if not params:
        return params
    
    normalized_params = {}
    for key, value in params.items():
        if isinstance(value, str):
            normalized_params[key] = smart_normalize_text(value)
        else:
            normalized_params[key] = smart_normalize_recursive(value)
    
    return normalized_params


def is_number_normalization_needed(text: str) -> bool:
    """
    بررسی اینکه آیا متن نیاز به تبدیل اعداد دارد یا نه
    """
    if not text or not isinstance(text, str):
        return False
    
    # بررسی وجود اعداد فارسی/عربی/هندی
    persian_arabic_numbers = '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩০১২৩৪৫৬৭৮৯०१२३४५६७८९'
    return any(char in persian_arabic_numbers for char in text)


def get_normalization_stats(data: bytes) -> Dict[str, int]:
    """
    آمار تبدیل اعداد
    """
    try:
        text = data.decode('utf-8', errors='ignore')
        persian_arabic_numbers = '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩০১২৩৪৫৬৭৮৯०१२३४५६७८९'
        
        total_chars = len(text)
        persian_numbers = sum(1 for char in text if char in persian_arabic_numbers)
        
        return {
            'total_chars': total_chars,
            'persian_numbers': persian_numbers,
            'normalization_ratio': persian_numbers / total_chars if total_chars > 0 else 0
        }
    except Exception:
        return {'total_chars': 0, 'persian_numbers': 0, 'normalization_ratio': 0}
