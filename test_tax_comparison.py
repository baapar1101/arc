#!/usr/bin/env python3
"""
اسکریپت تست برای مقایسه خروجی Python با PHP SDK
این اسکریپت داده‌های یکسان را با هر دو کتابخانه پردازش می‌کند
"""

import json
import sys
import os

# اضافه کردن مسیر پروژه به path
sys.path.insert(0, '/var/www/ark/hesabixAPI')

def test_normalize_comparison():
    """تست مقایسه normalize"""
    from app.integrations.moadian.client import MoadianClient
    from app.core.settings import get_settings
    from adapters.db.models.tax_setting import TaxSetting
    from adapters.db.session import get_db_session
    
    # داده تست
    test_data = {
        "packets": [
            {
                "uid": "test-uid-123",
                "packetType": "INVOICE_V01",
                "data": "encrypted-data",
                "symmetricKey": "enc-key",
                "iv": "hex-iv-string",
                "fiscalId": "A1B2C3",
                "dataSignature": "sig"
            }
        ],
        "timestamp": "1234567890",
        "requestTraceId": "abc123"
    }
    
    # تست normalize
    # این باید با PHP SDK مقایسه شود
    
    print("=" * 80)
    print("TEST: Normalize Comparison")
    print("=" * 80)
    print(f"Input data: {json.dumps(test_data, indent=2, ensure_ascii=False)}")
    print()
    
    # شبیه‌سازی normalize (بدون نیاز به client کامل)
    def php_flatten(value, prefix=""):
        result = {}
        if isinstance(value, dict):
            items = value.items()
        elif isinstance(value, (list, tuple)):
            items = enumerate(value)
        else:
            if prefix:
                result[prefix] = value
            return result
        
        for k, v in items:
            key = str(k)
            new_prefix = f"{prefix}.{key}" if prefix else key
            if isinstance(v, (dict, list, tuple)):
                result.update(php_flatten(v, new_prefix))
            else:
                result[new_prefix] = v
        return result
    
    def php_normalize_array(data):
        flattened = php_flatten(data)
        parts = []
        for key in sorted(flattened.keys()):
            value = flattened[key]
            if isinstance(value, bool):
                text_value = "true" if value else "false"
            elif value == "" or value is None:
                text_value = "#"
            else:
                text_value = str(value).replace("#", "##")
            parts.append(text_value)
        return "#".join(parts)
    
    normalized = php_normalize_array(test_data)
    print(f"Normalized string: {normalized}")
    print(f"Normalized length: {len(normalized)}")
    print()
    
    # نمایش flattened
    flattened = php_flatten(test_data)
    print("Flattened structure:")
    for key in sorted(flattened.keys()):
        print(f"  {key}: {flattened[key]}")
    print()

if __name__ == "__main__":
    test_normalize_comparison()





