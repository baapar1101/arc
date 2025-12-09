#!/usr/bin/env python3
"""
اسکریپت استخراج و صادرات ترجمه‌های ورک‌فلو
این اسکریپت رشته‌های قابل ترجمه را از نودهای ورک‌فلو استخراج و به فرمت مناسب صادر می‌کند
"""
import sys
import os
import json
from pathlib import Path

# افزودن مسیر پروژه
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.services.workflow.i18n import (
    COMMON_TRANSLATIONS,
    CREATE_INVOICE_TRANSLATIONS,
    SEND_TELEGRAM_TRANSLATIONS,
    SEND_EMAIL_TRANSLATIONS,
    OTHER_ACTIONS_TRANSLATIONS,
)


def export_to_arb(lang: str = "fa") -> dict:
    """صادرات ترجمه‌ها به فرمت arb"""
    arb = {}
    
    # مشترک
    for key, value in COMMON_TRANSLATIONS.get(lang, {}).items():
        arb[f"workflow{_to_camel_case(key)}"] = value
    
    # Create Invoice
    for key, value in CREATE_INVOICE_TRANSLATIONS.get(lang, {}).items():
        arb[f"workflowCreateInvoice{_to_camel_case(key)}"] = value
    
    # Send Telegram
    for key, value in SEND_TELEGRAM_TRANSLATIONS.get(lang, {}).items():
        arb[f"workflowSendTelegram{_to_camel_case(key)}"] = value
    
    # Send Email
    for key, value in SEND_EMAIL_TRANSLATIONS.get(lang, {}).items():
        arb[f"workflowSendEmail{_to_camel_case(key)}"] = value
    
    # Others
    for key, value in OTHER_ACTIONS_TRANSLATIONS.get(lang, {}).items():
        arb[f"workflowOthers{_to_camel_case(key)}"] = value
    
    return arb


def _to_camel_case(snake_str: str) -> str:
    """تبدیل snake_case به CamelCase"""
    components = snake_str.split('_')
    return ''.join(x.title() for x in components)


def save_to_arb_file(arb_data: dict, lang: str, output_path: str):
    """ذخیره ترجمه‌ها در فایل arb"""
    arb_file = {
        "@@locale": lang,
        "@@last_modified": "2025-12-04T00:00:00.000Z"
    }
    
    # اضافه کردن ترجمه‌ها
    for key, value in sorted(arb_data.items()):
        arb_file[key] = value
        # افزودن metadata (اختیاری)
        arb_file[f"@{key}"] = {
            "description": f"Workflow translation for {key}"
        }
    
    # ذخیره در فایل
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(arb_file, f, ensure_ascii=False, indent=2)
    
    print(f"✅ فایل ذخیره شد: {output_path}")
    print(f"   تعداد کلیدها: {len(arb_data)}")


def generate_dart_extension():
    """تولید extension برای AppLocalizations در Dart"""
    dart_code = '''// Generated file - Do not edit manually
// Use scripts/extract_workflow_translations.py to regenerate

import '../l10n/app_localizations.dart';

/// Extension برای ترجمه‌های ورک‌فلو
extension WorkflowLocalizations on AppLocalizations {
  
  // ترجمه‌های مشترک
  String get workflowSettings => workflow_settings;
  String get workflowBasicInfo => workflow_basic_info;
  String get workflowAdvanced => workflow_advanced;
  
  // Create Invoice
  String get workflowCreateInvoiceActionName => workflowCreateInvoice_action_name;
  String get workflowCreateInvoiceActionDescription => workflowCreateInvoice_action_description;
  String get workflowCreateInvoiceFieldInvoiceType => workflowCreateInvoice_field_invoice_type;
  String get workflowCreateInvoiceFieldPersonId => workflowCreateInvoice_field_person_id;
  String get workflowCreateInvoiceFieldDocumentDate => workflowCreateInvoice_field_document_date;
  String get workflowCreateInvoiceFieldDescription => workflowCreateInvoice_field_description;
  String get workflowCreateInvoiceFieldItems => workflowCreateInvoice_field_items;
  
  // Send Telegram
  String get workflowSendTelegramActionName => workflowSendTelegram_action_name;
  String get workflowSendTelegramActionDescription => workflowSendTelegram_action_description;
  String get workflowSendTelegramFieldUserId => workflowSendTelegram_field_user_id;
  String get workflowSendTelegramFieldMessage => workflowSendTelegram_field_message;
  
  // تابع کمکی برای دریافت ترجمه بر اساس کلید
  String getWorkflowTranslation(String action, String field) {
    final key = 'workflow\${_capitalize(action)}\${_capitalize(field)}';
    // در اینجا می‌توان از reflection یا map استفاده کرد
    // فعلاً به صورت ساده برمی‌گردانیم
    return key;
  }
  
  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
'''
    
    return dart_code


def main():
    """اجرای اصلی اسکریپت"""
    print("=" * 80)
    print("🌍 استخراج ترجمه‌های ورک‌فلو")
    print("=" * 80)
    
    # مسیر پروژه Flutter
    flutter_l10n_path = Path(__file__).parent.parent.parent / "hesabixUI" / "hesabix_ui" / "lib" / "l10n"
    
    if not flutter_l10n_path.exists():
        print(f"⚠️  مسیر Flutter یافت نشد: {flutter_l10n_path}")
        print("   ترجمه‌ها فقط در کنسول نمایش داده می‌شوند.")
        flutter_l10n_path = None
    
    # استخراج ترجمه‌های فارسی
    print("\n📝 استخراج ترجمه‌های فارسی...")
    fa_translations = export_to_arb("fa")
    print(f"   تعداد کلیدها: {len(fa_translations)}")
    
    # استخراج ترجمه‌های انگلیسی
    print("\n📝 استخراج ترجمه‌های انگلیسی...")
    en_translations = export_to_arb("en")
    print(f"   تعداد کلیدها: {len(en_translations)}")
    
    # ذخیره در فایل‌های arb (اگر مسیر موجود باشد)
    if flutter_l10n_path:
        print("\n💾 ذخیره در فایل‌های arb...")
        
        # فارسی
        fa_arb_path = flutter_l10n_path / "workflow_fa.arb"
        save_to_arb_file(fa_translations, "fa", str(fa_arb_path))
        
        # انگلیسی
        en_arb_path = flutter_l10n_path / "workflow_en.arb"
        save_to_arb_file(en_translations, "en", str(en_arb_path))
        
        # تولید Dart extension
        print("\n📦 تولید Dart extension...")
        dart_extension = generate_dart_extension()
        extension_path = flutter_l10n_path.parent / "extensions" / "workflow_localizations_extension.dart"
        extension_path.parent.mkdir(exist_ok=True)
        
        with open(extension_path, 'w', encoding='utf-8') as f:
            f.write(dart_extension)
        
        print(f"✅ Extension ذخیره شد: {extension_path}")
    
    # نمایش خلاصه
    print("\n" + "=" * 80)
    print("📊 خلاصه")
    print("=" * 80)
    print(f"✅ تعداد کلیدهای فارسی: {len(fa_translations)}")
    print(f"✅ تعداد کلیدهای انگلیسی: {len(en_translations)}")
    
    # نمایش نمونه کلیدها
    print("\n📋 نمونه کلیدها:")
    for i, key in enumerate(list(fa_translations.keys())[:10], 1):
        print(f"   {i}. {key}: {fa_translations[key]}")
    
    print("\n💡 برای استفاده در Flutter:")
    print("   1. flutter pub run build_runner build --delete-conflicting-outputs")
    print("   2. از AppLocalizations.of(context).workflowCreateInvoiceActionName استفاده کنید")
    
    print("\n✅ تمام!")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\n❌ خطا: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


